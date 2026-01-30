-- Path Score calculation for surface segments
-- Requires PostGIS extension enabled in Supabase

create extension if not exists postgis;

-- Base score for all segments
update public.surface_segments
set path_score = 100
where path_score is null;

-- Calculate a score for one segment id
create or replace function public.calculate_path_score(segment_id bigint)
returns numeric
language plpgsql
as $$
declare
  base_score numeric := 100;
  penalty numeric := 0;
  bonus numeric := 0;
  seg_centroid geometry;
begin
  select centroid into seg_centroid
  from public.surface_segments
  where id = segment_id;

  if seg_centroid is null then
    return base_score;
  end if;

  -- Penalize based on anomalies near the centroid
  select coalesce(sum(
    case
      when lower(a.category) = 'broken glass' then 12
      when lower(a.category) = 'cobblestones' then 8
      when lower(a.category) = 'broken lights' then 6
      when a.severity is not null and a.severity >= 8 then 12
      when a.severity is not null and a.severity >= 6 then 8
      when a.severity is not null and a.severity >= 4 then 4
      when a.severity is not null and a.severity >= 2 then 2
      else 3
    end
  ), 0)
  into penalty
  from public.anomalies a
  where st_dwithin(a.location::geometry, seg_centroid, 40);

  -- Bonus for positive feedback
  select coalesce(sum(
    case
      when lower(a.category) = 'perfect' then 5
      else 0
    end
  ), 0)
  into bonus
  from public.anomalies a
  where st_dwithin(a.location::geometry, seg_centroid, 40);

  base_score := greatest(0, least(100, base_score - penalty + bonus));
  return base_score;
end;
$$;

-- Update score on insert/update of anomalies
create or replace function public.update_path_score_from_anomaly()
returns trigger
language plpgsql
as $$
declare
  seg_id bigint;
begin
  select id into seg_id
  from public.surface_segments
  where st_dwithin(centroid, new.location::geometry, 40)
  order by st_distance(centroid, new.location::geometry)
  limit 1;

  if seg_id is not null then
    update public.surface_segments
    set path_score = public.calculate_path_score(seg_id),
        path_score_updated_at = now()
    where id = seg_id;
  end if;

  return new;
end;
$$;

create trigger trg_update_path_score
after insert or update on public.anomalies
for each row execute function public.update_path_score_from_anomaly();
