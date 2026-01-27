-- =====================================================
-- FIX: Update upsert_anomaly_vote to handle missing profiles table
-- Run this in Supabase SQL Editor
-- =====================================================

-- Drop and recreate the function without the profiles dependency
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

  -- Calculate verification score (-100 to +100)
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

  -- Note: Contribution points can be awarded separately if needed
  -- This function focuses only on voting to avoid dependency issues

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

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';

-- Verify the function exists
SELECT proname, pronargs FROM pg_proc WHERE proname = 'upsert_anomaly_vote';
