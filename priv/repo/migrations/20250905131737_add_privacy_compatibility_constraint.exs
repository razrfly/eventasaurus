defmodule EventasaurusApp.Repo.Migrations.AddPrivacyCompatibilityConstraint do
  use Ecto.Migration

  def change do
    # Prevent invalid combination: private visibility cannot be open join policy
    create constraint(:groups, :groups_privacy_compat_check,
      check: "NOT (visibility = 'private' AND join_policy = 'open')")
  end
end