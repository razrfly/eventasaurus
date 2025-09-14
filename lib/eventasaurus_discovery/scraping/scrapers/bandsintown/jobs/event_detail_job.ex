defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for fetching and parsing individual event detail pages from Bandsintown.

  This job:
  1. Receives event URL and basic data from CityIndexJob
  2. Fetches the event detail page
  3. Extracts comprehensive event information
  4. Stores or updates the event in database
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    unique: [
      period: 3600,  # Don't re-scrape same event within 1 hour
      fields: [:args],
      keys: [:url]
    ]

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.{Client, DetailExtractor, DateParser}
  alias EventasaurusDiscovery.Locations.VenueStore
  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventPerformer

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    url = args["url"]
    source_id = args["source_id"]
    event_data = args["event_data"] || %{}

    Logger.info("""
    🎵 Processing Bandsintown Event
    URL: #{url}
    Artist: #{event_data["artist_name"]}
    Venue: #{event_data["venue_name"]}
    Job ID: #{job_id}
    """)

    try do
      # Fetch the event detail page
      case fetch_event_details(url) do
        {:ok, details} ->
          # Merge with initial data from index
          full_event_data = Map.merge(event_data, details)

          # Store in database
          case store_event(full_event_data, source_id) do
            {:ok, event} ->
              Logger.info("✅ Successfully stored event: #{event.external_id}")
              {:ok, event}

            {:error, reason} ->
              Logger.error("❌ Failed to store event: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, :not_found} ->
          Logger.warning("⚠️ Event no longer available: #{url}")
          {:discard, :not_found}

        {:error, reason} ->
          Logger.error("❌ Failed to fetch event: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("❌ Event Detail Job failed: #{Exception.message(e)}")
        {:error, e}
    end
  end

  defp fetch_event_details(url) do
    case Client.fetch_event_page(url) do
      {:ok, html} ->
        # Parse the event detail page
        DetailExtractor.extract_event_details(html, url)

      {:error, {:http_error, 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_event(event_data, source_id) do
    Repo.transaction(fn ->
      # Extract and store venue
      venue_result = store_venue(event_data)
      venue = case venue_result do
        {:ok, v} -> v
        {:error, reason} ->
          Logger.error("Failed to store venue: #{inspect(reason)}")
          Repo.rollback({:venue_error, reason})
      end

      # Extract and store performer
      performer_result = store_performer(event_data, source_id)
      performer = case performer_result do
        {:ok, p} -> p
        {:error, reason} ->
          Logger.error("Failed to store performer: #{inspect(reason)}")
          Repo.rollback({:performer_error, reason})
      end

      # Create or update the event
      event_attrs = %{
        title: event_data["title"] || event_data["artist_name"],
        description: event_data["description"],
        starts_at: DateParser.parse_start_date(event_data["date"]),
        ends_at: DateParser.parse_end_date(event_data["end_date"]),
        venue_id: venue.id,
        category_id: 2, # Concerts - Bandsintown is primarily a music/concert platform
        source_id: source_id,
        external_id: event_data["external_id"] || extract_id_from_url(event_data["url"]),
        ticket_url: event_data["ticket_url"],
        min_price: parse_price(event_data["min_price"]),
        max_price: parse_price(event_data["max_price"]),
        currency: get_currency(event_data),
        metadata: %{
          image_url: event_data["image_url"],
          rsvp_count: event_data["rsvp_count"],
          interested_count: event_data["interested_count"],
          tags: event_data["tags"] || [],
          source_url: event_data["url"],
          event_status: event_data["event_status"],
          facebook_event: event_data["facebook_event"]
        }
      }

      event = case upsert_event(event_attrs) do
        {:ok, e} -> e
        {:error, %Ecto.Changeset{} = changeset} ->
          # Check if this is a validation failure for required fields
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

          if has_required_field_errors?(errors) do
            Logger.warning("🚫 Rejecting event - missing required fields: #{inspect(errors)}")
            Logger.warning("   Event data: title=#{event_attrs[:title]}, starts_at=#{event_attrs[:starts_at]}")
            Repo.rollback({:validation_failure, :missing_required_fields})
          else
            Logger.error("Failed to store event: #{inspect(changeset)}")
            Repo.rollback({:event_error, changeset})
          end
        {:error, reason} ->
          Logger.error("Failed to store event: #{inspect(reason)}")
          Repo.rollback({:event_error, reason})
      end

      # Link performer to event
      link_performer_to_event(event, performer)

      Logger.info("✅ Successfully stored event: #{event.title} (#{event.id})")
      event
    end)
  end

  defp store_venue(event_data) do
    venue_attrs = %{
      name: event_data["venue_name"],
      address: event_data["venue_address"],
      latitude: event_data["venue_latitude"],
      longitude: event_data["venue_longitude"],
      city_name: event_data["venue_city"],
      country_code: extract_country_code(event_data["venue_country"]),
      external_id: extract_venue_external_id(event_data)
    }

    VenueStore.find_or_create_venue(venue_attrs)
  end

  defp store_performer(event_data, source_id) do
    performer_attrs = %{
      name: event_data["artist_name"],
      external_id: extract_artist_external_id(event_data),
      image_url: event_data["image_url"],
      genre: event_data["genre"],
      source_id: source_id,
      metadata: %{
        artist_url: event_data["artist_url"],
        social_links: event_data["artist_same_as"] || []
      }
    }

    PerformerStore.find_or_create_performer(performer_attrs)
  end

  defp upsert_event(attrs) do
    changeset = %PublicEvent{}
    |> PublicEvent.changeset(attrs)

    Repo.insert(changeset,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:external_id, :source_id],
      returning: true
    )
  end

  defp link_performer_to_event(%PublicEvent{id: event_id}, %{id: performer_id}) do
    # Check if link already exists
    existing = Repo.get_by(PublicEventPerformer,
      event_id: event_id,
      performer_id: performer_id
    )

    if existing do
      {:ok, existing}
    else
      %PublicEventPerformer{}
      |> PublicEventPerformer.changeset(%{
        event_id: event_id,
        performer_id: performer_id,
        billing_order: 1,
        metadata: %{is_headliner: true}
      })
      |> Repo.insert()
    end
  end

  defp extract_venue_external_id(_event_data) do
    # TODO: Extract venue ID from Bandsintown data if available
    nil
  end

  defp extract_artist_external_id(_event_data) do
    # TODO: Extract artist ID from Bandsintown data if available
    nil
  end

  defp extract_country_code(country_name) when is_binary(country_name) do
    # Use the countries library to properly get country code
    case Countries.filter_by(:name, country_name) do
      [country | _] -> country.alpha2
      [] ->
        # Try common name variations
        case Countries.filter_by(:unofficial_names, country_name) do
          [country | _] -> country.alpha2
          [] ->
            Logger.warning("Could not find country code for: #{country_name}")
            nil
        end
    end
  end
  defp extract_country_code(_), do: nil

  defp parse_price(nil), do: nil
  defp parse_price(price) when is_number(price), do: Decimal.from_float(price * 1.0)
  defp parse_price(price) when is_binary(price) do
    case Decimal.parse(price) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp extract_id_from_url(url) when is_binary(url) do
    case Regex.run(~r/\/e\/(\d+)/, url) do
      [_, id] -> id
      _ -> nil
    end
  end
  defp extract_id_from_url(_), do: nil


  defp has_required_field_errors?(errors) do
    # Check if errors contain missing title or starts_at
    Enum.any?([:title, :starts_at], fn field ->
      Map.has_key?(errors, field)
    end)
  end

  defp get_currency(event_data) do
    # Only set currency if we have actual price data
    min_price = event_data["min_price"]
    max_price = event_data["max_price"]

    if min_price || max_price do
      event_data["currency"] || "USD"
    else
      nil
    end
  end

end