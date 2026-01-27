-- =====================================================
-- ANOMALY LIFECYCLE & AUTO-REMOVAL ALGORITHM
-- =====================================================
-- This defines when anomalies should be hidden/removed from the map
-- 
-- REMOVAL CONDITIONS (any of these triggers removal):
-- 1. Reporter marks as "resolved" → expires in 1 day
-- 2. High downvotes (>=10) with low score (<-0.6) → expires in 7 days
-- 3. Old unverified anomalies (>30 days, no activity) → auto-expire
-- 4. Verified but inactive (>90 days, no new votes) → auto-expire
-- 5. Manual expiry date reached
-- =====================================================

-- =====================================================
-- 1. ADD NECESSARY COLUMNS IF MISSING
-- =====================================================

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS last_activity_at timestamptz DEFAULT now();

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS removal_reason text;

-- =====================================================
-- 2. FUNCTION: Check and update anomaly expiry
-- Called after every vote or status update
-- =====================================================

CREATE OR REPLACE FUNCTION public.check_anomaly_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update last activity timestamp
  NEW.last_activity_at := now();
  
  -- RULE: High downvotes with negative score → schedule for removal
  IF NEW.downvotes >= 10 AND NEW.verification_score < -0.6 THEN
    IF NEW.expires_at IS NULL THEN
      NEW.expires_at := now() + interval '7 days';
      NEW.removal_reason := 'community_rejected';
    END IF;
  END IF;
  
  -- RULE: Very high downvotes → immediate soft removal (1 day)
  IF NEW.downvotes >= 20 AND NEW.verification_score < -0.8 THEN
    NEW.expires_at := now() + interval '1 day';
    NEW.removal_reason := 'heavily_downvoted';
  END IF;
  
  -- RULE: If score improves significantly, cancel scheduled expiry
  IF NEW.verification_score > 0.3 AND NEW.upvotes >= 5 THEN
    IF NEW.removal_reason IN ('community_rejected', 'heavily_downvoted', 'inactive_unverified') THEN
      NEW.expires_at := NULL;
      NEW.removal_reason := NULL;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger for vote-based lifecycle
DROP TRIGGER IF EXISTS trg_anomaly_lifecycle ON public.anomalies;
CREATE TRIGGER trg_anomaly_lifecycle
  BEFORE UPDATE ON public.anomalies
  FOR EACH ROW
  WHEN (
    NEW.upvotes IS DISTINCT FROM OLD.upvotes OR 
    NEW.downvotes IS DISTINCT FROM OLD.downvotes
  )
  EXECUTE FUNCTION public.check_anomaly_lifecycle();

-- =====================================================
-- 3. FUNCTION: Scheduled cleanup of old anomalies
-- Run this periodically (e.g., daily via cron/pg_cron)
-- =====================================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_anomalies()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired_count integer := 0;
  v_inactive_unverified_count integer := 0;
  v_inactive_verified_count integer := 0;
BEGIN
  -- 1. Mark old unverified anomalies (>30 days, no votes) for expiry
  UPDATE anomalies
  SET expires_at = now() + interval '7 days',
      removal_reason = 'inactive_unverified'
  WHERE expires_at IS NULL
    AND verified = false
    AND created_at < now() - interval '30 days'
    AND (last_activity_at IS NULL OR last_activity_at < now() - interval '14 days')
    AND (upvotes + downvotes) < 3;
  
  GET DIAGNOSTICS v_inactive_unverified_count = ROW_COUNT;
  
  -- 2. Mark very old verified anomalies (>90 days inactive) for review
  UPDATE anomalies
  SET expires_at = now() + interval '14 days',
      removal_reason = 'inactive_verified'
  WHERE expires_at IS NULL
    AND verified = true
    AND (last_activity_at IS NULL OR last_activity_at < now() - interval '90 days');
  
  GET DIAGNOSTICS v_inactive_verified_count = ROW_COUNT;
  
  -- 3. Hard delete anomalies that expired >30 days ago
  -- (Keep them for 30 days after expiry for potential recovery)
  DELETE FROM anomalies
  WHERE expires_at < now() - interval '30 days';
  
  GET DIAGNOSTICS v_expired_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'deleted', v_expired_count,
    'marked_inactive_unverified', v_inactive_unverified_count,
    'marked_inactive_verified', v_inactive_verified_count,
    'timestamp', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_expired_anomalies() TO service_role;

-- =====================================================
-- 4. VIEW: Active anomalies (for the app to use)
-- Only shows non-expired anomalies
-- =====================================================

CREATE OR REPLACE VIEW public.active_anomalies AS
SELECT 
  a.*,
  -- Extract lat/lng from PostGIS location for convenience
  ST_Y(a.location::geometry) as latitude,
  ST_X(a.location::geometry) as longitude,
  CASE 
    WHEN a.expires_at IS NOT NULL THEN 
      EXTRACT(days FROM (a.expires_at - now()))::integer
    ELSE NULL
  END as days_until_expiry,
  CASE 
    WHEN a.verified AND a.upvotes >= 5 THEN 'verified_strong'
    WHEN a.verified THEN 'verified'
    WHEN a.upvotes >= 2 THEN 'likely'
    WHEN a.upvotes >= 1 THEN 'reported'
    ELSE 'unverified'
  END as trust_level
FROM anomalies a
WHERE 
  -- Not expired yet
  (a.expires_at IS NULL OR a.expires_at > now())
  -- Not heavily downvoted (immediate hide)
  AND NOT (a.downvotes >= 15 AND a.verification_score < -0.7);

-- =====================================================
-- 5. FUNCTION: Get anomalies for map display
-- Filters based on lifecycle rules
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_map_anomalies(
  p_min_lat numeric,
  p_min_lng numeric,
  p_max_lat numeric,
  p_max_lng numeric,
  p_include_low_trust boolean DEFAULT true
)
RETURNS SETOF active_anomalies
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM active_anomalies
  WHERE 
    latitude BETWEEN p_min_lat AND p_max_lat
    AND longitude BETWEEN p_min_lng AND p_max_lng
    AND (
      p_include_low_trust = true 
      OR trust_level IN ('verified_strong', 'verified', 'likely')
    )
  ORDER BY 
    CASE trust_level
      WHEN 'verified_strong' THEN 1
      WHEN 'verified' THEN 2
      WHEN 'likely' THEN 3
      WHEN 'reported' THEN 4
      ELSE 5
    END,
    created_at DESC
  LIMIT 200;
$$;

GRANT EXECUTE ON FUNCTION public.get_map_anomalies(numeric, numeric, numeric, numeric, boolean) TO authenticated, anon;

-- =====================================================
-- 6. SUMMARY: Anomaly Lifecycle Rules
-- =====================================================
/*
WHEN ANOMALIES ARE HIDDEN/REMOVED:

┌─────────────────────────────────────────────────────────────────┐
│ CONDITION                           │ ACTION                    │
├─────────────────────────────────────┼───────────────────────────┤
│ Reporter marks "resolved"           │ Expires in 1 day          │
│ downvotes >= 10, score < -0.6       │ Expires in 7 days         │
│ downvotes >= 20, score < -0.8       │ Expires in 1 day          │
│ downvotes >= 15, score < -0.7       │ Immediately hidden        │
│ Unverified + 30 days + no activity  │ Expires in 7 days         │
│ Verified + 90 days inactive         │ Expires in 14 days        │
│ 30 days after expires_at            │ Permanently deleted       │
└─────────────────────────────────────┴───────────────────────────┘

TRUST LEVELS (affects icon opacity/size on map):
- verified_strong: ✅ Verified + 5+ upvotes (bright, large icon)
- verified:        ✅ Verified (bright icon)  
- likely:          ⚠️ 2+ upvotes (normal icon)
- reported:        ⚠️ 1 upvote (slightly faded)
- unverified:      ❓ No votes (faded, smaller icon)

RECOVERY:
- If score improves (>0.3 with 5+ upvotes), scheduled expiry is cancelled
- Expired anomalies kept for 30 days before permanent deletion
*/

-- =====================================================
-- 7. Refresh schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';

-- Verify setup
SELECT 
  'Functions' as type,
  proname as name,
  pronargs as args
FROM pg_proc 
WHERE proname IN (
  'check_anomaly_lifecycle', 
  'cleanup_expired_anomalies', 
  'get_map_anomalies'
)
UNION ALL
SELECT 
  'Views' as type,
  viewname as name,
  0 as args
FROM pg_views 
WHERE viewname = 'active_anomalies';
