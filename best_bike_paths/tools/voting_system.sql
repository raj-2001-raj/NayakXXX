-- =====================================================
-- COMPREHENSIVE ANOMALY VOTING SYSTEM
-- Run this in Supabase SQL Editor
-- A robust, scalable voting system for anomaly verification
-- =====================================================

-- =====================================================
-- 1. CREATE/FIX ANOMALY_VOTES TABLE
-- =====================================================

-- Drop and recreate the anomaly_votes table with proper structure
DROP TABLE IF EXISTS public.anomaly_votes CASCADE;

CREATE TABLE public.anomaly_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  anomaly_id uuid NOT NULL REFERENCES public.anomalies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vote_type text NOT NULL CHECK (vote_type IN ('upvote', 'downvote')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  -- Additional context for better voting
  proximity_meters numeric, -- How close was user to anomaly when voting
  comment text, -- Optional comment explaining vote
  UNIQUE(anomaly_id, user_id) -- One vote per user per anomaly
);

-- Create indexes for performance
CREATE INDEX idx_anomaly_votes_anomaly ON public.anomaly_votes(anomaly_id);
CREATE INDEX idx_anomaly_votes_user ON public.anomaly_votes(user_id);
CREATE INDEX idx_anomaly_votes_type ON public.anomaly_votes(vote_type);

-- Enable RLS
ALTER TABLE public.anomaly_votes ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Users can view all votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can insert own votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can update own votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can delete own votes" ON public.anomaly_votes;

-- Anyone can view vote counts (for transparency)
CREATE POLICY "Users can view all votes" ON public.anomaly_votes
FOR SELECT TO authenticated
USING (true);

-- Users can only insert their own votes
CREATE POLICY "Users can insert own votes" ON public.anomaly_votes
FOR INSERT TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Users can only update their own votes
CREATE POLICY "Users can update own votes" ON public.anomaly_votes
FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Users can only delete their own votes
CREATE POLICY "Users can delete own votes" ON public.anomaly_votes
FOR DELETE TO authenticated
USING ((SELECT auth.uid()) = user_id);

-- =====================================================
-- 2. ADD VOTE COLUMNS TO ANOMALIES TABLE IF MISSING
-- =====================================================

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS upvotes integer DEFAULT 0;

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS downvotes integer DEFAULT 0;

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS verification_score numeric DEFAULT 0;

ALTER TABLE public.anomalies 
ADD COLUMN IF NOT EXISTS last_verified_at timestamptz;

-- =====================================================
-- 3. FUNCTION: Upsert Vote (Insert or Update)
-- This is the main voting function - handles everything atomically
-- =====================================================

CREATE OR REPLACE FUNCTION public.upsert_anomaly_vote(
  p_anomaly_id uuid,
  p_vote_type text,
  p_proximity_meters numeric DEFAULT NULL,
  p_comment text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_existing_vote text;
  v_upvotes integer;
  v_downvotes integer;
  v_verification_score numeric;
  v_verified boolean;
  v_action text;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Not authenticated'
    );
  END IF;

  -- Check if anomaly exists
  IF NOT EXISTS (SELECT 1 FROM anomalies WHERE id = p_anomaly_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Anomaly not found'
    );
  END IF;

  -- Check for existing vote
  SELECT vote_type INTO v_existing_vote
  FROM anomaly_votes
  WHERE anomaly_id = p_anomaly_id AND user_id = v_user_id;

  IF v_existing_vote IS NOT NULL THEN
    IF v_existing_vote = p_vote_type THEN
      -- Same vote: Toggle off (remove vote)
      DELETE FROM anomaly_votes
      WHERE anomaly_id = p_anomaly_id AND user_id = v_user_id;
      v_action := 'removed';
    ELSE
      -- Different vote: Update
      UPDATE anomaly_votes
      SET vote_type = p_vote_type,
          updated_at = now(),
          proximity_meters = COALESCE(p_proximity_meters, proximity_meters),
          comment = COALESCE(p_comment, comment)
      WHERE anomaly_id = p_anomaly_id AND user_id = v_user_id;
      v_action := 'changed';
    END IF;
  ELSE
    -- New vote: Insert
    INSERT INTO anomaly_votes (anomaly_id, user_id, vote_type, proximity_meters, comment)
    VALUES (p_anomaly_id, v_user_id, p_vote_type, p_proximity_meters, p_comment);
    v_action := 'added';
  END IF;

  -- Recalculate vote counts
  SELECT 
    COALESCE(SUM(CASE WHEN vote_type = 'upvote' THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN vote_type = 'downvote' THEN 1 ELSE 0 END), 0)
  INTO v_upvotes, v_downvotes
  FROM anomaly_votes
  WHERE anomaly_id = p_anomaly_id;

  -- Calculate verification score
  -- Score ranges from -1 (definitely fixed) to +1 (definitely verified)
  -- Uses a weighted formula: more votes = more confidence
  IF (v_upvotes + v_downvotes) > 0 THEN
    v_verification_score := (v_upvotes - v_downvotes)::numeric / (v_upvotes + v_downvotes);
  ELSE
    v_verification_score := 0;
  END IF;

  -- Determine verified status
  -- Verified if: score > 0.5 AND at least 3 upvotes
  v_verified := (v_verification_score > 0.5) AND (v_upvotes >= 3);

  -- Update anomaly with new counts
  UPDATE anomalies
  SET 
    upvotes = v_upvotes,
    downvotes = v_downvotes,
    verification_score = v_verification_score,
    verified = v_verified,
    last_verified_at = CASE WHEN v_action != 'removed' THEN now() ELSE last_verified_at END
  WHERE id = p_anomaly_id;

  -- Award contribution points for voting (1 point per vote)
  IF v_action = 'added' THEN
    UPDATE profiles
    SET contribution_score = COALESCE(contribution_score, 0) + 1
    WHERE id = v_user_id;
  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'action', v_action,
    'message', CASE 
      WHEN v_action = 'removed' THEN 'Vote removed'
      WHEN v_action = 'changed' THEN 'Vote changed'
      ELSE 'Vote recorded'
    END,
    'upvotes', v_upvotes,
    'downvotes', v_downvotes,
    'verification_score', round(v_verification_score * 100),
    'verified', v_verified,
    'user_vote', CASE 
      WHEN v_action = 'removed' THEN NULL
      ELSE p_vote_type
    END
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.upsert_anomaly_vote(uuid, text, numeric, text) TO authenticated;

-- =====================================================
-- 4. FUNCTION: Get User's Vote on an Anomaly
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_user_anomaly_vote(p_anomaly_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT vote_type
  FROM anomaly_votes
  WHERE anomaly_id = p_anomaly_id AND user_id = (SELECT auth.uid())
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_anomaly_vote(uuid) TO authenticated;

-- =====================================================
-- 5. FUNCTION: Get Anomaly Vote Summary
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_anomaly_vote_summary(p_anomaly_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'anomaly_id', a.id,
    'upvotes', COALESCE(a.upvotes, 0),
    'downvotes', COALESCE(a.downvotes, 0),
    'verification_score', COALESCE(a.verification_score, 0),
    'verified', COALESCE(a.verified, false),
    'user_vote', (SELECT vote_type FROM anomaly_votes WHERE anomaly_id = p_anomaly_id AND user_id = (SELECT auth.uid())),
    'total_voters', (SELECT COUNT(*) FROM anomaly_votes WHERE anomaly_id = p_anomaly_id),
    'last_verified_at', a.last_verified_at
  )
  FROM anomalies a
  WHERE a.id = p_anomaly_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_anomaly_vote_summary(uuid) TO authenticated, anon;

-- =====================================================
-- 6. TRIGGER: Auto-expire anomalies with many downvotes
-- =====================================================

CREATE OR REPLACE FUNCTION public.check_anomaly_expiry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If downvotes >= 10 and score < -0.6, mark for expiry
  IF NEW.downvotes >= 10 AND NEW.verification_score < -0.6 THEN
    NEW.expires_at := now() + interval '7 days';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_anomaly_expiry ON public.anomalies;
CREATE TRIGGER trg_check_anomaly_expiry
  BEFORE UPDATE ON public.anomalies
  FOR EACH ROW
  WHEN (NEW.downvotes IS DISTINCT FROM OLD.downvotes)
  EXECUTE FUNCTION public.check_anomaly_expiry();

-- =====================================================
-- 7. VIEW: Anomalies with vote details for the app
-- =====================================================

CREATE OR REPLACE VIEW public.anomalies_with_votes AS
SELECT 
  a.*,
  COALESCE(a.upvotes, 0) as vote_up,
  COALESCE(a.downvotes, 0) as vote_down,
  COALESCE(a.verification_score, 0) as score,
  CASE 
    WHEN a.verified THEN 'verified'
    WHEN COALESCE(a.upvotes, 0) > 0 THEN 'partial'
    ELSE 'unverified'
  END as verification_status
FROM anomalies a
WHERE a.expires_at IS NULL OR a.expires_at > now();

-- =====================================================
-- 8. Refresh schema cache
-- =====================================================
NOTIFY pgrst, 'reload schema';

-- =====================================================
-- VERIFICATION: Check everything is set up
-- =====================================================

-- Show anomaly_votes table structure
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'anomaly_votes'
ORDER BY ordinal_position;

-- Show anomalies columns for voting
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'anomalies' 
AND column_name IN ('upvotes', 'downvotes', 'verified', 'verification_score', 'last_verified_at');

-- Test the upsert function exists
SELECT proname, pronargs FROM pg_proc WHERE proname = 'upsert_anomaly_vote';
