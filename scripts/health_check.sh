#!/bin/bash

# Health Check Script for Eventasaurus
# Run this script to verify the application is working correctly

set -e

echo "🔍 Eventasaurus Health Check - $(date)"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

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
}

echo ""
echo "1. 🌐 Basic Connectivity"
echo "------------------------"

# Test main site
if curl -f -s -I https://eventasaur.us/ | head -n1 | grep -q "200"; then
    check_pass "Main site responding (https://eventasaur.us/)"
else
    check_fail "Main site not responding"
fi

# Test auth callback endpoint
if curl -f -s -I https://eventasaur.us/auth/callback | head -n1 | grep -qE "(200|302)"; then
    check_pass "Auth callback endpoint responding"
else
    check_fail "Auth callback endpoint not responding"
fi

echo ""
echo "2. 🚀 Application Status"
echo "-----------------------"

# Check if fly CLI is available and app status
if command -v fly &> /dev/null; then
    if fly auth whoami &> /dev/null; then
        APP_STATUS=$(fly status --app eventasaurus 2>/dev/null | grep "Status" | awk '{print $2}' || echo "unknown")
        if [ "$APP_STATUS" = "running" ]; then
            check_pass "Application status: running"
        else
            check_fail "Application status: $APP_STATUS"
        fi
    else
        check_warn "Not logged into Fly.io - cannot check app status"
    fi
else
    check_warn "Fly CLI not available - cannot check app status"
fi

echo ""
echo "3. 🗄️ Database Connectivity"
echo "---------------------------"

# Test database connection (requires fly CLI and auth)
if command -v fly &> /dev/null && fly auth whoami &> /dev/null; then
    if fly ssh console --app eventasaurus -C "/app/bin/eventasaurus eval 'EventasaurusApp.Repo.query(\"SELECT 1\")'" 2>/dev/null | grep -q "ok"; then
        check_pass "Database connection working"
    else
        check_fail "Database connection failed"
    fi
else
    check_warn "Cannot test database connection (requires fly CLI and auth)"
fi

echo ""
echo "4. 📧 Authentication Endpoints"
echo "------------------------------"

# Test specific auth-related endpoints
AUTH_ENDPOINTS=(
    "https://eventasaur.us/auth/login"
    "https://eventasaur.us/auth/register"
    "https://eventasaur.us/auth/callback"
)

for endpoint in "${AUTH_ENDPOINTS[@]}"; do
    if curl -f -s -I "$endpoint" | head -n1 | grep -qE "(200|302)"; then
        check_pass "$(basename "$endpoint") endpoint responding"
    else
        check_fail "$(basename "$endpoint") endpoint not responding"
    fi
done

echo ""
echo "5. 🔍 Error Monitoring"
echo "---------------------"

# Check recent logs for errors (if fly CLI available)
if command -v fly &> /dev/null && fly auth whoami &> /dev/null; then
    ERROR_COUNT=$(fly logs --app eventasaurus | tail -100 | grep -cE "(ERROR|CRITICAL|FATAL)" || echo "0")
    if [ "$ERROR_COUNT" -eq 0 ]; then
        check_pass "No recent errors in logs"
    elif [ "$ERROR_COUNT" -lt 5 ]; then
        check_warn "Found $ERROR_COUNT recent errors (check logs)"
    else
        check_fail "Found $ERROR_COUNT recent errors (investigate immediately)"
    fi
else
    check_warn "Cannot check logs (requires fly CLI and auth)"
fi

echo ""
echo "📊 Health Check Summary"
echo "======================"
echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Checks failed: ${RED}$CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All critical checks passed!${NC}"
    echo ""
    echo "System appears to be healthy. Continue monitoring."
    exit 0
else
    echo -e "${RED}⚠️  Some checks failed${NC}"
    echo ""
    echo "Investigate failed checks immediately."
    echo "Check application logs: fly logs --app eventasaurus"
    echo "Check Supabase dashboard for service status."
    exit 1
fi 