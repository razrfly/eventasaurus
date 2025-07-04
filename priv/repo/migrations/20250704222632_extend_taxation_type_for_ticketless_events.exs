defmodule EventasaurusApp.Repo.Migrations.ExtendTaxationTypeForTicketlessEvents do
  use Ecto.Migration

  def up do
    # Step 1: Drop the existing check constraint that only allows 'ticketed_event' and 'contribution_collection'
    drop constraint(:events, :valid_taxation_type)

    # Step 2: Add new check constraint that includes 'ticketless' option
    create constraint(:events, :valid_taxation_type,
      check: "taxation_type IN ('ticketed_event', 'contribution_collection', 'ticketless')"
    )

    # Step 3: Change the default value for new events to 'ticketless'
    # This only affects new records - existing records keep their current values
    alter table(:events) do
      modify :taxation_type, :string, default: "ticketless", null: false
    end

    # Note: We do NOT update existing events - they retain their current classification
    # This ensures backward compatibility and reflects the reality that existing events
    # already had their taxation type explicitly chosen or defaulted to 'ticketed_event'
  end

  def down do
    # Step 1: Change default back to 'ticketed_event'
    alter table(:events) do
      modify :taxation_type, :string, default: "ticketed_event", null: false
    end

    # Step 2: Drop the extended constraint
    drop constraint(:events, :valid_taxation_type)

    # Step 3: Re-create the original constraint (without 'ticketless')
    create constraint(:events, :valid_taxation_type,
      check: "taxation_type IN ('ticketed_event', 'contribution_collection')"
    )

    # Note: Any events that were set to 'ticketless' will need to be manually updated
    # before rolling back this migration, or the rollback will fail due to constraint violation
  end
end
