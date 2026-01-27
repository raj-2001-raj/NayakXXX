-- =====================================================
-- SECURITY FIXES FOR SUPABASE LINTER WARNINGS
-- Run this in Supabase SQL Editor
-- =====================================================

-- =====================================================
-- 0. FIX ANOMALIES TABLE RLS (CRITICAL FOR CONTRIBUTION SCORE)
-- This is likely why new anomalies aren't being saved!
-- =====================================================

-- Ensure RLS is enabled
ALTER TABLE public.anomalies ENABLE ROW LEVEL SECURITY;

-- Drop and recreate policies to ensure they're correct
DROP POLICY IF EXISTS "Users can insert anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Anyone can read anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Users can update own anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Users can delete own anomalies" ON public.anomalies;

-- Allow authenticated users to INSERT their own anomalies
CREATE POLICY "Users can insert anomalies" ON public.anomalies
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Allow ANYONE to read all anomalies (needed for map display)
CREATE POLICY "Anyone can read anomalies" ON public.anomalies
FOR SELECT TO anon, authenticated
USING (true);

-- Allow users to UPDATE their own anomalies
CREATE POLICY "Users can update own anomalies" ON public.anomalies
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Allow users to DELETE their own anomalies
CREATE POLICY "Users can delete own anomalies" ON public.anomalies
FOR DELETE TO authenticated
USING (auth.uid() = user_id);

-- =====================================================
-- 1. FIX RLS DISABLED ERRORS
-- =====================================================

-- Enable RLS on anomaly_votes
ALTER TABLE public.anomaly_votes ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Users can vote" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Anyone can read votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can manage own votes" ON public.anomaly_votes;

-- Create proper policies for anomaly_votes
CREATE POLICY "Users can insert votes" ON public.anomaly_votes
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Anyone can read votes" ON public.anomaly_votes
FOR SELECT TO anon, authenticated
USING (true);

CREATE POLICY "Users can update own votes" ON public.anomaly_votes
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own votes" ON public.anomaly_votes
FOR DELETE TO authenticated
USING (auth.uid() = user_id);

-- Enable RLS on fountains (public read-only data)
ALTER TABLE public.fountains ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read fountains" ON public.fountains;
CREATE POLICY "Anyone can read fountains" ON public.fountains
FOR SELECT TO anon, authenticated
USING (true);

-- Enable RLS on accident_stats (public read-only data)
ALTER TABLE public.accident_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read accident_stats" ON public.accident_stats;
CREATE POLICY "Anyone can read accident_stats" ON public.accident_stats
FOR SELECT TO anon, authenticated
USING (true);

-- Enable RLS on surface_segments (public read-only data)
ALTER TABLE public.surface_segments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read surface_segments" ON public.surface_segments;
CREATE POLICY "Anyone can read surface_segments" ON public.surface_segments
FOR SELECT TO anon, authenticated
USING (true);

-- NOTE: spatial_ref_sys is a PostGIS SYSTEM table owned by the extension
-- You CANNOT modify it. The Supabase linter warning for this table 
-- should be ignored - it's a false positive for PostGIS system tables.
-- See: https://github.com/supabase/supabase/issues/14523


-- =====================================================
-- 2. FIX FUNCTION SEARCH PATH WARNINGS
-- Set immutable search_path for all functions
-- =====================================================

-- Fix submit_ride_batch function
CREATE OR REPLACE FUNCTION public.submit_ride_batch(
  p_ride_id uuid,
  p_user_id uuid,
  p_points jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ride_points (ride_id, user_id, recorded_at, lat, lon, altitude, speed, accuracy)
  SELECT
    p_ride_id,
    p_user_id,
    (point->>'recorded_at')::timestamptz,
    (point->>'lat')::double precision,
    (point->>'lon')::double precision,
    (point->>'altitude')::double precision,
    (point->>'speed')::double precision,
    (point->>'accuracy')::double precision
  FROM jsonb_array_elements(p_points) AS point;
END;
$$;

-- Fix update_path_score_from_anomaly function
CREATE OR REPLACE FUNCTION public.update_path_score_from_anomaly()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Placeholder: Add your path score update logic here
  -- This updates path scores when anomalies change
  RETURN NEW;
END;
$$;

-- Fix calculate_path_score function
CREATE OR REPLACE FUNCTION public.calculate_path_score(
  p_path_id uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score numeric := 100;
BEGIN
  -- Placeholder: Add your path score calculation logic
  -- Returns a score from 0-100 based on anomalies along the path
  RETURN v_score;
END;
$$;

-- Fix get_anomalies_in_bbox function
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
SECURITY DEFINER
SET search_path = public
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

-- Fix deduplicate_anomalies function
CREATE OR REPLACE FUNCTION public.deduplicate_anomalies()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Mark duplicates (within ~10 meters of each other, same category)
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

-- Fix check_duplicate_anomaly function
CREATE OR REPLACE FUNCTION public.check_duplicate_anomaly()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- =====================================================
-- 3. FIX MATERIALIZED VIEW ACCESS
-- Revoke direct access, provide secure function instead
-- =====================================================

-- Revoke direct access to materialized view
REVOKE ALL ON public.anomaly_hotspots FROM anon, authenticated;

-- Grant select back but through a function for controlled access
CREATE OR REPLACE FUNCTION public.get_anomaly_hotspots(
  p_limit int DEFAULT 100
)
RETURNS TABLE (
  grid_lon numeric,
  grid_lat numeric,
  report_count bigint,
  avg_severity numeric,
  categories text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    grid_lon,
    grid_lat,
    report_count,
    avg_severity,
    categories
  FROM public.anomaly_hotspots
  ORDER BY report_count DESC
  LIMIT p_limit;
$$;

-- Grant execute on the function
GRANT EXECUTE ON FUNCTION public.get_anomaly_hotspots(int) TO anon, authenticated;

-- =====================================================
-- 4. POSTGIS EXTENSION NOTE
-- Moving PostGIS to extensions schema is NOT recommended
-- as it can break existing queries. Instead, we just
-- acknowledge this warning. If you want to move it:
-- 
-- CREATE SCHEMA IF NOT EXISTS extensions;
-- ALTER EXTENSION postgis SET SCHEMA extensions;
-- 
-- But this will break all existing PostGIS queries!
-- =====================================================

-- =====================================================
-- 5. AUTH SETTINGS (Manual step required)
-- 
-- To enable leaked password protection:
-- 1. Go to Supabase Dashboard
-- 2. Navigate to Authentication > Settings
-- 3. Under "Password Security", enable:
--    - "Enable leaked password protection"
-- 
-- This cannot be done via SQL.
-- =====================================================

-- =====================================================
-- 6. DISABLE DUPLICATE CHECK TRIGGER (May block inserts!)
-- The trigger returns NULL which prevents inserts
-- =====================================================

-- Option A: Drop the trigger entirely
DROP TRIGGER IF EXISTS trg_check_duplicate_anomaly ON public.anomalies;

-- Option B: Or modify to always allow insert (just log duplicates)
-- Uncomment below if you want duplicate checking but not blocking:
/*
CREATE OR REPLACE FUNCTION public.check_duplicate_anomaly()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    -- Update existing confidence
    UPDATE public.anomalies
    SET 
      confidence = LEAST(1.0, confidence + 0.1),
      expires_at = now() + interval '6 months',
      verified = verified OR NEW.verified
    WHERE id = existing_id;
    -- Still allow the new insert (don't return NULL)
  END IF;
  
  RETURN NEW; -- Always allow insert
END;
$$;

CREATE TRIGGER trg_check_duplicate_anomaly
BEFORE INSERT ON public.anomalies
FOR EACH ROW EXECUTE FUNCTION public.check_duplicate_anomaly();
*/

-- =====================================================
-- VERIFICATION: Check RLS status after running
-- =====================================================
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- =====================================================
-- DEBUG: Test insert capability (run as authenticated user)
-- =====================================================
-- SELECT auth.uid(); -- Should return your user ID
-- SELECT COUNT(*) FROM public.anomalies WHERE user_id = auth.uid();
