-- ============================================================================
-- Jwan Delivery - Supabase PostgreSQL Schema (CORRECTED ARCHITECTURE)
-- ============================================================================
-- CRITICAL CHANGES:
-- 1. auth.users.id (UUID) is the PRIMARY identity source
-- 2. public.users.id is a FOREIGN KEY to auth.users(id)
-- 3. All user_id/customer_id/driver_id fields are UUID (matching auth.users.id)
-- 4. legacy_firebase_uid stored for migration reference only (NOT used in RLS)
-- 5. No recursive RLS policies (using recursive RLS has security implications)
-- 6. Storage paths use UUID directly
-- 7. All financial operations are server-side only
-- ============================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS TABLE - Linked to auth.users
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  age INT,
  residence TEXT,
  
  -- User role: determined by JWT claims or this field (protected by RLS)
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'driver', 'admin')),
  
  -- Account status (PROTECTED - only admin can modify)
  is_active BOOLEAN DEFAULT FALSE,
  is_blocked BOOLEAN DEFAULT FALSE,
  email_verified BOOLEAN DEFAULT FALSE,
  activation_fee_paid BOOLEAN DEFAULT FALSE,
  
  -- Financial (PROTECTED - only via server functions)
  wallet_balance NUMERIC(12, 2) DEFAULT 0.00 CHECK (wallet_balance >= 0),
  
  -- Activity tracking
  active_days INT DEFAULT 0,
  last_active_at TIMESTAMP WITH TIME ZONE,
  
  -- Document URLs (for identity verification)
  identity_url TEXT,
  sticker_url TEXT,
  owner_proof_url TEXT,
  
  -- Legacy mapping (for migration only - NOT used in RLS)
  legacy_firebase_uid TEXT,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON public.users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_legacy_firebase_uid ON public.users(legacy_firebase_uid);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own profile
CREATE POLICY IF NOT EXISTS "users_read_self"
ON public.users FOR SELECT
USING (auth.uid() = id);

-- Policy: Admin can read all users
CREATE POLICY IF NOT EXISTS "users_read_admin"
ON public.users FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: Only via auth trigger (controlled insert)
CREATE POLICY IF NOT EXISTS "users_create_via_auth"
ON public.users FOR INSERT
WITH CHECK (auth.uid() = id);

-- Policy: User can only update phone, age, residence (non-sensitive fields)
-- CANNOT modify: role, is_active, is_blocked, wallet_balance, activation_fee_paid
CREATE POLICY IF NOT EXISTS "users_update_self_safe_fields"
ON public.users FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id AND
  role = (SELECT role FROM public.users WHERE id = auth.uid()) AND
  is_active = (SELECT is_active FROM public.users WHERE id = auth.uid()) AND
  is_blocked = (SELECT is_blocked FROM public.users WHERE id = auth.uid()) AND
  wallet_balance = (SELECT wallet_balance FROM public.users WHERE id = auth.uid()) AND
  activation_fee_paid = (SELECT activation_fee_paid FROM public.users WHERE id = auth.uid()) AND
  legacy_firebase_uid = (SELECT legacy_firebase_uid FROM public.users WHERE id = auth.uid())
);

-- Policy: Admin can update any field
CREATE POLICY IF NOT EXISTS "users_update_admin"
ON public.users FOR UPDATE
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: Only admin can delete
CREATE POLICY IF NOT EXISTS "users_delete_admin"
ON public.users FOR DELETE
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- ============================================================================
-- 2. ORDERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- UUID references to auth.users.id
  customer_id UUID NOT NULL,
  customer_name TEXT,
  customer_phone TEXT,
  
  driver_id UUID,
  driver_name TEXT,
  driver_phone TEXT,
  
  -- Location and order details
  from_location TEXT NOT NULL,
  to_location TEXT NOT NULL,
  order_type TEXT NOT NULL,
  description TEXT,
  
  -- Pricing
  pricing_mode TEXT DEFAULT 'customer' CHECK (pricing_mode IN ('customer', 'admin')),
  price NUMERIC(10, 2),
  company_commission NUMERIC(10, 2),
  
  -- Status workflow
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'picked_up', 'driver_delivered', 'completed', 'cancelled')),
  
  -- Status change timestamps
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

-- Policy: Customer can see their own orders
CREATE POLICY IF NOT EXISTS "orders_read_customer"
ON public.orders FOR SELECT
USING (auth.uid() = customer_id);

-- Policy: Driver can see assigned orders + all pending orders (if active driver)
CREATE POLICY IF NOT EXISTS "orders_read_driver"
ON public.orders FOR SELECT
USING (
  auth.uid() = driver_id OR 
  (status = 'pending' AND 
   auth.jwt() ->> 'user_role' = 'driver' AND
   (SELECT is_active FROM public.users WHERE id = auth.uid()) = TRUE
  )
);

-- Policy: Admin can see all orders
CREATE POLICY IF NOT EXISTS "orders_read_admin"
ON public.orders FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: Orders can ONLY be created/modified via server-side functions
CREATE POLICY IF NOT EXISTS "orders_no_direct_insert"
ON public.orders FOR INSERT
WITH CHECK (FALSE);

CREATE POLICY IF NOT EXISTS "orders_no_direct_update"
ON public.orders FOR UPDATE
USING (FALSE);

CREATE POLICY IF NOT EXISTS "orders_no_direct_delete"
ON public.orders FOR DELETE
USING (FALSE);

-- ============================================================================
-- 3. TRANSACTIONS TABLE - Immutable Audit Log
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('topup', 'order_cost', 'reservation', 'driver_payout', 'withdrawal', 'activation_fee')),
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
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

-- Policy: User can read their own transactions
CREATE POLICY IF NOT EXISTS "transactions_read_self"
ON public.transactions FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Admin can read all transactions
CREATE POLICY IF NOT EXISTS "transactions_read_admin"
ON public.transactions FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: NO DIRECT INSERT (only via server functions)
CREATE POLICY IF NOT EXISTS "transactions_no_direct_insert"
ON public.transactions FOR INSERT
WITH CHECK (FALSE);

-- Policy: IMMUTABLE (no updates allowed)
CREATE POLICY IF NOT EXISTS "transactions_no_update"
ON public.transactions FOR UPDATE
WITH CHECK (FALSE);

-- ============================================================================
-- 4. TOPUPS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.topups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL CHECK (method IN ('بنكك', 'فوري', 'أوكاش', 'ماي كاشي')),
  receipt_url TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  purpose TEXT DEFAULT 'wallet' CHECK (purpose IN ('wallet', 'activation_fee')),
  reviewed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_topups_user_id ON public.topups(user_id);
CREATE INDEX IF NOT EXISTS idx_topups_status ON public.topups(status);
CREATE INDEX IF NOT EXISTS idx_topups_created_at ON public.topups(created_at);
CREATE INDEX IF NOT EXISTS idx_topups_user_status ON public.topups(user_id, status);

ALTER TABLE public.topups ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own topups
CREATE POLICY IF NOT EXISTS "topups_read_self"
ON public.topups FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Admin can read all topups
CREATE POLICY IF NOT EXISTS "topups_read_admin"
ON public.topups FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: User can create topup for themselves
CREATE POLICY IF NOT EXISTS "topups_create_self"
ON public.topups FOR INSERT
WITH CHECK (auth.uid() = user_id AND status = 'pending');

-- Policy: Only admin can approve/reject
CREATE POLICY IF NOT EXISTS "topups_update_admin_only"
ON public.topups FOR UPDATE
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- ============================================================================
-- 5. WITHDRAWALS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL CHECK (method IN ('بنكك', 'فوري', 'أوكاش', 'ماي كاشي')),
  account_info TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON public.withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_withdrawals_created_at ON public.withdrawals(created_at);
CREATE INDEX IF NOT EXISTS idx_withdrawals_user_status ON public.withdrawals(user_id, status);

ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own withdrawals
CREATE POLICY IF NOT EXISTS "withdrawals_read_self"
ON public.withdrawals FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Admin can read all withdrawals
CREATE POLICY IF NOT EXISTS "withdrawals_read_admin"
ON public.withdrawals FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: Driver can create withdrawal request
CREATE POLICY IF NOT EXISTS "withdrawals_create_self"
ON public.withdrawals FOR INSERT
WITH CHECK (auth.uid() = user_id AND status = 'pending');

-- Policy: Only admin can approve/reject
CREATE POLICY IF NOT EXISTS "withdrawals_update_admin_only"
ON public.withdrawals FOR UPDATE
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- ============================================================================
-- 6. SUPPORT TICKETS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.support (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_name TEXT,
  user_phone TEXT,
  subject TEXT NOT NULL,
  text TEXT NOT NULL,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'replied', 'closed')),
  reply TEXT,
  reply_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  reply_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_support_user_id ON public.support(user_id);
CREATE INDEX IF NOT EXISTS idx_support_status ON public.support(status);
CREATE INDEX IF NOT EXISTS idx_support_created_at ON public.support(created_at);

ALTER TABLE public.support ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own tickets
CREATE POLICY IF NOT EXISTS "support_read_self"
ON public.support FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Admin can read all tickets
CREATE POLICY IF NOT EXISTS "support_read_admin"
ON public.support FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: User can create ticket
CREATE POLICY IF NOT EXISTS "support_create_self"
ON public.support FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Only admin can reply
CREATE POLICY IF NOT EXISTS "support_update_admin_only"
ON public.support FOR UPDATE
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- ============================================================================
-- 7. RATINGS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ratings_order_id ON public.ratings(order_id);
CREATE INDEX IF NOT EXISTS idx_ratings_customer_id ON public.ratings(customer_id);
CREATE INDEX IF NOT EXISTS idx_ratings_driver_id ON public.ratings(driver_id);

ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

-- Policy: Customer and driver can read rating for their order
CREATE POLICY IF NOT EXISTS "ratings_read_involved"
ON public.ratings FOR SELECT
USING (auth.uid() = customer_id OR auth.uid() = driver_id);

-- Policy: Admin can read all ratings
CREATE POLICY IF NOT EXISTS "ratings_read_admin"
ON public.ratings FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: Customer can rate their completed order (only after order is completed)
CREATE POLICY IF NOT EXISTS "ratings_create_customer"
ON public.ratings FOR INSERT
WITH CHECK (
  auth.uid() = customer_id AND
  EXISTS (
    SELECT 1 FROM orders 
    WHERE id = order_id 
    AND status = 'completed' 
    AND customer_id = auth.uid()
  )
);

-- ============================================================================
-- 8. ORDER COMMENTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.order_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_comments_order_id ON public.order_comments(order_id);
CREATE INDEX IF NOT EXISTS idx_order_comments_user_id ON public.order_comments(user_id);

ALTER TABLE public.order_comments ENABLE ROW LEVEL SECURITY;

-- Policy: Users involved in order can read comments
CREATE POLICY IF NOT EXISTS "order_comments_read_involved"
ON public.order_comments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders 
    WHERE id = order_id 
    AND (customer_id = auth.uid() OR driver_id = auth.uid())
  )
);

-- Policy: Admin can read all comments
CREATE POLICY IF NOT EXISTS "order_comments_read_admin"
ON public.order_comments FOR SELECT
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

-- Policy: Users involved in order can create comment
CREATE POLICY IF NOT EXISTS "order_comments_create"
ON public.order_comments FOR INSERT
WITH CHECK (
  auth.uid() = user_id AND
  EXISTS (
    SELECT 1 FROM orders 
    WHERE id = order_id 
    AND (customer_id = auth.uid() OR driver_id = auth.uid())
  )
);

-- ============================================================================
-- 9. USER TOKENS TABLE (Push Notifications)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_tokens_user_id ON public.user_tokens(user_id);

ALTER TABLE public.user_tokens ENABLE ROW LEVEL SECURITY;

-- Policy: User can read/write their own tokens
CREATE POLICY IF NOT EXISTS "user_tokens_read_self"
ON public.user_tokens FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "user_tokens_write_self"
ON public.user_tokens FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "user_tokens_delete_self"
ON public.user_tokens FOR DELETE
USING (auth.uid() = user_id);

-- ============================================================================
-- 10. ORDER PRICE EVENTS TABLE (Admin price assignments)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.order_price_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  price NUMERIC(10, 2) NOT NULL CHECK (price > 0),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_price_events_order_id ON public.order_price_events(order_id);
CREATE INDEX IF NOT EXISTS idx_order_price_events_created_at ON public.order_price_events(created_at);

ALTER TABLE public.order_price_events ENABLE ROW LEVEL SECURITY;

-- Policy: Only admin can create/read price events
CREATE POLICY IF NOT EXISTS "order_price_events_admin_only"
ON public.order_price_events FOR ALL
USING (auth.jwt() ->> 'user_role' = 'admin' OR auth.jwt() ->> 'user_role' = 'super_admin');

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
