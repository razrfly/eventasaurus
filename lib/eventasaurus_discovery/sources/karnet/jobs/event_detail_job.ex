defmodule EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Karnet event details.

  Fetches the event page, extracts details, and processes them through
  the unified discovery pipeline.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Sources.Karnet.{Client, DetailExtractor, DateParser}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    url = args["url"]
    source_id = args["source_id"]
    event_metadata = args["event_metadata"] || %{}
    external_id = args["external_id"] || extract_external_id(url)

    Logger.info("🎭 Processing Karnet event: #{url} (External ID: #{external_id})")

    # Check if we can extract event ID for bilingual processing
    case extract_event_id_from_external_id(external_id) do
      nil ->
        Logger.warning("Cannot extract event ID from external_id: #{external_id}, falling back to single language")
        fallback_to_single_language(url, source_id, event_metadata)

      event_id ->
        # Validate that the event ID is numeric
        if is_binary(event_id) and event_id =~ ~r/^\d+$/ do
          Logger.info("🌐 Processing bilingual event ID: #{event_id}")
          process_bilingual_event(url, event_id, source_id, event_metadata)
        else
          Logger.warning("Invalid event ID format: #{event_id}, falling back to single language")
          fallback_to_single_language(url, source_id, event_metadata)
        end
    end
  end

  defp fallback_to_single_language(url, source_id, event_metadata) do
    # Original single-language processing
    case Client.fetch_page(url) do
      {:ok, html} ->
        process_event_html(html, url, source_id, event_metadata)

      {:error, :not_found} ->
        Logger.warning("Event page not found: #{url}")
        {:ok, :not_found}

      {:error, reason} ->
        Logger.error("Failed to fetch event page #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_bilingual_event(original_url, event_id, source_id, event_metadata) do
    # Build bilingual URLs
    urls = build_bilingual_urls(original_url, event_id)

    Logger.info("🌐 Fetching bilingual content for event #{event_id}")
    Logger.debug("Polish URL: #{urls.polish}")
    Logger.debug("English URL: #{urls.english}")

    # Fetch both language versions
    {polish_result, english_result} = fetch_bilingual_content(urls, original_url)

    # Merge bilingual content
    case merge_bilingual_content(polish_result, english_result, event_metadata) do
      {:ok, enriched_data} ->
        Logger.debug("✅ Bilingual content merged successfully")

        # Check if venue data is valid
        if is_nil(enriched_data[:venue_data]) do
          Logger.warning("⚠️ Discarding event without valid venue: #{original_url}")
          {:discard, :no_valid_venue}
        else
          # Parse dates and process through pipeline
          enriched_data = add_parsed_dates(enriched_data)

          # Get source and process
          source = Repo.get!(Source, source_id)
          process_through_pipeline(enriched_data, source)
        end

      {:error, reason} ->
        Logger.error("❌ Bilingual processing failed for #{original_url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_event_html(html, url, source_id, metadata) do
    Logger.debug("🔍 Processing event HTML for URL: #{url}")

    # Extract event details
    case DetailExtractor.extract_event_details(html, url) do
      {:ok, event_data} ->
        Logger.debug(
          "📋 Extracted event data - Title: #{event_data[:title]}, Venue: #{inspect(event_data[:venue_data])}"
        )

        # Check if venue data is nil (events without venues should be discarded)
        if is_nil(event_data[:venue_data]) do
          Logger.warning("⚠️ Discarding event without valid venue: #{url}")
          {:discard, :no_valid_venue}
        else
          # Merge with metadata from index if available
          enriched_data = merge_metadata(event_data, metadata)
          Logger.debug("📊 Enriched data - Date text: #{enriched_data[:date_text]}")

          # Parse dates
          enriched_data = add_parsed_dates(enriched_data)

          Logger.debug(
            "📅 Parsed dates - Start: #{inspect(enriched_data[:starts_at])}, End: #{inspect(enriched_data[:ends_at])}"
          )

          # Get source
          source = Repo.get!(Source, source_id)

          # Process through unified pipeline
          case process_through_pipeline(enriched_data, source) do
            {:ok, event} ->
              Logger.info("✅ Successfully processed Karnet event: #{event.id} - #{event.title}")
              {:ok, event}

            {:error, reason} ->
              Logger.error("❌ Pipeline processing failed for #{url}: #{inspect(reason)}")
              Logger.debug("🔍 Failed event data: #{inspect(enriched_data, limit: :infinity)}")
              {:error, reason}
          end
        end

      {:error, reason} ->
        Logger.error("❌ Failed to extract event details from #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp merge_metadata(event_data, metadata) do
    # Prefer extracted data but fall back to metadata from index
    Map.merge(metadata, event_data, fn _key, meta_val, event_val ->
      if is_nil(event_val) || event_val == "", do: meta_val, else: event_val
    end)
  end

  defp add_parsed_dates(event_data) do
    # Parse the date text into actual DateTime values
    case DateParser.parse_date_string(event_data[:date_text]) do
      {:ok, {start_dt, end_dt}} ->
        event_data
        |> Map.put(:starts_at, start_dt)
        |> Map.put(:ends_at, if(start_dt == end_dt, do: nil, else: end_dt))

      _ ->
        # If we can't parse the date, use a fallback
        Logger.warning("Could not parse date: #{event_data[:date_text]}")

        # Use a reasonable fallback: 30 days from now for the event
        # This allows the event to be stored but marked as needing review
        fallback_date = DateTime.add(DateTime.utc_now(), 30 * 86400, :second)

        event_data
        |> Map.put(:starts_at, fallback_date)
        |> Map.put(:ends_at, nil)
        |> Map.update(:source_metadata, %{}, fn meta ->
          Map.put(meta, "date_parse_failed", true)
        end)
    end
  end

  defp process_through_pipeline(event_data, source) do
    # Transform data to match processor expectations
    processor_data = transform_for_processor(event_data)

    # Process through unified pipeline
    Processor.process_single_event(processor_data, source)
  end

  defp transform_for_processor(event_data) do
    # Venue is required - no fallback
    venue_data = event_data[:venue_data]

    Logger.debug(
      "🔄 Transforming for processor - Venue: #{inspect(venue_data)}, Start: #{inspect(event_data[:starts_at])}"
    )

    %{
      # Required fields
      title: event_data[:title] || "Untitled Event",
      title_translations: event_data[:title_translations],
      description_translations: event_data[:description_translations],
      source_url: event_data[:url],

      # CRITICAL: Processor expects 'start_at' not 'starts_at'!
      # Changed from 'starts_at' to 'start_at'
      start_at: event_data[:starts_at],
      ends_at: event_data[:ends_at],

      # Venue - will be processed by VenueProcessor
      venue_data: venue_data,

      # Performers
      performers: event_data[:performers] || [],
      performer_names: extract_performer_names(event_data[:performers]),

      # Additional fields
      ticket_url: event_data[:ticket_url],
      image_url: event_data[:image_url],
      category: event_data[:category],
      is_free: event_data[:is_free] || false,
      is_festival: event_data[:is_festival] || false,

      # Metadata
      external_id: extract_external_id(event_data[:url]),
      metadata: %{
        "url" => event_data[:url],
        "category" => event_data[:category],
        "date_text" => event_data[:date_text],
        "extracted_at" => event_data[:extracted_at],
        "source_url" => event_data[:url]
      },

      # CRITICAL FIX: Add raw_event_data for CategoryExtractor
      # This allows the category system to extract and learn Polish translations
      raw_event_data: %{
        category: event_data[:category],
        url: event_data[:url],
        title: event_data[:title],
        description_translations: event_data[:description_translations]
      }
    }
  end

  defp extract_performer_names(nil), do: []
  defp extract_performer_names([]), do: []

  defp extract_performer_names(performers) when is_list(performers) do
    Enum.map(performers, fn
      %{name: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp extract_external_id(url) do
    # Extract the event ID from the URL
    # Format: /60682-krakow-event-name
    case Regex.run(~r/\/(\d+)-/, url) do
      [_, id] -> "karnet_#{id}"
      _ -> nil
    end
  end

  # New bilingual support functions

  defp extract_event_id_from_external_id("karnet_" <> id), do: id
  defp extract_event_id_from_external_id(_), do: nil

  defp build_bilingual_urls(original_url, _event_id) do
    # Extract slug from original URL
    # Original: https://karnet.krakowculture.pl/60671-krakow-brncui-sculpting-with-light
    # Extract: 60671-krakow-brncui-sculpting-with-light
    slug = case Regex.run(~r/\/(\d+-krakow-.+)$/, original_url) do
      [_, slug] -> slug
      _ ->
        # Fallback: extract everything after the last slash
        original_url |> String.split("/") |> List.last() || ""
    end

    %{
      polish: "https://karnet.krakowculture.pl/pl/#{slug}",
      english: "https://karnet.krakowculture.pl/en/#{slug}"
    }
  end

  defp fetch_bilingual_content(urls, _original_url) do
    Logger.debug("🌐 Fetching bilingual content - PL: #{urls.polish}, EN: #{urls.english}")

    # Fetch Polish version (should always exist)
    polish_result = case Client.fetch_page(urls.polish) do
      {:ok, html} ->
        Logger.debug("✅ Polish content fetched successfully")
        case DetailExtractor.extract_event_details(html, urls.polish) do
          {:error, :error_page} ->
            Logger.warning("⚠️ Polish URL returned an error page: #{urls.polish}")
            {:error, :error_page}
          result ->
            result
        end
      {:error, reason} ->
        Logger.warning("❌ Failed to fetch Polish version: #{inspect(reason)}")
        {:error, reason}
    end

    # Fetch English version (may not exist)
    english_result = case Client.fetch_page(urls.english) do
      {:ok, html} ->
        Logger.debug("✅ English content fetched successfully")
        case DetailExtractor.extract_event_details(html, urls.english) do
          {:error, :error_page} ->
            Logger.info("ℹ️ English version returned error page (404 likely): #{urls.english}")
            {:ok, nil}  # Treat error page as missing English version
          result ->
            result
        end
      {:error, :not_found} ->
        Logger.info("ℹ️ English version not available: #{urls.english}")
        {:ok, nil}
      {:error, reason} ->
        Logger.warning("⚠️ Failed to fetch English version: #{inspect(reason)}")
        {:ok, nil}
    end

    {polish_result, english_result}
  end

  defp merge_bilingual_content(polish_result, english_result, metadata) do
    case {polish_result, english_result} do
      {{:ok, polish_data}, {:ok, english_data}} when not is_nil(english_data) ->
        Logger.debug("🔀 Merging Polish and English content")
        merged_data = merge_language_data(polish_data, english_data, metadata)
        {:ok, merged_data}

      {{:ok, polish_data}, {:ok, nil}} ->
        Logger.debug("📝 Using Polish-only content")
        enriched_data = merge_metadata(polish_data, metadata)
        # Add Polish translation when there's no English version
        enriched_data = enriched_data
          |> Map.put(:title_translations, %{"pl" => polish_data[:title]})
          |> Map.put(:description_translations, %{"pl" => get_description_text(polish_data)})
        {:ok, enriched_data}

      {{:ok, polish_data}, {:error, _}} ->
        Logger.debug("📝 Using Polish content (English failed)")
        enriched_data = merge_metadata(polish_data, metadata)
        # Add Polish translation when English extraction failed
        enriched_data = enriched_data
          |> Map.put(:title_translations, %{"pl" => polish_data[:title]})
          |> Map.put(:description_translations, %{"pl" => get_description_text(polish_data)})
        {:ok, enriched_data}

      {{:error, reason}, _} ->
        Logger.error("❌ Polish content extraction failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp merge_language_data(polish_data, english_data, metadata) do
    # Start with Polish data as base
    base_data = merge_metadata(polish_data, metadata)

    # Merge title translations
    polish_title = polish_data[:title]
    english_title = english_data[:title]

    # Validate that the English content is actually for the same event
    if english_title && !validate_translation_match(polish_data, english_data) do
      Logger.warning("⚠️ English translation seems unrelated to Polish event, skipping English data")
      Logger.warning("  Polish: #{inspect(polish_title)}")
      Logger.warning("  English: #{inspect(english_title)}")

      # Only use Polish data - don't include bad English translation
      title_translations = %{"pl" => polish_title}
      description_translations = %{"pl" => get_description_text(polish_data)}

      base_data
      |> Map.put(:title_translations, title_translations)
      |> Map.put(:description_translations, description_translations)
      |> Map.put(:title, polish_title || base_data[:title])  # Keep original title
    else
      # Normal flow - merge both languages
      title_translations = %{}
      title_translations = if polish_title, do: Map.put(title_translations, "pl", polish_title), else: title_translations
      title_translations = if english_title, do: Map.put(title_translations, "en", english_title), else: title_translations

      # Merge description translations
      polish_desc = get_description_text(polish_data)
      english_desc = get_description_text(english_data)

      description_translations = %{}
      description_translations = if polish_desc, do: Map.put(description_translations, "pl", polish_desc), else: description_translations
      description_translations = if english_desc, do: Map.put(description_translations, "en", english_desc), else: description_translations

      # Merge the translation data
      base_data
      |> Map.put(:title_translations, title_translations)
      |> Map.put(:description_translations, description_translations)
      |> Map.put(:title, polish_title || english_title)  # Fallback to available title
    end
  end

  defp get_description_text(nil), do: nil
  defp get_description_text(data) do
    # Extract description text from event data
    # This might be in different fields depending on the extractor
    data[:description] || data[:summary] || data[:content] || ""
  end

  defp validate_translation_match(polish_data, english_data) do
    # Simple validation - if dates or venues match, they're likely the same event
    polish_date = polish_data[:date_text] || polish_data[:event_date]
    english_date = english_data[:date_text] || english_data[:event_date]

    polish_venue = polish_data[:venue_data]
    english_venue = english_data[:venue_data]

    # If both have dates and they match, it's the same event
    dates_match = polish_date && english_date && polish_date == english_date

    # If both have venue names and they're similar, it's the same event
    venues_match = case {polish_venue, english_venue} do
      {%{name: pv}, %{name: ev}} when is_binary(pv) and is_binary(ev) ->
        String.downcase(pv) == String.downcase(ev) ||
        String.contains?(String.downcase(pv), String.downcase(ev)) ||
        String.contains?(String.downcase(ev), String.downcase(pv))
      _ -> false
    end

    # If we have evidence it's the same event, return true
    # Otherwise, check if titles are suspiciously different
    if dates_match || venues_match do
      true
    else
      # Check if titles share any numbers or key patterns
      polish_title = polish_data[:title] || ""
      english_title = english_data[:title] || ""

      # Extract numbers from both titles
      polish_numbers = Regex.scan(~r/\d+/, polish_title) |> List.flatten()
      english_numbers = Regex.scan(~r/\d+/, english_title) |> List.flatten()

      # If they share numbers, they might be related
      numbers_match = length(polish_numbers) > 0 && length(english_numbers) > 0 &&
                     Enum.any?(polish_numbers, &(&1 in english_numbers))

      # Default to true unless we're sure they're different
      numbers_match || (polish_title == "" || english_title == "")
    end
  end
end
