# Документация для разработчиков

Как устроен конвейер, как им управлять через GitHub Actions и что уже
известно про грабли. Пользовательская инструкция — в [README.md](../README.md).

## Архитектура

Каждый слой компилируется отдельным Garmin-продуктом (свой `family-id` и
TYP), затем всё склеивается `mkgmap --gmapsupp` в один `gmapsupp.img` —
поэтому на приборе слои включаются независимо.

| Слой | family-id | mapname-префикс | Стиль |
|---|---|---|---|
| base | 3543 | 3543xxxx | официальный OpenTopoMap (скачивается в `styles/base-otm/`) |
| contours | 3544 | 3544xxxx | `styles/contours/` (transparent, draw-priority 28) |
| cadastre | 3545 | 3545xxxx | `styles/cadastre/` (transparent, draw-priority 30) |

```
run_all.sh            оркестратор; --stages tools,style,boundary,osm,
                      contours,cadastre,compile,join (любое подмножество)
scripts/
  common.sh           все переменные окружения и умолчания
  fetch_tools.sh      mkgmap r4924 + splitter r654 (пины в common.sh)
  fetch_style.sh      sparse-clone der-stefan/OpenTopoMap (garmin/)
  make_boundary.py    Nominatim | bbox | GeoJSON | .poly → region.poly,
                      region.bbox, boundary.geojson
  fetch_osm.sh        Geofabrik (кеш в data/) + osmium extract --polygon;
                      whole-extract режим — симлинк без вырезания
  make_contours.sh    pyhgtmap: фаза --download-only (ретраи) + генерация
  fetch_cadastre.py   НСПД WFS с пагинацией | --from-geojson | --proxy
  cadastre_to_osm.py  GeoJSON → OSM XML (cadastre=parcel, name=кад.номер)
  compile_layer.sh    splitter → TYP (mkgmap --family-id) → mkgmap
  join_gmapsupp.sh    склейка; позиционные --family-id перед каждым слоем
  inspect_img.py      парсер FAT+MPS готового img; --expect FID,FID
  yaml_get.py         мини-YAML-парсер (stdlib) для config/*.yaml
```

## GitHub Actions

Три workflow:

* **`_build-region.yml`** — переиспользуемая сборка одного региона
  (`workflow_call`). Ставит тулчейн (osmium из apt, pyhgtmap из pip,
  Temurin 21), кеширует `tools/` + `hgt/` (actions/cache, ключ по
  geofabrik-источнику), запускает `run_all.sh`, публикует артефакт
  `<region>-gmapsupp`. Таймаут 350 мин, `JAVA_XMX` — входом.
* **`build-map.yml`** — ручная сборка произвольного региона
  (Actions → build-map → Run workflow). Поля повторяют переменные
  пайплайна; результат в Artifacts запуска.
* **`release-scheduled.yml`** — плановые релизы: cron `0 3 1 1,7 *`
  (1 января и 1 июля, 03:00 UTC) + ручной запуск. Job `plan` читает
  `config/release_regions.yaml` (через `yaml_get.py`+jq) и строит матрицу;
  job `build` вызывает `_build-region.yml` на каждый регион
  (`fail-fast: false` — упавший регион не валит остальные); job `release`
  скачивает все артефакты и публикует одним релизом `maps-YYYY-MM-DD`
  (`gh release create`). При ручном запуске поле `only` ограничивает
  список регионов (`only: kaliningrad,crimean-fd`), `tag` переопределяет тег.

Требование GitHub: расписание работает только для workflow в **дефолтной
ветке** репозитория.

### Секреты

* `CADASTRE_PROXY` *(опционально)* — `http://user:pass@host:port` прокси с
  российским IP. Если задан, регионы с `cadastre: true` без
  `cadastre_geojson` выгружают участки напрямую с nspd.gov.ru.
  Оба caller-workflow передают секреты через `secrets: inherit`.

### Лимиты релизов и раннеров

* Релизы: **2 GiB на файл-ассет**, суммарный объём и трафик не ограничены,
  ≤1000 ассетов на релиз. Если карта округа превысит 2 GiB — увеличить
  `contour_step` или разбить регион в `release_regions.yaml`.
* Раннер `ubuntu-latest`: 4 vCPU, 16 ГБ RAM, ~14 ГБ диска (шаг
  «Free disk space» освобождает ещё ~20 ГБ), лимит job — 6 ч.

## Кадастр: состояние дел

Старый API `pkk.rosreestr.ru/arcgis/rest/...` мёртв. ПКК живёт на НСПД:

* слой «Земельные участки из ЕГРН» — id **36048**:
  `https://nspd.gov.ru/api/aeggis/v3/36048/wfs` (WFS 2.0 GetFeature,
  GeoJSON, пагинация STARTINDEX/COUNT);
* поиск по кадастровому номеру:
  `https://nspd.gov.ru/api/geoportal/v2/search/geoportal?thematicSearchId=1&query=...`
  (сверено с работающим [rosreestr2coord](https://github.com/rendrom/rosreestr2coord)).

Портал **геоблокирован вне РФ** (TCP reset) и использует сертификаты
Russian Trusted Root CA (`--insecure` в `fetch_cadastre.py`). Схема API
недокументированная: если запросы с российского IP перестанут работать —
открыть nspd.gov.ru/map, включить слой «Земельные участки», подсмотреть
актуальный URL в DevTools → Network и передать `--base-url`/`--layer`.

Приоритет источников в пайплайне: `CADASTRE_GEOJSON` (файл) →
НСПД напрямую/через `CADASTRE_PROXY`. Ошибка кадастра не валит сборку.

## Известные грабли (уже учтены в коде)

* **mkgmap --gmapsupp теряет family-id**: при склейке готовых .img MPS
  переписывается дефолтной family 6324 у всех слоёв → на приборе один
  общий продукт. Решение: mkgmap применяет опции к файлам, идущим в
  командной строке ПОСЛЕ них, поэтому `join_gmapsupp.sh` ставит
  `--family-id/--family-name` перед каждой группой тайлов.
  Каждая сборка проверяется `inspect_img.py --expect 3543,3544[,3545]`.
* **pyhgtmap 4.1 дедлочится при `--jobs > 1`**: воркеры форкаются при
  живых потоках npyosmium-писателя и навсегда виснут в `add_way`
  (диагностировано py-spy). Генерация — только в один процесс
  (`PYHGT_JOBS` переопределяет на свой страх и риск).
* **viewfinderpanoramas.org подвешивает соединения**, а pyhgtmap не
  ставит таймауты на сокеты: качаем отдельной фазой `--download-only` с
  `socket.setdefaulttimeout(90)` и 5 ретраями; кеш `hgt/` сохраняет
  прогресс между попытками (и кешируется между CI-запусками).
* **phyghtmap мёртв** (не работает на Python ≥3.10) — используется форк
  [pyhgtmap](https://github.com/agrenott/pyhgtmap), CLI совместим.
* **Опции OTM устарели**: `check-roundabouts`/`check-roundabout-flares`
  дают SEVERE на mkgmap r4924 — убраны из `config/mkgmap/base_options`.
* **Кириллица**: все слои собираются с `code-page=1251`; без этого mkgmap
  пакует подписи в 6-битную кодировку (только A-Z/0-9). Unicode
  сознательно не используется — новые прошивки Garmin блокируют
  неофициальные unicode-карты.
* **Подписи горизонталей в метрах**: оригинальный стиль OTM конвертирует
  в футы (`conv:m=>ft`) — в `styles/contours/lines` конверсия убрана.
* **Свежесозданный репозиторий**: GitHub регистрирует dispatch-only
  workflow только после пуша, меняющего сам файл workflow. Если
  `actions/workflows` API возвращает пусто — тронуть файлы и запушить.

## Тестовый цикл

```bash
# маленький регион (~3 мин с кешами): 174k точек OSM, 2 SRTM-тайла
./run_all.sh --config config/examples/test-chernyakhovsk.env

# перезапуск отдельных этапов
./run_all.sh --config ... --stages contours,compile,join

# проверка слоёв в готовом файле
python3 scripts/inspect_img.py out/chernyakhovsk/gmapsupp.img --expect 3543,3544,3545
```

Логи каждого этапа — в `out/<region>/layers/<layer>/*.log` и
`out/<region>/join.log`.

Прогнанные конфигурации: Черняховский округ (район, с кадастром из
выгрузки), Калининградская область (Nominatim-граница), Крымский ФО и
Приволжский ФО (целые geofabrik-экстракты, multi-tile). Релизы-прогоны:
`test-2026-07-08`, `test-volga-2026-07-08`.

## Версии инструментов

Пины в `scripts/common.sh`: `MKGMAP_VERSION=r4924`, `SPLITTER_VERSION=r654`
(проверять на [mkgmap.org.uk/download](https://www.mkgmap.org.uk/download/mkgmap.html)).
Версии GitHub Actions — Node 24-мажоры (checkout v6, setup-java v5,
setup-python v6, cache v5, upload-artifact v6, download-artifact v8).
