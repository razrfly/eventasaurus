# Clerk User Migration

This directory contains scripts to migrate users from Supabase Auth to Clerk.

## Files

- `users.json` - Exported Supabase users (auto-generated)
- `import-users.js` - Node.js script to import users to Clerk
- `package.json` - Dependencies

## Prerequisites

1. Clerk credentials in `.env`:
   ```
   CLERK_PUBLISHABLE_KEY=pk_test_...
   CLERK_SECRET_KEY=sk_test_...
   ```

2. Node.js 18+

## Usage

### 1. Export Users from Supabase (already done)

The `users.json` file was generated with:

```sql
SELECT json_agg(
  json_build_object(
    'userId', id::text,
    'email', email,
    'firstName', split_part(raw_user_meta_data->>'name', ' ', 1),
    'lastName', CASE
      WHEN position(' ' in raw_user_meta_data->>'name') > 0
      THEN substring(raw_user_meta_data->>'name' from position(' ' in raw_user_meta_data->>'name') + 1)
      ELSE ''
    END,
    'password', encrypted_password,
    'passwordHasher', 'bcrypt'
  )
)
FROM auth.users
WHERE email IS NOT NULL;
```

### 2. Install Dependencies

```bash
cd scripts/clerk-migration
npm install
```

### 3. Preview Import (Dry Run)

```bash
npm run dry-run
```

### 4. Run Import

```bash
npm start
```

## What Happens

1. Each Supabase user is created in Clerk with:
   - `external_id` = Supabase UUID (preserves ID mapping)
   - `email_address` = user's email
   - `first_name`, `last_name` = parsed from name metadata
   - `password_digest` = bcrypt hash (users keep same password)

2. Results are saved to `import-results-{timestamp}.json`

## Post-Import: Configure Session Claims

After import, configure Clerk to use the external_id in JWT claims:

1. Go to Clerk Dashboard → Sessions → Customize session token
2. Add custom claim:
   ```json
   {
     "userId": "{{user.external_id || user.id}}"
   }
   ```

This ensures the Elixir backend receives the original Supabase UUID.

## Troubleshooting

### Rate Limiting
The script includes a 100ms delay between requests (10 req/sec).
Clerk allows 20 req/sec, so we have headroom.

### Duplicate Emails
If a user already exists in Clerk, the import will fail for that user.
Check the results file for details.

### Password Issues
All Supabase passwords are bcrypt ($2a$10$...). Clerk supports this natively.
Users can sign in with their existing passwords.
