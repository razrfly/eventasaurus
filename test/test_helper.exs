# Exclude external API tests by default (they make real API calls and consume rate limits)
# To run them: mix test --include external_api
ExUnit.start(exclude: [:external_api])
Ecto.Adapters.SQL.Sandbox.mode(EventasaurusApp.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(EventasaurusApp.JobRepo, :manual)
