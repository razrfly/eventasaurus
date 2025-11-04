defmodule EventasaurusDiscovery.Sources.KinoKrakow.Extractors.ShowtimeExtractor do
  @moduledoc """
  Extracts movie showtimes from Kino Krakow cinema program page.

  Parses the /cinema_program/by_movie page to extract:
  - Movie link/slug
  - Cinema link/slug
  - Showtime datetime
  - Ticket purchase URL
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser

  @doc """
  Extract all showtimes from HTML document.

  Returns list of maps with:
  - movie_slug: String
  - movie_title: String (Polish)
  - cinema_slug: String
  - cinema_name: String
  - datetime: DateTime
  - ticket_url: String (optional)

  The page structure is:
  - <th class="date">czwartek, 2 października</th> (date header)
  - <th><a class="preview-link film" href="/film/XXX.html">Title</a></th> (film header)
  - <tr> rows with:
      <td class="cinema_film"><a href="/cinema-slug">Cinema</a></td>
      <td class="hours"><span class="hour"><a>HH:MM</a></span></td>
  """
  def extract(html, base_date \\ Date.utc_today()) when is_binary(html) do
    doc = Floki.parse_document!(html)

    # Find the showtime table
    doc
    |> Floki.find("table.repert")
    |> Floki.find("tbody")
    |> extract_all_showtimes(base_date)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Process all rows in the table, tracking current film and date
  defp extract_all_showtimes(tbody_elements, _base_date) do
    tbody_elements
    |> Enum.flat_map(fn tbody ->
      tbody
      |> Floki.find("tr")
      |> process_rows(nil, nil, [])
    end)
  end

  # Recursively process table rows, accumulating showtimes
  defp process_rows([], _current_film, _current_date, acc), do: Enum.reverse(acc)

  defp process_rows([row | rest], current_film, current_date, acc) do
    cond do
      # Date header row
      is_date_row?(row) ->
        date = extract_date_from_row(row)
        process_rows(rest, current_film, date, acc)

      # Film header row
      is_film_row?(row) ->
        film = extract_film_from_row(row)
        process_rows(rest, film, current_date, acc)

      # Cinema/showtime row
      is_showtime_row?(row) ->
        showtimes = extract_showtimes_from_row(row, current_film, current_date)
        process_rows(rest, current_film, current_date, showtimes ++ acc)

      # Skip other rows
      true ->
        process_rows(rest, current_film, current_date, acc)
    end
  end

  # Check if row is a date header
  defp is_date_row?(row) do
    row
    |> Floki.find("th.date")
    |> length() > 0
  end

  # Check if row is a film header
  defp is_film_row?(row) do
    row
    |> Floki.find("a.preview-link.film")
    |> length() > 0
  end

  # Check if row has cinema and showtime data
  defp is_showtime_row?(row) do
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

  # Extract film info from film header row
  defp extract_film_from_row(row) do
    link =
      row
      |> Floki.find("a.preview-link.film")
      |> List.first()

    case link do
      {_, attrs, [title]} ->
        href = Enum.find_value(attrs, fn {k, v} -> k == "href" && v end)
        slug = extract_slug_from_url(href)

        %{
          slug: slug,
          title: String.trim(title)
        }

      _ ->
        nil
    end
  end

  # Extract all showtimes from a cinema row
  defp extract_showtimes_from_row(row, film, date_str)
       when not is_nil(film) and not is_nil(date_str) do
    # Get cinema info
    cinema_link =
      row
      |> Floki.find("td.cinema_film a")
      |> List.first()

    cinema_info = extract_cinema_info(cinema_link)

    # Get all time slots from this row
    row
    |> Floki.find("span.hour")
    |> Enum.map(fn hour_span ->
      extract_single_showtime(hour_span, film, cinema_info, date_str)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_showtimes_from_row(_row, _film, _date), do: []

  # Extract a single showtime from a <span class="hour"> element
  defp extract_single_showtime(hour_span, film, cinema_info, date_str) do
    # Extract time from link text
    time_str =
      hour_span
      |> Floki.find("a")
      |> Enum.find(fn
        {_, attrs, _} ->
          href = Enum.find_value(attrs, fn {k, v} -> k == "href" && v end)
          String.contains?(href || "", "/by_cinema/")

        _ ->
          false
      end)
      |> case do
        {_, _, [time]} -> String.trim(time)
        _ -> nil
      end

    # Extract ticket URL if present
    ticket_url =
      hour_span
      |> Floki.find("a.buy_ticket")
      |> Floki.attribute("href")
      |> List.first()

    # Build datetime using MultilingualDateParser
    case parse_datetime(date_str, time_str) do
      %DateTime{} = datetime ->
        %{
          movie_slug: film.slug,
          movie_title: film.title,
          cinema_slug: cinema_info.slug,
          cinema_name: cinema_info.name,
          datetime: datetime,
          ticket_url: ticket_url && ensure_absolute_url(ticket_url)
        }

      nil ->
        Logger.warning("Failed to parse datetime: #{date_str} #{time_str}")
        nil
    end
  end

  # Parse datetime using MultilingualDateParser (replaces old KinoKrakow.DateParser)
  # Combines Polish date string and time string, delegates to shared parser
  defp parse_datetime(date_str, time_str) when is_binary(date_str) and is_binary(time_str) do
    # Combine date and time into a single string for MultilingualDateParser
    # E.g., "czwartek, 2 października" + "15:30" -> "czwartek, 2 października 15:30"
    combined_text = "#{date_str} #{time_str}"

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

  # Extract cinema info from link element
  defp extract_cinema_info({_, attrs, [name]}) do
    href = Enum.find_value(attrs, fn {k, v} -> k == "href" && v end)
    slug = String.trim_leading(href || "", "/")

    %{
      name: String.trim(name),
      slug: slug
    }
  end

  defp extract_cinema_info(_), do: %{name: nil, slug: nil}

  # Extract slug from film URL
  defp extract_slug_from_url(url) when is_binary(url) do
    case Regex.run(~r/\/film\/([^.]+)\.html/, url) do
      [_, slug] -> slug
      _ -> nil
    end
  end

  defp extract_slug_from_url(_), do: nil

  # Ensure URL is absolute
  defp ensure_absolute_url("http" <> _ = url), do: url

  defp ensure_absolute_url(url) do
    "https://www.kino.krakow.pl#{url}"
  end
end
