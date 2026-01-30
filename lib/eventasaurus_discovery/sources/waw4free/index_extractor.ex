defmodule EventasaurusDiscovery.Sources.Waw4free.IndexExtractor do
  @moduledoc """
  Extracts event listings from waw4free.pl category pages.

  Parses HTML to extract:
  - Event URLs (format: /wydarzenie-{id}-{slug})
  - Event titles
  - External IDs
  - Extraction timestamps

  Note: Detailed event data (categories, dates, districts) is extracted
  by DetailExtractor from individual event pages.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Waw4free.Config

  @doc """
  Extract events from category page HTML.
  Returns a list of event data maps with URLs and metadata.
  """
  def extract_events_from_html(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        events = extract_event_urls(document)
        Logger.info("📊 Extracted #{length(events)} event URLs from category page")
        events

      {:error, reason} ->
        Logger.error("Failed to parse HTML: #{inspect(reason)}")
        []
    end
  end

  # Extract event URLs from document.
  # waw4free.pl uses links in format: /wydarzenie-{id}-{slug}
  defp extract_event_urls(document) do
    # Find all links that match the event URL pattern
    event_links = Floki.find(document, "a[href*='wydarzenie-']")

    Logger.debug("Found #{length(event_links)} potential event links")

    event_links
    |> Enum.map(&extract_event_from_link(&1, document))
    |> Enum.filter(&(&1 != nil))
    # Remove duplicates by URL
    |> Enum.uniq_by(& &1.url)
  end

  defp extract_event_from_link(link, _document) do
    try do
      # Extract URL
      url =
        Floki.attribute(link, "href")
        |> List.first()
        |> case do
          nil -> nil
          href -> build_full_url(href)
        end

      # Extract title
      title =
        Floki.text(link)
        |> String.trim()

      # Only process if we have a valid URL and non-empty title
      if url && String.length(title) > 3 && valid_event_url?(url) do
        # Extract external_id from URL
        external_id = Config.extract_external_id(url)

        # Guard against nil external_id
        if is_nil(external_id) do
          nil
        else
          %{
            url: url,
            title: title,
            external_id: external_id,
            extracted_at: DateTime.utc_now()
          }
        end
      else
        nil
      end
    rescue
      e ->
        Logger.warning("Failed to extract event from link: #{inspect(e)}")
        nil
    end
  end

  # Validate that URL is actually an event URL and not navigation/pagination.
  defp valid_event_url?(url) do
    # Must contain "wydarzenie-" with a numeric ID
    # Must have numeric ID after wydarzenie-
    # Exclude common non-event pages
    String.contains?(url, "wydarzenie-") &&
      Regex.match?(~r/wydarzenie-\d+/, url) &&
      !String.contains?(url, "/page/") &&
      !String.contains?(url, "/kategorie/") &&
      !String.contains?(url, "/wydarzenia?") &&
      !String.contains?(url, "utm_")
  end

  defp build_full_url(href) when is_binary(href) do
    cond do
      # Already a full URL
      String.starts_with?(href, "http://") or String.starts_with?(href, "https://") ->
        href

      # Relative URL starting with /
      String.starts_with?(href, "/") ->
        Config.base_url() <> href

      # Relative URL without /
      true ->
        Config.base_url() <> "/" <> href
    end
  end
end
