defmodule Eventasaurus.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :eventasaurus

  def migrate do
    load_app()

    # Only run migrations on SessionRepo which uses direct database connection
    # Both Repo and SessionRepo point to the same database, so we only need to migrate once
    # SessionRepo supports long-running transactions required for complex migrations
    repo = EventasaurusApp.SessionRepo
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp load_app do
    Application.load(@app)
  end
end
