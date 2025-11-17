defmodule EventasaurusApp.Repo.Migrations.RemovePollsEventPollTypeUniqueConstraint do
  use Ecto.Migration

  @moduledoc """
  Removes the overly restrictive unique constraint that prevented multiple polls
  of the same type per event. This constraint was preventing legitimate use cases
  where event organizers want to create multiple polls of the same type (e.g.,
  progressive refinement: binary poll for initial interest, approval poll for
  narrowing options, ranked poll for final decision).
  """

  # Required for concurrent index operations
  @disable_ddl_transaction true

  def change do
    # Drop the unique index that prevents multiple polls of same type per event
    # Use concurrently: true to avoid blocking queries in production
    drop_if_exists unique_index(:polls, [:event_id, :poll_type],
      name: :polls_event_poll_type_unique,
      where: "phase != 'closed'",
      concurrently: true
    )
  end
end
