defmodule Eventasaurus.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :eventasaurus

  @spec migrate() :: {:ok, term(), term()}
  def migrate do
    load_app()

    # Use SessionRepo for migrations because it bypasses PgBouncer (direct connection on port 5432)
    # PgBouncer in transaction mode doesn't support DDL transactions needed for migrations
    #
    # IMPORTANT: We explicitly specify priv/repo/migrations as the migrations path
    # so that all migrations live in ONE canonical location. This prevents the
    # confusion of having separate priv/session_repo/migrations/ folder.
    #
    # Developers should ONLY create migrations in priv/repo/migrations/
    repo = EventasaurusApp.SessionRepo

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        migrations_path = Application.app_dir(@app, "priv/repo/migrations")
        Ecto.Migrator.run(repo, migrations_path, :up, all: true)
      end)
  end

  @spec rollback(module(), integer()) :: {:ok, term(), term()}
  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        migrations_path = Application.app_dir(@app, "priv/repo/migrations")
        Ecto.Migrator.run(repo, migrations_path, :down, to: version)
      end)
  end

  defp load_app do
    Application.load(@app)
  end
end
