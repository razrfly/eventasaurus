defmodule EventasaurusDiscovery.Sources.QuestionOne.IntegrationTest do
  use EventasaurusApp.DataCase, async: false

  import Mox

  alias EventasaurusApp.Repo

  alias EventasaurusDiscovery.Sources.QuestionOne.{
    Client,
    Jobs.IndexPageJob,
    Jobs.VenueDetailJob,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.{Source, SourceStore}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Venues.Venue

  setup :verify_on_exit!

  @rss_feed_fixture """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0">
    <channel>
      <title>Question One Venues</title>
      <item>
        <title>PUB QUIZ – The Red Lion</title>
        <link>https://questionone.com/venues/red-lion/</link>
        <description>Weekly trivia at The Red Lion</description>
      </item>
      <item>
        <title>The Crown Pub Quiz</title>
        <link>https://questionone.com/venues/crown/</link>
        <description>Fun quiz night</description>
      </item>
    </channel>
  </rss>
  """

  @venue_detail_fixture """
  <!DOCTYPE html>
  <html>
    <head><title>The Red Lion - Question One</title></head>
    <body>
      <div class="text-with-icon">
        <svg><use href="#pin"></use></svg>
        <span class="text-with-icon__text">123 High Street, London, SW1A 1AA</span>
      </div>
      <div class="text-with-icon">
        <svg><use href="#calendar"></use></svg>
        <span class="text-with-icon__text">Wednesdays at 8pm</span>
      </div>
      <div class="text-with-icon">
        <svg><use href="#tag"></use></svg>
        <span class="text-with-icon__text">£2 per person</span>
      </div>
      <div class="text-with-icon">
        <svg><use href="#phone"></use></svg>
        <span class="text-with-icon__text">020 1234 5678</span>
      </div>
      <a href="https://redlion.com">Visit Website</a>
      <div class="post-content-area">
        <p>Join us for our weekly trivia night every Wednesday!</p>
      </div>
      <img src="https://questionone.com/wp-content/uploads/red-lion.jpg" />
    </body>
  </html>
  """

  describe "full integration test" do
    setup do
      # Create Question One source
      {:ok, source} =
        %Source{}
        |> Source.changeset(%{
          name: "Question One",
          slug: "question-one",
          website_url: "https://questionone.com",
          priority: 35,
          is_active: true,
          metadata: %{
            rate_limit_seconds: 2,
            timeout: 30_000
          }
        })
        |> Repo.insert()

      %{source: source}
    end

    test "scrapes RSS feed, creates events, and handles idempotency", %{source: source} do
      # Mock HTTP responses
      expect(HTTPoison.MockClient, :get, 2, fn url, _headers, _opts ->
        cond do
          String.contains?(url, "/venues/feed") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: @rss_feed_fixture}}

          String.contains?(url, "/venues/red-lion") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: @venue_detail_fixture}}

          String.contains?(url, "/venues/crown") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: @venue_detail_fixture}}

          true ->
            {:error, :not_found}
        end
      end)

      # Run index page job (page 1)
      {:ok, _result} =
        perform_job(IndexPageJob, %{
          "source_id" => source.id,
          "page" => 1,
          "limit" => 2
        })

      # Wait for detail jobs to be enqueued
      :timer.sleep(100)

      # Verify detail jobs were created
      detail_jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "EventasaurusDiscovery.Sources.QuestionOne.Jobs.VenueDetailJob",
            where: j.state == "available"
          )
        )

      assert length(detail_jobs) == 2

      # Run detail jobs
      Enum.each(detail_jobs, fn job ->
        perform_job(VenueDetailJob, job.args)
      end)

      # Verify events were created
      events = Repo.all(PublicEvent)
      assert length(events) >= 1

      # Verify venue was created and geocoded would happen
      venues = Repo.all(Venue)
      assert length(venues) >= 1

      venue = List.first(venues)
      assert venue.name == "The Red Lion"
      assert venue.address == "123 High Street, London, SW1A 1AA"
      # Note: latitude/longitude would be nil until VenueProcessor geocodes
      assert is_nil(venue.latitude)
      assert is_nil(venue.longitude)

      # Verify event structure
      event = List.first(events)
      assert event.title == "Trivia Night at The Red Lion"
      assert String.starts_with?(event.external_id, "question_one_")
      assert event.category == "trivia"
      assert event.is_free == false
      assert event.is_ticketed == true
      assert event.currency == "GBP"
      assert event.source_id == source.id
      assert not is_nil(event.last_seen_at)

      # Test idempotency - run again with same data
      initial_event_count = Repo.aggregate(PublicEvent, :count)
      initial_venue_count = Repo.aggregate(Venue, :count)

      # Run detail job again for same venue
      {:ok, _result} =
        perform_job(VenueDetailJob, %{
          "source_id" => source.id,
          "venue_url" => "https://questionone.com/venues/red-lion/",
          "venue_title" => "PUB QUIZ – The Red Lion"
        })

      # Verify no duplicates created
      final_event_count = Repo.aggregate(PublicEvent, :count)
      final_venue_count = Repo.aggregate(Venue, :count)

      assert final_event_count == initial_event_count, "Should not create duplicate events"
      assert final_venue_count == initial_venue_count, "Should not create duplicate venues"

      # Verify last_seen_at was updated
      updated_event = Repo.get(PublicEvent, event.id)
      assert DateTime.compare(updated_event.last_seen_at, event.last_seen_at) == :gt
    end
  end

  defp perform_job(worker_module, args) do
    job = %Oban.Job{
      worker: to_string(worker_module),
      args: args,
      attempt: 1,
      max_attempts: 3
    }

    worker_module.perform(job)
  end
end
