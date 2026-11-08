#!/usr/bin/env bash
# Build NYC speed-limit tiles from OpenStreetMap for Velo Maps' own server (owner, 11/8: host
# them on our DigitalOcean droplet instead of depending on the public Overpass API).
#
#   ./scripts/build_speed_limit_tiles.sh        # download, extract, tile → build.nosync/tiles
#   ./scripts/deploy_speed_limit_tiles.sh       # upload to the droplet
#
# Source: Geofabrik's New York extract (OSM, ODbL). Output: one JSON per 0.01° tile over the
# NYC bounding box, same shape the app caches ({"ways":[{"tags":{"maxspeed":..},"geometry":[..]}]}),
# including empty tiles so the app knows "no posted limits here" without asking anyone else.
# Re-run monthly; limits rarely change.
set -euo pipefail
cd "$(dirname "$0")/.."
W=build.nosync/osm; mkdir -p "$W"
BBOX="-74.26,40.49,-73.70,40.92"      # NYC five boroughs
if [ ! -f "$W/new-york-latest.osm.pbf" ] || [ -n "$(find "$W/new-york-latest.osm.pbf" -mtime +25)" ]; then
  echo "== downloading Geofabrik New York extract =="
  curl -fL --progress-bar -o "$W/new-york-latest.osm.pbf" https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf
fi
echo "== NYC box, roads with maxspeed =="
osmium extract -b "$BBOX" --overwrite -o "$W/nyc.osm.pbf" "$W/new-york-latest.osm.pbf"
osmium tags-filter --overwrite -o "$W/nyc-maxspeed.osm.pbf" "$W/nyc.osm.pbf" w/highway w/maxspeed --remove-tags
osmium tags-filter --overwrite -o "$W/nyc-maxspeed2.osm.pbf" "$W/nyc-maxspeed.osm.pbf" w/maxspeed
osmium export --overwrite -f geojsonseq -o "$W/nyc-maxspeed.geojsonseq" "$W/nyc-maxspeed2.osm.pbf" --geometry-types=linestring
echo "== tiling =="
python3 -I scripts/tile_speed_limits.py "$W/nyc-maxspeed.geojsonseq" build.nosync/tiles "$BBOX"
