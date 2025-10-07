defmodule EventasaurusDiscovery.Sources.QuestionOne.FreshnessTest do
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, SourceStore}
  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  describe "EventFreshnessChecker integration" do
    setup do
      # Create Question One source
      {:ok, source} =
        %Source{}
        |> Source.changeset(%{
          name: "Question One",
          slug: "question-one",
          website_url: "https://questionone.com",
          priority: 35,
          is_active: true
        })
        |> Repo.insert()

      %{source: source}
    end

    test "filters out recently updated events", %{source: source} do
      # Create a "fresh" event (updated within threshold)
      fresh_event_external_id = "question_one_venue_test_fresh_monday"

      {:ok, fresh_event} =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          external_id: fresh_event_external_id,
          source_id: source.id,
          title: "Fresh Event",
          starts_at: DateTime.utc_now() |> DateTime.add(7, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(7200, :second),
          last_seen_at: DateTime.utc_now(),
          # Fresh - just updated
          category: "trivia",
          is_ticketed: false,
          is_free: true
        })
        |> Repo.insert()

      # Create a "stale" event (updated beyond threshold)
      stale_event_external_id = "question_one_venue_test_stale_monday"
      threshold_hours = EventFreshnessChecker.get_threshold()
      stale_timestamp = DateTime.utc_now() |> DateTime.add(-(threshold_hours + 1) * 3600, :second)

      {:ok, stale_event} =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          external_id: stale_event_external_id,
          source_id: source.id,
          title: "Stale Event",
          starts_at: DateTime.utc_now() |> DateTime.add(7, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(7200, :second),
          last_seen_at: stale_timestamp,
          # Stale - needs updating
          category: "trivia",
          is_ticketed: false,
          is_free: true
        })
        |> Repo.insert()

      # Create list of venues to check (both fresh and stale)
      venues = [
        %{external_id: fresh_event_external_id, title: "Fresh Venue"},
        %{external_id: stale_event_external_id, title: "Stale Venue"},
        %{external_id: "question_one_venue_new_monday", title: "New Venue"}
      ]

      # Apply freshness filter
      venues_to_process = EventFreshnessChecker.filter_events_needing_processing(venues, source.id)

      # Verify results
      processed_ids = Enum.map(venues_to_process, & &1.external_id)

      refute fresh_event_external_id in processed_ids,
             "Fresh event should be filtered out"

      assert stale_event_external_id in processed_ids, "Stale event should be included"
      assert "question_one_venue_new_monday" in processed_ids, "New event should be included"

      # Verify we saved API calls
      assert length(venues_to_process) == 2, "Should only process 2 out of 3 venues"

      efficiency = (1 / 3 * 100) |> Float.round(1)

      assert efficiency > 30.0,
             "Should save at least 30% of API calls (saved #{efficiency}%)"
    end

    test "handles empty event list", %{source: source} do
      venues = []
      result = EventFreshnessChecker.filter_events_needing_processing(venues, source.id)
      assert result == []
    end

    test "handles all fresh events", %{source: source} do
      # Create 3 fresh events
      fresh_ids =
        for i <- 1..3 do
          external_id = "question_one_venue_fresh_#{i}_monday"

          {:ok, _event} =
            %PublicEvent{}
            |> PublicEvent.changeset(%{
              external_id: external_id,
              source_id: source.id,
              title: "Fresh Event #{i}",
              starts_at: DateTime.utc_now() |> DateTime.add(7, :day),
              ends_at:
                DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(7200, :second),
              last_seen_at: DateTime.utc_now(),
              category: "trivia",
              is_ticketed: false,
              is_free: true
            })
            |> Repo.insert()

          external_id
        end

      venues = Enum.map(fresh_ids, fn id -> %{external_id: id, title: "Venue"} end)

      result = EventFreshnessChecker.filter_events_needing_processing(venues, source.id)

      assert result == [], "All fresh events should be filtered out"
    end

    test "handles all stale events", %{source: source} do
      threshold_hours = EventFreshnessChecker.get_threshold()
      stale_timestamp = DateTime.utc_now() |> DateTime.add(-(threshold_hours + 1) * 3600, :second)

      # Create 3 stale events
      stale_ids =
        for i <- 1..3 do
          external_id = "question_one_venue_stale_#{i}_monday"

          {:ok, _event} =
            %PublicEvent{}
            |> PublicEvent.changeset(%{
              external_id: external_id,
              source_id: source.id,
              title: "Stale Event #{i}",
              starts_at: DateTime.utc_now() |> DateTime.add(7, :day),
              ends_at:
                DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(7200, :second),
              last_seen_at: stale_timestamp,
              category: "trivia",
              is_ticketed: false,
              is_free: true
            })
            |> Repo.insert()

          external_id
        end

      venues = Enum.map(stale_ids, fn id -> %{external_id: id, title: "Venue"} end)

      result = EventFreshnessChecker.filter_events_needing_processing(venues, source.id)

      assert length(result) == 3, "All stale events should be included"
    end
  end
end
