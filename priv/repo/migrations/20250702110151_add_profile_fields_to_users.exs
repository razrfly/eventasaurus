defmodule EventasaurusApp.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Core profile fields
      add :username, :string
      add :bio, :string
      add :website_url, :string
      add :profile_public, :boolean, default: true

      # Social media handles
      add :instagram_handle, :string
      add :twitter_handle, :string
      add :youtube_handle, :string
      add :tiktok_handle, :string
      add :linkedin_handle, :string

      # User preferences
      add :default_currency, :string, default: "USD"
      add :timezone, :string
    end

    # Create unique index on username (case-insensitive)
    create unique_index(:users, ["lower(username)"], name: :users_username_lower_index)

    # Create index for public profile lookups
    create index(:users, [:profile_public])

    # Create composite index for efficient public profile queries by username
    create index(:users, [:profile_public, "lower(username)"], name: :users_public_username_index)
  end
end
