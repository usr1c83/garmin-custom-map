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

## Настройка автосборки с нуля (пошагово)

1. **Репозиторий**: форкните/скопируйте репо. Workflow-файлы должны лежать
   в **ветке по умолчанию** — иначе cron не сработает и workflow не появятся
   во вкладке Actions.
2. **Включите Actions**: Settings → Actions → General → «Allow all actions».
   В форках scheduled-workflow дополнительно требует ручного включения:
   вкладка Actions → выбрать workflow → кнопка «Enable workflow».
3. **Права токена**: ничего настраивать не нужно — job `release` объявляет
   `permissions: contents: write`, стандартного `GITHUB_TOKEN` достаточно.
   (Если в организации ужёсточены настройки: Settings → Actions → General →
   Workflow permissions → «Read and write permissions».)
4. **Секрет для кадастра** *(опционально)*: Settings → Secrets and
   variables → Actions → New repository secret → имя `CADASTRE_PROXY`,
   значение `http://user:pass@host:port` (прокси с российским IP).
5. **Выгрузки кадастра** *(опционально, надёжнее прокси)*: положите
   GeoJSON-файлы в `cadastre/<имя-региона>.geojson` (до 100 МБ) или
   загрузите ассетами в релиз с тегом `cadastre-data` (без лимита 100 МБ,
   поддерживается gzip): `gh release create cadastre-data central-fd.geojson.gz`.
   Пайплайн подхватит их автоматически (см. алгоритм ниже).
6. **Список регионов**: правится декларативно в
   [`config/release_regions.yaml`](../config/release_regions.yaml) — имя,
   граница (Nominatim-запрос или весь экстракт), шаг горизонталей, кадастр.
7. **Расписание**: строка `cron:` в `release-scheduled.yml` (сейчас —
   1-е число каждого второго месяца, интервал ≤62 дня). GitHub отключает
   cron после 60 дней без активности в репозитории (частота запусков сама
   по себе этого не лечит) — от отключения защищает `keepalive.yml`:
   раз в месяц сбрасывает таймер вызовом API «enable workflow», коммиты
   не требуются. Реактивация вручную — кнопкой на странице workflow.
8. **Первый запуск**: Actions → release-scheduled → Run workflow с пустым
   `only` (все регионы) или `only: kaliningrad` для быстрой проверки.
   Готовые карты появятся в Releases; ручные одиночные сборки — build-map,
   результат в Artifacts.

### Алгоритм кадастрового слоя в CI

Источники перебираются по порядку, каждый шаг ограничен по времени —
сборка не может зависнуть и не падает, если кадастр недоступен:

1. `cadastre_geojson` из `release_regions.yaml` (или поле ручного запуска);
2. файл `cadastre/<регион>.geojson`, закоммиченный в репозиторий;
3. ассет `<регион>.geojson(.gz)` из релиза-хранилища `cadastre-data`
   этого репо (curl, таймаут 300 с, 2 ретрая; другой сервер —
   `CADASTRE_DATA_BASE`);
4. прямая выгрузка с НСПД через `CADASTRE_PROXY` (WFS с пагинацией,
   таймаут 90 с/запрос, 5 ретраев); без прокси в CI шаг пропускается
   мгновенно (портал геоблокирован за рубежом);
5. если все источники пусты — слой пропускается с предупреждением, карта
   собирается из топоосновы и горизонталей.

### Контроль размера (лимит GitHub 2 GiB на файл)

`scripts/build_with_size_guard.sh` (его вызывает CI вместо `run_all.sh`)
после сборки сравнивает размер img с порогом `MAX_IMG_MB` (1950 МиБ).
Если больше — шаг горизонталей увеличивается на 5 м и слой пересобирается
(этапы contours+compile+join, OSM-данные не перекачиваются), до
`MAX_TRIES` (3) раз. Если и после этого не влезло, job падает с
подсказкой разбить регион в `release_regions.yaml`. Размер каждой карты
выводится в Summary запуска.

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
* **`release-scheduled.yml`** — плановые релизы: cron `0 3 1 */2 *`
  (1-е число каждого второго месяца, 03:00 UTC) + ручной запуск. Job `plan` читает
  `config/release_regions.yaml` (через `yaml_get.py`+jq) и строит матрицу;
  job `build` вызывает `_build-region.yml` на каждый регион
  (`fail-fast: false` — упавший регион не валит остальные); job `release`
  скачивает все артефакты и публикует одним релизом `maps-YYYY-MM-DD`
  (`gh release create`). При ручном запуске поле `only` ограничивает
  список регионов (`only: kaliningrad,crimean-fd`), `tag` переопределяет тег.
  Пустое `only` = все регионы, как и по cron.
* **`cleanup-releases.yml`** — служебный: удаление релизов с тегами
  (например, тестовых): Run workflow → теги через запятую.
* **`keepalive.yml`** — служебный: ежемесячно сбрасывает 60-дневный
  таймер отключения scheduled-workflow (API enable), чтобы плановые
  сборки не отваливались при бездействии репозитория.

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
* **TYP и кириллица**: детектор кодировки mkgmap видит `CodePage=` только
  в колонке 0. Файл с `CodePage=1252` в колонке 0 и кириллицей падает с
  безмолвным SEVERE; у OpenTopoMap строка с табуляцией — поэтому «у них
  работает». `scripts/prepare_typ.py` нормализует любой TYP-исходник:
  CodePage=1251 в колонке 0 + перекодировка файла в cp1251 (строки, не
  влезающие в cp1251 — немецкие умляуты OTM — отбрасываются).
  Русские подписи типов делает `scripts/russify_typ.py` при скачивании
  стиля (~80 переводов, building→здание и т.д.).
* **Кириллица в argv/MPS**: JVM в C-локали читает argv как latin-1, а MPS
  mkgmap пишет строго в latin1 — русские имена слоёв через командную
  строку не проходят. Пайплайн передаёт ASCII-транслит той же байтовой
  длины (Topoosnova/Gorizontali/Kadastr), а `scripts/fix_mps_names.py`
  после склейки вписывает cp1251-кириллицу байт-в-байт прямо в MPS.
* **Поиск по адресам**: работает только если склейка выполнена с
  `--index` — mkgmap кладёт в gmapsupp по MDR-индексу на каждую family
  (00003543.MDR и т.д.). CI также ставит `WITH_BOUNDS=1` (предвычисленные
  границы НП, кешируются) для корректной привязки улиц к городам.
* **Кадастр в CI**: без источника данных (нет `cadastre/<region>.geojson`
  и секрета `CADASTRE_PROXY`) стадия пропускается мгновенно — прямая
  попытка в НСПД из CI лишь сжигала ~9 минут на таймаутах геоблокировки.

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
