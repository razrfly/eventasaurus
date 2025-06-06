#!/bin/bash

# Production Readiness Verification Script
# Run this before deploying the authentication flow enhancement

set -e

echo "🔍 Production Readiness Verification"
echo "===================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Helper functions
check_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((CHECKS_WARNING++))
}

echo "1. 🔧 Checking Local Development Environment"
echo "--------------------------------------------"

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    check_fail "Not in Elixir project root directory"
    exit 1
fi
check_pass "In Elixir project root directory"

# Check if Fly CLI is installed
if command -v fly &> /dev/null; then
    check_pass "Fly CLI is installed"
    FLY_VERSION=$(fly version | head -n1)
    echo "   Version: $FLY_VERSION"
else
    check_fail "Fly CLI not installed. Install from https://fly.io/docs/hands-on/install-flyctl/"
fi

# Check if logged into Fly
if fly auth whoami &> /dev/null; then
    check_pass "Logged into Fly.io"
    FLY_USER=$(fly auth whoami)
    echo "   User: $FLY_USER"
else
    check_fail "Not logged into Fly.io. Run: fly auth login"
fi

echo ""
echo "2. 🚀 Checking Fly.io App Configuration"
echo "---------------------------------------"

# Check if app exists
if fly apps list | grep -q "eventasaurus"; then
    check_pass "Eventasaurus app exists on Fly.io"
else
    check_fail "Eventasaurus app not found on Fly.io"
fi

# Check app status
APP_STATUS=$(fly status --app eventasaurus 2>/dev/null | grep "Status" | awk '{print $2}' || echo "unknown")
if [ "$APP_STATUS" = "running" ]; then
    check_pass "App is currently running"
elif [ "$APP_STATUS" = "stopped" ]; then
    check_warn "App is currently stopped"
else
    check_warn "App status unknown: $APP_STATUS"
fi

echo ""
echo "3. 🔐 Checking Environment Variables"
echo "-----------------------------------"

# Check required secrets
REQUIRED_SECRETS=("SECRET_KEY_BASE" "SUPABASE_URL" "SUPABASE_API_KEY" "SUPABASE_DATABASE_URL")

for secret in "${REQUIRED_SECRETS[@]}"; do
    if fly secrets list --app eventasaurus | grep -q "$secret"; then
        check_pass "Secret $secret is set"
    else
        check_fail "Secret $secret is missing"
    fi
done

# Check optional secrets
OPTIONAL_SECRETS=("SUPABASE_BUCKET" "POOL_SIZE" "SSL_VERIFY_PEER")

for secret in "${OPTIONAL_SECRETS[@]}"; do
    if fly secrets list --app eventasaurus | grep -q "$secret"; then
        check_pass "Optional secret $secret is set"
    else
        check_warn "Optional secret $secret not set (will use default)"
    fi
done

echo ""
echo "4. 🗄️ Checking Database Connectivity"
echo "------------------------------------"

# Test database connection (if possible)
if [ -n "$SUPABASE_DATABASE_URL" ]; then
    if command -v psql &> /dev/null; then
        if psql "$SUPABASE_DATABASE_URL" -c "SELECT 1;" &> /dev/null; then
            check_pass "Database connection successful"
        else
            check_fail "Cannot connect to database"
        fi
    else
        check_warn "psql not installed, cannot test database connection"
    fi
else
    check_warn "SUPABASE_DATABASE_URL not set locally, cannot test connection"
fi

echo ""
echo "5. 📦 Checking Application Build"
echo "-------------------------------"

# Check if assets are compiled
if [ -d "priv/static" ] && [ "$(ls -A priv/static)" ]; then
    check_pass "Static assets directory exists and is not empty"
else
    check_warn "Static assets may not be compiled. Run: mix assets.deploy"
fi

# Check if dependencies are up to date
if mix deps.get --only prod &> /dev/null; then
    check_pass "Dependencies are available"
else
    check_fail "Dependencies check failed"
fi

# Test compilation
if mix compile --warnings-as-errors &> /dev/null; then
    check_pass "Application compiles without warnings"
else
    check_warn "Application has compilation warnings or errors"
fi

echo ""
echo "6. 🧪 Checking Test Suite"
echo "------------------------"

# Run critical tests
if mix test test/eventasaurus_web/controllers/auth_controller_callback_test.exs --max-failures=1 &> /dev/null; then
    check_pass "Authentication callback tests pass"
else
    check_fail "Authentication callback tests fail"
fi

if mix test test/eventasaurus_web/live/simple_registration_test.exs --max-failures=1 &> /dev/null; then
    check_pass "Registration flow tests pass"
else
    check_fail "Registration flow tests fail"
fi

echo ""
echo "7. 📋 Pre-Deployment Checklist"
echo "------------------------------"

echo "Manual verification required:"
echo ""
echo "Supabase Configuration:"
echo "  [ ] Site URL set to: https://eventasaur.us"
echo "  [ ] Redirect URLs include: https://eventasaur.us/auth/callback"
echo "  [ ] Email confirmation enabled (auto_confirm_email: false)"
echo "  [ ] Email templates configured for production domain"
echo ""
echo "Security Configuration:"
echo "  [ ] Production API keys (not test keys) configured"
echo "  [ ] Rate limiting configured"
echo "  [ ] CORS settings restricted to production domains"
echo ""
echo "Backup & Rollback:"
echo "  [ ] Current version tagged in git"
echo "  [ ] Database backup created"
echo "  [ ] Rollback plan tested"

echo ""
echo "📊 Summary"
echo "=========="
echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Checks failed: ${RED}$CHECKS_FAILED${NC}"
echo -e "Warnings: ${YELLOW}$CHECKS_WARNING${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 Ready for deployment!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Complete manual checklist above"
    echo "2. Create backup: git tag v1.0.0-pre-auth-enhancement"
    echo "3. Deploy: fly deploy --wait-timeout 300"
    echo "4. Monitor: fly logs --follow"
    exit 0
else
    echo -e "${RED}🚫 Not ready for deployment${NC}"
    echo ""
    echo "Please fix the failed checks before deploying."
    exit 1
fi 