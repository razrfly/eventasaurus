# Configure ExUnit for optimal performance
# Use 2x the number of CPU cores for max parallelization
max_cases = System.schedulers_online() * 2

ExUnit.configure(
  max_cases: max_cases,
  capture_log: true,
  # Increase timeout for Wallaby tests
  timeout: 60_000,
  # Allow excluding slow tests in CI if needed
  exclude: [:skip_ci]
)

ExUnit.start()

# Start Wallaby for browser automation tests
Application.ensure_all_started(:wallaby)

# Configure Ecto for testing with optimized pool settings
Ecto.Adapters.SQL.Sandbox.mode(EventasaurusApp.Repo, :manual)

# Set up Mox for external service mocking
Mox.defmock(EventasaurusApp.HTTPoison.Mock, for: HTTPoison.Base)
Mox.defmock(EventasaurusApp.Auth.ClientMock, for: EventasaurusApp.Auth.ClientBehaviour)

Mox.defmock(EventasaurusWeb.Services.UnsplashServiceMock,
  for: EventasaurusWeb.Services.UnsplashServiceBehaviour
)

Mox.defmock(EventasaurusWeb.Services.TmdbServiceMock,
  for: EventasaurusWeb.Services.TmdbServiceBehaviour
)

Mox.defmock(EventasaurusApp.StripeMock, for: EventasaurusApp.Stripe.Behaviour)

# Set global mode for all Mox mocks to private (default behavior)
Application.put_env(:mox, :verify_on_exit!, true)

# Print performance info
IO.puts("ExUnit Performance Configuration:")
IO.puts("  CPU cores detected: #{System.schedulers_online()}")
IO.puts("  Max concurrent test cases: #{max_cases}")

IO.puts(
  "  Database pool size: #{Application.get_env(:eventasaurus, EventasaurusApp.Repo)[:pool_size] || 10}"
)
