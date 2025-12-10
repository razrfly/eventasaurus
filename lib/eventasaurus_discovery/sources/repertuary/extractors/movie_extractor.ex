defmodule EventasaurusDiscovery.Sources.KinoKrakow.Extractors.MovieExtractor do
  @moduledoc """
  Extracts movie metadata from Kino Krakow movie detail pages.

  Extracts:
  - Original title (for TMDB matching)
  - Polish title
  - Director
  - Release year
  - Country of origin
  - Runtime (minutes)
  - Cast
  - Genre
  """

  require Logger

  @doc """
  Extract movie metadata from HTML document.

  Returns map with:
  - original_title: String (primary for TMDB matching)
  - polish_title: String
  - director: String
  - year: Integer
  - country: String
  - runtime: Integer (minutes)
  - cast: List of strings
  - genre: String
  """
  def extract(html) when is_binary(html) do
    doc = Floki.parse_document!(html)

    %{
      original_title: extract_original_title(doc),
      polish_title: extract_polish_title(doc),
      director: extract_director(doc),
      year: extract_year(doc),
      country: extract_country(doc),
      runtime: extract_runtime(doc),
      cast: extract_cast(doc),
      genre: extract_genre(doc)
    }
  end

  # Extract the original (international) title
  # This is critical for TMDB matching
  # Look for "Tytuł oryginalny:" followed by the title text
  defp extract_original_title(doc) do
    # Try to find the original title in the metadata section
    title =
      doc
      |> Floki.find("strong")
      |> Enum.find_value(fn element ->
        text = Floki.text(element) |> String.trim()

        if text =~ ~r/Tytuł oryginalny:/i do
          # Get the next text node after this <strong> tag
          case element do
            {_, _, _} ->
              # Find parent element and extract text after the strong tag
              parent = Floki.find(doc, "strong:fl-contains('Tytuł oryginalny')")

              case parent do
                [] ->
                  nil

                _ ->
                  # Get the raw HTML around this section
                  html = Floki.raw_html(doc)

                  case Regex.run(
                         ~r/Tytuł oryginalny:\s*<\/strong>\s*([^<\n]+)/,
                         html,
                         capture: :all_but_first
                       ) do
                    [title_text] -> String.trim(title_text)
                    _ -> nil
                  end
              end

            _ ->
              nil
          end
        else
          nil
        end
      end)

    # Fallback to h1 if no original title found (might be Polish-only film)
    title || extract_polish_title(doc)
  end

  # Extract the Polish title from h1
  defp extract_polish_title(doc) do
    doc
    |> Floki.find("h1")
    |> List.first()
    |> case do
      nil -> nil
      element -> Floki.text(element) |> String.trim()
    end
  end

  # Extract director name
  # Look for "Reżyseria:" in HTML and extract the linked name
  defp extract_director(doc) do
    html = Floki.raw_html(doc)

    case Regex.run(
           ~r/Reżyseria:\s*<\/strong>\s*<a[^>]*>([^<]+)<\/a>/,
           html,
           capture: :all_but_first
         ) do
      [director] -> String.trim(director)
      _ -> nil
    end
  end

  # Extract release year
  # Kino Krakow has two formats:
  # 1. Old movies: "Produkcja: Country, YEAR" (e.g., "USA, 1995")
  # 2. New movies: "Premiera: DD month YYYY" (e.g., "10 października 2025")
  defp extract_year(doc) do
    html = Floki.raw_html(doc)

    # Try format 1: Produkcja with year
    case Regex.run(
           ~r/Produkcja:\s*<\/strong>\s*[^,]+,\s*(\d{4})/,
           html,
           capture: :all_but_first
         ) do
      [year] ->
        String.to_integer(year)

      _ ->
        # Try format 2: Premiera (premiere date)
        # Format: <strong>\n Premiera:\n </strong>\n DD month YYYY
        # Note: \w doesn't match Polish chars, use .+? for month name
        case Regex.run(
               ~r/Premiera:.*?(\d+)\s+.+?\s+(\d{4})/s,
               html,
               capture: :all_but_first
             ) do
          [_day, year] -> String.to_integer(year)
          _ -> nil
        end
    end
  end

  # Extract country of origin
  # Look for "Produkcja:" section which contains country like "USA / Wielka Brytania"
  defp extract_country(doc) do
    html = Floki.raw_html(doc)

    case Regex.run(
           ~r/Produkcja:\s*<\/strong>\s*([^,<]+)/,
           html,
           capture: :all_but_first
         ) do
      [country] -> String.trim(country)
      _ -> nil
    end
  end

  # Extract runtime in minutes
  # Look for "Czas trwania:" followed by minutes like "169 min."
  defp extract_runtime(doc) do
    html = Floki.raw_html(doc)

    case Regex.run(
           ~r/Czas trwania:\s*<\/strong>\s*(\d+)/,
           html,
           capture: :all_but_first
         ) do
      [minutes] -> String.to_integer(minutes)
      _ -> nil
    end
  end

  # Extract cast members
  # Look for "Obsada:" section with linked actor names
  defp extract_cast(doc) do
    html = Floki.raw_html(doc)

    case Regex.run(
           ~r/Obsada:\s*<\/strong>\s*(.+?)(?:<br|<\/div)/s,
           html,
           capture: :all_but_first
         ) do
      [cast_html] ->
        # Extract all <a> tag text content from the cast HTML
        cast_html
        |> Floki.parse_fragment!()
        |> Floki.find("a")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> case do
          [] -> nil
          cast -> cast
        end

      _ ->
        nil
    end
  end

  # Extract genre
  # Look for "Gatunek:" section with linked genre names
  defp extract_genre(doc) do
    html = Floki.raw_html(doc)

    case Regex.run(
           ~r/Gatunek:\s*<\/strong>\s*(.+?)(?:<br|<\/div|<strong)/s,
           html,
           capture: :all_but_first
         ) do
      [genre_html] ->
        # Extract all <a> tag text content from the genre HTML
        genres =
          genre_html
          |> Floki.parse_fragment!()
          |> Floki.find("a")
          |> Enum.map(&Floki.text/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        case genres do
          [] -> nil
          [single] -> single
          multiple -> Enum.join(multiple, " / ")
        end

      _ ->
        nil
    end
  end
end
