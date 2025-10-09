defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Extractors.VenueExtractor do
  @moduledoc """
  Extracts venue data from Geeks Who Drink map API HTML response.

  The map API returns HTML blocks, each containing a venue with data
  embedded in data attributes and child elements. Each venue block
  has an ID like "quizBlock-12345" where 12345 is the venue_id.

  ## Data Fields Extracted
  - venue_id: From id="quizBlock-{id}" attribute
  - title: From <h2> text (HTML entities encoded)
  - address: From data-address attribute
  - latitude: From data-lat attribute (Float)
  - longitude: From data-lon attribute (Float)
  - brand: From .quizBlock__brand text
  - time_text: From <time> text (e.g., "Tuesdays at 7:00 pm")
  - logo_url: From .quizBlock__logo img[src]
  """

  require Logger

  @doc """
  Extracts venue data from a venue block HTML fragment.

  ## Parameters
  - `block` - HTML string or Floki parsed document of a single venue block

  ## Returns
  - `{:ok, venue_data}` - Successfully extracted all required fields
  - `{:error, :missing_required_field}` - One or more required fields missing
  - `{:error, reason}` - Parsing error
  """
  def extract_venue_data(block) when is_binary(block) do
    case Floki.parse_fragment(block) do
      {:ok, document} ->
        extract_venue_data(document)

      {:error, reason} ->
        Logger.warning("❌ Error parsing venue block HTML: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def extract_venue_data(document) when is_list(document) do
    fields = [
      {:venue_id, extract_venue_id(document)},
      {:url, extract_url(document)},
      {:title, extract_title(document)},
      {:address, extract_address(document)},
      {:latitude, extract_lat(document)},
      {:longitude, extract_lon(document)},
      {:brand, extract_brand(document)},
      {:time_text, extract_time_text(document)},
      {:logo_url, extract_logo_url(document)}
    ]

    # Check for missing required fields (url and brand are optional)
    missing_fields =
      Enum.filter(fields, fn {name, value} ->
        is_nil(value) and name not in [:url, :brand, :logo_url]
      end)

    if Enum.empty?(missing_fields) do
      fields_map = Map.new(fields)
      venue_id = fields_map.venue_id

      # Ensure we have a valid URL - if not, construct one from the venue ID
      url =
        if is_nil(fields_map.url) or fields_map.url == "" do
          "https://www.geekswhodrink.com/venues/#{venue_id}/"
        else
          fields_map.url
        end

      {:ok,
       %{
         venue_id: venue_id,
         url: url,
         title: fields_map.title,
         address: fields_map.address,
         latitude: fields_map.latitude,
         longitude: fields_map.longitude,
         brand: fields_map.brand || "Geeks Who Drink",
         time_text: fields_map.time_text,
         logo_url: fields_map.logo_url,
         source_url: url
       }}
    else
      missing = missing_fields |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")
      Logger.warning("⚠️  Missing required fields: #{missing}")
      {:error, :missing_required_field}
    end
  end

  # Private extraction functions

  defp extract_venue_id(document) do
    document
    |> Floki.attribute("id")
    |> List.first()
    |> case do
      nil -> nil
      id -> String.replace(id, "quizBlock-", "")
    end
  end

  defp extract_url(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_title(document) do
    document
    |> Floki.find("h2")
    |> Floki.text()
    |> case do
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_address(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("data-address")
    |> List.first()
  end

  defp extract_lat(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("data-lat")
    |> List.first()
    |> parse_float()
  end

  defp extract_lon(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("data-lon")
    |> List.first()
    |> parse_float()
  end

  defp extract_brand(document) do
    document
    |> Floki.find(".quizBlock__brand")
    |> Floki.text()
    |> case do
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_time_text(document) do
    document
    |> Floki.find("time")
    |> Floki.text()
    |> case do
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_logo_url(document) do
    document
    |> Floki.find(".quizBlock__logo")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp parse_float(nil), do: nil

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> nil
    end
  end
end
