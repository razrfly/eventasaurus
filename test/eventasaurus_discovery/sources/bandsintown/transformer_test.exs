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
