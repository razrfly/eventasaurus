defmodule EventasaurusWeb.Services.MusicBrainzRichDataProviderTest do
  use ExUnit.Case, async: true
  alias EventasaurusWeb.Services.MusicBrainzRichDataProvider

  @moduletag :external_api

  describe "provider configuration" do
    test "returns correct provider information" do
      assert MusicBrainzRichDataProvider.provider_id() == :musicbrainz
      assert MusicBrainzRichDataProvider.provider_name() == "MusicBrainz"
      assert MusicBrainzRichDataProvider.supported_types() == [:track, :artist, :album, :playlist]
    end

    test "validates configuration successfully" do
      # MusicBrainz doesn't require API keys, so this should always pass
      assert MusicBrainzRichDataProvider.validate_config() == :ok
    end

    test "provides configuration schema" do
      schema = MusicBrainzRichDataProvider.config_schema()
      
      assert is_map(schema)
      assert Map.has_key?(schema, :base_url)
      assert Map.has_key?(schema, :user_agent)
      assert Map.has_key?(schema, :rate_limit)
      assert Map.has_key?(schema, :cache_ttl)
    end
  end

  describe "search/2" do
    test "searches for artists" do
      case MusicBrainzRichDataProvider.search("Beatles", %{content_type: :artist}) do
        {:ok, results} ->
          assert is_list(results)
          assert length(results) > 0
          
          first_result = List.first(results)
          assert first_result.type == :artist
          assert is_binary(first_result.id)
          assert is_binary(first_result.title)
          assert is_map(first_result.metadata)
          assert first_result.metadata.media_type == "artist"

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "searches for tracks" do
      case MusicBrainzRichDataProvider.search("Yesterday", %{content_type: :track}) do
        {:ok, results} ->
          assert is_list(results)
          assert length(results) > 0
          
          first_result = List.first(results)
          assert first_result.type == :track
          assert is_binary(first_result.id)
          assert is_binary(first_result.title)
          assert is_map(first_result.metadata)
          assert first_result.metadata.media_type == "recording"

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "searches for albums" do
      case MusicBrainzRichDataProvider.search("Abbey Road", %{content_type: :album}) do
        {:ok, results} ->
          assert is_list(results)
          assert length(results) > 0
          
          first_result = List.first(results)
          assert first_result.type == :album
          assert is_binary(first_result.id)
          assert is_binary(first_result.title)
          assert is_map(first_result.metadata)
          assert first_result.metadata.media_type == "release_group"

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "handles empty queries gracefully" do
      assert {:ok, []} = MusicBrainzRichDataProvider.search("", %{})
      assert {:ok, []} = MusicBrainzRichDataProvider.search(nil, %{})
    end
  end

  describe "get_details/3" do
    test "gets artist details" do
      # Use a known MusicBrainz artist ID (The Beatles)
      beatles_id = "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"
      
      case MusicBrainzRichDataProvider.get_details(beatles_id, :artist) do
        {:ok, details} ->
          assert details.id == beatles_id
          assert details.type == :artist
          assert details.title == "The Beatles"
          assert is_binary(details.description)
          assert is_map(details.metadata)
          assert details.metadata.musicbrainz_id == beatles_id
          assert is_map(details.external_urls)
          assert String.contains?(details.external_urls.musicbrainz_url, beatles_id)

        {:error, reason} ->
          # If we get a rate limit error, that's expected in tests
          if String.contains?(to_string(reason), "rate") do
            IO.puts("Rate limited - this is expected for MusicBrainz tests")
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "handles invalid content types" do
      assert {:error, "Unsupported content type: invalid"} = 
        MusicBrainzRichDataProvider.get_details("some_id", :invalid)
    end
  end

  describe "get_cached_details/3" do
    test "gets cached artist details" do
      # Use a known MusicBrainz artist ID (The Beatles)
      beatles_id = "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"
      
      case MusicBrainzRichDataProvider.get_cached_details(beatles_id, :artist) do
        {:ok, details} ->
          assert details.id == beatles_id
          assert details.type == :artist
          assert details.title == "The Beatles"

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