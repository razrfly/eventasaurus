# Test script for TMDB Alternative Titles matching
# Run with: mix run test_alternative_titles.exs
#
# This script tests the alternative titles approach on all 7 failed Cinema City movies
# to validate that TMDB's alternative titles API can solve the matching problem.

defmodule AlternativeTitlesTest do
  @moduledoc """
  Test TMDB Alternative Titles API on failed Cinema City movies.

  Approach:
  1. For each failed movie, extract original title (if English film)
  2. Search TMDB for candidates
  3. For top 5 candidates, fetch alternative titles
  4. Check if Cinema City's Polish title matches any alternative title
  5. Report success/failure and calculate success rate
  """

  require Logger

  # The 7 unique failed movies from Cinema City
  @failed_movies [
    %{
      film_id: "7441s2r",
      polish_title: "Wicked: Na dobre",
      release_year: 2025,
      runtime: 137,
      original_language: "en"
    },
    %{
      film_id: "7381d2r",
      polish_title: "Zwierzogród 2",
      release_year: 2025,
      runtime: 108,
      original_language: "en"
    },
    %{
      film_id: "7760d2r",
      polish_title: "Psi patrol. Pieski ratują święta",
      release_year: 2025,
      runtime: 68,
      original_language: nil
    },
    %{
      film_id: "7671o2r",
      polish_title: "Uwierz w Mikołaja 2",
      release_year: 2025,
      runtime: 98,
      original_language: "pl"
    },
    %{
      film_id: "7742s2r",
      polish_title: "Eternity. Wybieram ciebie",
      release_year: 2025,
      runtime: 112,
      original_language: "en"
    },
    %{
      film_id: "7622d2r",
      polish_title: "Koszmarek",
      release_year: 2025,
      runtime: 90,
      original_language: nil
    },
    %{
      film_id: "7793s2r",
      polish_title: "Bez przebaczenia",
      release_year: 2024,
      runtime: 105,
      original_language: "en"
    }
  ]

  def run_all_tests do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TMDB Alternative Titles Test")
    IO.puts("Testing #{length(@failed_movies)} failed Cinema City movies")
    IO.puts(String.duplicate("=", 80) <> "\n")

    results =
      Enum.map(@failed_movies, fn movie ->
        test_movie(movie)
      end)

    # Calculate success rate
    successful = Enum.count(results, fn {status, _} -> status == :matched end)
    total = length(results)
    success_rate = Float.round(successful / total * 100, 1)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("RESULTS SUMMARY")
    IO.puts(String.duplicate("=", 80))
    IO.puts("✅ Matched: #{successful}/#{total} (#{success_rate}%)")
    IO.puts("❌ Not Matched: #{total - successful}/#{total}")

    cond do
      successful == total ->
        IO.puts("\n🎉 SUCCESS! All movies matched using alternative titles!")
      successful > 0 ->
        IO.puts("\n⚠️  Partial success. Alternative titles help but don't solve everything.")
      true ->
        IO.puts("\n❌ FAILURE! Alternative titles approach doesn't work.")
    end

    IO.puts(String.duplicate("=", 80) <> "\n")
  end

  defp test_movie(movie) do
    IO.puts("\n#{String.duplicate("-", 80)}")
    IO.puts("Testing: #{movie.polish_title}")
    IO.puts("  Film ID: #{movie.film_id}")
    IO.puts("  Year: #{movie.release_year}, Runtime: #{movie.runtime} min")
    IO.puts("  Original Language: #{inspect(movie.original_language)}")
    IO.puts(String.duplicate("-", 80))

    # Step 1: Extract original title if English film
    extracted_title = extract_original_title(movie.polish_title, movie.original_language)

    if extracted_title do
      IO.puts("  Extracted title: \"#{extracted_title}\"")
    else
      IO.puts("  No extraction (Polish-only or no separator)")
    end

    # Step 2: Search TMDB for candidates
    search_title = extracted_title || movie.polish_title
    IO.puts("  Searching TMDB for: \"#{search_title}\"")

    case search_tmdb(search_title, movie.release_year) do
      {:ok, [_ | _] = candidates} ->
        IO.puts("  Found #{length(candidates)} candidates, checking top 5...")

        # Step 3: Check alternative titles for top 5 candidates
        top_candidates = Enum.take(candidates, 5)

        result =
          Enum.find_value(top_candidates, fn candidate ->
            check_alternative_titles(candidate, movie.polish_title, movie.release_year)
          end)

        case result do
          {:matched, tmdb_id, tmdb_title, alt_title} ->
            IO.puts("\n✅ MATCHED!")
            IO.puts("  TMDB ID: #{tmdb_id}")
            IO.puts("  TMDB Title: #{tmdb_title}")
            IO.puts("  Alternative Title: #{alt_title}")
            {:matched, tmdb_id}

          nil ->
            IO.puts("\n❌ NO MATCH")
            IO.puts("  None of the top 5 candidates have matching Polish alternative titles")
            {:no_match, nil}
        end

      {:ok, []} ->
        IO.puts("  ❌ NO RESULTS from TMDB search")
        {:no_match, nil}

      {:error, reason} ->
        IO.puts("  ❌ SEARCH ERROR: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Extract original English title from mixed-language titles
  defp extract_original_title(polish_title, "en") when is_binary(polish_title) do
    separators = [". ", ": ", " - ", " – ", " — "]

    Enum.reduce_while(separators, nil, fn separator, _acc ->
      case String.split(polish_title, separator, parts: 2) do
        [original_part, _polish_part] ->
          {:halt, String.trim(original_part)}

        _ ->
          {:cont, nil}
      end
    end)
  end

  defp extract_original_title(_polish_title, _language), do: nil

  # Search TMDB using the service
  defp search_tmdb(query, year) do
    api_key = System.get_env("TMDB_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      url = "https://api.themoviedb.org/3/search/multi?api_key=#{URI.encode(api_key)}&query=#{URI.encode(query)}&page=1"

      case HTTPoison.get(url, [{"Accept", "application/json"}]) do
        {:ok, response} when response.__struct__ == HTTPoison.Response and response.status_code == 200 ->
          case Jason.decode(response.body) do
            {:ok, %{"results" => results}} ->
              movies =
                results
                |> Enum.filter(fn result -> result["media_type"] == "movie" end)
                |> Enum.map(fn movie ->
                  %{
                    id: movie["id"],
                    title: movie["title"],
                    original_title: movie["original_title"],
                    release_date: movie["release_date"],
                    popularity: movie["popularity"]
                  }
                end)
                |> Enum.filter(fn movie ->
                  # Filter by year if available (±1 year tolerance)
                  case {get_year_from_date(movie.release_date), year} do
                    {movie_year, search_year} when is_integer(movie_year) and is_integer(search_year) ->
                      abs(movie_year - search_year) <= 1

                    _ ->
                      true
                  end
                end)

              {:ok, movies}

            {:error, _} ->
              {:error, :decode_error}
          end

        {:ok, response} ->
          {:error, {:http_error, response.status_code}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Check if candidate has matching Polish alternative title
  defp check_alternative_titles(candidate, polish_title, _year) do
    IO.puts("    Checking TMDB #{candidate.id} (#{candidate.title})...")

    case fetch_alternative_titles(candidate.id) do
      {:ok, alternative_titles} ->
        # Normalize titles for comparison (case-insensitive, trimmed)
        normalized_polish = normalize_title(polish_title)

        matching_title =
          Enum.find(alternative_titles, fn alt ->
            normalize_title(alt.title) == normalized_polish
          end)

        case matching_title do
          %{title: alt_title} ->
            IO.puts("      ✓ Match found: \"#{alt_title}\"")
            {:matched, candidate.id, candidate.title, alt_title}

          nil ->
            IO.puts("      ✗ No matching Polish title")
            nil
        end

      {:error, reason} ->
        IO.puts("      ✗ Error fetching alternatives: #{inspect(reason)}")
        nil
    end
  end

  # Fetch alternative titles from TMDB
  defp fetch_alternative_titles(movie_id) do
    api_key = System.get_env("TMDB_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      url = "https://api.themoviedb.org/3/movie/#{movie_id}/alternative_titles?api_key=#{URI.encode(api_key)}&country=PL"

      case HTTPoison.get(url, [{"Accept", "application/json"}]) do
        {:ok, response} when response.__struct__ == HTTPoison.Response and response.status_code == 200 ->
          case Jason.decode(response.body) do
            {:ok, %{"titles" => titles}} ->
              polish_titles =
                titles
                |> Enum.filter(fn title -> title["iso_3166_1"] == "PL" end)
                |> Enum.map(fn title ->
                  %{
                    title: title["title"],
                    type: title["type"],
                    iso: title["iso_3166_1"]
                  }
                end)

              {:ok, polish_titles}

            {:error, _} ->
              {:error, :decode_error}
          end

        {:ok, response} ->
          {:error, {:http_error, response.status_code}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Normalize title for comparison
  defp normalize_title(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.trim()
  end

  defp normalize_title(_), do: ""

  # Extract year from TMDB release date
  defp get_year_from_date(nil), do: nil

  defp get_year_from_date(date_string) when is_binary(date_string) do
    case String.split(date_string, "-") do
      [year_str | _] ->
        case Integer.parse(year_str) do
          {year, _} -> year
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp get_year_from_date(_), do: nil
end

# Run the tests
AlternativeTitlesTest.run_all_tests()
