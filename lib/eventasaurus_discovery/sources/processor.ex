defmodule EventasaurusDiscovery.Sources.Processor do
  @moduledoc """
  Unified processor for all event sources.

  Handles the standard workflow of processing venues, performers, and events
  from any source using the shared processors.
  """

  require Logger

  alias EventasaurusDiscovery.Scraping.Processors.{EventProcessor, VenueProcessor}
  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.Metrics.ErrorCategories

  @doc """
  Process a list of events from any source.

  ## Parameters
  - `events` - List of event data maps to process
  - `source` - Source struct, source_id (integer), or scraper name (string) - used for performer attribution
  - `scraper_name` - Optional explicit scraper name (string) for venue metadata attribution

  ## Returns
    - {:ok, processed_events} - Successfully processed events
    - {:error, reason} - Processing failed with retryable error
    - {:discard, reason} - Critical failure, job should be discarded (e.g., missing GPS coordinates)
  """
  def process_source_data(events, source, scraper_name \\ nil) when is_list(events) do
    results =
      Enum.map(events, fn event_data ->
        process_single_event(event_data, source, scraper_name)
      end)

    # Check if any events failed with critical GPS coordinate errors
    critical_failures =
      Enum.filter(results, fn
        {:error, {:discard, _}} -> true
        _ -> false
      end)

    # If we have critical failures (missing GPS coordinates), fail the entire job
    if length(critical_failures) > 0 do
      failure_messages = Enum.map(critical_failures, fn {:error, {:discard, msg}} -> msg end)
      combined_message = Enum.join(failure_messages, "; ")

      # Log summary without exposing full address details
      Logger.error(
        "🚫 CRITICAL: Discarding job due to missing GPS coordinates. failures=#{length(critical_failures)}/#{length(events)}"
      )

      # Return error that will cause Oban to discard the job
      {:discard, "GPS coordinate validation failed: #{combined_message}"}
    else
      successful =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      failed =
        Enum.filter(results, fn
          {:error, _} -> true
          _ -> false
        end)

      # Return proper error tuples based on results
      case {successful, failed} do
        {[], [_ | _] = failed} ->
          # All events failed - log detailed error info for debugging
          Logger.error("❌ All #{length(failed)} events failed processing")

          # Log each failure reason with details
          Enum.with_index(failed, 1)
          |> Enum.each(fn {{:error, reason}, index} ->
            Logger.error("  Event #{index} failed: #{inspect(reason)}")
          end)

          # Capture first error and error type aggregation for Oban metadata
          first_error = List.first(failed)

          # Aggregate error types for pattern analysis
          error_types =
            failed
            |> Enum.map(fn {:error, reason} ->
              # Categorize based on actual error formats returned by processors
              categorize_error(reason)
            end)
            |> Enum.frequencies()

          # Return structured error with debugging context preserved
          {:error,
           {:all_events_failed,
            %{
              first_error: first_error,
              total_failed: length(failed),
              error_types: error_types
            }}}

        {successful, []} ->
          # All events succeeded
          Logger.info("✅ Successfully processed all #{length(successful)} events")
          {:ok, Enum.map(successful, fn {:ok, event} -> event end)}

        {_successful, failed} ->
          # Partial success - return error so Oban can retry
          Logger.warning(
            "⚠️ Partial failure: #{length(failed)} failed out of #{length(events)} total events"
          )

          # Log each failure for debugging
          Enum.with_index(failed, 1)
          |> Enum.each(fn {{:error, reason}, index} ->
            Logger.warning("  Event #{index} failed: #{inspect(reason)}")
          end)

          {:error, {:partial_failure, length(failed), length(events)}}
      end
    end
  end

  @doc """
  Process a single event with its venue and performers
  """
  def process_single_event(event_data, source, scraper_name \\ nil) do
    # Handle different key names for venue data
    venue_data =
      event_data[:venue] || event_data["venue"] ||
        event_data[:venue_data] || event_data["venue_data"]

    # Note: Job execution logging is now handled via Oban telemetry
    # (see EventasaurusDiscovery.Metrics.MetricsTracker)
    # The ScraperProcessingLogs module was removed in Issue #3048 Phase 3

    with {:ok, venue} <- process_venue(venue_data, source, scraper_name),
         {:ok, performers} <-
           process_performers(event_data[:performers] || event_data["performers"] || [], source),
         {:ok, event} <- process_event(event_data, source, venue, performers) do
      {:ok, event}
    else
      {:error, reason} when is_binary(reason) ->
        # Check if this is a GPS coordinate error that should fail the job
        # More robust matching for GPS-related errors
        if String.contains?(String.downcase(reason), "gps coordinates") or
             String.contains?(String.downcase(reason), "latitude") or
             String.contains?(String.downcase(reason), "longitude") do
          Logger.error("🚫 Critical venue error - Missing GPS coordinates")
          # Log limited event data to avoid PII exposure
          event_summary = Map.take(event_data, [:external_id, :title])
          Logger.debug("Event summary: #{inspect(event_summary)}")
          # Return a special error tuple that indicates job should be discarded
          {:error, {:discard, reason}}
        else
          Logger.error("Failed to process event: #{String.slice(reason, 0, 200)}")
          {:error, reason}
        end

      {:error, reason} = error ->
        Logger.error("Failed to process event: #{inspect(reason)}")
        Logger.debug("Event data: #{inspect(event_data)}")
        error
    end
  end

  defp process_venue(nil, _source, _scraper_name) do
    {:error, :venue_required}
  end

  defp process_venue(venue_data, source, scraper_name) when is_map(venue_data) do
    # Use explicit scraper_name if provided, otherwise extract from source
    source_scraper = scraper_name || extract_scraper_name(source)
    VenueProcessor.process_venue(venue_data, source, source_scraper)
  end

  # Extract scraper name from source parameter
  # Source can be: struct (Source), integer (source_id), string ("question_one"), or atom (:question_one)
  defp extract_scraper_name(%{name: name}) when is_binary(name) do
    # Source struct with name field - extract the scraper name
    name
  end

  defp extract_scraper_name(source) when is_integer(source) do
    # For source_id integers, we can't reliably determine scraper name
    # This will be nil and VenueProcessor will handle it
    nil
  end

  defp extract_scraper_name(source) when is_binary(source) do
    source
  end

  defp extract_scraper_name(source) when is_atom(source) do
    Atom.to_string(source)
  end

  defp extract_scraper_name(_), do: nil

  defp process_performers(nil, _source), do: {:ok, []}
  defp process_performers([], _source), do: {:ok, []}

  defp process_performers(performers_data, source) when is_list(performers_data) do
    results =
      Enum.map(performers_data, fn performer_data ->
        # Normalize performer data - handle both maps and plain strings
        attrs =
          case performer_data do
            %{} = map -> map
            name when is_binary(name) -> %{"name" => name}
            other -> %{"name" => to_string(other)}
          end

        # Add source_id to performer data if not present
        attrs_with_source = Map.put_new(attrs, "source_id", source.id)
        PerformerStore.find_or_create_performer(attrs_with_source)
      end)

    performers =
      Enum.reduce(results, {:ok, []}, fn
        {:ok, performer}, {:ok, acc} -> {:ok, [performer | acc]}
        # Skip failed performers
        {:error, _reason}, {:ok, acc} -> {:ok, acc}
        _, error -> error
      end)

    case performers do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp process_event(event_data, source, venue, performers) do
    event_with_venue = Map.put(event_data, :venue_id, venue.id)

    # EventProcessor expects performer_names as a list of strings
    # Clean UTF-8 from performer names to prevent Slug library crashes
    performer_names =
      Enum.map(performers, fn p ->
        EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(p.name)
      end)

    event_with_performers = Map.put(event_with_venue, :performer_names, performer_names)

    # EventProcessor expects source_id and source_priority
    source_id = if is_struct(source), do: source.id, else: source
    source_priority = if is_struct(source), do: source.priority, else: 10
    EventProcessor.process_event(event_with_performers, source_id, source_priority)
  end

  # Use ErrorCategories for comprehensive error categorization
  # ErrorCategories.categorize_error/1 already returns an atom
  defp categorize_error(reason) do
    ErrorCategories.categorize_error(reason)
  end

  @doc """
  Gets the current Oban job ID from the process dictionary.

  Returns the job ID if the current process is executing within an Oban job,
  otherwise returns nil.

  ## Examples

      # Within an Oban worker
      iex> get_oban_job_id()
      12345

      # Outside an Oban worker
      iex> get_oban_job_id()
      nil
  """
  def get_oban_job_id do
    case Process.get(:oban_job) do
      %Oban.Job{id: id} -> id
      _ -> nil
    end
  end
end
