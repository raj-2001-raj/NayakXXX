import csv
import json
import os
from typing import Any, Dict, Iterable, List, Tuple

from supabase import create_client
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise SystemExit(
        "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars. "
        "Create a .env file or export them before running."
    )

client = create_client(SUPABASE_URL, SUPABASE_KEY)

SURFACE_ALLOWED = {
    "cobblestone",
    "sett",
    "setts",
    "paving_stones",
    "unhewn_cobblestone",
}


def batch_insert(table: str, rows: List[Dict[str, Any]], batch_size: int = 500) -> None:
    for start in range(0, len(rows), batch_size):
        chunk = rows[start : start + batch_size]
        if not chunk:
            continue
        client.table(table).insert(chunk).execute()


def to_wkt_point(lon: float, lat: float) -> str:
    return f"SRID=4326;POINT({lon} {lat})"


def centroid_from_coords(coords: List[List[float]]) -> Tuple[float, float]:
    if not coords:
        return 0.0, 0.0
    lon_sum = 0.0
    lat_sum = 0.0
    for lon, lat in coords:
        lon_sum += lon
        lat_sum += lat
    return lon_sum / len(coords), lat_sum / len(coords)


def load_accidents(csv_path: str) -> None:
    rows: List[Dict[str, Any]] = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            year = int(row.get("ANNO_INCIDENTE") or 0)
            comune = row.get("COMUNE")
            rows.append({"year": year, "comune": comune, "data": row})

    batch_insert("accident_stats", rows, batch_size=200)


def load_fountains(geojson_path: str) -> None:
    with open(geojson_path, encoding="utf-8") as f:
        data = json.load(f)

    rows: List[Dict[str, Any]] = []
    for feature in data.get("features", []):
        geom = feature.get("geometry") or {}
        coords = geom.get("coordinates") or []
        if geom.get("type") != "Point" or len(coords) < 2:
            continue
        lon, lat = coords[0], coords[1]
        rows.append(
            {
                "osm_id": feature.get("id"),
                "location": to_wkt_point(lon, lat),
                "properties": feature.get("properties") or {},
            }
        )

    batch_insert("fountains", rows)


def load_surfaces(geojson_path: str) -> None:
    with open(geojson_path, encoding="utf-8") as f:
        data = json.load(f)

    rows: List[Dict[str, Any]] = []
    for feature in data.get("features", []):
        props = feature.get("properties") or {}
        surface = (props.get("surface") or "").lower()
        if surface not in SURFACE_ALLOWED:
            continue

        geom = feature.get("geometry") or {}
        coords: List[List[float]] = []
        if geom.get("type") == "LineString":
            coords = geom.get("coordinates") or []
        elif geom.get("type") == "Polygon":
            rings = geom.get("coordinates") or []
            if rings:
                coords = rings[0]
        elif geom.get("type") == "MultiLineString":
            lines = geom.get("coordinates") or []
            if lines:
                coords = lines[0]

        if not coords:
            continue

        lon, lat = centroid_from_coords(coords)
        rows.append(
            {
                "osm_id": feature.get("id"),
                "surface": surface,
                "highway": props.get("highway"),
                "name": props.get("name"),
                "centroid": to_wkt_point(lon, lat),
                "geometry": geom,
            }
        )

    batch_insert("surface_segments", rows, batch_size=200)


def main() -> None:
    base = os.environ.get("DATASET_BASE", "/Users/rahul/Desktop")
    accident_csv = os.path.join(base, "INCIDENTI_STRADALI_nel_COMUNE_MILANO_20260125.csv")
    fountains_geojson = os.path.join(base, "export water fountains.geojson")
    surfaces_geojson = os.path.join(base, "export road surface.geojson")

    print("Importing accidents...")
    load_accidents(accident_csv)
    print("Importing fountains...")
    load_fountains(fountains_geojson)
    print("Importing cobblestones...")
    load_surfaces(surfaces_geojson)
    print("Done.")


if __name__ == "__main__":
    main()
