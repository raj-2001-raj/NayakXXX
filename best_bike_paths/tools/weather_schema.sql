-- =====================================================
-- WEATHER DATA STORAGE FOR RIDE ENRICHMENT
-- Run this in Supabase SQL Editor
-- Based on RASD: Trip Context and Enrichment
-- =====================================================

-- Add weather_data column to rides table (JSONB for flexibility)
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS weather_data jsonb;

-- Create index for querying rides by weather condition
CREATE INDEX IF NOT EXISTS idx_rides_weather_condition 
ON public.rides ((weather_data->>'condition'));

-- Example of stored weather data structure:
-- {
--   "temperature": 22.5,
--   "humidity": 65,
--   "wind_speed": 3.2,
--   "condition": "clear",
--   "description": "Clear sky",
--   "timestamp": "2026-01-27T14:30:00.000Z"
-- }

-- =====================================================
-- SURFACE-DEPENDENT WEATHER PENALTIES (RASD: Dynamic Routing)
-- =====================================================

-- Create table for surface type penalties based on weather
CREATE TABLE IF NOT EXISTS public.surface_weather_penalties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  surface_type text NOT NULL,
  weather_condition text NOT NULL,
  penalty_multiplier numeric DEFAULT 1.0,
  warning_message text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(surface_type, weather_condition)
);

-- Enable RLS
ALTER TABLE public.surface_weather_penalties ENABLE ROW LEVEL SECURITY;

-- Anyone can read penalties (used for route calculation)
CREATE POLICY "Anyone can read surface penalties" ON public.surface_weather_penalties
FOR SELECT TO anon, authenticated
USING (true);

-- Insert default penalties based on RASD requirements
INSERT INTO public.surface_weather_penalties (surface_type, weather_condition, penalty_multiplier, warning_message)
VALUES
  -- Gravel/Unpaved paths
  ('gravel', 'rain', 2.0, 'Warning: Likely Muddy/Slippery'),
  ('gravel', 'heavyRain', 3.0, 'Warning: Very Muddy - Avoid'),
  ('gravel', 'snow', 3.0, 'Warning: Icy/Slippery'),
  ('unpaved', 'rain', 2.5, 'Warning: Likely Muddy/Slippery'),
  ('unpaved', 'heavyRain', 4.0, 'Warning: Very Muddy - Avoid'),
  ('unpaved', 'snow', 3.5, 'Warning: Icy/Slippery'),
  ('dirt', 'rain', 2.0, 'Warning: Muddy Trail'),
  ('dirt', 'heavyRain', 3.5, 'Warning: Very Muddy - Avoid'),
  
  -- Paved roads (lower penalties)
  ('asphalt', 'rain', 1.2, 'Caution: Wet Road'),
  ('asphalt', 'heavyRain', 1.5, 'Caution: Reduced Visibility'),
  ('asphalt', 'snow', 2.0, 'Warning: Icy Road'),
  ('asphalt', 'fog', 1.3, 'Caution: Reduced Visibility'),
  ('concrete', 'rain', 1.2, 'Caution: Wet Surface'),
  ('concrete', 'heavyRain', 1.4, 'Caution: Reduced Visibility'),
  ('concrete', 'snow', 1.8, 'Warning: Slippery Surface'),
  
  -- Cobblestone
  ('cobblestone', 'rain', 1.8, 'Warning: Slippery Cobblestones'),
  ('cobblestone', 'heavyRain', 2.5, 'Warning: Very Slippery'),
  ('cobblestone', 'snow', 2.5, 'Warning: Icy Cobblestones'),
  
  -- Clear weather (no penalty)
  ('gravel', 'clear', 1.0, NULL),
  ('unpaved', 'clear', 1.0, NULL),
  ('asphalt', 'clear', 1.0, NULL),
  ('concrete', 'clear', 1.0, NULL),
  ('cobblestone', 'clear', 1.0, NULL)
ON CONFLICT (surface_type, weather_condition) DO NOTHING;

-- =====================================================
-- FUNCTION: Get weather penalty for a surface type
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_weather_penalty(
  p_surface_type text,
  p_weather_condition text
)
RETURNS TABLE (
  penalty_multiplier numeric,
  warning_message text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    COALESCE(penalty_multiplier, 1.0) as penalty_multiplier,
    warning_message
  FROM public.surface_weather_penalties
  WHERE surface_type = p_surface_type
    AND weather_condition = p_weather_condition
  LIMIT 1;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_weather_penalty(text, text) TO anon, authenticated;

-- =====================================================
-- VERIFICATION
-- =====================================================
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'rides' AND column_name = 'weather_data';

SELECT * FROM public.surface_weather_penalties ORDER BY surface_type, weather_condition;
