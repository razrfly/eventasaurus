defmodule EventasaurusApp.Repo do
  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres
end
