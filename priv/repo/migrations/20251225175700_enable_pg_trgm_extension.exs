defmodule EventasaurusApp.Repo.Migrations.EnablePgTrgmExtension do
  @moduledoc """
  Enable pg_trgm extension for trigram-based text search.

  This extension is required for gin_trgm_ops indexes used in Phase 2 performance
  improvements. It must run in a separate migration with normal transaction mode
  because CREATE EXTENSION cannot run with @disable_ddl_transaction.

  See: https://github.com/razrfly/eventasaurus/issues/2908
  """
  use Ecto.Migration

  # Note: No @disable_ddl_transaction - extension creation needs transaction context

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
  end

  def down do
    # Don't drop - other features may depend on it
    :ok
  end
end
