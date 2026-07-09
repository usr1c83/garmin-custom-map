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
- [x] Зелёный прогон release-scheduled.yml через workflow_dispatch (релиз test-2026-07-08: kaliningrad 18 МБ + crimean-fd 33 МБ)
- [x] Прогон на более крупном регионе: Калининградская область целиком и весь Крымский ФО (multi-tile, ~4 мин в CI)

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
- CI-зависание Крыма (3.5 ч): две причины. (1) viewfinderpanoramas.org
  подвешивает соединения, у pyhgtmap нет таймаутов → фаза --download-only
  с socket-таймаутом 90с и 5 ретраями; (2) дедлок pyhgtmap 4.1 при
  --jobs>1 (fork при живых потоках npyosmium-писателя, воркеры виснут в
  add_way) → генерация в 1 процесс (PYHGT_JOBS для переопределения).
  С кешем тайлов Крым считается ~1 мин.
- Node 20 deprecation в Actions: подняты мажоры (checkout v6, setup-java v5,
  setup-python v6, cache v5, upload-artifact v6, download-artifact v8).
- Подписи горизонталей в метрах (у OTM были футы) — по запросу.
- Кадастр: сборка не падает без ПКК; секрет CADASTRE_PROXY (прокси с RU IP)
  включает прямую выгрузку из CI.

## Доработки по фидбеку (2026-07-08, вторая итерация)

- [x] Кадастр в CI: каталог cadastre/ для готовых QGIS-выгрузок,
  поле cadastre_geojson в release_regions.yaml, прокинуто в release-workflow;
  секрет CADASTRE_PROXY — альтернатива (прокси с RU IP)
- [x] Лимиты GitHub Releases выяснены: 2 GiB на файл, суммарно и по
  трафику без лимитов, ≤1000 ассетов на релиз
- [x] README.md переработан для пользователей (релизы сверху, сборка ниже,
  FAQ); всё про CI/архитектуру → docs/DEVELOPMENT.md
- [x] Тест Приволжского ФО: зелёный за ~18 мин целиком (сборка ~15 мин),
  volga-fd_gmapsupp.img = 667 МБ, 101 тайл (82 base + 19 contours),
  оба продукта в MPS корректны. Релиз test-volga-2026-07-08.
  Вывод: целые ФО собираются быстро и в лимит 2 GiB/файл влезают
  (запас у крупнейшего ЦФО оценочно ~1.5-2 ГБ — при превышении поднять
  contour_step или разбить регион).

## Доработки (третья итерация)

- [x] Кадастровый слой включён по умолчанию во всех релизных регионах;
  источники по приоритету: cadastre_geojson → cadastre/<name>.geojson →
  НСПД через CADASTRE_PROXY; в CI без источника — мгновенный пропуск
- [x] size-guard: контроль 2 GiB на файл прямо в CI, автоповышение шага
  горизонталей +5 м (до 3 пересборок), размер в step summary
- [x] Скриншот webgui в README (Playwright + перехват тайлов через curl)
- [x] Список совместимых моделей Garmin в README (по OSM wiki)
- [x] Русификация: TYP-строки базового стиля (~80 переводов через
  russify_typ.py + prepare_typ.py, квирк CodePage в колонке 0), русские
  имена слоёв в MPS (транслит + байтовый постпатч fix_mps_names.py),
  подписи наших TYP (горизонталь, кадастровый участок), метры вместо футов
- [x] Поиск по адресам: --index при склейке (MDR на каждый слой,
  города/улицы проверены в индексе), WITH_BOUNDS=1 в CI

## Доработки (четвёртая итерация)

- [x] Кадастр в CI: полная цепочка источников с ограничением по времени на
  каждом шаге (явный файл → cadastre/<регион>.geojson в git → ассет
  <регион>.geojson(.gz) из релиза-хранилища cadastre-data → НСПД через
  CADASTRE_PROXY → пропуск слоя). Зависаний нет by design.
- [x] Контроль 2 GiB подтверждён автоматизированным (build_with_size_guard.sh
  в CI: порог 1950 МиБ, +5 м к шагу, до 3 пересборок, размер в Summary)
- [x] docs/DEVELOPMENT.md: пошаговая настройка автосборки (Actions, права,
  секреты, cron-грабли, форки) + алгоритм кадастра + size-guard
- [x] Комментарии «что где менять» во всех yml; новый служебный
  cleanup-releases.yml (удаление релизов с тегами)
- [x] Тестовые релизы удалены; Приволжский ФО пересобран на свежем коде
  (зелёный, 683 МБ с адресным индексом и русскими подписями)
- [x] Полный прогон всех 10 регионов: релиз maps-2026-07-09 опубликован
  целиком (12 файлов, 8.83 GiB). Нарезка работает в бою: Сибирь и
  Дальний Восток > 1950 МиБ → по 2 части каждая, все части < 2 GiB.
  По пути добиты: aria2-загрузчик с докачкой (Geofabrik рвал соединения
  с раннеров на ~60 c), баг валидации .tmp (osmium fileinfo -F pbf),
  публикация при частичных сбоях, retrigger.yml (перезапуск джобов
  пушем при недоступности API), пережиты два инцидента GitHub Actions
  (нехватка раннеров).

## Доработки (пятая итерация)

- [x] Карта высот (DEM) встроена в base-слой (mkgmap --dem из SRTM-кеша):
  отмывка, высота в точке, профиль маршрута; WITH_DEM=0 отключает
- [x] Видимые номера домов (правило addr:housenumber + TYP-точка 0x11500,
  вставка до <finalize>; проверено по подписям в собранной карте)
- [x] Ретраи скачивания .poly (make_boundary), автоочистка старых релизов
  maps-* (KEEP=2), публикация при частичных сбоях матрицы
- [x] При превышении 2 GiB карта режется на части .partN.img (жадная
  упаковка тайлов, адаптивный бюджет, у каждой части свои TYP/MDR) —
  качество DEM/горизонталей не снижается; проверено в бою (Сибирь, ДВ)
- [x] aria2 с докачкой для всех скачиваний (scripts/download.sh, fallback
  curl -C -); починен баг валидации osmium fileinfo на *.tmp
- [x] cron каждые 2 месяца + keepalive.yml против 60-дневного отключения
- [x] Служебные workflow: cleanup-releases (удаление релизов с тегами),
  retrigger (перезапуск упавших джобов пушем .retrigger — выручил при
  инциденте GitHub «Delays starting Actions runs»)

## ИТОГ: релиз maps-2026-07-09

| Регион | Размер |
|---|---|
| central-fd | 848 MiB |
| crimean-fd | 39 MiB |
| far-eastern-fd | part1 1641 + part2 949 MiB |
| kaliningrad | 52 MiB |
| north-caucasus-fd | 182 MiB |
| northwestern-fd | 1114 MiB |
| siberian-fd | part1 1662 + part2 611 MiB |
| south-fd | 339 MiB |
| ural-fd | 653 MiB |
| volga-fd | 949 MiB |
