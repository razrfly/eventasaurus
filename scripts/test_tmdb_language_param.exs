# Test TMDB language parameter to see if it returns Polish titles
# Run with: mix run test_tmdb_language_param.exs

defmodule TmdbLanguageTest do
  @moduledoc """
  Test TMDB API language parameter to understand how it affects title fields.
  """

  def run_tests do
    api_key = System.get_env("TMDB_API_KEY")

    if is_nil(api_key) or api_key == "" do
      IO.puts("❌ TMDB_API_KEY not set in environment")
      System.halt(1)
    end

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TMDB Language Parameter Investigation")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Test 1: Search without language parameter
    IO.puts("TEST 1: Search 'Wicked' WITHOUT language parameter")
    IO.puts(String.duplicate("-", 80))
    test_search(api_key, "Wicked", nil)

    IO.puts("\n" <> String.duplicate("=", 80) <> "\n")

    # Test 2: Search with Polish language parameter
    IO.puts("TEST 2: Search 'Wicked' WITH language=pl-PL")
    IO.puts(String.duplicate("-", 80))
    test_search(api_key, "Wicked", "pl-PL")

    IO.puts("\n" <> String.duplicate("=", 80) <> "\n")

    # Test 3: Get movie details without language
    IO.puts("TEST 3: Get movie 967941 (Wicked: For Good) WITHOUT language")
    IO.puts(String.duplicate("-", 80))
    test_movie_details(api_key, 967941, nil)

    IO.puts("\n" <> String.duplicate("=", 80) <> "\n")

    # Test 4: Get movie details with Polish language
    IO.puts("TEST 4: Get movie 967941 (Wicked: For Good) WITH language=pl-PL")
    IO.puts(String.duplicate("-", 80))
    test_movie_details(api_key, 967941, "pl-PL")

    IO.puts("\n" <> String.duplicate("=", 80) <> "\n")

    # Test 5: Alternative titles endpoint
    IO.puts("TEST 5: Get alternative titles for movie 967941")
    IO.puts(String.duplicate("-", 80))
    test_alternative_titles(api_key, 967941)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Tests Complete")
    IO.puts(String.duplicate("=", 80) <> "\n")
  end

  defp test_search(api_key, query, language) do
    url_base = "https://api.themoviedb.org/3/search/movie?api_key=#{URI.encode(api_key)}&query=#{URI.encode(query)}"

    url = if language do
      url_base <> "&language=#{language}"
    else
      url_base
    end

    IO.puts("  URL: #{url}")
    IO.puts("")

    case HTTPoison.get(url, [{"Accept", "application/json"}]) do
      {:ok, response} when response.__struct__ == HTTPoison.Response and response.status_code == 200 ->
        case Jason.decode(response.body) do
          {:ok, %{"results" => results}} when is_list(results) and length(results) > 0 ->
            first = List.first(results)
            IO.puts("  ✅ Found #{length(results)} results")
            IO.puts("  First result:")
            IO.puts("    ID: #{first["id"]}")
            IO.puts("    title: \"#{first["title"]}\"")
            IO.puts("    original_title: \"#{first["original_title"]}\"")
            IO.puts("    release_date: #{first["release_date"]}")

          {:ok, %{"results" => []}} ->
            IO.puts("  ⚠️  No results found")

          {:ok, data} ->
            IO.puts("  ❌ Unexpected response structure")
            IO.inspect(data, label: "Response", pretty: true)

          {:error, reason} ->
            IO.puts("  ❌ JSON decode error: #{inspect(reason)}")
        end

      {:ok, response} ->
        IO.puts("  ❌ HTTP error: #{response.status_code}")
        IO.puts("  Response: #{response.body}")

      {:error, error} ->
        IO.puts("  ❌ Request error: #{inspect(error)}")
    end
  end

  defp test_movie_details(api_key, movie_id, language) do
    url_base = "https://api.themoviedb.org/3/movie/#{movie_id}?api_key=#{URI.encode(api_key)}"

    url = if language do
      url_base <> "&language=#{language}"
    else
      url_base
    end

    IO.puts("  URL: #{url}")
    IO.puts("")

    case HTTPoison.get(url, [{"Accept", "application/json"}]) do
      {:ok, response} when response.__struct__ == HTTPoison.Response and response.status_code == 200 ->
        case Jason.decode(response.body) do
          {:ok, movie} when is_map(movie) ->
            IO.puts("  ✅ Got movie details:")
            IO.puts("    ID: #{movie["id"]}")
            IO.puts("    title: \"#{movie["title"]}\"")
            IO.puts("    original_title: \"#{movie["original_title"]}\"")
            IO.puts("    release_date: #{movie["release_date"]}")
            IO.puts("    original_language: #{movie["original_language"]}")

          {:error, reason} ->
            IO.puts("  ❌ JSON decode error: #{inspect(reason)}")
        end

      {:ok, response} ->
        IO.puts("  ❌ HTTP error: #{response.status_code}")
        IO.puts("  Response: #{response.body}")

      {:error, error} ->
        IO.puts("  ❌ Request error: #{inspect(error)}")
    end
  end

  defp test_alternative_titles(api_key, movie_id) do
    url = "https://api.themoviedb.org/3/movie/#{movie_id}/alternative_titles?api_key=#{URI.encode(api_key)}"

    IO.puts("  URL: #{url}")
    IO.puts("")

    case HTTPoison.get(url, [{"Accept", "application/json"}]) do
      {:ok, response} when response.__struct__ == HTTPoison.Response and response.status_code == 200 ->
        case Jason.decode(response.body) do
          {:ok, %{"titles" => titles}} when is_list(titles) ->
            IO.puts("  ✅ Found #{length(titles)} alternative titles:")

            # Filter to just Polish titles
            polish_titles = Enum.filter(titles, fn t -> t["iso_3166_1"] == "PL" end)

            if Enum.empty?(polish_titles) do
              IO.puts("    ⚠️  No Polish (PL) titles found")
              IO.puts("    Available countries: #{titles |> Enum.map(& &1["iso_3166_1"]) |> Enum.uniq() |> Enum.join(", ")}")
            else
              IO.puts("    Polish titles:")
              Enum.each(polish_titles, fn t ->
                IO.puts("      - \"#{t["title"]}\" (type: #{t["type"]})")
              end)
            end

          {:error, reason} ->
            IO.puts("  ❌ JSON decode error: #{inspect(reason)}")
        end

      {:ok, response} ->
        IO.puts("  ❌ HTTP error: #{response.status_code}")

      {:error, error} ->
        IO.puts("  ❌ Request error: #{inspect(error)}")
    end
  end
end

# Run the tests
TmdbLanguageTest.run_tests()
