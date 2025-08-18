#!/bin/bash

echo "Testing OAuth endpoints..."
echo

echo "1. Testing Facebook OAuth endpoint:"
response=$(curl -I -s http://localhost:4000/auth/facebook | head -n 1)
location=$(curl -I -s http://localhost:4000/auth/facebook | grep -i location)
echo "   Response: $response"
echo "   Redirect: $location"
echo

echo "2. Testing Google OAuth endpoint:"
response=$(curl -I -s http://localhost:4000/auth/google | head -n 1)
location=$(curl -I -s http://localhost:4000/auth/google | grep -i location)
echo "   Response: $response"
echo "   Redirect: $location"
echo

echo "3. Checking login page for OAuth buttons:"
facebook_button=$(curl -s http://localhost:4000/auth/login | grep -c "Continue with Facebook")
google_button=$(curl -s http://localhost:4000/auth/login | grep -c "Continue with Google")
echo "   Facebook button found: $([ $facebook_button -gt 0 ] && echo "✓" || echo "✗")"
echo "   Google button found: $([ $google_button -gt 0 ] && echo "✓" || echo "✗")"
echo

echo "Test complete!"
