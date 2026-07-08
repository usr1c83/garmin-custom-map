# Полный тулчейн для локальной сборки карт на Windows/macOS/Linux.
#   docker build -t garmin-custom-map .
#   ./docker-run.sh --config config/examples/test-chernyakhovsk.env
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-21-jre-headless \
        osmium-tool \
        gdal-bin \
        python3 \
        python3-pip \
        git curl wget unzip zip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# pyhgtmap — поддерживаемый форк phyghtmap (генерация горизонталей из SRTM)
RUN pip3 install --no-cache-dir --break-system-packages pyhgtmap

# Репозиторий монтируется в /work (см. docker-run.sh / docker-run.ps1);
# mkgmap/splitter скачиваются пайплайном в /work/tools и кешируются там.
WORKDIR /work

ENTRYPOINT ["/bin/bash"]
