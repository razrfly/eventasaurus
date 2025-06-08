# Cascading Delete Issues in Eventasaurus - Problem Analysis & Solution

## Problem Summary

When deleting users from the `public.users` table in the Supabase UI, orphaned records are left behind in multiple related tables:
- `auth.users` (Supabase authentication records)
- `event_participants` 
- `event_users`
- `event_date_votes`
- Other user-related data

This breaks referential integrity and creates data inconsistencies.

## Root Cause Analysis

### 1. **Missing Bidirectional Triggers**
The current migration `20250608104045_add_auth_users_foreign_key.exs` only handles deletion from `auth.users` → `public.users`:

```sql
CREATE TRIGGER on_auth_user_deleted
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.delete_user_on_auth_delete();
```

**Missing:** Trigger for `public.users` → `auth.users` deletion

### 2. **Supabase's Auth Schema Isolation**
According to Supabase documentation, the `auth.users` table is isolated and:
- Cannot have direct foreign key constraints from public tables
- Requires trigger-based synchronization
- Must be handled carefully to avoid 500 authentication errors

### 3. **Current Foreign Key Setup**
While our `public` schema tables have correct CASCADE constraints:
```sql
-- These work correctly within public schema
event_participants.user_id → users.id ON DELETE CASCADE
event_users.user_id → users.id ON DELETE CASCADE  
event_date_votes.user_id → users.id ON DELETE CASCADE
```

The problem is the disconnect between `auth.users` and `public.users`.

### 4. **Temporary User Pattern Complication**
Our application creates **temporary users** with `supabase_id` like `"temp_<UUID>"` for users who:
- Register for events before confirming their email
- Haven't completed Supabase authentication yet

These temporary records should **NOT** trigger `auth.users` deletions since they don't have corresponding auth records.

## Supabase's Official Recommendations

Based on Supabase documentation review, they recommend:

### 1. **Use Triggers for auth.users Synchronization**
> "Since we can't create a direct FK between UUID and string, we'll use the official Supabase approach: database triggers"

### 2. **Avoid Direct Foreign Keys to auth.users**
The docs warn that foreign keys referencing `auth.users` can cause:
- 500 authentication errors
- Auth server being unable to update/delete users
- System instability

### 3. **Bidirectional Trigger Pattern**
```sql
-- Handle auth.users deletion
CREATE TRIGGER on_auth_user_deleted
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.delete_user_on_auth_delete();

-- Handle public.users deletion  
CREATE TRIGGER on_public_user_deleted
  AFTER DELETE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.delete_auth_user_on_public_delete();
```

## Exact Solution Required

### Step 1: Create Missing Reverse Trigger Function

Create a new migration file: `priv/repo/migrations/20250608110000_add_bidirectional_user_triggers.exs`

```elixir
defmodule EventasaurusApp.Repo.Migrations.AddBidirectionalUserTriggers do
  use Ecto.Migration

  def up do
    # Function to delete auth user when public user is deleted
    execute """
    CREATE OR REPLACE FUNCTION public.delete_auth_user_on_public_delete()
    RETURNS TRIGGER AS $$
    BEGIN
      -- Only attempt deletion if supabase_id is valid UUID (not temporary)
      -- Temporary IDs start with 'temp_' and should not be deleted from auth.users
      IF OLD.supabase_id IS NOT NULL 
         AND OLD.supabase_id !~ '^temp_' 
         AND OLD.supabase_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        DELETE FROM auth.users WHERE id = OLD.supabase_id::uuid;
      END IF;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """

    # Trigger on public.users deletion
    execute """
    CREATE TRIGGER on_public_user_deleted
      AFTER DELETE ON public.users
      FOR EACH ROW EXECUTE FUNCTION public.delete_auth_user_on_public_delete();
    """
  end

  def down do
    # Remove the trigger and function
    execute "DROP TRIGGER IF EXISTS on_public_user_deleted ON public.users"
    execute "DROP FUNCTION IF EXISTS public.delete_auth_user_on_public_delete()"
  end
end
```

### Step 2: Verify Existing CASCADE Constraints

Run this SQL to verify your current foreign key constraints are properly set up:

```sql
SELECT 
    tc.table_name, 
    tc.constraint_name, 
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
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
    AND tc.table_name IN ('event_participants', 'event_users', 'event_date_votes', 'event_date_polls', 'event_date_options')
ORDER BY tc.table_name, tc.constraint_name;
```

Expected results should show `delete_rule = 'CASCADE'` for all user_id foreign keys.

### Step 3: Test the Solution

After running the migration:

1. **Create a test user:**
   ```sql
   -- Create auth user
   INSERT INTO auth.users (id, email) VALUES (gen_random_uuid(), 'test@example.com');
   
   -- This should trigger creation of public.users record via existing trigger
   ```

2. **Test deletion from public.users:**
   ```sql
   DELETE FROM public.users WHERE email = 'test@example.com';
   -- Should now also delete from auth.users
   ```

3. **Test deletion from auth.users:**
   ```sql
   DELETE FROM auth.users WHERE email = 'test@example.com';
   -- Should delete from public.users (existing functionality)
   ```

### Step 4: Update Documentation

Update your application's user management documentation to note:
- Users should be deleted through the application, not directly via SQL
- Deletions will cascade through both auth and public schemas
- Manual database operations should be avoided for user management

## Expected Behavior After Fix

### When deleting from `public.users`:
1. Trigger deletes corresponding `auth.users` record
2. CASCADE constraints delete all related records:
   - `event_participants` 
   - `event_users`
   - `event_date_votes`
   - Any other tables with `user_id` foreign keys

### When deleting from `auth.users`:
1. Existing trigger deletes corresponding `public.users` record
2. CASCADE constraints delete all related records (same as above)

## Verification Commands

After implementing the fix, use these commands to verify proper cleanup:

```sql
-- Check for orphaned auth.users (should be 0)
SELECT COUNT(*) FROM auth.users a 
WHERE NOT EXISTS (SELECT 1 FROM public.users p WHERE p.supabase_id = a.id::text);

-- Check for orphaned public.users (should be 0)  
SELECT COUNT(*) FROM public.users p
WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id::text = p.supabase_id);

-- Check for orphaned event_participants (should be 0)
SELECT COUNT(*) FROM event_participants ep
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = ep.user_id);
```

## Code Improvements Implemented

### 1. **Improved Temporary ID Generation**
Updated the temporary `supabase_id` generation from:
```elixir
# Old: Potential collision risk
temp_supabase_id = "temp_#{System.unique_integer([:positive])}_#{System.system_time(:microsecond)}"

# New: Guaranteed uniqueness with UUID
temp_supabase_id = "temp_#{Ecto.UUID.generate()}"
```

Benefits:
- **Guaranteed uniqueness** using UUID standard
- **Cleaner format** that's easier to identify as temporary
- **Better pattern matching** for our trigger logic

### 2. **Enhanced Response Validation**
Improved magic link response handling with better logging:
```elixir
{:ok, %{"email_sent" => true} = magic_link_response} ->
  Logger.info("Magic link sent for new user", %{
    response: Map.take(magic_link_response, ["email_sent", "message_id"])
  })
```

## Additional Recommendations

### 1. Application-Level User Deletion
Implement user deletion through your Elixir application rather than direct SQL:

```elixir
def delete_user(%User{} = user) do
  # This will trigger all the cascades properly
  Repo.delete(user)
end
```

### 2. Soft Deletes Consideration
For audit purposes, consider implementing soft deletes:
- Add `deleted_at` timestamp field
- Use scopes to filter out deleted users
- Preserve data for compliance/audit requirements

### 3. Background Cleanup Job
Implement a periodic cleanup job to catch any edge cases:
```elixir
def cleanup_orphaned_records do
  # Clean up any orphaned auth.users
  # Clean up any orphaned public records
end
```

This solution follows Supabase's official recommendations and should resolve all cascading delete issues. 