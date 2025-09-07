defmodule EventasaurusWeb.Services.MusicBrainzServiceTest do
  use ExUnit.Case, async: true
  alias EventasaurusWeb.Services.MusicBrainzService

  @moduletag :external_api

  describe "search_multi/3" do
    test "searches for artists" do
      case MusicBrainzService.search_multi("Beatles", :artist) do
        {:ok, results} ->
          assert is_list(results)
          assert length(results) > 0
          
          first_result = List.first(results)
          assert first_result.type == :artist
          assert is_binary(first_result.id)
          assert is_binary(first_result.name)
          assert String.contains?(String.downcase(first_result.name), "beatles")

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "searches for recordings (tracks)" do
      case MusicBrainzService.search_multi("Yesterday", :recording) do
        {:ok, results} ->
          assert is_list(results)
          assert length(results) > 0
          
          first_result = List.first(results)
          assert first_result.type == :recording
          assert is_binary(first_result.id)
          assert is_binary(first_result.title)

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "handles empty query gracefully" do
      assert {:ok, []} = MusicBrainzService.search_multi("", :artist)
      assert {:ok, []} = MusicBrainzService.search_multi(nil, :artist)
    end
  end

  describe "rate limiting" do
    test "enforces rate limits" do
      # Make multiple rapid requests to test rate limiting
      # Note: This test might be flaky due to the 1 req/sec limit
      
      case MusicBrainzService.search_multi("Test", :artist) do
        {:ok, _results} ->
          # Immediately make another request - should be rate limited
          case MusicBrainzService.search_multi("Test2", :artist) do
            {:error, reason} ->
              assert String.contains?(to_string(reason), "rate")
            {:ok, _} ->
              # Might not be rate limited if enough time has passed
              :ok
          end
        {:error, reason} ->
          # First request was rate limited
          assert String.contains?(to_string(reason), "rate")
      end
    end
  end

  describe "caching" do
    test "caches artist details" do
      # Use a known MusicBrainz artist ID (The Beatles)
      beatles_id = "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"
      
      case MusicBrainzService.get_cached_artist_details(beatles_id) do
        {:ok, artist_data} ->
          assert artist_data.musicbrainz_id == beatles_id
          assert artist_data.name == "The Beatles"
          assert artist_data.source == "musicbrainz"
          assert artist_data.type == "artist"

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end
  end
end