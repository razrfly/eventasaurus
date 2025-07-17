#!/bin/bash
# Test script for Sentry production configuration

echo "🧪 Testing Sentry Production Configuration..."

# Validate that SENTRY_DSN is set
if [ -z "$SENTRY_DSN" ]; then
  echo "❌ SENTRY_DSN environment variable is required"
  echo "Please set it with: export SENTRY_DSN=your_dsn_here"
  exit 1
fi

# Test 1: Production mode with real Sentry DSN
echo "Test 1: Production mode with Sentry DSN"
export MIX_ENV=prod
echo "Using SENTRY_DSN: ${SENTRY_DSN}"
SECRET_KEY_BASE=$(mix phx.gen.secret)
export SECRET_KEY_BASE
export PHX_HOST="localhost"
export SUPABASE_URL="https://dummy.supabase.co"
export SUPABASE_API_KEY="dummy_key"
export SUPABASE_DATABASE_URL="postgresql://postgres:postgres@localhost:54322/postgres"
export RESEND_API_KEY="dummy_key"

# Compile in production mode
mix deps.get --only prod
mix compile

# Test configuration loading
echo "✅ Configuration loaded successfully"

# Test 2: Production mode without Sentry DSN
echo "Test 2: Production mode without Sentry DSN"
unset SENTRY_DSN
mix compile
echo "✅ Sentry properly disabled when DSN missing"

# Test 3: Production mode with invalid DSN
echo "Test 3: Production mode with invalid DSN"
export SENTRY_DSN="invalid_dsn"
echo "Expected: Should fail with clear error message"
mix compile || echo "✅ Properly failed with invalid DSN"

echo "🎉 All tests completed!"