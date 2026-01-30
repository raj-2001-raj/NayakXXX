-- Dataset tables for accidents, fountains, and cobblestone surfaces
-- Run in Supabase SQL editor

create table if not exists public.accident_stats (
  id bigserial primary key,
  year int,
  comune text,
  data jsonb
);

create table if not exists public.fountains (
  id bigserial primary key,
  osm_id text unique,
  location geometry(Point, 4326),
  properties jsonb
);

create index if not exists fountains_location_gix
  on public.fountains using gist (location);

create table if not exists public.surface_segments (
  id bigserial primary key,
  osm_id text,
  surface text,
  highway text,
  name text,
  centroid geometry(Point, 4326),
  geometry jsonb,
  path_score numeric default 100,
  path_score_updated_at timestamptz
);

create index if not exists surface_segments_centroid_gix
  on public.surface_segments using gist (centroid);
