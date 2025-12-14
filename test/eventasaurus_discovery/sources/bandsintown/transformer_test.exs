defmodule EventasaurusDiscovery.Sources.Bandsintown.TransformerTest do
  @moduledoc """
  Tests for Bandsintown event transformer.

  Ensures stable external_id generation and proper unified format transformation.
  """

  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Bandsintown.Transformer

  describe "transform_event/2" do
    test "transforms basic event data to unified format" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "venue_city" => "Kraków",
        "venue_country" => "Poland",
        "venue_latitude" => 50.0614,
        "venue_longitude" => 19.9372,
        "date" => "2025-10-15T20:00:00",
        "description" => "Test Concert",
        "external_id" => "bandsintown_104563789"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Verify required fields
      assert transformed.title == "Test Artist"
      assert transformed.external_id == "bandsintown_104563789"
      assert %DateTime{} = transformed.starts_at

      # Verify venue data
      assert transformed.venue_data.name == "Test Venue"
      assert transformed.venue_data.city == "Kraków"
      assert transformed.venue_data.country == "Poland"
      assert transformed.venue_data.latitude == 50.0614
      assert transformed.venue_data.longitude == 19.9372
    end

    test "generates stable external_id from URL" do
      raw_event1 = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "date" => "2025-10-15T20:00:00",
        "external_id" => "bandsintown_104563789"
      }

      raw_event2 = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "date" => "2025-10-15T20:00:00",
        "external_id" => "bandsintown_104563789"
      }

      {:ok, transformed1} = Transformer.transform_event(raw_event1)
      {:ok, transformed2} = Transformer.transform_event(raw_event2)

      # External ID must be stable across runs
      assert transformed1.external_id == transformed2.external_id
    end

    test "creates placeholder venue when venue data is missing" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "date" => "2025-10-15T20:00:00",
        "external_id" => "bandsintown_104563789"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Should create placeholder venue with artist name
      assert transformed.venue_data.name =~ "Test Artist"
      assert transformed.venue_data.metadata.placeholder == true
    end

    test "handles events with GPS coordinates" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "venue_latitude" => 50.0614,
        "venue_longitude" => 19.9372,
        "date" => "2025-10-15T20:00:00",
        "external_id" => "bandsintown_104563789"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # GPS coordinates should be preserved
      assert transformed.venue_data.latitude == 50.0614
      assert transformed.venue_data.longitude == 19.9372
    end

    test "handles events without GPS coordinates by using city center" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "venue_city" => "Kraków",
        "venue_country" => "Poland",
        "venue_address" => "ul. Floriańska 3",
        "date" => "2025-10-15T20:00:00",
        "external_id" => "bandsintown_104563789"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Should still transform with city center coordinates as fallback
      assert transformed.venue_data.name == "Test Venue"
      # City center coordinates will be filled in as fallback
      assert transformed.venue_data.latitude != nil
      assert transformed.venue_data.longitude != nil
    end
  end

  describe "performer extraction" do
    test "extracts performer as list for Processor compatibility" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Omasta",
        "venue_name" => "Jazz Club Hipnoza",
        "venue_latitude" => 50.2649,
        "venue_longitude" => 19.0238,
        "date" => "2025-10-30T20:00:00",
        "genres" => ["jazz", "funk"],
        "image_url" => "https://example.com/omasta.jpg"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Must use plural key `performers` with list value
      assert is_list(transformed.performers)
      assert length(transformed.performers) == 1

      [performer] = transformed.performers
      assert performer.name == "Omasta"
      assert performer.genres == ["jazz", "funk"]
      assert performer.image_url == "https://example.com/omasta.jpg"
    end

    test "returns empty performers list when no artist_name" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-event",
        "venue_name" => "Test Venue",
        "venue_latitude" => 50.0614,
        "venue_longitude" => 19.9372,
        "date" => "2025-10-15T20:00:00"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Should return empty list, not nil
      assert transformed.performers == []
    end

    test "filters invalid image URLs for performers" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "venue_latitude" => 50.0614,
        "venue_longitude" => 19.9372,
        "date" => "2025-10-15T20:00:00",
        "image_url" => "https://example.com/thumb/null.jpg"
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      [performer] = transformed.performers
      # Invalid image URL should be filtered to nil
      assert performer.image_url == nil
    end
  end

  describe "external_id stability" do
    test "external_id remains constant across multiple transformations" do
      raw_event = %{
        "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
        "artist_name" => "Test Artist",
        "venue_name" => "Test Venue",
        "date" => "2025-10-15T20:00:00",
        "external_id" => "bandsintown_104563789"
      }

      # Transform 10 times
      external_ids =
        1..10
        |> Enum.map(fn _ ->
          {:ok, transformed} = Transformer.transform_event(raw_event)
          transformed.external_id
        end)

      # All IDs should be identical
      assert Enum.uniq(external_ids) |> length() == 1
    end
  end
end
