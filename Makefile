# Convenience wrapper around run_all.sh.
#   make map CONFIG=config/examples/test-chernyakhovsk.env
#   make map REGION_NAME=suzdal REGION_QUERY="Суздальский район" GEOFABRIK=central-fd
#   make tools style           # just the toolchain / style
CONFIG ?=
CONFIG_ARG = $(if $(CONFIG),--config $(CONFIG),)

.PHONY: map tools style boundary osm contours cadastre compile join clean docker

map:
	./run_all.sh $(CONFIG_ARG)

tools style boundary osm contours cadastre compile join:
	./run_all.sh $(CONFIG_ARG) --stages $@

docker:
	docker build -t garmin-custom-map .

clean:
	rm -rf out
