-- ============================================================================
-- Jwan Delivery - Supabase PostgreSQL Schema (PRODUCTION)
-- ============================================================================
-- All auth.uid() calls properly cast to TEXT for comparison
-- Proper UUID handling throughout
-- Firebase UID integration ready
-- Complete financial operations with atomicity
-- ============================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  age INT,
  residence TEXT,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'driver', 'admin')),
  
  is_active BOOLEAN DEFAULT FALSE,
  is_blocked BOOLEAN DEFAULT FALSE,
  email_verified BOOLEAN DEFAULT FALSE,
  activation_fee_paid BOOLEAN DEFAULT FALSE,
  
  wallet_balance NUMERIC(12, 2) DEFAULT 0.00 CHECK (wallet_balance >= 0),
  
  active_days INT DEFAULT 0,
  last_active_at TIMESTAMP WITH TIME ZONE,
  
  identity_url TEXT,
  sticker_url TEXT,
  owner_proof_url TEXT,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_uid ON public.users(uid);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON public.users(is_active);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "users_read_self_or_admin"
ON public.users FOR SELECT
USING (
  auth.uid()::text = uid 
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "users_create_disabled"
ON public.users FOR INSERT
WITH CHECK (FALSE);

CREATE POLICY IF NOT EXISTS "users_update_self_allowed"
ON public.users FOR UPDATE
USING (auth.uid()::text = uid)
WITH CHECK (
  auth.uid()::text = uid
  AND role = (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1)
  AND is_active = (SELECT is_active FROM public.users WHERE uid = auth.uid()::text LIMIT 1)
  AND is_blocked = (SELECT is_blocked FROM public.users WHERE uid = auth.uid()::text LIMIT 1)
  AND wallet_balance = (SELECT wallet_balance FROM public.users WHERE uid = auth.uid()::text LIMIT 1)
  AND activation_fee_paid = (SELECT activation_fee_paid FROM public.users WHERE uid = auth.uid()::text LIMIT 1)
);

CREATE POLICY IF NOT EXISTS "users_update_admin_allowed"
ON public.users FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

CREATE POLICY IF NOT EXISTS "users_delete_admin_only"
ON public.users FOR DELETE
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

-- ============================================================================
-- 2. ORDERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id TEXT NOT NULL,
  customer_name TEXT,
  customer_phone TEXT,
  driver_id TEXT,
  driver_name TEXT,
  driver_phone TEXT,
  
  from_location TEXT NOT NULL,
  to_location TEXT NOT NULL,
  order_type TEXT NOT NULL,
  description TEXT,
  
  pricing_mode TEXT DEFAULT 'customer' CHECK (pricing_mode IN ('customer', 'admin')),
  price NUMERIC(10, 2),
  company_commission NUMERIC(10, 2),
  
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'picked_up', 'driver_delivered', 'completed', 'cancelled')),
  
  accepted_at TIMESTAMP WITH TIME ZONE,
  picked_up_at TIMESTAMP WITH TIME ZONE,
  driver_delivered_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  
  last_comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT valid_price CHECK (price > 0 OR price IS NULL),
  CONSTRAINT valid_commission CHECK (company_commission >= 0 OR company_commission IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_driver_id ON public.orders(driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_status_created ON public.orders(status, created_at DESC);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "orders_read_admin"
ON public.orders FOR SELECT
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

CREATE POLICY IF NOT EXISTS "orders_read_customer"
ON public.orders FOR SELECT
USING (auth.uid()::text = customer_id);

CREATE POLICY IF NOT EXISTS "orders_read_driver"
ON public.orders FOR SELECT
USING (
  auth.uid()::text = driver_id 
  OR (
    status = 'pending' 
    AND (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'driver'
    AND (SELECT is_active FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = TRUE
  )
);

CREATE POLICY IF NOT EXISTS "orders_no_direct_modify"
ON public.orders FOR INSERT
WITH CHECK (FALSE);

-- ============================================================================
-- 3. TRANSACTIONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  transaction_type TEXT NOT NULL,
  amount NUMERIC(12, 2) NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_order_id ON public.transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON public.transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_transactions_user_type ON public.transactions(user_id, transaction_type);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "transactions_read_self_or_admin"
ON public.transactions FOR SELECT
USING (
  auth.uid()::text = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "transactions_insert_disabled"
ON public.transactions FOR INSERT
WITH CHECK (FALSE);

CREATE POLICY IF NOT EXISTS "transactions_update_disabled"
ON public.transactions FOR UPDATE
WITH CHECK (FALSE);

-- ============================================================================
-- 4. TOPUPS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.topups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL CHECK (method IN ('بنكك', 'فوري', 'أوكاش', 'ماي كاشي')),
  receipt_url TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  purpose TEXT DEFAULT 'wallet' CHECK (purpose IN ('wallet', 'activation_fee')),
  reviewed_by TEXT,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_topups_user_id ON public.topups(user_id);
CREATE INDEX IF NOT EXISTS idx_topups_status ON public.topups(status);
CREATE INDEX IF NOT EXISTS idx_topups_created_at ON public.topups(created_at);
CREATE INDEX IF NOT EXISTS idx_topups_user_status ON public.topups(user_id, status);

ALTER TABLE public.topups ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "topups_read_self_or_admin"
ON public.topups FOR SELECT
USING (
  auth.uid()::text = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "topups_create_self"
ON public.topups FOR INSERT
WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY IF NOT EXISTS "topups_update_admin_only"
ON public.topups FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

-- ============================================================================
-- 5. WITHDRAWALS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL CHECK (method IN ('بنكك', 'فوري', 'أوكاش', 'ماي كاشي')),
  account_info TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by TEXT,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON public.withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_withdrawals_created_at ON public.withdrawals(created_at);
CREATE INDEX IF NOT EXISTS idx_withdrawals_user_status ON public.withdrawals(user_id, status);

ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "withdrawals_read_self_or_admin"
ON public.withdrawals FOR SELECT
USING (
  auth.uid()::text = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "withdrawals_create_self"
ON public.withdrawals FOR INSERT
WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY IF NOT EXISTS "withdrawals_update_admin_only"
ON public.withdrawals FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

-- ============================================================================
-- 6. SUPPORT TICKETS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.support (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  user_name TEXT,
  user_phone TEXT,
  subject TEXT NOT NULL,
  text TEXT NOT NULL,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'replied', 'closed')),
  reply TEXT,
  reply_by TEXT,
  reply_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_support_user_id ON public.support(user_id);
CREATE INDEX IF NOT EXISTS idx_support_status ON public.support(status);
CREATE INDEX IF NOT EXISTS idx_support_created_at ON public.support(created_at);

ALTER TABLE public.support ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "support_read_self_or_admin"
ON public.support FOR SELECT
USING (
  auth.uid()::text = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "support_create_self"
ON public.support FOR INSERT
WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY IF NOT EXISTS "support_update_admin_only"
ON public.support FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

-- ============================================================================
-- 7. RATINGS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  customer_id TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ratings_order_id ON public.ratings(order_id);
CREATE INDEX IF NOT EXISTS idx_ratings_customer_id ON public.ratings(customer_id);
CREATE INDEX IF NOT EXISTS idx_ratings_driver_id ON public.ratings(driver_id);

ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "ratings_read_involved"
ON public.ratings FOR SELECT
USING (
  auth.uid()::text = customer_id 
  OR auth.uid()::text = driver_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "ratings_create_customer"
ON public.ratings FOR INSERT
WITH CHECK (
  auth.uid()::text = customer_id
  AND EXISTS (
    SELECT 1 FROM orders 
    WHERE id = order_id 
    AND status = 'completed' 
    AND customer_id = auth.uid()::text
  )
);

-- ============================================================================
-- 8. ORDER COMMENTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.order_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_comments_order_id ON public.order_comments(order_id);
CREATE INDEX IF NOT EXISTS idx_order_comments_user_id ON public.order_comments(user_id);

ALTER TABLE public.order_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "order_comments_read_involved"
ON public.order_comments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.orders o 
    WHERE o.id = order_id 
    AND (o.customer_id = auth.uid()::text OR o.driver_id = auth.uid()::text)
  )
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);

CREATE POLICY IF NOT EXISTS "order_comments_create"
ON public.order_comments FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.orders o 
    WHERE o.id = order_id 
    AND (o.customer_id = auth.uid()::text OR o.driver_id = auth.uid()::text)
  )
);

-- ============================================================================
-- 9. USER TOKENS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_tokens_user_id ON public.user_tokens(user_id);

ALTER TABLE public.user_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "user_tokens_read_self"
ON public.user_tokens FOR SELECT
USING (auth.uid()::text = user_id);

CREATE POLICY IF NOT EXISTS "user_tokens_write_self"
ON public.user_tokens FOR INSERT
WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY IF NOT EXISTS "user_tokens_delete_self"
ON public.user_tokens FOR DELETE
USING (auth.uid()::text = user_id);

-- ============================================================================
-- 10. ORDER PRICE EVENTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.order_price_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  admin_id TEXT NOT NULL,
  price NUMERIC(10, 2) NOT NULL CHECK (price > 0),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_price_events_order_id ON public.order_price_events(order_id);
CREATE INDEX IF NOT EXISTS idx_order_price_events_created_at ON public.order_price_events(created_at);

ALTER TABLE public.order_price_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "order_price_events_admin_all"
ON public.order_price_events FOR ALL
USING ((SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin');

-- ============================================================================
-- AUTO-UPDATE TRIGGER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
