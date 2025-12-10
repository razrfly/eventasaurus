defmodule EventasaurusDiscovery.Sources.KinoKrakow.Extractors.MoviePageExtractor do
  @moduledoc """
  Extracts all showtimes from a Kino Krakow movie page.

  Movie pages display a 7-day calendar with all showtimes for that specific film
  across all cinemas. This replaces the day-based scraping approach which had
  race condition issues.

  The page structure is:
  - <th class="date">Polish date string</th> (date header for each day)
  - <tr> rows with:
      <td class="cinema_film"><a href="/cinema-slug">Cinema Name</a></td>
      <td class="showtime"><span class="hour">10:30</span>...</td>
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser

  @doc """
  Extract all showtimes from a movie page HTML.

  Returns list of maps with:
  - cinema_slug: String
  - cinema_name: String
  - datetime: DateTime
  - ticket_url: String (optional)

  ## Example

      iex> html = File.read!("movie_page.html")
      iex> MoviePageExtractor.extract(html, "bugonia", "Bugonia")
      {:ok, [
        %{
          cinema_slug: "pod-baranami",
          cinema_name: "Pod Baranami",
          datetime: ~U[2025-11-19 10:30:00Z],
          ticket_url: "https://www.kino.krakow.pl/..."
        }
      ]}
  """
  def extract(html, movie_slug, movie_title) when is_binary(html) do
    try do
      doc = Floki.parse_document!(html)

      # Find the showtime table
      showtimes =
        doc
        |> Floki.find("table.repert")
        |> Floki.find("tbody")
        |> extract_all_showtimes(movie_slug, movie_title)
        |> List.flatten()
        |> Enum.reject(&is_nil/1)

      {:ok, showtimes}
    rescue
      e ->
        Logger.error("Failed to parse movie page HTML: #{inspect(e)}")
        {:error, :parse_failed}
    end
  end

  # Process all rows in the table, tracking current date as we go
  defp extract_all_showtimes(tbody_elements, movie_slug, movie_title) do
    tbody_elements
    |> Enum.flat_map(fn tbody ->
      tbody
      |> Floki.find("tr")
      |> process_rows(nil, [], movie_slug, movie_title)
    end)
  end

  # Recursively process table rows, accumulating showtimes
  defp process_rows([], _current_date, acc, _movie_slug, _movie_title), do: Enum.reverse(acc)

  defp process_rows([row | rest], current_date, acc, movie_slug, movie_title) do
    cond do
      # Date header row - update current date
      is_date_row?(row) ->
        date = extract_date_from_row(row)
        process_rows(rest, date, acc, movie_slug, movie_title)

      # Cinema/showtime row - extract showtimes for this cinema
      is_cinema_row?(row) ->
        showtimes = extract_showtimes_from_row(row, current_date, movie_slug, movie_title)
        process_rows(rest, current_date, showtimes ++ acc, movie_slug, movie_title)

      # Skip header rows and other non-data rows
      true ->
        process_rows(rest, current_date, acc, movie_slug, movie_title)
    end
  end

  # Check if row is a date header
  defp is_date_row?(row) do
    row
    |> Floki.find("th.date")
    |> length() > 0
  end

  # Check if row has cinema and showtime data
  defp is_cinema_row?(row) do
    row
    |> Floki.find("td.cinema_film")
    |> length() > 0
  end

  # Extract date from date header row
  defp extract_date_from_row(row) do
    row
    |> Floki.find("th.date")
    |> Floki.text()
    |> String.trim()
  end

  # Extract all showtimes from a cinema row
  defp extract_showtimes_from_row(row, date_str, movie_slug, movie_title)
       when not is_nil(date_str) do
    # Get cinema info
    cinema_info = extract_cinema_info(row)

    # Get all showtime cells (<td class="showtime">)
    row
    |> Floki.find("td.showtime")
    |> Enum.flat_map(fn showtime_cell ->
      # Each cell can have multiple <span class="hour"> elements
      showtime_cell
      |> Floki.find("span.hour")
      |> Enum.map(fn hour_span ->
        extract_single_showtime(hour_span, date_str, cinema_info, movie_slug, movie_title)
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_showtimes_from_row(_row, _date, _movie_slug, _movie_title), do: []

  # Extract cinema info from row
  defp extract_cinema_info(row) do
    case row |> Floki.find("td.cinema_film a") |> List.first() do
      {_, attrs, [name]} ->
        href = Enum.find_value(attrs, fn {k, v} -> k == "href" && v end)
        slug = String.trim_leading(href || "", "/")

        %{
          name: String.trim(name),
          slug: slug
        }

      _ ->
        %{name: nil, slug: nil}
    end
  end

  # Extract a single showtime from a <span class="hour"> element
  defp extract_single_showtime(hour_span, date_str, cinema_info, movie_slug, movie_title) do
    # Extract time text (might be nested in <a> tag or direct text)
    time_str =
      hour_span
      |> Floki.text()
      |> String.trim()
      |> String.split("\n")
      |> List.first()
      |> String.trim()

    # Extract ticket URL if present
    ticket_url =
      hour_span
      |> Floki.find("a.buy_ticket")
      |> Floki.attribute("data-showtime-id")
      |> case do
        [showtime_id] -> "https://www.kino.krakow.pl/showtime/#{showtime_id}"
        _ -> nil
      end

    # Parse datetime
    case parse_datetime(date_str, time_str) do
      %DateTime{} = datetime ->
        %{
          movie_slug: movie_slug,
          movie_title: movie_title,
          cinema_slug: cinema_info.slug,
          cinema_name: cinema_info.name,
          datetime: datetime,
          ticket_url: ticket_url
        }

      nil ->
        Logger.warning("Failed to parse datetime: #{date_str} #{time_str}")
        nil
    end
  end

  # Parse datetime using MultilingualDateParser
  # Combines Polish date string with time string
  defp parse_datetime(date_str, time_str)
       when is_binary(date_str) and is_binary(time_str) do
    # Get current year (movie pages don't include year in date headers)
    current_year = Date.utc_today().year

    # Combine date, year, and time into a single string for MultilingualDateParser
    # E.g., "wtorek, 18 listopada" + "2025" + "15:30" -> "wtorek, 18 listopada 2025 15:30"
    combined_text = "#{date_str} #{current_year} #{time_str}"

    case MultilingualDateParser.extract_and_parse(combined_text,
           languages: [:polish],
           timezone: "Europe/Warsaw"
         ) do
      {:ok, %{starts_at: datetime}} ->
        datetime

      {:error, reason} ->
        Logger.debug("MultilingualDateParser failed for '#{combined_text}': #{inspect(reason)}")
        nil
    end
  end

  defp parse_datetime(_date_str, _time_str), do: nil
end
