# ToDo — garmin-custom-map

Конвейер автоматической сборки карты для Garmin GPSMAP 65/66/67 в стиле
opentopomap.org с тремя независимо переключаемыми слоями в одном `gmapsupp.img`.

## Цель

Один `gmapsupp.img`, внутри три слоя (Setup → Map → Map Information на устройстве):

1. **base** — топооснова OSM в стиле OpenTopoMap (готовый стиль из `der-stefan/OpenTopoMap`, папка `garmin/`)
2. **contours** — горизонтали из SRTM/DEM (phyghtmap/pyhgtmap), слой `transparent`, draw-priority выше base
3. **cadastre** — границы кадастровых участков РФ (ПКК Росреестра), слой `transparent`, draw-priority выше всех

У каждого слоя свой `family-id`/`product-id`; склейка через `mkgmap --gmapsupp` из готовых `.img` + `.typ`.

## Чек-лист

### Инфраструктура и тулчейн
- [x] Установить локально: Java, osmium-tool, gdal, phyghtmap (pyhgtmap), mkgmap
- [x] Проверить актуальность внешних URL: mkgmap.org.uk, Geofabrik, OpenTopoMap garmin style, ПКК
- [x] `Dockerfile` с полным тулчейном (Java, osmium, gdal, pyhgtmap, mkgmap)
- [x] `docker-run.sh` (bash) и `docker-run.ps1` (PowerShell) — обёртки запуска
- [x] Нативная сборка на Linux/WSL остаётся рабочей (`run_all.sh` без Docker)

### Пайплайн (scripts/)
- [x] `boundary` — регион по имени через Nominatim (реальная админ-граница → .poly) или bbox/GeoJSON
- [x] `osm` — скачать Geofabrik-экстракт (федеральные округа РФ в конфиге) + `osmium extract --polygon`
- [x] `contours` — pyhgtmap из SRTM/viewfinderpanoramas → contours.osm.pbf
- [x] `cadastre` — выгрузка участков с ПКК (проверить актуальный URL/схему через DevTools; ретраи, паузы, пагинация) → GeoJSON → OSM
- [x] fallback для кадастра: приём готового GeoJSON (QGIS / NGQ Rosreestr Tools)
- [x] `compile` — mkgmap: три слоя отдельно, каждый со своим family-id и TYP
- [x] `join` — mkgmap `--gmapsupp`: единый gmapsupp.img из .img+.typ всех слоёв
- [x] Оркестратор `run_all.sh` (этапы можно пропускать/повторять)

### Стили (styles/)
- [x] base: скачивание OpenTopoMap garmin style + TYP скриптом (не хранится в git)
- [x] contours: свой mkgmap-стиль + TYP (transparent, draw-priority > base)
- [x] cadastre: свой mkgmap-стиль + TYP (transparent, draw-priority > contours)

### Конфигурация (config/)
- [x] `geofabrik_sources.yaml` — источники экстрактов (федеральные округа РФ + страны)
- [x] `release_regions.yaml` — декларативный список регионов для плановых релизов
- [x] Пример конфига произвольного региона

### Web GUI
- [x] `webgui/index.html` — Leaflet, поиск по Nominatim, рисование полигона, экспорт GeoJSON (без бэкенда)

### GitHub Actions
- [x] `_build-region.yml` — переиспользуемая сборка одного региона (`workflow_call`)
- [x] `build-map.yml` — `workflow_dispatch`: region_name/bbox/contour_step/include_cadastre → Artifacts
- [x] `release-scheduled.yml` — cron `0 3 1 1,7 *` + ручной запуск; матрица из `release_regions.yaml`; все .img в один GitHub Release (тег `maps-YYYY-MM-DD`)

### Реальная проверка (не только код)
- [x] Тестовая сборка base-слоя на маленьком регионе
- [x] Тестовая сборка contours
- [x] Тестовая сборка cadastre (или fallback-путь, если ПКК недоступна из CI)
- [x] Склейка в gmapsupp.img, проверка валидности (все три слоя видны в файле)
- [x] Сборка Docker-образа + прогон run_all.sh через docker-run.sh
- [x] Зелёный прогон build-map.yml на тестовом регионе (артефакт chernyakhovsk-gmapsupp, ~2.5 мин)
- [ ] Зелёный прогон release-scheduled.yml через workflow_dispatch
- [ ] Прогон на более крупном регионе (область) — после зелёного CI

### Документация
- [x] README.md — что реализовано, как запускать (Docker/нативно/CI), как ставить карту в Garmin

## Заметки по ходу работы

- 2026-07-08: репозиторий был пуст, начинаю с нуля. Java 21, Python 3.11, Docker
  есть в среде; osmium/gdal доставлены через apt.
- phyghtmap мёртв (не работает на новых Python) → используется активный форк
  **pyhgtmap** (agrenott/pyhgtmap), CLI совместим. mkgmap r4924, splitter r654.
- Старый `pkk.rosreestr.ru/arcgis/rest/...` не существует: ПКК переехала на
  **nspd.gov.ru** (НСПД), слой «Земельные участки из ЕГРН» = 36048
  (`/api/aeggis/v3/36048/...`; поиск `/api/geoportal/v2/search/geoportal`,
  подтверждено по rendrom/rosreestr2coord). Портал геоблокирован вне РФ
  (connection reset) — из CI работает только fallback-GeoJSON; выгрузку с
  живого API нужно проверить с российского IP.
- В стиле OTM опции `check-roundabouts`/`check-roundabout-flares` устарели в
  mkgmap r4924 (SEVERE в логе) — убраны из base_options.
- **Главный подводный камень склейки**: `mkgmap --gmapsupp img...` перезаписывает
  MPS дефолтным family-id 6324 для всех слоёв. Лечится позиционными опциями:
  `--family-id=X` перед файлами каждого слоя (mkgmap применяет опции к
  следующим за ними входам). Проверяется inspect_img.py --expect.
- Кириллица: base собирается с code-page=1251 (LBL формат 09, метки читаются);
  оверлеям тоже прописан cp1251, иначе mkgmap пакует метки в 6-бит.
- Тестовая сборка: Черняховский округ (Калининградская обл.), экстракт
  kaliningrad (~90 МБ), 2 SRTM-тайла view3 → gmapsupp.img 880 КБ, три
  продукта в MPS: 3543 base / 3544 contours / 3545 cadastre. ✓
