defmodule EventasaurusDiscovery.Sources.Repertuary.Extractors.MovieListExtractor do
  @moduledoc """
  Extracts the list of movies from Repertuary cinema program page.

  The /cinema_program/by_movie page contains links to all movies currently
  showing, which we use to determine which MoviePageJobs to schedule.

  Example HTML:
  <a class="preview-link film" href="/film/bugonia.html">Bugonia</a>
  """

  require Logger

  @doc """
  Extract all movies from cinema program HTML.

  Returns list of maps with:
  - movie_slug: String
  - movie_title: String

  ## Example

      iex> html = File.read!("cinema_program.html")
      iex> MovieListExtractor.extract(html)
      {:ok, [
        %{movie_slug: "bugonia", movie_title: "Bugonia"},
        %{movie_slug: "gladiator-ii", movie_title: "Gladiator II"}
      ]}
  """
  def extract(html) when is_binary(html) do
    try do
      doc = Floki.parse_document!(html)

      movies =
        doc
        |> Floki.find("a.preview-link.film")
        |> Enum.map(&extract_movie/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.movie_slug)

      {:ok, movies}
    rescue
      e ->
        Logger.error("Failed to parse cinema program HTML: #{inspect(e)}")
        {:error, :parse_failed}
    end
  end

  # Extract movie info from link element
  defp extract_movie({_tag, attrs, children}) do
    with href when is_binary(href) <- get_attr(attrs, "href"),
         slug when is_binary(slug) <- extract_slug_from_url(href),
         title when is_binary(title) <- extract_title(children) do
      %{
        movie_slug: slug,
        movie_title: title
      }
    else
      _ -> nil
    end
  end

  defp extract_movie(_), do: nil

  # Get attribute value from attribute list
  defp get_attr(attrs, key) do
    Enum.find_value(attrs, fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  # Extract slug from film URL and strip UUID suffix if present
  # Cinema program page may include UUID suffixes in links:
  # /film/dom-dobry-c74ad00c-2f8e-4fc6-a726-484848a8f041.html
  # But actual movie detail pages use clean slugs:
  # /film/dom-dobry.html
  defp extract_slug_from_url(url) when is_binary(url) do
    case Regex.run(~r/\/film\/([^.]+)\.html/, url) do
      [_, slug] ->
        # Strip UUID suffix: -[8hex]-[4hex]-[4hex]-[4hex]-[12hex]
        # This ensures we can fetch the correct movie detail page
        String.replace(
          slug,
          ~r/-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
          ""
        )

      _ ->
        nil
    end
  end

  defp extract_slug_from_url(_), do: nil

  # Extract title from children nodes
  defp extract_title([title]) when is_binary(title), do: String.trim(title)
  defp extract_title(_), do: nil
end
