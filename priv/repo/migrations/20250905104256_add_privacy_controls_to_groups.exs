defmodule EventasaurusApp.Repo.Migrations.AddPrivacyControlsToGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :visibility, :string, size: 20, default: "public", null: false
      add :join_policy, :string, size: 20, default: "open", null: false
    end

    # Add constraints for valid values
    create constraint(:groups, :groups_visibility_check, 
      check: "visibility IN ('public', 'unlisted', 'private')")
    create constraint(:groups, :groups_join_policy_check, 
      check: "join_policy IN ('open', 'request', 'invite_only')")

    # Add indexes for performance
    create index(:groups, [:visibility])
    create index(:groups, [:join_policy])
    create index(:groups, [:visibility, :join_policy])
  end
end
