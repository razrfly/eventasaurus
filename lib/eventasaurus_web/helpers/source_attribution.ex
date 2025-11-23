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

    url =
      cond do
        # PRIORITY 1: source_url (event-specific URLs)
        # Cinema City stores booking URL here (specific showtime booking page)
        # BandsInTown and other scrapers also use this for ticket links
        source.source_url -> source.source_url

        # PRIORITY 2: metadata-based event URLs (scrapers that store in metadata)
        # Ticketmaster stores URL in ticketmaster_data.url
        url = get_in(md, ["ticketmaster_data", "url"]) -> url
        # Bandsintown might have it in event_url or url
        url = md["event_url"] -> url
        url = md["url"] -> url
        # Karnet might have it in a different location
        url = md["link"] -> url
        # Kino Krakow stores movie page URL in metadata
        url = md["movie_url"] -> url

        # PRIORITY 3: Fallback to source website URL (general homepage, not event-specific)
        # This is the least useful but better than nothing
        source.source && source.source.website_url -> source.source.website_url

        true -> nil
      end

    normalize_http_url(url)
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
  Extract source URL from a container's source_event.

  Containers may have a reference event (source_event) that contains the original source data.
  This function checks the source_event's sources for URLs.
  """
  def get_container_source_url(nil), do: nil

  def get_container_source_url(%{source_event: source_event}) when not is_nil(source_event) do
    get_url_from_source_event(source_event)
  end

  def get_container_source_url(%{metadata: metadata}) when is_map(metadata) do
    # Try to construct from container metadata (Resident Advisor)
    case get_in(metadata, ["umbrella_event_id"]) do
      nil -> nil
      umbrella_event_id -> "https://ra.co/events/#{umbrella_event_id}"
    end
  end

  def get_container_source_url(_), do: nil

  # Private helper to extract URL from source event's sources
  defp get_url_from_source_event(%{sources: sources}) when is_list(sources) do
    Enum.find_value(sources, fn source ->
      # Try extracting URL using the main get_source_url function
      get_source_url(source)
    end)
  end

  defp get_url_from_source_event(_), do: nil

  # Normalize and validate HTTP/HTTPS URLs
  defp normalize_http_url(nil), do: nil

  defp normalize_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} = uri when scheme in ["http", "https"] -> URI.to_string(uri)
      _ -> nil
    end
  end
end
