defmodule EventasaurusDiscovery.Sources.Sortiraparis.Extractors.SitemapExtractor do
  @moduledoc """
  Extracts and parses URLs from Sortiraparis sitemap XML files.

  ## Responsibilities

  1. Parse sitemap XML structure
  2. Extract all `<loc>` URLs
  3. Extract optional metadata (`<lastmod>`, `<changefreq>`, `<priority>`)
  4. Handle malformed XML gracefully
  5. Validate URLs before returning

  ## Sitemap Format

  Standard XML sitemap format:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
      <loc>https://www.sortiraparis.com/articles/319282-indochine-concert</loc>
      <lastmod>2025-01-15T10:30:00+00:00</lastmod>
      <changefreq>weekly</changefreq>
      <priority>0.8</priority>
    </url>
  </urlset>
  ```

  ## Usage

      iex> xml = File.read!("sitemap.xml")
      iex> SitemapExtractor.extract_urls(xml)
      {:ok, ["https://www.sortiraparis.com/articles/319282-...", ...]}

      iex> SitemapExtractor.extract_urls_with_metadata(xml)
      {:ok, [
        %{
          url: "https://www.sortiraparis.com/articles/319282-...",
          last_modified: ~U[2025-01-15 10:30:00Z],
          change_frequency: "weekly",
          priority: 0.8
        },
        ...
      ]}
  """

  require Logger

  @doc """
  Extract URLs from sitemap XML.

  Returns a list of URL strings.

  ## Examples

      iex> extract_urls("<urlset><url><loc>https://example.com/1</loc></url></urlset>")
      {:ok, ["https://example.com/1"]}

      iex> extract_urls("<invalid>xml</invalid>")
      {:ok, []}

      iex> extract_urls("")
      {:ok, []}
  """
  def extract_urls(xml_content) when is_binary(xml_content) do
    case parse_sitemap_urls(xml_content) do
      {:ok, urls} -> {:ok, urls}
      {:error, _reason} = error -> error
    end
  end

  def extract_urls(_), do: {:error, :invalid_xml_content}

  @doc """
  Extract URLs with metadata from sitemap XML.

  Returns a list of maps with URL and metadata fields.

  ## Examples

      iex> xml = "<urlset><url><loc>https://example.com/1</loc><lastmod>2025-01-15</lastmod></url></urlset>"
      iex> extract_urls_with_metadata(xml)
      {:ok, [%{url: "https://example.com/1", last_modified: ~D[2025-01-15], ...}]}
  """
  def extract_urls_with_metadata(xml_content) when is_binary(xml_content) do
    case parse_sitemap_with_metadata(xml_content) do
      {:ok, url_entries} -> {:ok, url_entries}
      {:error, _reason} = error -> error
    end
  end

  def extract_urls_with_metadata(_), do: {:error, :invalid_xml_content}

  @doc """
  Extract sitemap index URLs from sitemap index XML.

  Sitemap index format:
  ```xml
  <sitemapindex>
    <sitemap>
      <loc>https://www.sortiraparis.com/sitemap-en-1.xml</loc>
      <lastmod>2025-01-15</lastmod>
    </sitemap>
  </sitemapindex>
  ```

  ## Examples

      iex> extract_sitemap_index_urls(sitemap_index_xml)
      {:ok, ["https://www.sortiraparis.com/sitemap-en-1.xml", ...]}
  """
  def extract_sitemap_index_urls(xml_content) when is_binary(xml_content) do
    case parse_sitemap_index(xml_content) do
      {:ok, sitemap_urls} -> {:ok, sitemap_urls}
      {:error, _reason} = error -> error
    end
  end

  def extract_sitemap_index_urls(_), do: {:error, :invalid_xml_content}

  # Private functions

  defp parse_sitemap_urls(xml_content) do
    # Simple regex-based extraction for <loc> tags
    # More robust than full XML parsing for our use case
    case Regex.scan(~r{<loc>(.*?)</loc>}s, xml_content, capture: :all_but_first) do
      [] ->
        Logger.debug("No <loc> tags found in sitemap")
        {:ok, []}

      matches ->
        urls =
          matches
          |> Enum.map(fn [url] -> String.trim(url) end)
          |> Enum.filter(&valid_url?/1)

        Logger.debug("Extracted #{length(urls)} URLs from sitemap")
        {:ok, urls}
    end
  rescue
    error ->
      Logger.error("Failed to parse sitemap XML: #{inspect(error)}")
      {:error, :parse_error}
  end

  defp parse_sitemap_with_metadata(xml_content) do
    # Extract full <url> blocks with all metadata
    case Regex.scan(~r{<url>(.*?)</url>}s, xml_content, capture: :all_but_first) do
      [] ->
        Logger.debug("No <url> entries found in sitemap")
        {:ok, []}

      matches ->
        url_entries =
          matches
          |> Enum.map(fn [url_block] -> parse_url_entry(url_block) end)
          |> Enum.reject(&is_nil/1)

        Logger.debug("Extracted #{length(url_entries)} URL entries with metadata")
        {:ok, url_entries}
    end
  rescue
    error ->
      Logger.error("Failed to parse sitemap with metadata: #{inspect(error)}")
      {:error, :parse_error}
  end

  defp parse_sitemap_index(xml_content) do
    # Extract <loc> tags from <sitemap> blocks
    case Regex.scan(~r{<sitemap>.*?<loc>(.*?)</loc>.*?</sitemap>}s, xml_content,
           capture: :all_but_first
         ) do
      [] ->
        Logger.debug("No sitemap entries found in sitemap index")
        {:ok, []}

      matches ->
        sitemap_urls =
          matches
          |> Enum.map(fn [url] -> String.trim(url) end)
          |> Enum.filter(&valid_url?/1)

        Logger.debug("Extracted #{length(sitemap_urls)} sitemap URLs from index")
        {:ok, sitemap_urls}
    end
  rescue
    error ->
      Logger.error("Failed to parse sitemap index: #{inspect(error)}")
      {:error, :parse_error}
  end

  defp parse_url_entry(url_block) do
    with {:ok, url} <- extract_tag_content(url_block, "loc"),
         true <- valid_url?(url) do
      %{
        url: url,
        last_modified: extract_tag_content(url_block, "lastmod") |> parse_date(),
        change_frequency: extract_tag_content(url_block, "changefreq") |> extract_value(),
        priority: extract_tag_content(url_block, "priority") |> parse_priority()
      }
    else
      _ -> nil
    end
  end

  defp extract_tag_content(xml_block, tag_name) do
    case Regex.run(~r{<#{tag_name}>(.*?)</#{tag_name}>}s, xml_block, capture: :all_but_first) do
      [content] -> {:ok, String.trim(content)}
      _ -> :error
    end
  end

  defp extract_value({:ok, value}), do: value
  defp extract_value(:error), do: nil

  defp parse_date({:ok, date_string}) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> parse_date_fallback(date_string)
    end
  end

  defp parse_date(:error), do: nil

  defp parse_date_fallback(date_string) do
    # Try parsing as date only (YYYY-MM-DD)
    case Date.from_iso8601(date_string) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_priority({:ok, priority_string}) do
    case Float.parse(priority_string) do
      {priority, _} -> priority
      :error -> nil
    end
  end

  defp parse_priority(:error), do: nil

  defp valid_url?(url) when is_binary(url) do
    String.starts_with?(url, "http://") or String.starts_with?(url, "https://")
  end

  defp valid_url?(_), do: false
end
