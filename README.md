Jwan Delivery

Jwan Delivery is a web-based delivery management platform designed to connect customers, delivery drivers, and administrators.

The project is being migrated from Firebase to Supabase and uses GitHub for source code management and deployment.

Features

Customers

- Create an account and log in
- Create delivery orders
- Track order status
- View order history
- Add balance to the wallet
- Request support
- Rate delivery drivers

Drivers

- Create a driver account
- View available orders
- Accept delivery orders
- Update delivery status
- View delivery history
- Request wallet withdrawals

Administrators

- Manage users
- Review driver accounts
- Manage orders
- Review wallet top-ups
- Review withdrawal requests
- Manage delivery pricing
- Monitor transactions and platform activity

Technology Stack

Frontend

- HTML
- CSS
- JavaScript
- Progressive Web App (PWA)

Backend

- Supabase Auth
- Supabase PostgreSQL Database
- Supabase Storage
- Supabase Realtime
- Supabase Edge Functions

Development and Hosting

- GitHub
- GitHub Pages

Project Structure

Jwan-final/
│
├── assets/
│   ├── banner.png
│   ├── logo.svg
│   └── project images
│
├── supabase/
│   ├── schema.sql
│   ├── storage_policies.sql
│   └── MIGRATION_ISSUES.md
│
├── functions/
│   └── Firebase functions (legacy backup)
│
├── index.html
├── manifest.webmanifest
├── firebase-messaging-sw.js
├── README_SETUP.md
├── DATA_MODEL.md
├── netlify.toml
└── .env.example

Supabase Setup

The project uses Supabase as its backend.

Required services:

- Authentication
- PostgreSQL Database
- Storage
- Row Level Security (RLS)
- Realtime

Before running the project:

1. Create a Supabase project.
2. Configure Supabase Authentication.
3. Run the database schema from:

supabase/schema.sql

4. Configure Storage policies from:

supabase/storage_policies.sql

5. Create the required Storage bucket:

jwan-files

6. Add your Supabase project URL and publishable key to the application configuration.

Environment Variables

Example configuration:

SUPABASE_URL=your_supabase_project_url
SUPABASE_PUBLISHABLE_KEY=your_supabase_publishable_key

Never expose the following in frontend code:

- Supabase service role key
- Database password
- Private API keys

Security

Jwan Delivery uses Supabase Row Level Security (RLS) to protect user data.

Security rules ensure that:

- Users can access only their authorized data.
- Drivers can access relevant delivery orders.
- Customers can access their own orders.
- Administrative operations are restricted.
- Sensitive wallet and financial operations are protected.
- Users cannot modify their own administrative roles.
- Sensitive operations should be handled by secure backend functions.

Deployment

The frontend is intended to be deployed using GitHub Pages.

Supabase handles:

- Authentication
- Database
- File storage
- Realtime updates
- Backend services

Migration Status

The project originally used Firebase.

The migration includes:

- Firebase Authentication → Supabase Auth
- Firestore → Supabase PostgreSQL
- Firebase Storage → Supabase Storage
- Firestore Security Rules → Supabase RLS
- Firebase Realtime Listeners → Supabase Realtime
- Firebase Functions → Supabase Edge Functions

Firebase files are temporarily preserved during migration for backup and compatibility purposes.

Development Status

🚧 The project is currently under active development and migration.

Before production deployment, all database policies, authentication flows, financial operations, and security rules should be reviewed and tested.

Repository

Source code:

https://github.com/mis3pco/Jwan-final

License

This project is currently private development work for Jwan Delivery.

Unauthorized copying, redistribution, or commercial use may require permission from the project owner.
