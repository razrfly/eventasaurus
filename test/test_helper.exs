ExUnit.start()

# Configure Ecto for testing
Ecto.Adapters.SQL.Sandbox.mode(EventasaurusApp.Repo, :manual)
