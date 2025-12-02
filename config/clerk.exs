# Clerk Authentication Configuration
#
# This file configures Clerk as the authentication provider.
# Credentials are loaded from environment variables in runtime.exs
#
# Required environment variables:
#   CLERK_PUBLISHABLE_KEY - Frontend publishable key (pk_test_... or pk_live_...)
#   CLERK_SECRET_KEY - Backend secret key (sk_test_... or sk_live_...)

import Config

# Clerk configuration (credentials loaded at runtime)
config :eventasaurus, :clerk,
  # Enable/disable Clerk auth (allows gradual migration from Supabase)
  enabled: false,
  # Clerk domain extracted from publishable key at runtime
  domain: nil,
  # JWKS endpoint for JWT verification (set at runtime based on domain)
  jwks_url: nil,
  # Authorized parties for token verification (your app URLs)
  authorized_parties: ["http://localhost:4000"],
  # Cache JWKS keys for this duration (in milliseconds)
  jwks_cache_ttl: 3_600_000
