defmodule EventasaurusWeb.Helpers.SourceAttribution do
  @moduledoc """
  Shared helper functions for displaying source attribution across different page types.

  Provides consistent source URL extraction, name display, and timestamp formatting
  for both individual events and containers (festivals, conferences, etc.).
  """

  @doc """
  Extract source URL from a source record.

  Priority order:
  1. source_url (event-specific URLs like booking pages)
  2. metadata-based event URLs (ticketmaster_data.url, event_url, etc.)
  3. source.website_url (fallback to general homepage)
  """
  def get_source_url(source) do
    # Guard against nil metadata and sanitize URLs
    md = source.metadata || %{}

    # Try candidates in priority order, returning first that normalizes successfully
    # This ensures we fall back to other candidates if earlier ones are blank/invalid
    [
      # PRIORITY 1: source_url (event-specific URLs)
      # Cinema City stores booking URL here (specific showtime booking page)
      # BandsInTown and other scrapers also use this for ticket links
      source.source_url,
      # PRIORITY 2: metadata-based event URLs (scrapers that store in metadata)
      # Ticketmaster stores URL in ticketmaster_data.url
      get_in(md, ["ticketmaster_data", "url"]),
      # Bandsintown might have it in event_url or url
      md["event_url"],
      md["url"],
      # Karnet might have it in a different location
      md["link"],
      # Repertuary stores movie page URL in metadata
      md["movie_url"],
      # PRIORITY 3: Fallback to source website URL (general homepage, not event-specific)
      # This is the least useful but better than nothing
      source.source && source.source.website_url
    ]
    |> Enum.find_value(fn candidate -> normalize_http_url(candidate) end)
  end

  @doc """
  Get the display name for a source.

  Returns the source's name if available, otherwise "Unknown".
  """
  def get_source_name(source) do
    # Use the associated source name if available
    if source.source do
      source.source.name
    else
      "Unknown"
    end
  end

  @doc """
  Get the logo URL for a source.

  Returns the source's logo_url if available, otherwise nil.
  """
  def get_source_logo_url(source) do
    if source.source do
      source.source.logo_url
    else
      nil
    end
  end

  @doc """
  Get the first letter initial for a source name.

  Used as fallback when logo is not available.
  """
  def get_source_initial(source) do
    name = get_source_name(source)

    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      char -> String.upcase(char)
    end
  end

  @doc """
  Format a relative time string from a datetime.

  Examples:
    - "5 minutes ago"
    - "3 hours ago"
    - "2 days ago"
    - "Nov 20, 2024" (for older dates)
  """
  def format_relative_time(nil), do: "unknown"

  def format_relative_time(%NaiveDateTime{} = naive_datetime) do
    # Convert NaiveDateTime to DateTime (assume UTC)
    datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")
    format_relative_time(datetime)
  end

  def format_relative_time(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  @doc """
  Extract source URL from a container.

  Priority order:
  1. Container-specific metadata URLs (event_url, url, link, etc.)
  2. Source event URLs (if container has an associated source_event)
  3. Resident Advisor umbrella_event_id URLs
  4. source.website_url (fallback to general homepage)
  """
  def get_container_source_url(nil), do: nil

  def get_container_source_url(container) do
    md = container.metadata || %{}

    # Try candidates in priority order, returning first that normalizes successfully
    # This ensures we fall back to other candidates if earlier ones are blank/invalid
    [
      # PRIORITY 1: Container-specific metadata URLs
      md["event_url"],
      md["url"],
      md["link"],
      # PRIORITY 2: Source event URLs
      get_url_from_source_event(container.source_event),
      # PRIORITY 3: Resident Advisor umbrella event ID
      case get_in(md, ["umbrella_event_id"]) do
        nil -> nil
        umbrella_event_id -> "https://ra.co/events/#{umbrella_event_id}"
      end,
      # PRIORITY 4: Fallback to source website URL (general homepage)
      container.source && container.source.website_url
    ]
    |> Enum.find_value(&normalize_http_url/1)
  end

  # Private helper to extract URL from source event's sources
  defp get_url_from_source_event(%{sources: sources}) when is_list(sources) do
    Enum.find_value(sources, fn source ->
      # Try extracting URL using the main get_source_url function
      get_source_url(source)
    end)
  end

  defp get_url_from_source_event(_), do: nil

  @doc """
  Deduplicate sources by source_id, keeping only the most recent record for each unique source.

  This is needed because with Cinema City showtimes, we now have multiple PublicEventSource
  records per event (one per showtime), but we only want to display each unique source once
  in the UI (e.g., show "Cinema City" once, not 5 times).

  ## Examples

      iex> deduplicate_sources([source1, source2, source1_duplicate])
      [source1, source2]  # Only unique sources, keeping most recent
  """
  def deduplicate_sources(sources) when is_list(sources) do
    sources
    |> Enum.group_by(fn source ->
      # Group by source.id (the unique source identifier)
      if source.source, do: source.source.id, else: nil
    end)
    |> Enum.map(fn {_source_id, grouped_sources} ->
      # For each group, keep the most recently seen record
      # Use epoch timestamp as fallback for nil values to avoid crashes
      Enum.max_by(
        grouped_sources,
        fn s ->
          s.last_seen_at || ~U[1970-01-01 00:00:00Z]
        end,
        DateTime
      )
    end)
    |> Enum.sort_by(fn s -> s.last_seen_at || ~U[1970-01-01 00:00:00Z] end, {:desc, DateTime})
  end

  def deduplicate_sources(_), do: []

  # Normalize and validate HTTP/HTTPS URLs
  defp normalize_http_url(nil), do: nil

  defp normalize_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} = uri when scheme in ["http", "https"] -> URI.to_string(uri)
      _ -> nil
    end
  end
end
