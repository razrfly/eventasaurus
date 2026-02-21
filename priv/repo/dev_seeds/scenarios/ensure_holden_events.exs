defmodule DevSeeds.EnsureHoldenEvents do
  @moduledoc """
  Ensures holden.thomas@gmail.com (the only real Clerk-authenticated user)
  has events across all statuses for iOS testing.

  This is critical for Phase 0 of iOS testing — without this, the
  "Created" tab in MyEventsView may be empty or sparse.
  """

  alias EventasaurusApp.{Repo, Accounts, Events}
  alias EventasaurusApp.Events.EventUser
  import Ecto.Query

  Code.require_file("../support/helpers.exs", __DIR__)
  alias DevSeeds.Helpers

  @holden_email "holden.thomas@gmail.com"

  def run do
    Helpers.section("Ensuring Holden Has Test Events for iOS")

    case Accounts.get_user_by_email(@holden_email) do
      nil ->
        Helpers.error("#{@holden_email} not found — skipping")

      holden ->
        ensure_organized_events(holden)
        ensure_attending_events(holden)
        print_summary(holden)
    end
  end

  defp ensure_organized_events(holden) do
    existing =
      from(eu in EventUser,
        join: e in assoc(eu, :event),
        where:
          eu.user_id == ^holden.id and
            eu.role in ["owner", "organizer"] and
            is_nil(e.deleted_at),
        select: e.status
      )
      |> Repo.all()

    existing_statuses = MapSet.new(existing)

    # Ensure at least one event per key status
    needed = [
      {:draft, "My Draft Event — Untitled Gathering"},
      {:confirmed, "Holden's Published Meetup"},
      {:confirmed, "Weekend Brunch with Friends"},
      {:canceled, "Canceled: Rainy Day Picnic"}
    ]

    Enum.each(needed, fn {status, title} ->
      # Only create if we don't have enough of this status
      count_of_status = Enum.count(existing, &(&1 == status))

      if count_of_status < 1 do
        create_event_for_holden(holden, status, title)
      end
    end)
  end

  defp create_event_for_holden(holden, status, title) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {start_at, ends_at} =
      case status do
        :canceled ->
          # Past-ish
          start = DateTime.add(now, 3 * 86400, :second)
          {start, DateTime.add(start, 3 * 3600, :second)}

        _ ->
          days = Enum.random(7..30)
          start = DateTime.add(now, days * 86400, :second)
          {start, DateTime.add(start, 3 * 3600, :second)}
      end

    image_attrs = Helpers.get_random_image_attrs()

    event_params =
      Map.merge(
        %{
          title: title,
          description: "Test event created for iOS app testing.",
          tagline: "For testing",
          start_at: start_at,
          ends_at: ends_at,
          status: status,
          visibility: :public,
          theme: Enum.random([:minimal, :cosmic, :celebration]),
          is_virtual: true,
          virtual_venue_url: "https://meet.example.com/#{Ecto.UUID.generate() |> String.slice(0..7)}",
          timezone: "America/New_York"
        },
        image_attrs
      )

    case Events.create_event_with_organizer(event_params, holden) do
      {:ok, event} ->
        # Add some participants so stats show up
        add_random_participants(event, holden)
        Helpers.log("Created #{status} event: #{title}", :green)

      {:error, reason} ->
        Helpers.error("Failed to create #{status} event: #{inspect(reason)}")
    end
  end

  defp add_random_participants(event, holden) do
    users =
      from(u in Accounts.User,
        where: u.id != ^holden.id,
        order_by: fragment("RANDOM()"),
        limit: 8
      )
      |> Repo.all()

    Enum.each(users, fn user ->
      Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        status: Enum.random([:accepted, :accepted, :interested, :pending]),
        role: :ticket_holder,
        source: "holden_test_seeding"
      })
    end)
  end

  defp ensure_attending_events(holden) do
    # Check if Holden already has enough attending events
    attending_count =
      from(ep in Events.EventParticipant,
        join: e in assoc(ep, :event),
        where:
          ep.user_id == ^holden.id and
            is_nil(e.deleted_at) and
            e.start_at > ^DateTime.utc_now()
      )
      |> Repo.aggregate(:count)

    if attending_count < 5 do
      # Find some upcoming events Holden isn't already part of
      events =
        from(e in Events.Event,
          where:
            is_nil(e.deleted_at) and
              e.start_at > ^DateTime.utc_now() and
              e.status == :confirmed,
          order_by: fragment("RANDOM()"),
          limit: 10
        )
        |> Repo.all()

      added =
        Enum.reduce(events, 0, fn event, acc ->
          # Skip if already organizer or participant
          already =
            Repo.exists?(
              from(eu in EventUser,
                where: eu.event_id == ^event.id and eu.user_id == ^holden.id
              )
            ) or
              Repo.exists?(
                from(ep in Events.EventParticipant,
                  where: ep.event_id == ^event.id and ep.user_id == ^holden.id
                )
              )

          if already do
            acc
          else
            case Events.create_event_participant(%{
                   event_id: event.id,
                   user_id: holden.id,
                   status: Enum.random([:accepted, :interested]),
                   role: :ticket_holder,
                   source: "holden_test_seeding"
                 }) do
              {:ok, _} -> acc + 1
              _ -> acc
            end
          end
        end)

      Helpers.log("Added Holden to #{added} additional events as attendee", :green)
    end
  end

  defp print_summary(holden) do
    organized =
      from(eu in EventUser,
        join: e in assoc(eu, :event),
        where:
          eu.user_id == ^holden.id and
            eu.role in ["owner", "organizer"] and
            is_nil(e.deleted_at),
        select: e.status
      )
      |> Repo.all()

    attending =
      from(ep in Events.EventParticipant,
        join: e in assoc(ep, :event),
        where:
          ep.user_id == ^holden.id and
            is_nil(e.deleted_at) and
            e.start_at > ^DateTime.utc_now()
      )
      |> Repo.aggregate(:count)

    status_counts =
      Enum.frequencies(organized)
      |> Enum.map(fn {status, count} -> "#{status}: #{count}" end)
      |> Enum.join(", ")

    Helpers.success("Holden's events — Organized: #{length(organized)} (#{status_counts}), Attending: #{attending} upcoming")
  end
end
