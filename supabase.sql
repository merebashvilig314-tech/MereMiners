-- Required for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- users
CREATE TABLE IF NOT EXISTS public.users (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  email varchar UNIQUE,
  password_hash varchar,
  first_name varchar,
  last_name varchar,
  profile_image_url varchar,
  mere_balance numeric(20,8) NOT NULL DEFAULT '0',
  usdt_balance numeric(20,8) NOT NULL DEFAULT '0',
  total_mined numeric(20,8) NOT NULL DEFAULT '0',
  referral_code varchar UNIQUE,
  referred_by_id varchar REFERENCES public.users(id),
  total_referrals integer NOT NULL DEFAULT 0,
  total_referral_earnings numeric(20,8) NOT NULL DEFAULT '0',
  deposit_address varchar UNIQUE,
  deposit_private_key varchar,
  is_admin boolean NOT NULL DEFAULT false,
  created_at timestamp DEFAULT now(),
  updated_at timestamp DEFAULT now()
);

-- miner_types (shop catalog)
CREATE TABLE IF NOT EXISTS public.miner_types (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  description varchar,
  image_url varchar NOT NULL,
  th_rate real NOT NULL,
  base_price_usd numeric(10,2) NOT NULL,
  base_price_mere numeric(10,2) NOT NULL,
  daily_yield_usd numeric(10,2) NOT NULL,
  daily_yield_mere numeric(10,2) NOT NULL,
  roi_days integer NOT NULL,
  rarity varchar NOT NULL DEFAULT 'common',
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamp DEFAULT now()
);

-- user_miners (ownership)
CREATE TABLE IF NOT EXISTS public.user_miners (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id varchar NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  miner_type_id varchar NOT NULL REFERENCES public.miner_types(id),
  slot_position integer,
  upgrade_level integer NOT NULL DEFAULT 0,
  purchased_at timestamp DEFAULT now(),
  is_active boolean NOT NULL DEFAULT true,
  boost_multiplier real NOT NULL DEFAULT 1.0,
  last_earnings_update timestamp DEFAULT now(),
  -- Trial/temporary miner support
  is_temporary boolean NOT NULL DEFAULT false,
  expires_at timestamp
);

-- Safe migration for existing databases
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'user_miners' AND column_name = 'is_temporary'
  ) THEN
    ALTER TABLE public.user_miners ADD COLUMN is_temporary boolean NOT NULL DEFAULT false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'user_miners' AND column_name = 'expires_at'
  ) THEN
    ALTER TABLE public.user_miners ADD COLUMN expires_at timestamp;
  END IF;
END $$;

-- transactions (ledger)
CREATE TABLE IF NOT EXISTS public.transactions (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id varchar NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type varchar NOT NULL,
  amount_mere numeric(20,8) NOT NULL,
  amount_usd numeric(20,2),
  description varchar,
  status varchar NOT NULL DEFAULT 'completed',
  tx_hash varchar,
  metadata jsonb,
  created_at timestamp DEFAULT now()
);

-- seasons
CREATE TABLE IF NOT EXISTS public.seasons (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  start_at timestamp NOT NULL,
  end_at timestamp NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp DEFAULT now()
);

-- leaderboard_entries
CREATE TABLE IF NOT EXISTS public.leaderboard_entries (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id varchar NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  season_id varchar NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  total_mined numeric(20,8) NOT NULL DEFAULT '0',
  total_hashrate real NOT NULL DEFAULT 0,
  rank integer,
  updated_at timestamp DEFAULT now()
);

-- Ensure one row per (user, season) to support upsert logic
CREATE UNIQUE INDEX IF NOT EXISTS uq_leaderboard_user_season
  ON public.leaderboard_entries(user_id, season_id);

-- season_pass_rewards
CREATE TABLE IF NOT EXISTS public.season_pass_rewards (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id varchar NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  tier integer NOT NULL,
  is_premium boolean NOT NULL DEFAULT false,
  reward_type varchar NOT NULL,
  reward_value numeric(20,8),
  reward_metadata jsonb,
  created_at timestamp DEFAULT now()
);

-- user_season_pass
CREATE TABLE IF NOT EXISTS public.user_season_pass (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id varchar NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  season_id varchar NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  current_tier integer NOT NULL DEFAULT 0,
  has_premium boolean NOT NULL DEFAULT false,
  claimed_rewards jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamp DEFAULT now()
);

-- Ensure one row per (user, season)
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_season_pass_user_season
  ON public.user_season_pass(user_id, season_id);

-- achievements (catalog)
CREATE TABLE IF NOT EXISTS public.achievements (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  description varchar NOT NULL,
  icon varchar NOT NULL,
  category varchar NOT NULL,
  criteria jsonb NOT NULL,
  reward_mere numeric(10,2),
  tier varchar NOT NULL DEFAULT 'bronze',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp DEFAULT now()
);

-- user_achievements (progress/unlocks)
CREATE TABLE IF NOT EXISTS public.user_achievements (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id varchar NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  achievement_id varchar NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  progress real NOT NULL DEFAULT 0,
  is_unlocked boolean NOT NULL DEFAULT false,
  unlocked_at timestamp,
  created_at timestamp DEFAULT now()
);

-- Prevent duplicate achievement records per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_achievement
  ON public.user_achievements(user_id, achievement_id);

-- daily_games
CREATE TABLE IF NOT EXISTS public.daily_games (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id varchar NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  game_type varchar NOT NULL,
  last_played_at timestamp NOT NULL,
  reward_mere numeric(10,2) NOT NULL,
  metadata jsonb,
  created_at timestamp DEFAULT now()
);

-- 3) Helpful defaults and housekeeping triggers (optional)
-- Keep users.updated_at in sync on any change
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- sessions (for express-session via connect-pg-simple)
-- This table is optional because the server can auto-create it, but including it helps on fresh DBs
CREATE TABLE IF NOT EXISTS public.sessions (
  sid varchar PRIMARY KEY,
  sess jsonb NOT NULL,
  expire timestamp NOT NULL
);

CREATE INDEX IF NOT EXISTS IDX_session_expire ON public.sessions(expire);

-- Helpful indexes for performance
CREATE INDEX IF NOT EXISTS idx_transactions_user_created ON public.transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_miners_user ON public.user_miners(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_games_user_type ON public.daily_games(user_id, game_type);
-- Ensure no duplicate blockchain transaction hashes are recorded
CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_tx_hash
  ON public.transactions(tx_hash)
  WHERE tx_hash IS NOT NULL;

-- Safe migration: add users.deposit_private_key if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'deposit_private_key'
  ) THEN
    ALTER TABLE public.users ADD COLUMN deposit_private_key varchar;
  END IF;
END $$;

-- Row Level Security (RLS) for user_achievements
-- Enable RLS to satisfy Supabase security checks and protect data when using PostgREST
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements FORCE ROW LEVEL SECURITY;

-- Policies are idempotent via existence checks
DO $$
BEGIN
  -- Allow authenticated users to read only their own achievement rows via PostgREST
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_achievements' AND policyname = 'Users can view their achievements'
  ) THEN
    CREATE POLICY "Users can view their achievements" ON public.user_achievements
      FOR SELECT
      TO authenticated
      USING (user_id = auth.uid()::text);
  END IF;

  -- Allow authenticated users to insert/update/delete only their own rows via PostgREST
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_achievements' AND policyname = 'Users can manage their achievements'
  ) THEN
    CREATE POLICY "Users can manage their achievements" ON public.user_achievements
      FOR ALL
      TO authenticated
      USING (user_id = auth.uid()::text)
      WITH CHECK (user_id = auth.uid()::text);
  END IF;

  -- Permit backend role full access (server connects directly and does its own auth)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_achievements' AND policyname = 'Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.user_achievements
      FOR ALL
      TO postgres
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- Optional: grant minimal privileges for PostgREST roles (kept narrow)
-- These grants are safe with RLS enabled; adjust as needed if you plan to expose this table via Supabase REST
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_achievements TO authenticated;

-- RLS for other user-owned tables
-- user_miners
ALTER TABLE public.user_miners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_miners FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_miners' AND policyname='Users can view their miners'
  ) THEN
    CREATE POLICY "Users can view their miners" ON public.user_miners
      FOR SELECT TO authenticated USING (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_miners' AND policyname='Users can manage their miners'
  ) THEN
    CREATE POLICY "Users can manage their miners" ON public.user_miners
      FOR ALL TO authenticated USING (user_id = auth.uid()::text) WITH CHECK (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_miners' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.user_miners FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_miners TO authenticated;

-- transactions
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='Users can view their transactions'
  ) THEN
    CREATE POLICY "Users can view their transactions" ON public.transactions
      FOR SELECT TO authenticated USING (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='Users can insert their transactions'
  ) THEN
    CREATE POLICY "Users can insert their transactions" ON public.transactions
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.transactions FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT, INSERT ON public.transactions TO authenticated;

-- daily_games
ALTER TABLE public.daily_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_games FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='daily_games' AND policyname='Users can view their game status'
  ) THEN
    CREATE POLICY "Users can view their game status" ON public.daily_games
      FOR SELECT TO authenticated USING (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='daily_games' AND policyname='Users can insert their game plays'
  ) THEN
    CREATE POLICY "Users can insert their game plays" ON public.daily_games
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='daily_games' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.daily_games FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT, INSERT ON public.daily_games TO authenticated;

-- user_season_pass
ALTER TABLE public.user_season_pass ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_season_pass FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_season_pass' AND policyname='Users can view their season pass'
  ) THEN
    CREATE POLICY "Users can view their season pass" ON public.user_season_pass
      FOR SELECT TO authenticated USING (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_season_pass' AND policyname='Users can update their season pass'
  ) THEN
    CREATE POLICY "Users can update their season pass" ON public.user_season_pass
      FOR UPDATE TO authenticated USING (user_id = auth.uid()::text) WITH CHECK (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_season_pass' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.user_season_pass FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT, UPDATE ON public.user_season_pass TO authenticated;

-- Make sure anon can access public catalog tables when allowed by policies
GRANT USAGE ON SCHEMA public TO anon;

-- =============================================================
-- RLS for additional tables flagged by Supabase checks
-- =============================================================

-- achievements (catalog) — public read
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.achievements FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='achievements' AND policyname='Public can read achievements'
  ) THEN
    CREATE POLICY "Public can read achievements" ON public.achievements
      FOR SELECT TO anon, authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='achievements' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.achievements FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT ON public.achievements TO anon, authenticated;

-- miner_types (catalog) — public read
ALTER TABLE public.miner_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.miner_types FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='miner_types' AND policyname='Public can read miner types'
  ) THEN
    CREATE POLICY "Public can read miner types" ON public.miner_types
      FOR SELECT TO anon, authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='miner_types' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.miner_types FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT ON public.miner_types TO anon, authenticated;

-- seasons (catalog) — public read
ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seasons FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='seasons' AND policyname='Public can read seasons'
  ) THEN
    CREATE POLICY "Public can read seasons" ON public.seasons
      FOR SELECT TO anon, authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='seasons' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.seasons FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT ON public.seasons TO anon, authenticated;

-- season_pass_rewards (catalog) — public read
ALTER TABLE public.season_pass_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.season_pass_rewards FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='season_pass_rewards' AND policyname='Public can read season pass rewards'
  ) THEN
    CREATE POLICY "Public can read season pass rewards" ON public.season_pass_rewards
      FOR SELECT TO anon, authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='season_pass_rewards' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.season_pass_rewards FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT ON public.season_pass_rewards TO anon, authenticated;

-- leaderboard_entries — public read (no personal secrets, shows ranks)
ALTER TABLE public.leaderboard_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leaderboard_entries FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='leaderboard_entries' AND policyname='Public can read leaderboard'
  ) THEN
    CREATE POLICY "Public can read leaderboard" ON public.leaderboard_entries
      FOR SELECT TO anon, authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='leaderboard_entries' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.leaderboard_entries FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT ON public.leaderboard_entries TO anon, authenticated;

-- users — sensitive; keep closed to public. Allow self-access for PostgREST and full backend access.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='Users can read own profile'
  ) THEN
    CREATE POLICY "Users can read own profile" ON public.users
      FOR SELECT TO authenticated USING (id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile" ON public.users
      FOR UPDATE TO authenticated USING (id = auth.uid()::text) WITH CHECK (id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.users FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;
GRANT SELECT, UPDATE ON public.users TO authenticated;

-- sessions — internal only; restrict to backend
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions FORCE ROW LEVEL SECURITY;

-- Generic backend/service policy to match USDT tables style (defense in depth)
-- This keeps PostgREST exposure locked unless using service_role; direct backend (no JWT) remains allowed.
DO $$
BEGIN
  -- Helper to create the same policy name across multiple tables idempotently
  PERFORM 1;
END $$;

-- users
DROP POLICY IF EXISTS allow_backend_or_service ON public.users;
CREATE POLICY allow_backend_or_service ON public.users
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- sessions
DROP POLICY IF EXISTS allow_backend_or_service ON public.sessions;
CREATE POLICY allow_backend_or_service ON public.sessions
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- miner_types
DROP POLICY IF EXISTS allow_backend_or_service ON public.miner_types;
CREATE POLICY allow_backend_or_service ON public.miner_types
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- achievements
DROP POLICY IF EXISTS allow_backend_or_service ON public.achievements;
CREATE POLICY allow_backend_or_service ON public.achievements
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- seasons
DROP POLICY IF EXISTS allow_backend_or_service ON public.seasons;
CREATE POLICY allow_backend_or_service ON public.seasons
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- season_pass_rewards
DROP POLICY IF EXISTS allow_backend_or_service ON public.season_pass_rewards;
CREATE POLICY allow_backend_or_service ON public.season_pass_rewards
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- leaderboard_entries
DROP POLICY IF EXISTS allow_backend_or_service ON public.leaderboard_entries;
CREATE POLICY allow_backend_or_service ON public.leaderboard_entries
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- user_season_pass
DROP POLICY IF EXISTS allow_backend_or_service ON public.user_season_pass;
CREATE POLICY allow_backend_or_service ON public.user_season_pass
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- user_miners
DROP POLICY IF EXISTS allow_backend_or_service ON public.user_miners;
CREATE POLICY allow_backend_or_service ON public.user_miners
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- user_achievements
DROP POLICY IF EXISTS allow_backend_or_service ON public.user_achievements;
CREATE POLICY allow_backend_or_service ON public.user_achievements
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- transactions
DROP POLICY IF EXISTS allow_backend_or_service ON public.transactions;
CREATE POLICY allow_backend_or_service ON public.transactions
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );

-- daily_games
DROP POLICY IF EXISTS allow_backend_or_service ON public.daily_games;
CREATE POLICY allow_backend_or_service ON public.daily_games
  FOR ALL
  USING (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  )
  WITH CHECK (
    current_setting('request.jwt.claims', true) IS NULL
    OR auth.role() = 'service_role'
  );
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sessions' AND policyname='Backend full access (postgres)'
  ) THEN
    CREATE POLICY "Backend full access (postgres)" ON public.sessions FOR ALL TO postgres USING (true) WITH CHECK (true);
  END IF;
END $$;