# Готовые выгрузки кадастра

Самый надёжный способ получить кадастровый слой в автоматической сборке —
положить сюда заранее выгруженный GeoJSON с участками и указать путь к нему.

ПКК Росреестра (nspd.gov.ru) геоблокирована вне РФ, поэтому GitHub Actions
не может выгрузить участки напрямую (только через прокси с российским IP —
см. секрет `CADASTRE_PROXY` в [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)).

## Как сделать выгрузку

Через **QGIS** (рекомендуется):

1. Установите QGIS + плагин **NGQ Rosreestr Tools** (или «Rosreestr NSPD
   search»: Модули → Управление модулями → поиск «rosreestr»).
2. Загрузите слой «Земельные участки» по границе своего района
   (инструменты плагина позволяют выкачивать участки по территории).
3. Экспортируйте слой: ПКМ по слою → Export → Save Features As… →
   формат **GeoJSON**, СК **EPSG:4326**.
4. Сохраните файл сюда, например `cadastre/suzdal.geojson`.

Поле с кадастровым номером распознаётся автоматически: `cad_num`,
`cad_number`, `cadNum`, `cn`, `cadastral_number`, `label`, ….

## Как подключить

* **Локально / Docker**: `CADASTRE_GEOJSON=cadastre/suzdal.geojson`
* **Ручная сборка в Actions** (build-map): поле `cadastre_geojson` =
  `cadastre/suzdal.geojson` (+ `include_cadastre` = `1`)
* **Плановые релизы**: в `config/release_regions.yaml` у региона:

  ```yaml
  - name: suzdal
    query: "Суздальский район"
    geofabrik: central-fd
    contour_step: 10
    cadastre: true
    cadastre_geojson: cadastre/suzdal.geojson
  ```

Файлы выгрузок коммитятся в репозиторий рядом с этим README.
Учтите размер: границы участков целого района — обычно десятки мегабайт;
GitHub не принимает файлы больше 100 МБ (при необходимости разбейте регион
или упростите геометрию в QGIS: Vector → Geometry Tools → Simplify).
