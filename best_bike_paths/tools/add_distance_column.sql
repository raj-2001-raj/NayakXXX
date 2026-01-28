-- Add distance_km column to rides table if it doesn't exist
-- Run this in Supabase SQL Editor

-- Add distance_km column to rides table
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS distance_km numeric DEFAULT 0;

-- Add end_lat and end_lon columns if they don't exist
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS end_lat double precision;

ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS end_lon double precision;

-- Add completed and reached_destination columns
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS completed boolean DEFAULT false;

ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS reached_destination boolean DEFAULT false;

-- Backfill: Set end coordinates to start coordinates for rides that have end_time but no end coordinates
-- This is a placeholder - ideally end coords should be tracked during the ride
UPDATE public.rides 
SET end_lat = start_lat, end_lon = start_lon
WHERE end_time IS NOT NULL 
  AND (end_lat IS NULL OR end_lon IS NULL)
  AND start_lat IS NOT NULL 
  AND start_lon IS NOT NULL;

-- Mark rides as completed if they have an end_time
UPDATE public.rides 
SET completed = true
WHERE end_time IS NOT NULL AND (completed IS NULL OR completed = false);

-- Create profiles table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  total_distance_km numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add total_distance_km to profiles table if it already exists but column is missing
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS total_distance_km numeric DEFAULT 0;

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- RLS policies for profiles
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;

CREATE POLICY "Users can view own profile" ON public.profiles
FOR SELECT TO authenticated
USING ((SELECT auth.uid()) = id);

CREATE POLICY "Users can update own profile" ON public.profiles
FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = id)
WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Users can insert own profile" ON public.profiles
FOR INSERT TO authenticated
WITH CHECK ((SELECT auth.uid()) = id);

-- Create user_stats table if it doesn't exist (fallback for distance tracking)
CREATE TABLE IF NOT EXISTS public.user_stats (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  total_distance_km numeric DEFAULT 0,
  total_rides integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS on user_stats
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_stats
DROP POLICY IF EXISTS "Users can view own stats" ON public.user_stats;
DROP POLICY IF EXISTS "Users can update own stats" ON public.user_stats;
DROP POLICY IF EXISTS "Users can insert own stats" ON public.user_stats;

CREATE POLICY "Users can view own stats" ON public.user_stats
FOR SELECT TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update own stats" ON public.user_stats
FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert own stats" ON public.user_stats
FOR INSERT TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Optional: Recalculate total distance for existing users from rides table
-- This updates profiles.total_distance_km based on existing rides
DO $$
DECLARE
  user_record RECORD;
  total_dist numeric;
BEGIN
  FOR user_record IN SELECT DISTINCT user_id FROM public.rides LOOP
    SELECT COALESCE(SUM(distance_km), 0) INTO total_dist
    FROM public.rides
    WHERE user_id = user_record.user_id AND distance_km IS NOT NULL;
    
    UPDATE public.profiles 
    SET total_distance_km = total_dist
    WHERE id = user_record.user_id;
    
    RAISE NOTICE 'Updated user % with total distance: % km', user_record.user_id, total_dist;
  END LOOP;
END $$;

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_rides_user_distance ON public.rides(user_id, distance_km);
