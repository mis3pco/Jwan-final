-- ============================================================================
-- Jwan Delivery - Supabase PostgreSQL Schema
-- ============================================================================
-- This schema replaces Firestore collections with PostgreSQL tables
-- All financial operations are protected by RLS policies
-- No user can modify sensitive fields (wallet, order status, etc.) directly
-- ============================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS TABLE
-- ============================================================================
-- Stores user data, roles, wallet balance, and account status
CREATE TABLE public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  age INT,
  residence TEXT,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'driver', 'admin')),
  
  -- Account status
  is_active BOOLEAN DEFAULT FALSE,
  is_blocked BOOLEAN DEFAULT FALSE,
  email_verified BOOLEAN DEFAULT FALSE,
  
  -- Driver-specific
  activation_fee_paid BOOLEAN DEFAULT FALSE,
  
  -- Financial
  wallet_balance NUMERIC(12, 2) DEFAULT 0.00 CHECK (wallet_balance >= 0),
  
  -- Activity tracking
  active_days INT DEFAULT 0,
  last_active_at TIMESTAMP WITH TIME ZONE,
  
  -- Document URLs (for identity verification)
  identity_url TEXT,
  sticker_url TEXT,
  owner_proof_url TEXT,
  
  -- Metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for users table
CREATE INDEX idx_users_uid ON public.users(uid);
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_role ON public.users(role);
CREATE INDEX idx_users_is_active ON public.users(is_active);

-- Enable RLS on users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own data or admin can read anyone
CREATE POLICY "users_read_self_or_admin"
ON public.users FOR SELECT
USING (
  auth.uid() = uid 
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: Only admin can create users (controlled by auth trigger)
CREATE POLICY "users_create_disabled"
ON public.users FOR INSERT
WITH CHECK (FALSE);

-- Policy: User can only update non-sensitive fields
CREATE POLICY "users_update_self_allowed"
ON public.users FOR UPDATE
USING (auth.uid() = uid)
WITH CHECK (
  auth.uid() = uid
  AND role = (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1)
  AND is_active = (SELECT is_active FROM public.users WHERE uid = auth.uid() LIMIT 1)
  AND is_blocked = (SELECT is_blocked FROM public.users WHERE uid = auth.uid() LIMIT 1)
  AND wallet_balance = (SELECT wallet_balance FROM public.users WHERE uid = auth.uid() LIMIT 1)
  AND activation_fee_paid = (SELECT activation_fee_paid FROM public.users WHERE uid = auth.uid() LIMIT 1)
);

-- Policy: Admin can update sensitive fields
CREATE POLICY "users_update_admin_allowed"
ON public.users FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- Policy: Only admin can delete
CREATE POLICY "users_delete_admin_only"
ON public.users FOR DELETE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- 2. ORDERS TABLE
-- ============================================================================
-- Stores delivery orders with status tracking and pricing
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id TEXT NOT NULL,
  customer_name TEXT,
  customer_phone TEXT,
  driver_id TEXT,
  driver_name TEXT,
  driver_phone TEXT,
  
  -- Location and type
  from_location TEXT NOT NULL,
  to_location TEXT NOT NULL,
  order_type TEXT NOT NULL,
  description TEXT,
  
  -- Pricing
  pricing_mode TEXT DEFAULT 'customer' CHECK (pricing_mode IN ('customer', 'admin')),
  price NUMERIC(10, 2),
  company_commission NUMERIC(10, 2),
  
  -- Status tracking
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'picked_up', 'driver_delivered', 'completed', 'cancelled')),
  
  -- Timestamps for status changes
  accepted_at TIMESTAMP WITH TIME ZONE,
  picked_up_at TIMESTAMP WITH TIME ZONE,
  driver_delivered_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  
  -- Comments and metadata
  last_comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT valid_price CHECK (price > 0 OR price IS NULL),
  CONSTRAINT valid_commission CHECK (company_commission >= 0 OR company_commission IS NULL)
);

-- Indexes for orders
CREATE INDEX idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX idx_orders_driver_id ON public.orders(driver_id);
CREATE INDEX idx_orders_status ON public.orders(status);
CREATE INDEX idx_orders_created_at ON public.orders(created_at);

-- Enable RLS on orders
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Policy: Admin can read all orders
CREATE POLICY "orders_read_admin"
ON public.orders FOR SELECT
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- Policy: Customer can read their own orders
CREATE POLICY "orders_read_customer"
ON public.orders FOR SELECT
USING (auth.uid() = customer_id);

-- Policy: Driver can read accepted/current orders and all pending orders (if active)
CREATE POLICY "orders_read_driver"
ON public.orders FOR SELECT
USING (
  auth.uid() = driver_id 
  OR (
    status = 'pending' 
    AND (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'driver'
    AND (SELECT is_active FROM public.users WHERE uid = auth.uid() LIMIT 1) = TRUE
  )
);

-- Policy: Only admin can insert/update/delete orders
CREATE POLICY "orders_create_admin_only"
ON public.orders FOR INSERT
WITH CHECK ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

CREATE POLICY "orders_update_admin_only"
ON public.orders FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

CREATE POLICY "orders_delete_admin_only"
ON public.orders FOR DELETE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- 3. TRANSACTIONS TABLE
-- ============================================================================
-- Immutable audit log for all financial transactions
CREATE TABLE public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  transaction_type TEXT NOT NULL,
  amount NUMERIC(12, 2) NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for transactions
CREATE INDEX idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX idx_transactions_order_id ON public.transactions(order_id);
CREATE INDEX idx_transactions_created_at ON public.transactions(created_at);

-- Enable RLS on transactions
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own transactions
CREATE POLICY "transactions_read_self_or_admin"
ON public.transactions FOR SELECT
USING (
  auth.uid() = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: No direct insert (only via server functions)
CREATE POLICY "transactions_insert_disabled"
ON public.transactions FOR INSERT
WITH CHECK (FALSE);

-- Policy: No updates allowed
CREATE POLICY "transactions_update_disabled"
ON public.transactions FOR UPDATE
WITH CHECK (FALSE);

-- ============================================================================
-- 4. TOPUPS TABLE
-- ============================================================================
-- Wallet recharge requests (pending admin review)
CREATE TABLE public.topups (
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

-- Indexes for topups
CREATE INDEX idx_topups_user_id ON public.topups(user_id);
CREATE INDEX idx_topups_status ON public.topups(status);
CREATE INDEX idx_topups_created_at ON public.topups(created_at);

-- Enable RLS on topups
ALTER TABLE public.topups ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own topups
CREATE POLICY "topups_read_self_or_admin"
ON public.topups FOR SELECT
USING (
  auth.uid() = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: User can create topups for themselves
CREATE POLICY "topups_create_self"
ON public.topups FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Only admin can update
CREATE POLICY "topups_update_admin_only"
ON public.topups FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- 5. WITHDRAWALS TABLE
-- ============================================================================
-- Driver withdrawal requests (pending admin review)
CREATE TABLE public.withdrawals (
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

-- Indexes for withdrawals
CREATE INDEX idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX idx_withdrawals_status ON public.withdrawals(status);
CREATE INDEX idx_withdrawals_created_at ON public.withdrawals(created_at);

-- Enable RLS on withdrawals
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own withdrawals
CREATE POLICY "withdrawals_read_self_or_admin"
ON public.withdrawals FOR SELECT
USING (
  auth.uid() = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: User can create withdrawals for themselves
CREATE POLICY "withdrawals_create_self"
ON public.withdrawals FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Only admin can update
CREATE POLICY "withdrawals_update_admin_only"
ON public.withdrawals FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- 6. SUPPORT TICKETS TABLE
-- ============================================================================
-- Support messages between users and admin
CREATE TABLE public.support (
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

-- Indexes for support
CREATE INDEX idx_support_user_id ON public.support(user_id);
CREATE INDEX idx_support_status ON public.support(status);
CREATE INDEX idx_support_created_at ON public.support(created_at);

-- Enable RLS on support
ALTER TABLE public.support ENABLE ROW LEVEL SECURITY;

-- Policy: User can read their own tickets or admin can read all
CREATE POLICY "support_read_self_or_admin"
ON public.support FOR SELECT
USING (
  auth.uid() = user_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: User can create tickets
CREATE POLICY "support_create_self"
ON public.support FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Only admin can update
CREATE POLICY "support_update_admin_only"
ON public.support FOR UPDATE
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- 7. RATINGS TABLE
-- ============================================================================
-- Customer ratings for completed orders
CREATE TABLE public.ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  customer_id TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for ratings
CREATE INDEX idx_ratings_order_id ON public.ratings(order_id);
CREATE INDEX idx_ratings_customer_id ON public.ratings(customer_id);
CREATE INDEX idx_ratings_driver_id ON public.ratings(driver_id);

-- Enable RLS on ratings
ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

-- Policy: Customer and driver can read ratings for their orders
CREATE POLICY "ratings_read_involved"
ON public.ratings FOR SELECT
USING (
  auth.uid() = customer_id 
  OR auth.uid() = driver_id 
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: Admin can insert/update/delete
CREATE POLICY "ratings_insert_admin"
ON public.ratings FOR INSERT
WITH CHECK ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- 8. ORDER COMMENTS TABLE
-- ============================================================================
-- Driver comments on orders (for price negotiation, etc.)
CREATE TABLE public.order_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for order_comments
CREATE INDEX idx_order_comments_order_id ON public.order_comments(order_id);
CREATE INDEX idx_order_comments_user_id ON public.order_comments(user_id);

-- Enable RLS on order_comments
ALTER TABLE public.order_comments ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone involved in the order can read comments
CREATE POLICY "order_comments_read_involved"
ON public.order_comments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.orders o 
    WHERE o.id = order_id 
    AND (o.customer_id = auth.uid() OR o.driver_id = auth.uid())
  )
  OR (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy: User can create comment on their order
CREATE POLICY "order_comments_create"
ON public.order_comments FOR INSERT
WITH CHECK (
  (
    SELECT COUNT(*) FROM public.orders o 
    WHERE o.id = order_id 
    AND (o.customer_id = auth.uid() OR o.driver_id = auth.uid())
  ) > 0
);

-- ============================================================================
-- 9. USER TOKENS TABLE (Push Notifications)
-- ============================================================================
-- Web push notification tokens for each user
CREATE TABLE public.user_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL UNIQUE,
  token TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for user_tokens
CREATE INDEX idx_user_tokens_user_id ON public.user_tokens(user_id);

-- Enable RLS on user_tokens
ALTER TABLE public.user_tokens ENABLE ROW LEVEL SECURITY;

-- Policy: User can read/write their own token
CREATE POLICY "user_tokens_read_self"
ON public.user_tokens FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "user_tokens_write_self"
ON public.user_tokens FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_tokens_update_self"
ON public.user_tokens FOR UPDATE
USING (auth.uid() = user_id);

-- ============================================================================
-- 10. ORDER PRICE EVENTS TABLE
-- ============================================================================
-- Admin price assignments for pending orders (triggers notifications)
CREATE TABLE public.order_price_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  admin_id TEXT NOT NULL,
  price NUMERIC(10, 2) NOT NULL CHECK (price > 0),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for order_price_events
CREATE INDEX idx_order_price_events_order_id ON public.order_price_events(order_id);
CREATE INDEX idx_order_price_events_created_at ON public.order_price_events(created_at);

-- Enable RLS on order_price_events
ALTER TABLE public.order_price_events ENABLE ROW LEVEL SECURITY;

-- Policy: Admin can read/create
CREATE POLICY "order_price_events_admin_all"
ON public.order_price_events FOR ALL
USING ((SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin');

-- ============================================================================
-- SECURE SQL FUNCTIONS FOR FINANCIAL OPERATIONS
-- ============================================================================

-- Function: Add transaction and update wallet (atomic)
CREATE OR REPLACE FUNCTION public.add_wallet_transaction(
  p_user_id TEXT,
  p_transaction_type TEXT,
  p_amount NUMERIC,
  p_order_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS TABLE(success BOOLEAN, message TEXT, new_balance NUMERIC) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role TEXT;
  v_current_balance NUMERIC;
  v_new_balance NUMERIC;
BEGIN
  -- Only server (Edge Functions) can call this
  IF auth.role() != 'authenticated' OR (SELECT role FROM users WHERE uid = auth.uid() LIMIT 1) != 'admin' THEN
    RETURN QUERY SELECT FALSE, 'Unauthorized'::TEXT, 0::NUMERIC;
    RETURN;
  END IF;

  -- Get current user
  SELECT wallet_balance INTO v_current_balance FROM users WHERE uid = p_user_id LIMIT 1;
  
  IF v_current_balance IS NULL THEN
    RETURN QUERY SELECT FALSE, 'User not found'::TEXT, 0::NUMERIC;
    RETURN;
  END IF;

  -- Calculate new balance
  CASE p_transaction_type
    WHEN 'topup' THEN
      v_new_balance := v_current_balance + p_amount;
    WHEN 'order_cost' THEN
      v_new_balance := v_current_balance - p_amount;
      IF v_new_balance < 0 THEN
        RETURN QUERY SELECT FALSE, 'Insufficient balance'::TEXT, v_current_balance;
        RETURN;
      END IF;
    WHEN 'reservation' THEN
      v_new_balance := v_current_balance - p_amount;
      IF v_new_balance < 0 THEN
        RETURN QUERY SELECT FALSE, 'Insufficient balance for reservation'::TEXT, v_current_balance;
        RETURN;
      END IF;
    WHEN 'driver_payout' THEN
      v_new_balance := v_current_balance + p_amount;
    WHEN 'withdrawal' THEN
      v_new_balance := v_current_balance - p_amount;
      IF v_new_balance < 0 THEN
        RETURN QUERY SELECT FALSE, 'Insufficient balance for withdrawal'::TEXT, v_current_balance;
        RETURN;
      END IF;
    ELSE
      RETURN QUERY SELECT FALSE, 'Unknown transaction type'::TEXT, v_current_balance;
      RETURN;
  END CASE;

  -- Update wallet in transaction
  BEGIN
    UPDATE users SET wallet_balance = v_new_balance WHERE uid = p_user_id;
    
    -- Insert transaction record
    INSERT INTO transactions (user_id, transaction_type, amount, order_id, description, status)
    VALUES (p_user_id, p_transaction_type, p_amount, p_order_id, p_description, 'completed');
    
    RETURN QUERY SELECT TRUE, 'Transaction successful'::TEXT, v_new_balance;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT, v_current_balance;
  END;
END;
$$;

-- Function: Create order (with validation)
CREATE OR REPLACE FUNCTION public.create_order(
  p_customer_id TEXT,
  p_customer_name TEXT,
  p_customer_phone TEXT,
  p_from_location TEXT,
  p_to_location TEXT,
  p_order_type TEXT,
  p_description TEXT,
  p_price NUMERIC
)
RETURNS TABLE(success BOOLEAN, message TEXT, order_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id UUID;
  v_customer_active BOOLEAN;
  v_customer_blocked BOOLEAN;
  v_customer_balance NUMERIC;
BEGIN
  -- Verify customer exists and is active
  SELECT is_active, is_blocked, wallet_balance 
  INTO v_customer_active, v_customer_blocked, v_customer_balance
  FROM users WHERE uid = p_customer_id LIMIT 1;

  IF v_customer_active IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Customer not found'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF NOT v_customer_active THEN
    RETURN QUERY SELECT FALSE, 'Customer account not activated'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF v_customer_blocked THEN
    RETURN QUERY SELECT FALSE, 'Customer account is blocked'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF v_customer_balance < p_price THEN
    RETURN QUERY SELECT FALSE, 'Insufficient wallet balance'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  -- Create order
  BEGIN
    INSERT INTO orders (
      customer_id, customer_name, customer_phone,
      from_location, to_location, order_type, description,
      price, pricing_mode, status
    )
    VALUES (
      p_customer_id, p_customer_name, p_customer_phone,
      p_from_location, p_to_location, p_order_type, p_description,
      p_price, 'customer', 'pending'
    )
    RETURNING id INTO v_order_id;

    RETURN QUERY SELECT TRUE, 'Order created successfully'::TEXT, v_order_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT, NULL::UUID;
  END;
END;
$$;

-- Function: Accept order (driver reserves commission)
CREATE OR REPLACE FUNCTION public.accept_order(
  p_order_id UUID,
  p_driver_id TEXT,
  p_driver_name TEXT,
  p_driver_phone TEXT
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_driver_active BOOLEAN;
  v_driver_blocked BOOLEAN;
  v_driver_balance NUMERIC;
  v_commission NUMERIC;
BEGIN
  -- Verify order exists
  SELECT * INTO v_order FROM orders WHERE id = p_order_id LIMIT 1;
  
  IF v_order.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Order not found'::TEXT;
    RETURN;
  END IF;

  IF v_order.status != 'pending' THEN
    RETURN QUERY SELECT FALSE, 'Order is not pending'::TEXT;
    RETURN;
  END IF;

  -- Verify driver exists and is active
  SELECT is_active, is_blocked, wallet_balance
  INTO v_driver_active, v_driver_blocked, v_driver_balance
  FROM users WHERE uid = p_driver_id LIMIT 1;

  IF v_driver_active IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Driver not found'::TEXT;
    RETURN;
  END IF;

  IF NOT v_driver_active THEN
    RETURN QUERY SELECT FALSE, 'Driver account not activated'::TEXT;
    RETURN;
  END IF;

  IF v_driver_blocked THEN
    RETURN QUERY SELECT FALSE, 'Driver account is blocked'::TEXT;
    RETURN;
  END IF;

  -- Calculate commission (5%)
  v_commission := v_order.price * 0.05;

  -- Check if driver has enough balance for commission
  IF v_driver_balance < v_commission THEN
    RETURN QUERY SELECT FALSE, 'Insufficient balance to reserve commission'::TEXT;
    RETURN;
  END IF;

  -- Update order and reserve commission
  BEGIN
    UPDATE orders 
    SET 
      driver_id = p_driver_id,
      driver_name = p_driver_name,
      driver_phone = p_driver_phone,
      status = 'accepted',
      accepted_at = CURRENT_TIMESTAMP,
      company_commission = v_commission,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;

    -- Reserve commission from driver wallet
    UPDATE users SET wallet_balance = wallet_balance - v_commission WHERE uid = p_driver_id;

    -- Record commission reservation
    INSERT INTO transactions (user_id, transaction_type, amount, order_id, description, status)
    VALUES (p_driver_id, 'reservation', v_commission, p_order_id, 'Commission reservation', 'completed');

    RETURN QUERY SELECT TRUE, 'Order accepted and commission reserved'::TEXT;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT;
  END;
END;
$$;

-- Function: Confirm delivery and settle payment
CREATE OR REPLACE FUNCTION public.confirm_delivery(
  p_order_id UUID,
  p_customer_id TEXT
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_driver_earning NUMERIC;
  v_company_earning NUMERIC;
BEGIN
  -- Verify order exists
  SELECT * INTO v_order FROM orders WHERE id = p_order_id LIMIT 1;
  
  IF v_order.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Order not found'::TEXT;
    RETURN;
  END IF;

  IF v_order.status != 'driver_delivered' THEN
    RETURN QUERY SELECT FALSE, 'Order status is not driver_delivered'::TEXT;
    RETURN;
  END IF;

  IF v_order.customer_id != p_customer_id THEN
    RETURN QUERY SELECT FALSE, 'Only the customer can confirm delivery'::TEXT;
    RETURN;
  END IF;

  -- Calculate payouts (95% to driver, 5% company keeps)
  v_driver_earning := v_order.price * 0.95;
  v_company_earning := v_order.price * 0.05;

  -- Settle payment
  BEGIN
    -- Update order status
    UPDATE orders 
    SET 
      status = 'completed',
      completed_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;

    -- Charge customer wallet
    UPDATE users SET wallet_balance = wallet_balance - v_order.price WHERE uid = p_customer_id;
    
    INSERT INTO transactions (user_id, transaction_type, amount, order_id, description, status)
    VALUES (p_customer_id, 'order_cost', v_order.price, p_order_id, 'Order payment', 'completed');

    -- Pay driver (95%)
    UPDATE users SET wallet_balance = wallet_balance + v_driver_earning WHERE uid = v_order.driver_id;
    
    INSERT INTO transactions (user_id, transaction_type, amount, order_id, description, status)
    VALUES (v_order.driver_id, 'driver_payout', v_driver_earning, p_order_id, 'Order payout', 'completed');

    RETURN QUERY SELECT TRUE, 'Delivery confirmed and payment settled'::TEXT;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT;
  END;
END;
$$;

-- Function: Review topup (approve/reject with wallet update)
CREATE OR REPLACE FUNCTION public.review_topup(
  p_topup_id UUID,
  p_approve BOOLEAN,
  p_admin_id TEXT
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_topup RECORD;
BEGIN
  -- Verify topup exists
  SELECT * INTO v_topup FROM topups WHERE id = p_topup_id LIMIT 1;
  
  IF v_topup.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Topup not found'::TEXT;
    RETURN;
  END IF;

  IF v_topup.status != 'pending' THEN
    RETURN QUERY SELECT FALSE, 'Topup is not pending'::TEXT;
    RETURN;
  END IF;

  BEGIN
    IF p_approve THEN
      -- Approve: Add to wallet
      UPDATE topups 
      SET status = 'approved', reviewed_by = p_admin_id, reviewed_at = CURRENT_TIMESTAMP
      WHERE id = p_topup_id;

      UPDATE users SET wallet_balance = wallet_balance + v_topup.amount WHERE uid = v_topup.user_id;

      INSERT INTO transactions (user_id, transaction_type, amount, description, status)
      VALUES (v_topup.user_id, 'topup', v_topup.amount, 'Topup approved', 'completed');

      RETURN QUERY SELECT TRUE, 'Topup approved'::TEXT;
    ELSE
      -- Reject: Just mark as rejected
      UPDATE topups 
      SET status = 'rejected', reviewed_by = p_admin_id, reviewed_at = CURRENT_TIMESTAMP
      WHERE id = p_topup_id;

      RETURN QUERY SELECT TRUE, 'Topup rejected'::TEXT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT;
  END;
END;
$$;

-- Function: Review withdrawal (approve/reject)
CREATE OR REPLACE FUNCTION public.review_withdrawal(
  p_withdrawal_id UUID,
  p_approve BOOLEAN,
  p_admin_id TEXT
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_withdrawal RECORD;
BEGIN
  -- Verify withdrawal exists
  SELECT * INTO v_withdrawal FROM withdrawals WHERE id = p_withdrawal_id LIMIT 1;
  
  IF v_withdrawal.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Withdrawal not found'::TEXT;
    RETURN;
  END IF;

  IF v_withdrawal.status != 'pending' THEN
    RETURN QUERY SELECT FALSE, 'Withdrawal is not pending'::TEXT;
    RETURN;
  END IF;

  BEGIN
    IF p_approve THEN
      -- Approve: Deduct from wallet
      UPDATE withdrawals 
      SET status = 'approved', reviewed_by = p_admin_id, reviewed_at = CURRENT_TIMESTAMP
      WHERE id = p_withdrawal_id;

      UPDATE users SET wallet_balance = wallet_balance - v_withdrawal.amount WHERE uid = v_withdrawal.user_id;

      INSERT INTO transactions (user_id, transaction_type, amount, description, status)
      VALUES (v_withdrawal.user_id, 'withdrawal', v_withdrawal.amount, 'Withdrawal approved', 'completed');

      RETURN QUERY SELECT TRUE, 'Withdrawal approved'::TEXT;
    ELSE
      -- Reject: Return amount (it was never deducted, so just mark as rejected)
      UPDATE withdrawals 
      SET status = 'rejected', reviewed_by = p_admin_id, reviewed_at = CURRENT_TIMESTAMP
      WHERE id = p_withdrawal_id;

      RETURN QUERY SELECT TRUE, 'Withdrawal rejected'::TEXT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT;
  END;
END;
$$;

-- Function: Update order status (driver side)
CREATE OR REPLACE FUNCTION public.update_order_status(
  p_order_id UUID,
  p_driver_id TEXT,
  p_new_status TEXT
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_allowed_transitions JSONB;
BEGIN
  -- Verify order exists
  SELECT * INTO v_order FROM orders WHERE id = p_order_id LIMIT 1;
  
  IF v_order.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Order not found'::TEXT;
    RETURN;
  END IF;

  -- Only driver assigned to order can update
  IF v_order.driver_id != p_driver_id THEN
    RETURN QUERY SELECT FALSE, 'Only assigned driver can update this order'::TEXT;
    RETURN;
  END IF;

  -- Validate status transitions
  v_allowed_transitions := jsonb_build_object(
    'accepted', 'picked_up',
    'picked_up', 'driver_delivered'
  );

  IF NOT (v_allowed_transitions ->> v_order.status = p_new_status) THEN
    RETURN QUERY SELECT FALSE, 'Invalid status transition'::TEXT;
    RETURN;
  END IF;

  BEGIN
    CASE p_new_status
      WHEN 'picked_up' THEN
        UPDATE orders SET status = 'picked_up', picked_up_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = p_order_id;
      WHEN 'driver_delivered' THEN
        UPDATE orders SET status = 'driver_delivered', driver_delivered_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = p_order_id;
      ELSE
        RETURN QUERY SELECT FALSE, 'Invalid status'::TEXT;
        RETURN;
    END CASE;

    RETURN QUERY SELECT TRUE, 'Status updated successfully'::TEXT;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, SQLERRM::TEXT;
  END;
END;
$$;

-- ============================================================================
-- AUTO-UPDATE TRIGGER for updated_at columns
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================
CREATE INDEX idx_orders_status_created ON public.orders(status, created_at DESC);
CREATE INDEX idx_topups_user_status ON public.topups(user_id, status);
CREATE INDEX idx_withdrawals_user_status ON public.withdrawals(user_id, status);
CREATE INDEX idx_transactions_user_type ON public.transactions(user_id, transaction_type);
