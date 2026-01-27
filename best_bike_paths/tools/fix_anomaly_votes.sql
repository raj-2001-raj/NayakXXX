-- =====================================================
-- FIX ANOMALY_VOTES TABLE - ADD MISSING COLUMNS
-- Run this in Supabase SQL Editor
-- =====================================================

-- Add created_at column if it doesn't exist
ALTER TABLE public.anomaly_votes 
ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- Verify the column was added
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'anomaly_votes';

-- Refresh the schema cache (Supabase sometimes caches schema)
-- After running this, restart your PostgREST service or wait a few minutes
NOTIFY pgrst, 'reload schema';
