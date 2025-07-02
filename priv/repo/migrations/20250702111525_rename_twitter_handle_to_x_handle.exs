defmodule EventasaurusApp.Repo.Migrations.RenameTwitterHandleToXHandle do
  use Ecto.Migration

  def change do
    rename table(:users), :twitter_handle, to: :x_handle
  end
end
