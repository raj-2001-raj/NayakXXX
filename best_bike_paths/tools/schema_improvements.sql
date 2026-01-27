-- Schema improvements for Best Bike Paths
-- Run in Supabase SQL Editor

-- Enable PostGIS if not already enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Add expiry to anomalies (old reports become stale)
ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS expires_at timestamptz DEFAULT (now() + interval '6 months');

-- 2. Add index for faster location queries
-- Note: If location is geography type, use geography_ops. If geometry, use gist
CREATE INDEX IF NOT EXISTS anomalies_location_gix 
ON public.anomalies USING gist (location);

-- 3. Add confidence score for auto-detected anomalies
ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS confidence numeric DEFAULT 0.6;

-- 4. Function to find anomalies within a bounding box (for route planning)
CREATE OR REPLACE FUNCTION public.get_anomalies_in_bbox(
  min_lon double precision,
  min_lat double precision,
  max_lon double precision,
  max_lat double precision,
  max_results int DEFAULT 500
)
RETURNS TABLE (
  id uuid,
  location geography,
  severity double precision,
  category text,
  verified boolean,
  confidence numeric
)
LANGUAGE sql
STABLE
AS $$
  SELECT 
    a.id,
    a.location,
    a.severity,
    a.category,
    a.verified,
    a.confidence
  FROM public.anomalies a
  WHERE ST_Intersects(
    a.location,
    ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)::geography
  )
    AND (a.expires_at IS NULL OR a.expires_at > now())
  ORDER BY a.created_at DESC
  LIMIT max_results;
$$;

-- 5. Function to deduplicate anomalies (merge nearby reports)
CREATE OR REPLACE FUNCTION public.deduplicate_anomalies()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Mark duplicates (within ~10 meters of each other, same category)
  -- Using 0.0001 degrees ≈ ~11 meters
  WITH duplicates AS (
    SELECT 
      a1.id,
      ROW_NUMBER() OVER (
        PARTITION BY a1.category, 
          ROUND(ST_X(a1.location::geometry)::numeric, 4),
          ROUND(ST_Y(a1.location::geometry)::numeric, 4)
        ORDER BY 
          CASE WHEN a1.verified THEN 0 ELSE 1 END,
          a1.created_at
      ) as rn
    FROM public.anomalies a1
  )
  DELETE FROM public.anomalies
  WHERE id IN (SELECT id FROM duplicates WHERE rn > 1);
END;
$$;

-- 6. Trigger to prevent duplicate inserts
CREATE OR REPLACE FUNCTION public.check_duplicate_anomaly()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  existing_id uuid;
BEGIN
  -- Check if there's already an anomaly within 15 meters with same category
  SELECT id INTO existing_id
  FROM public.anomalies
  WHERE category = NEW.category
    AND ST_DWithin(location, NEW.location, 15)
    AND (expires_at IS NULL OR expires_at > now())
  LIMIT 1;
  
  IF existing_id IS NOT NULL THEN
    -- Update existing instead of inserting duplicate
    UPDATE public.anomalies
    SET 
      confidence = LEAST(1.0, confidence + 0.1),
      expires_at = now() + interval '6 months',
      verified = verified OR NEW.verified
    WHERE id = existing_id;
    
    RETURN NULL; -- Prevent insert
  END IF;
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_duplicate_anomaly
BEFORE INSERT ON public.anomalies
FOR EACH ROW EXECUTE FUNCTION public.check_duplicate_anomaly();

-- 7. Row Level Security for anomalies
ALTER TABLE public.anomalies ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert
CREATE POLICY "Users can insert anomalies" ON public.anomalies
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Allow anyone to read anomalies (for route planning)
CREATE POLICY "Anyone can read anomalies" ON public.anomalies
FOR SELECT TO anon, authenticated
USING (true);

-- Allow users to update their own anomalies
CREATE POLICY "Users can update own anomalies" ON public.anomalies
FOR UPDATE TO authenticated
USING (auth.uid() = user_id);

-- 8. Materialized view for hot spots (areas with many issues)
CREATE MATERIALIZED VIEW IF NOT EXISTS public.anomaly_hotspots AS
SELECT 
  ROUND(ST_X(location::geometry)::numeric, 3) as grid_lon,
  ROUND(ST_Y(location::geometry)::numeric, 3) as grid_lat,
  COUNT(*) as report_count,
  AVG(severity) as avg_severity,
  array_agg(DISTINCT category) as categories
FROM public.anomalies
WHERE expires_at IS NULL OR expires_at > now()
GROUP BY 
  ROUND(ST_X(location::geometry)::numeric, 3),
  ROUND(ST_Y(location::geometry)::numeric, 3)
HAVING COUNT(*) >= 3;

-- Refresh hotspots periodically (run via cron or manually)
-- REFRESH MATERIALIZED VIEW public.anomaly_hotspots;

-- =========================================
-- 9. VERIFICATION VOTING SYSTEM
-- =========================================

-- Add vote count columns to anomalies table
ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS upvotes integer DEFAULT 0;

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS downvotes integer DEFAULT 0;

-- Create votes table
CREATE TABLE IF NOT EXISTS public.anomaly_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  anomaly_id uuid NOT NULL REFERENCES public.anomalies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vote_type text NOT NULL CHECK (vote_type IN ('upvote', 'downvote')),
  created_at timestamptz DEFAULT now(),
  UNIQUE(anomaly_id, user_id)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_anomaly_votes_anomaly 
ON public.anomaly_votes(anomaly_id);

CREATE INDEX IF NOT EXISTS idx_anomaly_votes_user 
ON public.anomaly_votes(user_id);

-- RLS for votes
ALTER TABLE public.anomaly_votes ENABLE ROW LEVEL SECURITY;

-- Users can insert their own votes
CREATE POLICY "Users can vote" ON public.anomaly_votes
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can see all votes
CREATE POLICY "Anyone can read votes" ON public.anomaly_votes
FOR SELECT TO authenticated
USING (true);

-- Users can update/delete their own votes
CREATE POLICY "Users can manage own votes" ON public.anomaly_votes
FOR ALL TO authenticated
USING (auth.uid() = user_id);
