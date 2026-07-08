# garmin-custom-map

Конвейер автоматической сборки карт для **Garmin GPSMAP 65/66/67** (и других
приборов с поддержкой `gmapsupp.img`) в стиле [opentopomap.org](https://opentopomap.org)
с тремя независимыми слоями в одном файле:

| Слой | Источник | family-id | Управление на приборе |
|------|----------|-----------|----------------------|
| **base** — топооснова | OSM (Geofabrik) + официальный Garmin-стиль [OpenTopoMap](https://github.com/der-stefan/OpenTopoMap) | 3543 | Setup → Map → Map Information |
| **contours** — горизонтали | SRTM / viewfinderpanoramas.org через [pyhgtmap](https://github.com/agrenott/pyhgtmap) | 3544 | включается/выключается отдельно |
| **cadastre** — кадастровые участки РФ | ПКК Росреестра ([nspd.gov.ru](https://nspd.gov.ru)) или готовый GeoJSON | 3545 | включается/выключается отдельно |

Каждый слой компилируется отдельным продуктом (свой family-id и TYP),
затем склеивается `mkgmap --gmapsupp` в единый `gmapsupp.img`. Слои
contours и cadastre прозрачные (`transparent`) с draw-priority выше базы,
поэтому рисуются поверх топоосновы.

## Быстрый старт

### Docker (Windows / macOS / Linux)

```bash
./docker-run.sh --config config/examples/test-chernyakhovsk.env
# Windows PowerShell:
.\docker-run.ps1 --config config/examples/test-chernyakhovsk.env
```

Результат: `out/<регион>/<регион>_gmapsupp.img` — скопируйте в папку
`Garmin/` на microSD прибора.

### Нативно (Linux / WSL)

Требуются: Java 17+, osmium-tool, python3, pip (`pip install pyhgtmap`).

```bash
./run_all.sh --config config/examples/test-chernyakhovsk.env
# или без конфига:
REGION_NAME=suzdal REGION_QUERY="Суздальский район" GEOFABRIK=central-fd ./run_all.sh
```

mkgmap/splitter скачиваются автоматически в `tools/`, стиль OpenTopoMap —
в `styles/base-otm/` (в git не хранятся).

### GitHub Actions

* **Произвольный регион вручную** — workflow **build-map** (Run workflow):
  имя региона, Nominatim-запрос / bbox / GeoJSON, ключ Geofabrik-экстракта,
  шаг горизонталей, кадастр. Готовый `.img` — в Artifacts запуска.
* **Плановые релизы** — workflow **release-scheduled**: по cron
  (`0 3 1 1,7 *` — 1 января и 1 июля) собирает все регионы из
  [`config/release_regions.yaml`](config/release_regions.yaml)
  (федеральные округа РФ) и публикует все `.img` одним GitHub Release с
  тегом `maps-YYYY-MM-DD`. Можно запустить вручную; поле `only`
  ограничивает список регионов (для теста), `tag` задаёт тег релиза.

## Выбор региона

Четыре способа (приоритет сверху вниз, см. `run_all.sh`):

1. `BOUNDARY_GEOJSON=file.geojson` — произвольный полигон. Рисуется в
   [webgui/index.html](webgui/index.html) (открыть локально в браузере:
   поиск по Nominatim + рисование от руки + экспорт GeoJSON).
2. `BBOX=west,south,east,north` — прямоугольник.
3. `REGION_QUERY="Суздальский район"` — геокодирование через Nominatim,
   берётся **реальная административная граница** (полигон), не bbox.
4. Ничего из перечисленного — весь Geofabrik-экстракт целиком (граница
   берётся из `.poly` самого Geofabrik).

OSM-данные режутся точно по границе через `osmium extract --polygon`.

## Конфигурация

* `config/geofabrik_sources.yaml` — ключи экстрактов (федеральные округа РФ,
  `kaliningrad` — отдельный маленький экстракт, удобен для проверки).
* `config/release_regions.yaml` — декларативный список регионов плановых
  релизов: имя, запрос, экстракт, шаг горизонталей, кадастр.
* `config/examples/test-chernyakhovsk.env` — пример конфига региона
  (маленький округ Калининградской области, собирается за ~3 минуты).
* Все переменные окружения пайплайна описаны в `scripts/common.sh`.

## Кадастровый слой: важно

Публичная кадастровая карта переехала со старого `pkk.rosreestr.ru` на
**НСПД** (`nspd.gov.ru`); слой «Земельные участки из ЕГРН» — id 36048
(`/api/aeggis/v3/36048/...`, поиск — `/api/geoportal/v2/search/geoportal`).
Портал **геоблокирован вне РФ** и использует сертификаты Russian Trusted
Root CA, поэтому:

* с российского IP: `scripts/fetch_cadastre.py` выгружает участки по bbox
  региона (ретраи, паузы, постраничная выгрузка; `--insecure` для TLS).
  Так как API недокументированный, при смене схемы сверьте URL слоя через
  DevTools → Network на nspd.gov.ru/map и передайте `--base-url`/`--layer`.
* из CI / из-за рубежа: используйте **fallback** — готовый GeoJSON,
  выгруженный из QGIS (плагин NGQ Rosreestr Tools) или любым другим
  способом: `CADASTRE_GEOJSON=path/to/parcels.geojson`. Поле с кадастровым
  номером распознаётся автоматически (`cad_num`, `cadNum`, `cn`, …).

## Как это устроено

```
run_all.sh            оркестратор; этапы: tools style boundary osm contours
                      cadastre compile join (любой набор через --stages)
scripts/
  fetch_tools.sh      mkgmap r4924 + splitter r654 с mkgmap.org.uk
  fetch_style.sh      sparse-clone официального стиля OpenTopoMap
  make_boundary.py    Nominatim/bbox/GeoJSON/.poly → region.poly + boundary.geojson
  fetch_osm.sh        Geofabrik + osmium extract --polygon
  make_contours.sh    pyhgtmap: SRTM/view3 → contours.osm.pbf
  fetch_cadastre.py   НСПД (или fallback GeoJSON) → cadastre.geojson
  cadastre_to_osm.py  GeoJSON → OSM XML (cadastre=parcel + номер)
  compile_layer.sh    splitter + mkgmap для одного слоя (свой FID и TYP)
  join_gmapsupp.sh    mkgmap --gmapsupp: склейка слоёв (family-id
                      передаются позиционно перед файлами каждого слоя!)
  inspect_img.py      проверка: FAT + MPS-записи в готовом gmapsupp.img
  yaml_get.py         мини-парсер YAML (stdlib) для конфигов
styles/
  base-otm/           официальный стиль OpenTopoMap (скачивается, не в git)
  contours/           стиль+TYP горизонталей (по мотивам OTM, прозрачный)
  cadastre/           стиль+TYP участков (прозрачный, пурпурный пунктир,
                      подпись = кадастровый номер)
```

Технические детали:

* **Кириллица**: все слои собираются с `code-page=1251` (GPSMAP корректно
  отображает cp1251-карты; unicode-карты на новых прошивках блокируются).
* **Высоты**: подписи горизонталей конвертируются в футы
  (`conv:m=>ft`) — Garmin интерпретирует подпись типов 0x20–0x22 как
  высоту в футах и сам пересчитывает в единицы прибора.
* **Склейка**: mkgmap применяет `--family-id` к файлам, следующим за
  опцией, поэтому `join_gmapsupp.sh` перечисляет опции перед каждой
  группой тайлов — иначе все слои получили бы один family-id и не
  переключались бы на приборе независимо.
* `inspect_img.py --expect 3543,3544,3545` валидирует каждую сборку.
* Для прибрежных регионов включите `WITH_SEA=1` (precomp-sea, ~800 МБ),
  для адресного поиска — `WITH_BOUNDS=1`.

## Лицензии данных и стиля

* Картооснова: © участники OpenStreetMap (ODbL), экстракты Geofabrik.
* Стиль: OpenTopoMap, CC-BY-NC-SA 4.0 — готовые карты **нельзя
  использовать в коммерческих целях**.
* Рельеф: viewfinderpanoramas.org (условия на сайте), SRTM (public domain).
* Кадастр: данные ПКК Росреестра, только для справки; не является
  юридически значимым документом.
