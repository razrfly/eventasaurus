# Cascading Delete Diagnosis - Why Constraints Aren't Working

## Problem Statement

**CASCADE constraints aren't working anywhere in the database**, not just auth.users ↔ public.users synchronization. When deleting from `public.users`, related records in `event_participants`, `event_users`, `event_date_votes`, etc. are NOT being deleted, despite having what appear to be CASCADE constraints.

## Diagnostic Steps

### Step 1: Check What Constraints Actually Exist

Run this query to see what foreign key constraints are **actually** in your database:

```sql
SELECT 
    tc.table_name, 
    tc.constraint_name, 
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule,
    rc.update_rule
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
LEFT JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' 
    AND tc.table_schema = 'public'
ORDER BY tc.table_name, tc.constraint_name;
```

**Expected Results:** All `delete_rule` should show `CASCADE` for user_id foreign keys.

### Step 2: Check Specific Tables

Check each table individually:

```sql
-- Check event_participants
SELECT constraint_name, delete_rule 
FROM information_schema.referential_constraints 
WHERE constraint_name LIKE '%event_participants%user%';

-- Check event_users  
SELECT constraint_name, delete_rule 
FROM information_schema.referential_constraints 
WHERE constraint_name LIKE '%event_users%user%';

-- Check event_date_votes
SELECT constraint_name, delete_rule 
FROM information_schema.referential_constraints 
WHERE constraint_name LIKE '%event_date_votes%user%';
```

### Step 3: Test Basic CASCADE Functionality

Create a test to see if ANY cascade works:

```sql
-- Create test tables
CREATE TABLE test_parent (
    id SERIAL PRIMARY KEY,
    name TEXT
);

CREATE TABLE test_child (
    id SERIAL PRIMARY KEY,
    parent_id INTEGER REFERENCES test_parent(id) ON DELETE CASCADE,
    name TEXT
);

-- Insert test data
INSERT INTO test_parent (id, name) VALUES (999, 'Test Parent');
INSERT INTO test_child (parent_id, name) VALUES (999, 'Test Child');

-- Test cascade
DELETE FROM test_parent WHERE id = 999;

-- Check if child was deleted (should be empty)
SELECT * FROM test_child WHERE parent_id = 999;

-- Cleanup
DROP TABLE test_child;
DROP TABLE test_parent;
```

## Likely Root Causes

### 1. **Ecto `:delete_all` vs PostgreSQL `CASCADE` Mismatch**

Your migrations use `:delete_all`:
```elixir
add :user_id, references(:users, on_delete: :delete_all), null: false
```

But this might not be generating proper PostgreSQL `CASCADE` constraints.

### 2. **Migration Application Issues**

Possible issues:
- Migrations ran but failed silently
- Constraints were created then later dropped
- Database was restored from backup without constraints
- Manual database changes overwrote migration results

### 3. **Supabase-Specific Constraint Handling**

Supabase might:
- Override certain constraint behaviors
- Have different default behaviors for foreign keys
- Apply additional schema policies that interfere

## Immediate Fix Options

### Option A: Verify and Recreate Constraints (Recommended)

If constraints are missing or wrong, manually add them:

```sql
-- Drop existing constraints first (if they exist incorrectly)
ALTER TABLE event_participants DROP CONSTRAINT IF EXISTS event_participants_user_id_fkey;
ALTER TABLE event_users DROP CONSTRAINT IF EXISTS event_users_user_id_fkey;  
ALTER TABLE event_date_votes DROP CONSTRAINT IF EXISTS event_date_votes_user_id_fkey;

-- Add correct CASCADE constraints
ALTER TABLE event_participants 
    ADD CONSTRAINT event_participants_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE event_users 
    ADD CONSTRAINT event_users_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE event_date_votes 
    ADD CONSTRAINT event_date_votes_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
```

### Option B: Create New Migration with Explicit SQL

Create `priv/repo/migrations/20250608120000_fix_cascade_constraints.exs`:

```elixir
defmodule EventasaurusApp.Repo.Migrations.FixCascadeConstraints do
  use Ecto.Migration

  def up do
    # Drop existing constraints that might be wrong
    execute "ALTER TABLE event_participants DROP CONSTRAINT IF EXISTS event_participants_user_id_fkey"
    execute "ALTER TABLE event_users DROP CONSTRAINT IF EXISTS event_users_user_id_fkey"  
    execute "ALTER TABLE event_date_votes DROP CONSTRAINT IF EXISTS event_date_votes_user_id_fkey"
    execute "ALTER TABLE event_date_polls DROP CONSTRAINT IF EXISTS event_date_polls_created_by_id_fkey"
    execute "ALTER TABLE event_date_options DROP CONSTRAINT IF EXISTS event_date_options_event_date_poll_id_fkey"

    # Add correct CASCADE constraints using explicit SQL
    execute """
    ALTER TABLE event_participants 
        ADD CONSTRAINT event_participants_user_id_fkey 
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE event_users 
        ADD CONSTRAINT event_users_user_id_fkey 
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE event_date_votes 
        ADD CONSTRAINT event_date_votes_user_id_fkey 
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    """

    # Note: event_date_polls.created_by_id should probably be SET NULL on user deletion
    execute """
    ALTER TABLE event_date_polls 
        ADD CONSTRAINT event_date_polls_created_by_id_fkey 
        FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
    """

    # event_date_options cascade through poll deletion
    execute """
    ALTER TABLE event_date_options 
        ADD CONSTRAINT event_date_options_event_date_poll_id_fkey 
        FOREIGN KEY (event_date_poll_id) REFERENCES event_date_polls(id) ON DELETE CASCADE
    """
  end

  def down do
    # Drop the constraints
    execute "ALTER TABLE event_participants DROP CONSTRAINT IF EXISTS event_participants_user_id_fkey"
    execute "ALTER TABLE event_users DROP CONSTRAINT IF EXISTS event_users_user_id_fkey"  
    execute "ALTER TABLE event_date_votes DROP CONSTRAINT IF EXISTS event_date_votes_user_id_fkey"
    execute "ALTER TABLE event_date_polls DROP CONSTRAINT IF EXISTS event_date_polls_created_by_id_fkey"
    execute "ALTER TABLE event_date_options DROP CONSTRAINT IF EXISTS event_date_options_event_date_poll_id_fkey"
  end
end
```

## Testing After Fix

Once constraints are properly applied, test with a real user:

```sql
-- Find a test user (or create one)
SELECT id, email FROM users LIMIT 1;

-- Check their related data BEFORE deletion
SELECT 
    'event_participants' as table_name, count(*) as count 
FROM event_participants WHERE user_id = <USER_ID>
UNION ALL
SELECT 
    'event_users' as table_name, count(*) as count 
FROM event_users WHERE user_id = <USER_ID>
UNION ALL  
SELECT 
    'event_date_votes' as table_name, count(*) as count 
FROM event_date_votes WHERE user_id = <USER_ID>;

-- Delete the user
DELETE FROM users WHERE id = <USER_ID>;

-- Verify all related data was deleted (all counts should be 0)
SELECT 
    'event_participants' as table_name, count(*) as count 
FROM event_participants WHERE user_id = <USER_ID>
UNION ALL
SELECT 
    'event_users' as table_name, count(*) as count 
FROM event_users WHERE user_id = <USER_ID>
UNION ALL  
SELECT 
    'event_date_votes' as table_name, count(*) as count 
FROM event_date_votes WHERE user_id = <USER_ID>;
```

## Why This Happens

### Common Ecto/PostgreSQL Issues:

1. **Ecto Constraint Translation Problems**
   - `:delete_all` doesn't always generate `ON DELETE CASCADE`
   - Different Ecto versions handle this differently
   - Supabase might have specific overrides

2. **Migration Timing Issues**
   - Constraints added before tables exist
   - Migrations run out of order
   - Rollbacks that didn't properly restore constraints

3. **Database State Drift**
   - Manual changes that overrode migrations
   - Schema loads from dumps without constraints
   - Different environments having different schemas

The bottom line: **Don't trust that Ecto's `:delete_all` actually created CASCADE constraints**. Always verify with the diagnostic queries above and use explicit SQL when in doubt. 