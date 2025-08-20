defmodule EventasaurusApp.Repo.Migrations.AddReferralEventIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :referral_event_id, references(:events, on_delete: :nilify_all), null: true
    end

    create index(:users, [:referral_event_id])
  end
end
