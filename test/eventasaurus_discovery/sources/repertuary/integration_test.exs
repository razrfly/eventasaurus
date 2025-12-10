defmodule EventasaurusDiscovery.Sources.Repertuary.IntegrationTest do
  @moduledoc """
  Integration tests for Kino Krakow scraper against live website.

  These tests are excluded by default since they make real HTTP requests.
  Run with: mix test --include integration
  """

  use ExUnit.Case, async: false

  alias EventasaurusDiscovery.Sources.Repertuary.{
    Config,
    Extractors.ShowtimeExtractor,
    Extractors.MovieExtractor,
    Extractors.CinemaExtractor
  }

  @moduletag :integration
  @moduletag timeout: 30_000

  describe "Live website scraping" do
    # Remove this to enable
    @tag :skip
    test "fetches and parses showtimes from live website" do
      url = Config.showtimes_url()
      headers = [{"User-Agent", Config.user_agent()}]

      assert {:ok, %{status_code: 200, body: html}} =
               HTTPoison.get(url, headers, timeout: Config.timeout())

      assert is_binary(html)
      assert String.contains?(html, "Repertuar")

      # Extract showtimes
      showtimes = ShowtimeExtractor.extract(html, Date.utc_today())

      # Should find at least some showtimes
      assert length(showtimes) > 0

      # Verify first showtime has expected fields
      [first | _] = showtimes

      assert is_binary(first.movie_slug)
      assert is_binary(first.cinema_slug)
      assert %DateTime{} = first.datetime
    end

    # Remove this to enable
    @tag :skip
    test "fetches and parses movie detail page" do
      # This would need a real movie slug from the site
      # Example: "deadpool-wolverine"
      movie_slug = "test-movie"

      url = Config.movie_detail_url(movie_slug)
      headers = [{"User-Agent", Config.user_agent()}]

      case HTTPoison.get(url, headers, timeout: Config.timeout()) do
        {:ok, %{status_code: 200, body: html}} ->
          movie_data = MovieExtractor.extract(html)

          # Should extract some data
          assert movie_data.original_title != nil or movie_data.polish_title != nil

        {:ok, %{status_code: 404}} ->
          # Movie not found is acceptable for this test
          :ok

        error ->
          flunk("Failed to fetch movie: #{inspect(error)}")
      end
    end

    # Remove this to enable
    @tag :skip
    test "fetches and parses cinema info page" do
      # This would need a real cinema slug
      # Example: "kino-pod-baranami"
      cinema_slug = "test-cinema"

      url = Config.cinema_info_url(cinema_slug)
      headers = [{"User-Agent", Config.user_agent()}]

      case HTTPoison.get(url, headers, timeout: Config.timeout()) do
        {:ok, %{status_code: 200, body: html}} ->
          cinema_data = CinemaExtractor.extract(html, cinema_slug)

          # Should have basic cinema data
          assert is_binary(cinema_data.name)

        {:ok, %{status_code: 404}} ->
          # Cinema not found is acceptable
          :ok

        error ->
          flunk("Failed to fetch cinema: #{inspect(error)}")
      end
    end
  end

  describe "Manual testing helper" do
    test "provides helper for manual testing in IEx" do
      # This test just documents how to manually test in IEx
      # Run in IEx:
      #
      # alias EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob
      # {:ok, events} = SyncJob.fetch_events("Kraków", 10, %{})
      #
      # Then inspect the results

      assert true
    end
  end
end
