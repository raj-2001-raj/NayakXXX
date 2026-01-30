-- =====================================================
-- VOTING RULES UPDATE
-- 1. Reporter cannot vote on their own anomaly
-- 2. Other users can vote once, then only remove
-- 3. After removing, they can vote again
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
  v_reporter_id uuid;
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

  -- Check if anomaly exists and get reporter
  SELECT user_id INTO v_reporter_id
  FROM anomalies 
  WHERE id = p_anomaly_id;
  
  IF v_reporter_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Anomaly not found'
    );
  END IF;

  -- RULE 1: Reporter cannot vote on their own anomaly
  IF v_user_id = v_reporter_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'You cannot vote on your own report. Use status update instead.'
    );
  END IF;

  -- Check for existing vote
  SELECT vote_type INTO v_existing_vote
  FROM anomaly_votes
  WHERE anomaly_id = p_anomaly_id AND user_id = v_user_id;

  IF v_existing_vote IS NOT NULL THEN
    -- User already voted
    IF v_existing_vote = p_vote_type THEN
      -- RULE 2: Same vote clicked = Remove vote (toggle off)
      DELETE FROM anomaly_votes
      WHERE anomaly_id = p_anomaly_id AND user_id = v_user_id;
      v_action := 'removed';
    ELSE
      -- RULE 2: Different vote = Not allowed (must remove first)
      RETURN jsonb_build_object(
        'success', false,
        'message', 'Remove your current vote first before changing it'
      );
    END IF;
  ELSE
    -- RULE 3: No existing vote = Can vote
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

  -- Determine verified status (score > 0.5 AND at least 3 upvotes)
  v_verified := (v_verification_score > 0.5) AND (v_upvotes >= 3);

  -- Update anomaly with new counts
  UPDATE anomalies
  SET 
    upvotes = v_upvotes,
    downvotes = v_downvotes,
    verification_score = v_verification_score,
    verified = v_verified,
    last_verified_at = CASE WHEN v_action = 'added' THEN now() ELSE last_verified_at END
  WHERE id = p_anomaly_id;

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'action', v_action,
    'message', CASE 
      WHEN v_action = 'removed' THEN 'Vote removed. You can vote again.'
      ELSE 'Vote recorded. Click again to remove.'
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
-- FUNCTION: Reporter can update anomaly status
-- =====================================================

CREATE OR REPLACE FUNCTION public.update_anomaly_status_by_reporter(
  p_anomaly_id uuid,
  p_status text -- 'still_there' or 'resolved'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_reporter_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Not authenticated');
  END IF;

  -- Get reporter
  SELECT user_id INTO v_reporter_id FROM anomalies WHERE id = p_anomaly_id;
  
  IF v_reporter_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Anomaly not found');
  END IF;

  -- Only reporter can update status
  IF v_user_id != v_reporter_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Only the reporter can update status');
  END IF;

  IF p_status = 'resolved' THEN
    -- Mark as resolved (will be hidden/expired)
    UPDATE anomalies
    SET expires_at = now() + interval '1 day',
        verified = false
    WHERE id = p_anomaly_id;
    
    RETURN jsonb_build_object(
      'success', true, 
      'message', 'Marked as resolved. Thank you for updating!'
    );
  ELSE
    -- Still there - boost visibility
    UPDATE anomalies
    SET last_verified_at = now(),
        expires_at = NULL
    WHERE id = p_anomaly_id;
    
    RETURN jsonb_build_object(
      'success', true, 
      'message', 'Confirmed issue still exists'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_anomaly_status_by_reporter(uuid, text) TO authenticated;

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';

-- Verify
SELECT proname, pronargs FROM pg_proc WHERE proname IN ('upsert_anomaly_vote', 'update_anomaly_status_by_reporter');
