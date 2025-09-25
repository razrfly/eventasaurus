defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.EventDetailJob do
  @moduledoc """
  DEPRECATED: This job is replaced by Sources.Bandsintown.Jobs.SyncJob
  which uses the unified Processor for venue enforcement.

  Old Oban job for fetching and parsing individual event detail pages from Bandsintown.
  This job directly created events without going through the unified Processor,
  which bypassed venue requirements and collision detection.

  DO NOT USE - Kept for reference only.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    unique: [
      # Don't re-scrape same event within 1 hour
      period: 3600,
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
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Services.CollisionDetector
  alias EventasaurusDiscovery.Categories.CategoryExtractor

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

          Logger.info("🔀 Merged event data keys: #{inspect(Map.keys(full_event_data))}")
          Logger.info("   Artist: #{full_event_data["artist_name"]}")
          Logger.info("   Venue: #{full_event_data["venue_name"]}")

          # Store in database
          case store_event(full_event_data, source_id) do
            {:ok, event} ->
              Logger.info("✅ Successfully stored event: #{event.title}")
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
        result = DetailExtractor.extract_event_details(html, url)

        case result do
          {:ok, details} ->
            Logger.info("📄 DetailExtractor returned: #{inspect(Map.keys(details))}")

            Logger.info(
              "   Venue data: #{inspect(Map.take(details, ["venue_name", "venue_address", "venue_city", "venue_latitude", "venue_longitude"]))}"
            )

            {:ok, details}

          error ->
            error
        end

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

      venue =
        case venue_result do
          {:ok, v} ->
            Logger.info("✅ Venue stored: #{v.name} (ID: #{v.id})")
            v

          {:error, reason} ->
            Logger.error("❌ Failed to store venue: #{inspect(reason)}")
            # Don't rollback for missing venue - many events may not have complete venue data
            # Instead, create a minimal venue or skip
            nil
        end

      # Extract and store performer
      performer_result = store_performer(event_data, source_id)

      performer =
        case performer_result do
          {:ok, p} ->
            Logger.info("✅ Performer stored: #{p.name} (ID: #{p.id})")
            p

          {:error, reason} ->
            Logger.error("❌ Failed to store performer: #{inspect(reason)}")
            # Don't rollback for missing performer data
            nil
        end

      # Check for collision with existing events from other sources
      starts_at = DateParser.parse_start_date(event_data["date"])
      title = event_data["title"] || event_data["artist_name"]

      existing_event =
        if venue && starts_at do
          CollisionDetector.find_similar_event(venue, starts_at, title)
        else
          nil
        end

      event =
        if existing_event do
          Logger.info("""
          🔄 Found existing event from another source!
          Existing: #{existing_event.title} (ID: #{existing_event.id})
          Will link BandsInTown data to existing event instead of creating duplicate.
          """)

          # Update existing event with any missing data from BandsInTown
          # Note: description is now stored in public_event_sources, not public_events
          updates = []

          updates =
            if is_nil(existing_event.ends_at) && event_data["end_date"] do
              [{:ends_at, DateParser.parse_end_date(event_data["end_date"])} | updates]
            else
              updates
            end

          updates =
            if is_nil(existing_event.ticket_url) && event_data["ticket_url"] do
              [{:ticket_url, event_data["ticket_url"]} | updates]
            else
              updates
            end

          # Update title_translations if we have title and no translations yet
          updates =
            if title do
              merged =
                (existing_event.title_translations || %{})
                |> Map.merge(detect_title_language(title) || %{}, fn _k, old, new ->
                  if new in [nil, ""], do: old, else: new
                end)

              [{:title_translations, merged} | updates]
            else
              updates
            end

          updated_event =
            if Enum.any?(updates) do
              case existing_event |> PublicEvent.changeset(Map.new(updates)) |> Repo.update() do
                {:ok, updated} ->
                  Logger.info("✅ Updated existing event with BandsInTown data")
                  updated

                {:error, changeset} ->
                  Logger.error("Failed to update existing event: #{inspect(changeset)}")
                  existing_event
              end
            else
              existing_event
            end

          # Also ensure the existing event has categories assigned
          # CRITICAL: Pass raw_event_data for CategoryExtractor
          raw_event_data = %{
            title: title,
            artist_name: event_data["artist_name"],
            description: event_data["description"],
            url: event_data["url"],
            tags: event_data["tags"] || [],
            venue_name: event_data["venue_name"]
          }

          CategoryExtractor.assign_categories_to_event(
            updated_event.id,
            "bandsintown",
            raw_event_data
          )

          Logger.info("🏷️ Categories assigned to existing event #{updated_event.id}")

          updated_event
        else
          # No collision found, create new event
          event_attrs = %{
            title: title,
            title_translations: if(title, do: detect_title_language(title), else: nil),
            starts_at: starts_at,
            ends_at: DateParser.parse_end_date(event_data["end_date"]),
            venue_id: if(venue, do: venue.id, else: raise("Venue is required for all events")),
            # Remove hardcoded category_id - will assign via new system
            # external_id now stored only in public_event_sources
            ticket_url: event_data["ticket_url"],
            min_price: parse_price(event_data["min_price"]),
            max_price: parse_price(event_data["max_price"]),
            currency: get_currency(event_data)
            # metadata now stored only in public_event_sources
          }

          Logger.info(
            "📝 No collision found, creating new event with venue_id=#{event_attrs.venue_id}"
          )

          case upsert_event(event_attrs) do
            {:ok, e} ->
              Logger.info("✅ Event created: #{e.title} (ID: #{e.id}, venue_id: #{e.venue_id})")

              # Assign categories using the new system
              # CRITICAL: Pass raw_event_data for CategoryExtractor
              raw_event_data = %{
                title: e.title,
                artist_name: event_data["artist_name"],
                description: event_data["description"],
                url: event_data["url"],
                tags: event_data["tags"] || [],
                venue_name: event_data["venue_name"]
              }

              CategoryExtractor.assign_categories_to_event(e.id, "bandsintown", raw_event_data)
              Logger.info("🏷️ Categories assigned to Bandsintown event #{e.id}")

              e

            {:error, %Ecto.Changeset{} = changeset} ->
              # Check if this is a validation failure for required fields
              errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

              if has_required_field_errors?(errors) do
                Logger.warning("🚫 Rejecting event - missing required fields: #{inspect(errors)}")

                Logger.warning(
                  "   Event data: title=#{event_attrs[:title]}, starts_at=#{event_attrs[:starts_at]}"
                )

                Repo.rollback({:validation_failure, :missing_required_fields})
              else
                Logger.error("Failed to store event: #{inspect(changeset)}")
                Repo.rollback({:event_error, changeset})
              end

            {:error, reason} ->
              Logger.error("Failed to store event: #{inspect(reason)}")
              Repo.rollback({:event_error, reason})
          end
        end

      # Link performer to event (only if both exist)
      if event && performer do
        case link_performer_to_event(event, performer) do
          {:ok, _} ->
            Logger.info("✅ Linked performer #{performer.name} to event #{event.title}")

          {:error, reason} ->
            Logger.error("❌ Failed to link performer to event: #{inspect(reason)}")
            # Don't fail the whole transaction for this
        end
      else
        Logger.warning(
          "⚠️ Skipping performer link: event=#{!is_nil(event)}, performer=#{!is_nil(performer)}"
        )
      end

      # Create or update public_event_source record (only if we know the source)
      if is_nil(source_id) do
        Logger.warning("Skipping event-source link: missing source_id for event #{event.title}")
      else
        source_attrs = %{
          event_id: event.id,
          source_id: source_id,
          source_url: event_data["url"],
          external_id: event_data["external_id"] || extract_id_from_url(event_data["url"]),
          last_seen_at: DateTime.utc_now(),
          description_translations:
            if(event_data["description"],
              do: detect_description_language(event_data["description"]),
              else: nil
            ),
          # Store directly in field
          image_url: event_data["image_url"],
          metadata: %{
            "is_primary" => true,
            "scraper_version" => "1.0",
            "job_id" => event_data["job_id"],
            # Move event-specific metadata here
            # Keep in metadata for backward compat
            "image_url" => event_data["image_url"],
            "rsvp_count" => event_data["rsvp_count"],
            "interested_count" => event_data["interested_count"],
            "tags" => event_data["tags"] || [],
            "event_status" => event_data["event_status"],
            "facebook_event" => event_data["facebook_event"]
          }
        }

        case upsert_event_source(source_attrs) do
          {:ok, _source} ->
            Logger.info("✅ Successfully linked event to source")

          {:error, reason} ->
            Logger.warning(
              "Event source link already exists or cannot be created: #{inspect(reason)}"
            )

            # Don't fail - the event is still valid and may already be linked
            :ok
        end
      end

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
      country_code: extract_country_code(event_data["venue_country"])
    }

    Logger.info("🏢 Attempting to store venue: #{inspect(venue_attrs)}")

    # Check if we have minimum required data
    if is_nil(venue_attrs.name) or venue_attrs.name == "" do
      Logger.error("❌ Venue name is missing! Event data keys: #{inspect(Map.keys(event_data))}")

      Logger.error(
        "   Full venue data: #{inspect(Map.take(event_data, ["venue_name", "venue_address", "venue_city", "venue_latitude", "venue_longitude"]))}"
      )
    end

    VenueStore.find_or_create_venue(venue_attrs)
  end

  defp store_performer(event_data, source_id) do
    performer_attrs = %{
      name: event_data["artist_name"],
      image_url: event_data["image_url"],
      source_id: source_id,
      metadata: %{
        artist_url: event_data["artist_url"],
        social_links: event_data["artist_same_as"] || []
      }
    }

    Logger.info("🎭 Attempting to store performer: #{inspect(performer_attrs.name)}")

    if is_nil(performer_attrs.name) or performer_attrs.name == "" do
      Logger.error(
        "❌ Performer name is missing! Event data has artist_name: #{inspect(event_data["artist_name"])}"
      )
    end

    PerformerStore.find_or_create_performer(performer_attrs)
  end

  defp upsert_event(attrs) do
    changeset =
      %PublicEvent{}
      |> PublicEvent.changeset(attrs)

    # Since external_id is no longer in public_events, we can't use it as conflict target
    # Just insert the event, collision detection happens before this
    Repo.insert(changeset)
  end

  defp link_performer_to_event(%PublicEvent{id: event_id}, %{id: performer_id}) do
    # Check if link already exists
    existing =
      Repo.get_by(PublicEventPerformer,
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
        metadata: %{
          is_headliner: true,
          billing_order: 1
        }
      })
      |> Repo.insert()
    end
  end

  defp upsert_event_source(attrs) do
    # First check if a record already exists for this source and external_id
    existing =
      Repo.get_by(PublicEventSource,
        source_id: attrs.source_id,
        external_id: attrs.external_id
      )

    if existing do
      # Update existing record if event_id changed (collision detection)
      if existing.event_id != attrs.event_id do
        Logger.info(
          "Updating event source link from event #{existing.event_id} to #{attrs.event_id}"
        )

        existing
        |> PublicEventSource.changeset(%{
          event_id: attrs.event_id,
          source_url: attrs.source_url,
          last_seen_at: attrs.last_seen_at,
          metadata: attrs.metadata,
          image_url: attrs.image_url
        })
        |> Repo.update()
      else
        # Just update the last_seen_at
        existing
        |> PublicEventSource.changeset(%{
          last_seen_at: attrs.last_seen_at
        })
        |> Repo.update()
      end
    else
      # Check if the event already has a link from this source (different external_id)
      existing_by_event =
        Repo.get_by(PublicEventSource,
          event_id: attrs.event_id,
          source_id: attrs.source_id
        )

      if existing_by_event do
        Logger.warning(
          "Event #{attrs.event_id} already has a different link from source #{attrs.source_id}, updating external_id"
        )

        # Update the existing link with new external_id
        existing_by_event
        |> PublicEventSource.changeset(%{
          external_id: attrs.external_id,
          source_url: attrs.source_url,
          last_seen_at: attrs.last_seen_at,
          metadata: attrs.metadata,
          image_url: attrs.image_url
        })
        |> Repo.update()
      else
        # Create new link
        %PublicEventSource{}
        |> PublicEventSource.changeset(attrs)
        |> Repo.insert()
      end
    end
  end

  defp extract_country_code(country_name) when is_binary(country_name) do
    # Use the countries library to properly get country code
    case Countries.filter_by(:name, country_name) do
      [country | _] ->
        country.alpha2

      [] ->
        # Try common name variations
        case Countries.filter_by(:unofficial_names, country_name) do
          [country | _] ->
            country.alpha2

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

  defp detect_title_language(title) when is_binary(title) do
    # Use same logic as Ticketmaster transformer for consistency
    polish_indicators = [
      # Common Polish words in event titles
      "koncert",
      "wystawa",
      "spektakl",
      "przedstawienie",
      "festiwal",
      "teatr",
      "opera",
      "balet",
      "film",
      "kino",
      "muzeum",
      # Polish prepositions and articles
      " w ",
      " na ",
      " do ",
      " ze ",
      " przy ",
      " dla ",
      " gościnnie",
      " wystąpi",
      # Polish venue/location indicators
      "kraków",
      "warszawa",
      "gdańsk",
      "wrocław",
      "poznań",
      "hala",
      "centrum",
      # Polish diacritics
      "ą",
      "ć",
      "ę",
      "ł",
      "ń",
      "ó",
      "ś",
      "ź",
      "ż"
    ]

    title_lower = String.downcase(title)

    is_polish =
      Enum.any?(polish_indicators, fn indicator ->
        String.contains?(title_lower, String.downcase(indicator))
      end)

    if is_polish do
      %{"pl" => title}
    else
      %{"en" => title}
    end
  end

  defp detect_title_language(_), do: nil

  defp detect_description_language(description) when is_binary(description) do
    # Use same logic as title detection for consistency
    polish_indicators = [
      # Common Polish words
      "koncert",
      "wystawa",
      "spektakl",
      "przedstawienie",
      "festiwal",
      "teatr",
      "opera",
      "balet",
      "film",
      "kino",
      "muzeum",
      # Polish prepositions and articles
      " w ",
      " na ",
      " do ",
      " ze ",
      " przy ",
      " dla ",
      " gościnnie",
      " wystąpi",
      # Polish venue/location indicators
      "kraków",
      "warszawa",
      "gdańsk",
      "wrocław",
      "poznań",
      "hala",
      "centrum",
      # Polish diacritics
      "ą",
      "ć",
      "ę",
      "ł",
      "ń",
      "ó",
      "ś",
      "ź",
      "ż"
    ]

    description_lower = String.downcase(description)

    is_polish =
      Enum.any?(polish_indicators, fn indicator ->
        String.contains?(description_lower, String.downcase(indicator))
      end)

    if is_polish do
      %{"pl" => description}
    else
      %{"en" => description}
    end
  end

  defp detect_description_language(_), do: nil
end
