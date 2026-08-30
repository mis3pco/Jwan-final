# Jwan Delivery - GitHub Pages Deployment Guide

## Quick Start

### 1. Supabase Setup (Manual - One Time Only)

1. Go to [supabase.co](https://supabase.co) and create a project named `jwan-storage`
2. Note your **Project URL** and **Publishable Key** (Anon key)
3. In Supabase Dashboard:
   - Go to **SQL Editor** → **New Query**
   - Copy entire contents of `supabase/schema.sql` from this repo
   - Paste and click **Run**
   - Wait for all tables to be created

4. Create Storage bucket:
   - Go to **Storage** → **Create Bucket**
   - Name: `jwan-files`
   - Make it **Private**
   - Go to **Policies** tab
   - Create a new policy: Allow authenticated users to read/write their own files

5. Enable Email Authentication:
   - Go to **Authentication** → **Providers**
   - Enable **Email** (already enabled by default)
   - Disable **Email Confirmations** if testing locally, enable for production

### 2. GitHub Pages Setup (Automatic)

The repository is already configured for GitHub Pages:
- Static HTML file: `index.html`
- All CSS and JS are inline in the HTML
- Assets in `assets/` folder
- Deployed from `main` branch to GitHub Pages

### 3. Update Configuration

1. Copy `.env.example` to `.env.local` (for local testing only, never commit):
   ```bash
   cp .env.example .env.local
   ```

2. Add your Supabase credentials to `index.html` (lines 50-52):
   ```javascript
   const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
   const SUPABASE_PUBLISHABLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...";
   ```

### 4. GitHub Pages URL

Your website will be available at:
```
https://mis3pco.github.io/Jwan-final/
```

### 5. Test Locally

Open `index.html` in your browser:
```bash
# On macOS
open index.html

# On Linux
xdg-open index.html

# Or use a local server:
python3 -m http.server 8000
# Then visit http://localhost:8000
```

### 6. Troubleshooting

**"SUPABASE_URL is not configured":**
- Make sure you've added the URL and Publishable Key to `index.html`
- Check Supabase Dashboard for your project credentials

**Blank page:**
- Open browser DevTools (F12)
- Check Console for errors
- Most likely: Supabase credentials missing or incorrect

**Authentication fails:**
- Ensure Email provider is enabled in Supabase
- Check that users table was created properly
- Verify RLS policies allow anonymous auth to create users

**Storage uploads fail:**
- Verify `jwan-files` bucket exists
- Ensure Storage policies allow authenticated users

## What Works Now

✅ User Authentication (Email/Password)
✅ User Registration
✅ Role-based access (customer/driver/admin)
✅ Order creation and management
✅ Wallet balance tracking
✅ Topup and withdrawal requests
✅ Support tickets
✅ Order ratings and comments
✅ Real-time updates via Supabase Realtime
✅ File storage for identity/documents

## What Needs Manual Supabase Setup

Only these steps cannot be automated:

1. **Create Supabase Project** - Must visit supabase.co manually
2. **Get Publishable Key** - Must copy from Supabase Dashboard
3. **Run schema.sql** - Copy/paste into Supabase SQL Editor and run
4. **Create Storage Bucket** - Use Supabase Dashboard
5. **Enable Email Auth** - Should be enabled by default

## Security Notes

- Never commit `.env` or any file with secrets
- `SUPABASE_PUBLISHABLE_KEY` in `index.html` is safe (it's public)
- All financial operations are protected by server-side validation
- Users cannot modify their own wallet balance or status
- Admin operations require server-side verification

## Questions?

Check `README_SETUP.md` for detailed Firebase-to-Supabase migration info.
