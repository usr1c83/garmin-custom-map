# garmin-custom-map

Карты для навигаторов **Garmin GPSMAP 62/64/65/66/67** (и любых других,
понимающих `gmapsupp.img`) в стиле [opentopomap.org](https://opentopomap.org).

В одном файле — три слоя, каждый включается и выключается на приборе
независимо (**Setup → Map → Map Information**):

1. **Топооснова** — OpenStreetMap в оформлении OpenTopoMap, с маршрутизацией
   и адресным поиском, подписи на русском;
2. **Горизонтали** — рельеф из SRTM, шаг 10 м (подписи в метрах);
3. **Кадастр** *(опционально)* — границы земельных участков Росреестра
   с кадастровыми номерами.

---

## Скачать готовую карту

Готовые карты по федеральным округам РФ собираются автоматически два раза
в год (1 января и 1 июля) и публикуются в
**[Releases](../../releases)** — берите последний релиз `maps-ГГГГ-ММ-ДД`.

**Установка:**

1. Скачайте `<регион>_gmapsupp.img` нужного региона.
2. Скопируйте файл на карту памяти прибора в папку `Garmin/`
   (имя файла можно не менять — прибор подхватывает любые `.img`).
3. Включите нужные слои: **Setup → Map → Map Information** — там будут
   отдельные пункты «OTM …», «Contours …» и, если есть, «Cadastre …».

> ⚠ Стиль OpenTopoMap распространяется по лицензии **CC-BY-NC-SA** —
> карты можно использовать только в некоммерческих целях.

---

## Собрать карту самому

Можно собрать карту любого региона: страна, область, район или произвольная
нарисованная на карте территория.

### Вариант 1: Docker (Windows / macOS / Linux)

Нужен только [Docker](https://www.docker.com/products/docker-desktop/).

```bash
# Linux / macOS / Git Bash / WSL
./docker-run.sh --config config/examples/test-chernyakhovsk.env
```

```powershell
# Windows PowerShell
.\docker-run.ps1 --config config/examples/test-chernyakhovsk.env
```

Первый запуск соберёт образ с тулчейном (~5 мин), дальше — только сборка
карты. Результат: `out/<регион>/<регион>_gmapsupp.img`.

### Вариант 2: без Docker (Linux / WSL)

```bash
sudo apt install openjdk-21-jre-headless osmium-tool python3-pip
pip install pyhgtmap
./run_all.sh --config config/examples/test-chernyakhovsk.env
```

mkgmap/splitter и стиль OpenTopoMap скачаются автоматически при первом
запуске.

### Как задать свой регион

Скопируйте `config/examples/test-chernyakhovsk.env` и поменяйте значения —
или передайте переменные напрямую:

```bash
REGION_NAME=suzdal \
REGION_QUERY="Суздальский район" \
GEOFABRIK=central-fd \
./docker-run.sh
```

| Переменная | Что делает |
|---|---|
| `REGION_NAME` | имя региона → имя файла карты |
| `REGION_QUERY` | название региона — берётся **реальная административная граница** (Nominatim/OSM) |
| `BBOX=з,ю,в,с` | прямоугольник вместо названия |
| `BOUNDARY_GEOJSON=файл` | произвольная область (см. ниже) |
| `GEOFABRIK` | откуда брать OSM-данные: `central-fd`, `volga-fd`, `kaliningrad`, … — список в `config/geofabrik_sources.yaml`. Если регион не задан вообще — соберётся весь экстракт |
| `CONTOUR_STEP` | шаг горизонталей в метрах (10 по умолчанию) |
| `INCLUDE_CADASTRE=1` | добавить кадастровый слой |
| `CADASTRE_GEOJSON=файл` | готовая выгрузка участков (см. ниже) |
| `WITH_SEA=1` | корректные моря/побережья (скачает ~800 МБ) |
| `WITH_BOUNDS=1` | адресный поиск (скачает ~400 МБ) |

### Нарисовать регион на карте

Откройте `webgui/index.html` в браузере (просто двойной клик, сервер не
нужен): поиск по названию, рисование произвольного полигона, экспорт в
`region.geojson`. Затем:

```bash
REGION_NAME=myarea BOUNDARY_GEOJSON=region.geojson GEOFABRIK=central-fd ./docker-run.sh
```

### Кадастровый слой

Публичная кадастровая карта (nspd.gov.ru) **не открывается из-за рубежа**,
поэтому надёжнее всего готовая выгрузка:

1. Выгрузите участки своего района в GeoJSON через QGIS с плагином
   «NGQ Rosreestr Tools» — пошагово в [cadastre/README.md](cadastre/README.md).
2. Соберите карту с `INCLUDE_CADASTRE=1 CADASTRE_GEOJSON=cadastre/мой-район.geojson`.

С российского IP работает и прямая выгрузка: просто `INCLUDE_CADASTRE=1`
без `CADASTRE_GEOJSON` (скрипт сам скачает участки по границе региона с
ретраями и паузами). Если кадастр скачать не удалось, карта всё равно
соберётся — из двух слоёв.

---

## Частые вопросы

**Карта не появилась на приборе.** Проверьте, что файл лежит в папке
`Garmin/` на карте памяти и имеет расширение `.img`. На старых приборах
(62/64) файл должен называться строго `gmapsupp.img`.

**Слои не переключаются по отдельности.** Убедитесь, что смотрите
Setup → Map → Map Information: там должно быть три отдельных пункта.

**Кириллица квадратиками.** Карты собраны в кодировке CP1251 — на
GPSMAP 6x с прошивкой, поддерживающей русский язык, всё отображается;
выберите русский язык интерфейса.

**Хочу собрать регион, которого нет в списке Geofabrik.** Задайте
`GEOFABRIK` полным URL любого экстракта с
[download.geofabrik.de](https://download.geofabrik.de/) — граница региона
всё равно вырежется точно.

---

## Лицензии

* Данные карт: © участники [OpenStreetMap](https://www.openstreetmap.org/copyright) (ODbL), экстракты [Geofabrik](https://download.geofabrik.de/).
* Стиль: [OpenTopoMap](https://github.com/der-stefan/OpenTopoMap), **CC-BY-NC-SA 4.0** — некоммерческое использование.
* Рельеф: [viewfinderpanoramas.org](http://viewfinderpanoramas.org/) (Jonathan de Ferranti), SRTM.
* Кадастр: данные ПКК Росреестра; справочно, не является юридическим документом.

---

Разработчикам — архитектура пайплайна, GitHub Actions, отладка и известные
грабли: **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**.
