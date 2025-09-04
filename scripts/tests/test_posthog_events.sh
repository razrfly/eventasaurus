#!/bin/bash

echo "Testing PostHog Analytics Events..."
echo "================================"

# Base URL
BASE_URL="http://localhost:4000"

echo "1. Testing anonymous page view..."
curl -s -X GET "$BASE_URL" -H "User-Agent: PostHog-Test" > /dev/null
echo "✓ Homepage visited (anonymous)"

echo ""
echo "2. Testing event page view..."
# Try to find an event page
EVENT_HTML=$(curl -s "$BASE_URL")
EVENT_LINK=$(echo "$EVENT_HTML" | grep -oE 'href="/[a-z0-9]+"' | head -1 | cut -d'"' -f2)

if [ ! -z "$EVENT_LINK" ]; then
    echo "Found event link: $EVENT_LINK"
    curl -s -X GET "$BASE_URL$EVENT_LINK" -H "User-Agent: PostHog-Test" > /dev/null
    echo "✓ Event page visited"
else
    echo "No event links found on homepage"
fi

echo ""
echo "3. Checking PostHog service logs..."
echo "Run the following command in your Phoenix console to check PostHog service:"
echo "  Eventasaurus.Services.PosthogService.test_connection()"

echo ""
echo "To verify events in PostHog dashboard:"
echo "1. Go to https://eu.i.posthog.com"
echo "2. Log in with your PostHog account"
echo "3. Check the 'Events' section for recent activity"
echo "4. Look for events with the test User-Agent: PostHog-Test"