defmodule EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJobTest do
  use EventasaurusApp.DataCase, async: false
  use Oban.Testing, repo: Eventasaurus.Repo

  alias EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob
  alias Eventasaurus.Discovery.Event

  import Mox

  setup :verify_on_exit!

  describe "perform/1" do
    test "successfully processes single-date event" do
      html = """
      <html>
        <head>
          <title>Indochine Concert | Sortiraparis.com</title>
          <meta property="og:image" content="https://www.sortiraparis.com/images/indochine.jpg">
        </head>
        <body>
          <article>
            <h1>Indochine Concert at Accor Arena</h1>
            <time>October 31, 2025</time>
            <p>Indochine returns to Paris for an exclusive concert.</p>
            <p>Tickets from €45 to €85.</p>
          </article>
          <div class="venue">Accor Arena</div>
          <address>8 Boulevard de Bercy, 75012 Paris</address>
        </body>
      </html>
      """

      # Mock the HTTP client
      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      # Create job
      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/319282-indochine",
        "event_metadata" => %{
          "article_id" => "319282",
          "external_id_base" => "sortiraparis_319282"
        }
      }

      # Perform job
      assert {:ok, result} = perform_job(EventDetailJob, args)
      assert result.events_created == 1

      # Verify event was created in database
      events = Repo.all(Event)
      assert length(events) == 1

      event = List.first(events)
      assert event.source == "sortiraparis"
      assert event.external_id == "sortiraparis_319282_2025-10-31"
      assert event.title == "Indochine Concert at Accor Arena"
      assert event.description =~ "Indochine returns to Paris"
    end

    test "successfully processes multi-date event" do
      html = """
      <html>
        <head>
          <title>Music Festival | Sortiraparis.com</title>
        </head>
        <body>
          <article>
            <h1>Summer Music Festival</h1>
            <time>July 10, 12, 14, 2026</time>
            <p>Three-day music festival.</p>
            <p>Tickets €50.</p>
          </article>
          <div class="venue">Champ de Mars</div>
          <address>5 Avenue Anatole France, 75007 Paris</address>
        </body>
      </html>
      """

      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/320000-festival",
        "event_metadata" => %{
          "article_id" => "320000"
        }
      }

      assert {:ok, result} = perform_job(EventDetailJob, args)
      assert result.events_created == 3

      # Verify three separate events were created
      events = Repo.all(Event)
      assert length(events) == 3

      # Check external IDs are unique
      external_ids = Enum.map(events, & &1.external_id) |> Enum.sort()
      assert external_ids == [
               "sortiraparis_320000_2026-07-10",
               "sortiraparis_320000_2026-07-12",
               "sortiraparis_320000_2026-07-14"
             ]
    end

    test "handles bot protection 401 error" do
      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 401, body: "Unauthorized"}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "event_metadata" => %{"article_id" => "123"}
      }

      assert {:error, :bot_protection} = perform_job(EventDetailJob, args)

      # No events should be created
      assert Repo.all(Event) == []
    end

    test "handles 404 not found error" do
      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "Not Found"}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/999999-missing",
        "event_metadata" => %{"article_id" => "999999"}
      }

      assert {:error, :not_found} = perform_job(EventDetailJob, args)
      assert Repo.all(Event) == []
    end

    test "handles missing title extraction" do
      html = """
      <html>
        <body>
          <article>
            <time>October 31, 2025</time>
            <p>No title here</p>
          </article>
        </body>
      </html>
      """

      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/123-bad",
        "event_metadata" => %{"article_id" => "123"}
      }

      assert {:error, :title_not_found} = perform_job(EventDetailJob, args)
      assert Repo.all(Event) == []
    end

    test "handles missing date extraction" do
      html = """
      <html>
        <body>
          <article>
            <h1>Event Title</h1>
            <p>No date information</p>
          </article>
        </body>
      </html>
      """

      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/123-bad",
        "event_metadata" => %{"article_id" => "123"}
      }

      assert {:error, :date_not_found} = perform_job(EventDetailJob, args)
      assert Repo.all(Event) == []
    end

    test "handles missing venue extraction" do
      html = """
      <html>
        <body>
          <article>
            <h1>Event Title</h1>
            <time>October 31, 2025</time>
            <p>Event description</p>
          </article>
        </body>
      </html>
      """

      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/123-bad",
        "event_metadata" => %{"article_id" => "123"}
      }

      assert {:error, :venue_name_not_found} = perform_job(EventDetailJob, args)
      assert Repo.all(Event) == []
    end

    test "handles network errors" do
      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/123-timeout",
        "event_metadata" => %{"article_id" => "123"}
      }

      assert {:error, :timeout} = perform_job(EventDetailJob, args)
      assert Repo.all(Event) == []
    end

    test "processes complete event with all fields" do
      html = """
      <html>
        <head>
          <title>Complete Event | Sortiraparis.com</title>
          <meta property="og:title" content="Complete Event at Amazing Venue">
          <meta property="og:image" content="https://www.sortiraparis.com/images/complete.jpg">
        </head>
        <body>
          <article>
            <h1>Complete Event at Amazing Venue</h1>
            <time>December 25, 2025</time>
            <p>This is a comprehensive event with all details.</p>
            <p>It includes pricing information.</p>
            <p>Tickets available from €30 to €100.</p>
          </article>
          <div class="venue">Amazing Venue</div>
          <address>123 Main Street, 75001 Paris</address>
          <div data-lat="48.8566" data-lng="2.3522"></div>
        </body>
      </html>
      """

      expect(HTTPoisonMock, :get, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/999-complete",
        "event_metadata" => %{"article_id" => "999"}
      }

      assert {:ok, result} = perform_job(EventDetailJob, args)
      assert result.events_created == 1

      event = Repo.one(Event)
      assert event.title == "Complete Event at Amazing Venue"
      assert event.image_url == "https://www.sortiraparis.com/images/complete.jpg"
      assert event.is_ticketed == true
      assert event.is_free == false
      assert Decimal.equal?(event.min_price, Decimal.new("30"))
      assert Decimal.equal?(event.max_price, Decimal.new("100"))
      assert event.currency == "EUR"

      # Verify venue with GPS coordinates
      assert event.venue.name == "Amazing Venue"
      assert event.venue.address == "123 Main Street, 75001 Paris"
      assert event.venue.latitude == 48.8566
      assert event.venue.longitude == 2.3522
    end

    test "deduplicates events by external_id" do
      html = """
      <html>
        <body>
          <article>
            <h1>Duplicate Event</h1>
            <time>October 31, 2025</time>
            <p>Event description</p>
          </article>
          <div class="venue">Test Venue</div>
          <address>123 Test St, 75001 Paris</address>
        </body>
      </html>
      """

      expect(HTTPoisonMock, :get, 2, fn _url, _headers, _options ->
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end)

      args = %{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/111-duplicate",
        "event_metadata" => %{"article_id" => "111"}
      }

      # Process job first time
      assert {:ok, result1} = perform_job(EventDetailJob, args)
      assert result1.events_created == 1

      # Process same job again (should deduplicate)
      assert {:ok, _result2} = perform_job(EventDetailJob, args)

      # Should still only have one event in database
      events = Repo.all(Event)
      assert length(events) == 1
    end
  end
end
