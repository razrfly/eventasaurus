defmodule EventasaurusDiscovery.Sources.Kupbilecik.Config do
  @moduledoc """
  Configuration for Kupbilecik source.

  Kupbilecik.pl is a Polish ticketing platform with ~4,100+ events.
  Uses **Server-Side Rendering (SSR)** for SEO purposes - all event data
  is available in the initial HTML response without JavaScript.

  ## Sitemap Structure

  - sitemap.xml (index) -> sitemap_imprezy-{1-5}.xml (event sitemaps)
  - URLs follow pattern: /imprezy/{event_id}/ or /imprezy/{event_id}/{slug}/

  ## Access Pattern

  - Sitemaps: Plain HTTP (XML)
  - Event pages: Plain HTTP (SSR site, no JS rendering required)

  **Note**: Zyte API is NOT required for this source. Testing confirmed
  that all event data (meta tags, semantic HTML, Schema.org markup) is
  present in the initial HTML response.
  """

  @doc """
  Returns the base URL for kupbilecik.pl.
  """
  def base_url, do: "https://www.kupbilecik.pl"

  @doc """
  Returns list of event sitemap URLs.
  """
  def sitemap_urls do
    [
      "#{base_url()}/sitemap_imprezy-1.xml",
      "#{base_url()}/sitemap_imprezy-2.xml",
      "#{base_url()}/sitemap_imprezy-3.xml",
      "#{base_url()}/sitemap_imprezy-4.xml",
      "#{base_url()}/sitemap_imprezy-5.xml"
    ]
  end

  @doc """
  Returns the source identifier for external IDs.
  """
  def source_slug, do: "kupbilecik"

  @doc """
  Generates an external ID for an event.

  Format: kupbilecik_event_{event_id}_{YYYY-MM-DD}
  """
  def generate_external_id(event_id, date) when is_binary(date) do
    "#{source_slug()}_event_#{event_id}_#{date}"
  end

  def generate_external_id(event_id, %Date{} = date) do
    generate_external_id(event_id, Date.to_iso8601(date))
  end

  def generate_external_id(event_id, %DateTime{} = datetime) do
    generate_external_id(event_id, DateTime.to_date(datetime) |> Date.to_iso8601())
  end

  @doc """
  Generates article-level external ID for freshness tracking.

  Format: kupbilecik_article_{event_id}
  """
  def generate_article_external_id(event_id) do
    "#{source_slug()}_article_#{event_id}"
  end

  @doc """
  Returns rate limit in seconds between requests.

  Conservative limit to be respectful of the source server.
  """
  def rate_limit, do: 1

  @doc """
  Returns HTTP timeout in milliseconds.
  """
  def timeout, do: 30_000

  @doc """
  Returns retry configuration for failed requests.
  """
  def retry_config do
    %{
      max_attempts: 3,
      base_backoff: :timer.seconds(2),
      max_backoff: :timer.seconds(30)
    }
  end

  @doc """
  Returns headers for sitemap requests (plain HTTP).
  """
  def sitemap_headers do
    [
      {"Accept", "application/xml, text/xml"},
      {"Accept-Language", "pl-PL,pl;q=0.9,en;q=0.8"},
      {"User-Agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    ]
  end

  @doc """
  Checks if a URL is an event page URL.

  Valid patterns:
  - /imprezy/{id}/
  - /imprezy/{id}/{slug}/
  """
  def is_event_url?(url) when is_binary(url) do
    String.contains?(url, "/imprezy/") &&
      Regex.match?(~r{/imprezy/\d+}, url)
  end

  def is_event_url?(_), do: false

  @doc """
  Extracts event ID from a kupbilecik URL.

  ## Examples

      iex> Config.extract_event_id("https://www.kupbilecik.pl/imprezy/186000/")
      "186000"

      iex> Config.extract_event_id("https://www.kupbilecik.pl/imprezy/186000/rihanna-live-warszawa/")
      "186000"
  """
  def extract_event_id(url) when is_binary(url) do
    case Regex.run(~r{/imprezy/(\d+)}, url, capture: :all_but_first) do
      [event_id] -> event_id
      _ -> nil
    end
  end

  def extract_event_id(_), do: nil

  @doc """
  Polish month name to number mapping for date parsing.
  """
  def polish_months do
    %{
      "stycznia" => 1,
      "lutego" => 2,
      "marca" => 3,
      "kwietnia" => 4,
      "maja" => 5,
      "czerwca" => 6,
      "lipca" => 7,
      "sierpnia" => 8,
      "września" => 9,
      "października" => 10,
      "listopada" => 11,
      "grudnia" => 12
    }
  end

  @doc """
  Category mapping from Polish to canonical categories.

  Maps kupbilecik category slugs (from URL paths like /kabarety/, /koncerty/)
  and Polish display names to canonical event categories.
  """
  def category_mapping do
    %{
      # Music/Concert categories
      "koncerty" => "music",
      "muzyka" => "music",
      # Theater categories (use "theatre" to match _defaults.yml)
      "spektakle" => "theatre",
      "teatr" => "theatre",
      "opera" => "theatre",
      "musical" => "theatre",
      "balet" => "theatre",
      # Comedy categories
      "kabarety" => "comedy",
      "stand-up" => "comedy",
      # Shows and performances (map to arts as closest match)
      "widowiska" => "arts",
      # Festival
      "festiwale" => "festival",
      # Sports
      "sport" => "sports",
      # Family/Kids
      "dla-dzieci" => "family",
      # Other/Misc
      "inne" => "other"
    }
  end

  @doc """
  Maps a Polish category to canonical category.
  """
  def map_category(polish_category) when is_binary(polish_category) do
    normalized = String.downcase(polish_category) |> String.trim()
    Map.get(category_mapping(), normalized, "other")
  end

  def map_category(_), do: "other"
end
