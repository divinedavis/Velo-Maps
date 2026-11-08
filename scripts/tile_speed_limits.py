#!/usr/bin/env python3
"""geojsonseq of OSM ways with maxspeed → one JSON per 0.01° tile (matches SpeedLimitCache.Tile).
A way goes in every tile its points fall in (grown by ~30 m, as the app does).
  tile_speed_limits.py in.geojsonseq outdir minLon,minLat,maxLon,maxLat
"""
import json, math, os, sys
from collections import defaultdict

SIZE, MARGIN = 0.01, 0.0003
src, out, bbox = sys.argv[1], sys.argv[2], [float(x) for x in sys.argv[3].split(",")]
tiles = defaultdict(list)
n = 0
with open(src) as f:
    for line in f:
        line = line.lstrip("\x1e").strip()
        if not line:
            continue
        feat = json.loads(line)
        ms = feat["properties"].get("maxspeed")
        coords = feat["geometry"]["coordinates"]
        if not ms or len(coords) < 2:
            continue
        way = {"tags": {"maxspeed": ms}, "geometry": [{"lat": round(c[1], 6), "lon": round(c[0], 6)} for c in coords]}
        keys = set()
        for c in coords:
            for dlat in (-MARGIN, 0, MARGIN):
                for dlon in (-MARGIN, 0, MARGIN):
                    keys.add((math.floor((c[1] + dlat) / SIZE), math.floor((c[0] + dlon) / SIZE)))
        for k in keys:
            tiles[k].append(way)
        n += 1
os.makedirs(out, exist_ok=True)
lat0, lat1 = math.floor(bbox[1] / SIZE), math.floor(bbox[3] / SIZE)
lon0, lon1 = math.floor(bbox[0] / SIZE), math.floor(bbox[2] / SIZE)
written = nonempty = 0
for la in range(lat0, lat1 + 1):
    for lo in range(lon0, lon1 + 1):
        ways = tiles.get((la, lo), [])
        with open(os.path.join(out, f"{la}_{lo}.json"), "w") as f:
            json.dump({"ways": ways}, f, separators=(",", ":"))
        written += 1
        nonempty += bool(ways)
with open(os.path.join(out, "coverage.json"), "w") as f:
    json.dump({"bbox": bbox, "tileSize": SIZE, "lat": [lat0, lat1], "lon": [lon0, lon1]}, f)
print(f"{n} ways with maxspeed → {written} tiles ({nonempty} with roads) in {out}")
