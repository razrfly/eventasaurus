defmodule EventasaurusDiscovery.Sources.PubquizPl.VenueExtractor do
  @moduledoc """
  Extracts venue information from PubQuiz.pl city pages.

  Ported from trivia_advisor Extractor module.
  """

  @doc """
  Extracts list of venues from a city page.

  Returns a list of venue maps with name, url, and image_url.
  """
  def extract_venues(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".e-n-tabs-content .product-category")
    |> Enum.map(&extract_venue_card/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.name)
  end

  defp extract_venue_card(venue_element) do
    %{
      name: extract_venue_name(venue_element),
      url: extract_venue_url(venue_element),
      image_url: extract_venue_image(venue_element)
    }
  end

  defp extract_venue_name(venue_element) do
    venue_element
    |> Floki.find(".woocommerce-loop-category__title")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_venue_url(venue_element) do
    venue_element
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_venue_image(venue_element) do
    venue_element
    |> Floki.find("img")
    |> Floki.attribute("src")
    |> List.first()
  end
end
