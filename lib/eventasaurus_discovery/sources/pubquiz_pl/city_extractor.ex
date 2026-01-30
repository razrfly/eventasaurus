defmodule EventasaurusDiscovery.Sources.Pubquiz.CityExtractor do
  @moduledoc """
  Extracts city URLs from PubQuiz.pl index page.

  Ported from trivia_advisor Extractor module.
  """

  @doc """
  Extracts list of city URLs from the main index page.

  ## Examples

      iex> html = "<a href='https://pubquiz.pl/bilety/warszawa/' class='category-pill'>Warszawa</a>"
      iex> CityExtractor.extract_cities(html)
      ["https://pubquiz.pl/bilety/warszawa/"]
  """
  def extract_cities(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".shop-page-categories .category-pill")
    |> Enum.map(&extract_city_url/1)
    |> Enum.reject(&is_nil/1)
    # Filter out the "Liga" link which is not a city
    |> Enum.reject(&String.contains?(&1, "liga"))
  end

  defp extract_city_url({"a", attrs, _children}) do
    Enum.find_value(attrs, fn
      {"href", url} -> url
      _ -> nil
    end)
  end

  defp extract_city_url(_), do: nil
end
