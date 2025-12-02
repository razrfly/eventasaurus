# Clerk User Migration

Migrate confirmed users to Clerk with our `users.id` as the canonical identifier.

## Architecture

- **Our `users.id`** (integer primary key) is the canonical identifier
- **Clerk `external_id`** stores our user ID
- **JWT claims** include `external_id` for user lookup
- **No Supabase UUID references** - clean slate architecture

## Files

- `users.json` - Exported users (generated from SQL query)
- `import-users.js` - Node.js script to import users to Clerk
- `package.json` - Dependencies

## Prerequisites

1. Clerk production credentials in `.env`:
   ```
   CLERK_PUBLISHABLE_KEY=pk_live_...
   CLERK_SECRET_KEY=sk_live_...
   ```

2. Node.js 18+

## Usage

### 1. Export Confirmed Users from Database

Run this SQL query in Supabase SQL Editor (joins public.users with auth.users):

```sql
SELECT json_agg(
  json_build_object(
    'userId', u.id::text,
    'email', au.email,
    'firstName', split_part(u.name, ' ', 1),
    'lastName', CASE
      WHEN position(' ' in u.name) > 0
      THEN substring(u.name from position(' ' in u.name) + 1)
      ELSE ''
    END,
    'password', au.encrypted_password,
    'passwordHasher', 'bcrypt'
  )
)
FROM public.users u
JOIN auth.users au ON u.supabase_id = au.id::text
WHERE au.email_confirmed_at IS NOT NULL;
```

Save the JSON array output to `users.json`.

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

1. Each user is created in Clerk with:
   - `external_id` = our `users.id` (integer, as string)
   - `email_address` = user's email
   - `first_name`, `last_name` = parsed from name
   - `password_digest` = bcrypt hash (users keep same password)

2. Results are saved to `import-results-{timestamp}.json`

## Post-Import: Configure Session Claims

After import, configure Clerk to include external_id in JWT claims:

1. Go to Clerk Dashboard → Sessions → Customize session token
2. Add custom claim:
   ```json
   {
     "userId": "{{user.external_id}}"
   }
   ```

This ensures the Elixir backend receives our user ID for direct database lookup.

## Troubleshooting

### Rate Limiting
The script includes a 100ms delay between requests (10 req/sec).
Clerk allows 20 req/sec, so we have headroom.

### Duplicate Emails
If a user already exists in Clerk, the import will fail for that user.
Check the results file for details.

### Password Issues
All passwords are bcrypt ($2a$10$...). Clerk supports this natively.
Users can sign in with their existing passwords.

## Next Steps

After successful import:
1. Configure Clerk session claims (see above)
2. Update application code to use `external_id` for user lookup
3. Make `supabase_id` column nullable
4. Eventually drop `supabase_id` column
