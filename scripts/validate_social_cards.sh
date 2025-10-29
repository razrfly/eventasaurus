#!/bin/bash

# Social Card Validation Script
# Validates social card endpoints and meta tags

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${APP_URL:-http://localhost:4000}"
VERBOSE="${VERBOSE:-0}"

# Counters
PASS=0
FAIL=0
WARN=0

echo ""
echo "======================================================================"
echo "🔍 Social Card Validation Suite"
echo "======================================================================"
echo ""
echo "Base URL: $BASE_URL"
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS++))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAIL++))
}

warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARN++))
}

info() {
    echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

# Test 1: Check server is running
echo "📡 Testing Server Connectivity..."
if curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200\|302\|301"; then
    pass "Server is reachable at $BASE_URL"
else
    fail "Server is not reachable at $BASE_URL"
    exit 1
fi
echo ""

# Test 2: Validate social card endpoints
echo "🖼️  Testing Social Card Endpoints..."

# Test event social card (example)
EVENT_URL="$BASE_URL/sample-event/social-card-abc12345.png"
if [ "$VERBOSE" = "1" ]; then
    info "Testing: $EVENT_URL"
fi

RESPONSE=$(curl -s -I "$EVENT_URL" || true)
HTTP_CODE=$(echo "$RESPONSE" | grep -i "^HTTP" | awk '{print $2}')

if [ "$HTTP_CODE" = "200" ]; then
    pass "Event social card endpoint responds with 200"

    # Check content type
    CONTENT_TYPE=$(echo "$RESPONSE" | grep -i "^content-type:" | awk '{print $2}' | tr -d '\r')
    if echo "$CONTENT_TYPE" | grep -q "image/png"; then
        pass "Content-Type is image/png"
    else
        fail "Content-Type is $CONTENT_TYPE, expected image/png"
    fi

    # Check cache headers
    CACHE_CONTROL=$(echo "$RESPONSE" | grep -i "^cache-control:" | awk '{print $2}' | tr -d '\r')
    if echo "$CACHE_CONTROL" | grep -q "max-age"; then
        pass "Cache-Control includes max-age"
    else
        warn "Cache-Control does not include max-age: $CACHE_CONTROL"
    fi

    # Check ETag
    ETAG=$(echo "$RESPONSE" | grep -i "^etag:" | awk '{print $2}' | tr -d '\r')
    if [ -n "$ETAG" ]; then
        pass "ETag header present: $ETAG"
    else
        warn "ETag header not found"
    fi

elif [ "$HTTP_CODE" = "404" ]; then
    info "Event endpoint returned 404 (sample data may not exist)"
elif [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    info "Event endpoint redirected (hash mismatch test working)"
    pass "Hash mismatch redirect working"
else
    warn "Event endpoint returned HTTP $HTTP_CODE"
fi
echo ""

# Test 3: Meta tags validation (requires HTML page)
echo "📋 Testing Meta Tags..."

# Test event page meta tags
EVENT_PAGE_URL="$BASE_URL/"
if [ "$VERBOSE" = "1" ]; then
    info "Fetching: $EVENT_PAGE_URL"
fi

HTML=$(curl -s "$EVENT_PAGE_URL" || true)

# Check for Open Graph tags
if echo "$HTML" | grep -q 'property="og:title"'; then
    pass "og:title tag present"
else
    warn "og:title tag not found"
fi

if echo "$HTML" | grep -q 'property="og:description"'; then
    pass "og:description tag present"
else
    warn "og:description tag not found"
fi

if echo "$HTML" | grep -q 'property="og:image"'; then
    pass "og:image tag present"

    # Extract image URL
    OG_IMAGE=$(echo "$HTML" | grep 'property="og:image"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1)
    if [ "$VERBOSE" = "1" ]; then
        info "og:image URL: $OG_IMAGE"
    fi

    # Check if URL is absolute
    if echo "$OG_IMAGE" | grep -q "^https\?://"; then
        pass "og:image is absolute URL"
    else
        fail "og:image is not absolute URL: $OG_IMAGE"
    fi
else
    warn "og:image tag not found"
fi

if echo "$HTML" | grep -q 'property="og:type"'; then
    pass "og:type tag present"
else
    warn "og:type tag not found"
fi

if echo "$HTML" | grep -q 'property="og:url"'; then
    pass "og:url tag present"
else
    warn "og:url tag not found"
fi

# Check for Twitter Card tags
if echo "$HTML" | grep -q 'name="twitter:card"'; then
    pass "twitter:card tag present"

    TWITTER_CARD=$(echo "$HTML" | grep 'name="twitter:card"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1)
    if echo "$TWITTER_CARD" | grep -q "summary_large_image"; then
        pass "twitter:card is summary_large_image"
    else
        warn "twitter:card is $TWITTER_CARD (expected summary_large_image)"
    fi
else
    warn "twitter:card tag not found"
fi

if echo "$HTML" | grep -q 'name="twitter:image"'; then
    pass "twitter:image tag present"
else
    warn "twitter:image tag not found"
fi

echo ""

# Test 4: JSON-LD structured data
echo "📊 Testing JSON-LD Structured Data..."

if echo "$HTML" | grep -q 'type="application/ld+json"'; then
    pass "JSON-LD script tag present"

    # Extract JSON-LD
    JSON_LD=$(echo "$HTML" | sed -n '/<script type="application\/ld+json">/,/<\/script>/p' | sed '1d;$d')

    if [ "$VERBOSE" = "1" ]; then
        info "JSON-LD content found"
    fi

    # Check if valid JSON (requires jq)
    if command -v jq &> /dev/null; then
        if echo "$JSON_LD" | jq . > /dev/null 2>&1; then
            pass "JSON-LD is valid JSON"

            # Check for @type
            if echo "$JSON_LD" | jq -e '.["@type"]' > /dev/null 2>&1; then
                TYPE=$(echo "$JSON_LD" | jq -r '.["@type"]')
                info "Schema type: $TYPE"
            fi
        else
            fail "JSON-LD is not valid JSON"
        fi
    else
        info "jq not installed, skipping JSON validation"
    fi
else
    warn "JSON-LD script tag not found"
fi

echo ""

# Test 5: Canonical URL
echo "🔗 Testing Canonical URL..."

if echo "$HTML" | grep -q 'rel="canonical"'; then
    pass "Canonical link tag present"

    CANONICAL=$(echo "$HTML" | grep 'rel="canonical"' | sed 's/.*href="\([^"]*\)".*/\1/' | head -1)

    if [ "$VERBOSE" = "1" ]; then
        info "Canonical URL: $CANONICAL"
    fi

    # Check if URL is absolute
    if echo "$CANONICAL" | grep -q "^https\?://"; then
        pass "Canonical URL is absolute"
    else
        fail "Canonical URL is not absolute: $CANONICAL"
    fi
else
    warn "Canonical link tag not found"
fi

echo ""

# Test 6: Performance check
echo "⚡ Testing Performance..."

# Measure response time for social card
if [ "$HTTP_CODE" = "200" ]; then
    START_TIME=$(date +%s%N)
    curl -s -o /dev/null "$EVENT_URL"
    END_TIME=$(date +%s%N)

    DURATION_MS=$(( ($END_TIME - $START_TIME) / 1000000 ))

    if [ "$VERBOSE" = "1" ]; then
        info "Response time: ${DURATION_MS}ms"
    fi

    if [ $DURATION_MS -lt 500 ]; then
        pass "Response time ${DURATION_MS}ms < 500ms target"
    elif [ $DURATION_MS -lt 1000 ]; then
        warn "Response time ${DURATION_MS}ms > 500ms target but < 1000ms acceptable"
    else
        fail "Response time ${DURATION_MS}ms > 1000ms acceptable limit"
    fi
fi

echo ""

# Test 7: Image dimensions (requires ImageMagick)
if command -v identify &> /dev/null && [ "$HTTP_CODE" = "200" ]; then
    echo "📐 Testing Image Dimensions..."

    # Download image to temp file
    TEMP_IMG=$(mktemp /tmp/social-card.XXXXXX.png)
    curl -s "$EVENT_URL" -o "$TEMP_IMG"

    # Get dimensions
    DIMENSIONS=$(identify -format "%wx%h" "$TEMP_IMG" 2>/dev/null || echo "unknown")

    if [ "$DIMENSIONS" = "1200x630" ]; then
        pass "Image dimensions are 1200x630px (optimal)"
    elif [ "$DIMENSIONS" != "unknown" ]; then
        warn "Image dimensions are $DIMENSIONS (expected 1200x630)"
    else
        info "Could not determine image dimensions"
    fi

    # Get file size
    SIZE_BYTES=$(stat -f%z "$TEMP_IMG" 2>/dev/null || stat -c%s "$TEMP_IMG" 2>/dev/null || echo "0")
    SIZE_KB=$(( $SIZE_BYTES / 1024 ))

    if [ $SIZE_KB -lt 200 ]; then
        pass "Image size ${SIZE_KB}KB < 200KB (optimal)"
    elif [ $SIZE_KB -lt 500 ]; then
        pass "Image size ${SIZE_KB}KB < 500KB (acceptable)"
    elif [ $SIZE_KB -lt 8192 ]; then
        warn "Image size ${SIZE_KB}KB > 500KB but < 8MB (platform limit)"
    else
        fail "Image size ${SIZE_KB}KB > 8MB platform limit"
    fi

    # Cleanup
    rm "$TEMP_IMG"

    echo ""
fi

# Summary
echo "======================================================================"
echo "📊 Test Summary"
echo "======================================================================"
echo ""
echo -e "${GREEN}✅ Passed:  $PASS${NC}"
echo -e "${YELLOW}⚠️  Warnings: $WARN${NC}"
echo -e "${RED}❌ Failed:  $FAIL${NC}"
echo ""

TOTAL=$((PASS + WARN + FAIL))
if [ $TOTAL -gt 0 ]; then
    PASS_RATE=$(( (PASS * 100) / TOTAL ))
    echo "Pass rate: $PASS_RATE%"
fi

echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}⚠️  Some tests failed. Review the output above.${NC}"
    exit 1
elif [ $WARN -gt 0 ]; then
    echo -e "${YELLOW}⚠️  All tests passed but there are warnings.${NC}"
    exit 0
else
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
fi
