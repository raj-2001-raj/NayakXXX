# best_bike_paths

Best Bike Paths is a Flutter app that tracks rides, detects road anomalies, and summarizes ride stats.

## Background ride tracking

While a ride is active, the app keeps a foreground location service running so
navigation and tracking continue in the background. If the OS force-stops the
app, tracking will pause and resume when the app is reopened.

Make sure location services are enabled and the app is allowed to access
location **Always** (or **While Using** on iOS with background enabled).

## App Navigation

- **Home**: dashboard stats and start ride button.
- **Map**: live map, destination search, and ride recording.
- **History**: list of past rides with detailed summary cards.
- **Profile**: user account details and stats.

Tap a ride in **History** to open the **Ride Details** screen, which shows:

- Ride timing, start/end points, duration, straight-line distance, and average speed.
- Anomalies reported during the ride (category, type, severity, verified status).
- A mini map preview with start/end markers.

## Dataset Layers (Safety • Comfort • Amenities)

This project supports loading official datasets into Supabase to make routing smarter:

- **Accident stats** → `accident_stats`
- **Water fountains** → `fountains`
- **Cobblestone / rough surface segments** → `surface_segments`

### 1) Create tables in Supabase

Open Supabase SQL editor and run:

```
tools/schema.sql
```

### 2) Import datasets

Install the importer dependencies:

```bash
python -m pip install -r tools/requirements.txt
```

Set your Supabase credentials in a `.env` file:

```
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

Then run:

```bash
python tools/import_datasets.py
```

### Notes

- The provided accident CSV is city‑level (no coordinates). It’s stored for analytics in `accident_stats`.
- For per‑street safety scoring, you’ll need a geocoded accident dataset (street/lat‑lon).

## Path Score Calculation (0–100)

Path Score is a safety/quality rating stored per road segment. Higher is better.

- **Green (Optimal)**: > 80
- **Red (High Risk)**: < 40

### How it’s computed

Each segment starts at 100, then penalties and bonuses are applied:

- Verified anomalies (potholes) reduce the score.
- Manual reports (Broken Glass, Cobblestones) apply specific penalties.
- Time‑dependent issues (e.g., Broken Lights at night) can be weighted in the function.
- Positive feedback ("Perfect" surface) adds a bonus.

### Enable the backend trigger

Run the SQL below in Supabase (SQL editor):

```
tools/path_score.sql
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
