-- =====================================================
-- PERFORMANCE FIXES FOR SUPABASE LINTER WARNINGS
-- Run this in Supabase SQL Editor
-- =====================================================

-- =====================================================
-- 1. FIX DUPLICATE POLICIES ON ANOMALIES TABLE
-- Remove old policies, keep only optimized ones
-- =====================================================

-- Drop ALL existing policies on anomalies to start fresh
DROP POLICY IF EXISTS "Users can insert anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Users can insert their own anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Anyone can read anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Public can read verified anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Users can update own anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Users can update their own anomalies" ON public.anomalies;
DROP POLICY IF EXISTS "Users can delete own anomalies" ON public.anomalies;

-- Create OPTIMIZED policies using (SELECT auth.uid()) for better performance
-- This prevents re-evaluation for each row

-- INSERT: Users can only insert their own anomalies
CREATE POLICY "anomalies_insert_policy" ON public.anomalies
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

-- SELECT: Anyone can read all anomalies (single policy, not multiple!)
CREATE POLICY "anomalies_select_policy" ON public.anomalies
FOR SELECT TO anon, authenticated
USING (true);

-- UPDATE: Users can only update their own anomalies
CREATE POLICY "anomalies_update_policy" ON public.anomalies
FOR UPDATE TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

-- DELETE: Users can only delete their own anomalies
CREATE POLICY "anomalies_delete_policy" ON public.anomalies
FOR DELETE TO authenticated
USING (user_id = (SELECT auth.uid()));

-- =====================================================
-- 2. FIX DUPLICATE POLICIES ON ANOMALY_VOTES TABLE
-- =====================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can insert votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Anyone can read votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can update own votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can delete own votes" ON public.anomaly_votes;
DROP POLICY IF EXISTS "Users can manage own votes" ON public.anomaly_votes;

-- Create OPTIMIZED policies
CREATE POLICY "votes_insert_policy" ON public.anomaly_votes
FOR INSERT TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "votes_select_policy" ON public.anomaly_votes
FOR SELECT TO anon, authenticated
USING (true);

CREATE POLICY "votes_update_policy" ON public.anomaly_votes
FOR UPDATE TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "votes_delete_policy" ON public.anomaly_votes
FOR DELETE TO authenticated
USING (user_id = (SELECT auth.uid()));

-- =====================================================
-- 3. FIX RIDES TABLE POLICY
-- =====================================================

-- Drop existing policy
DROP POLICY IF EXISTS "Users can only access their own rides" ON public.rides;

-- Create OPTIMIZED policy
CREATE POLICY "rides_access_policy" ON public.rides
FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

-- =====================================================
-- 4. FIX DUPLICATE INDEX ON ANOMALIES
-- =====================================================

-- Keep anomalies_location_gix (newer naming convention), drop the old one
DROP INDEX IF EXISTS public.anomalies_geo_idx;

-- Verify remaining index exists
-- CREATE INDEX IF NOT EXISTS anomalies_location_gix 
-- ON public.anomalies USING gist (location);

-- =====================================================
-- VERIFICATION: Check policies after running
-- =====================================================

-- List all policies on anomalies table
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'anomalies'
ORDER BY policyname;

-- List all policies on anomaly_votes table
SELECT 
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies 
WHERE tablename = 'anomaly_votes'
ORDER BY policyname;

-- List all policies on rides table
SELECT 
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies 
WHERE tablename = 'rides'
ORDER BY policyname;

-- Check indexes on anomalies
SELECT 
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'anomalies'
ORDER BY indexname;
