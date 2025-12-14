defmodule EventasaurusDiscovery.Sources.Repertuary.TransformerTest do
  @moduledoc """
  Tests for Kino Krakow event transformer.

  Ensures stable external_id generation and proper unified format transformation.
  """

  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Repertuary.Transformer

  describe "transform_event/1" do
    test "transforms basic showtime data to unified format" do
      raw_event = %{
        external_id: "repertuary_krakow_test-movie_kino-plaza_2025-10-15T18:00:00Z",
        movie_slug: "test-movie",
        cinema_slug: "kino-plaza",
        movie_title: "Test Movie",
        original_title: "Test Movie Original",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z],
        runtime: 120,
        cinema_data: %{
          name: "Kino Kraków Plaza",
          address: "ul. Kamieńskiego 11",
          city: "Kraków",
          country: "Poland",
          latitude: 50.0614,
          longitude: 19.9372
        }
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Verify required fields
      assert transformed.title
      assert String.contains?(transformed.title, "Test Movie")
      assert String.contains?(transformed.title, "Kino Kraków Plaza")

      assert transformed.external_id ==
               "repertuary_krakow_test-movie_kino-plaza_2025-10-15T18:00:00Z"

      assert transformed.starts_at == ~U[2025-10-15 18:00:00Z]

      # Verify venue data
      assert transformed.venue_data.name == "Kino Kraków Plaza"
      assert transformed.venue_data.city == "Kraków"
      assert transformed.venue_data.country == "Poland"

      # Verify movie data
      assert transformed.movie_data.tmdb_id == 550
      assert transformed.movie_id == 1
    end

    test "preserves external_id from input" do
      external_id = "repertuary_krakow_test-movie_kino-plaza_2025-10-15T18:00:00Z"

      raw_event1 = %{
        external_id: external_id,
        movie_slug: "test-movie",
        cinema_slug: "kino-plaza",
        movie_title: "Test Movie",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z],
        runtime: 120,
        cinema_data: %{
          name: "Kino Kraków Plaza",
          city: "Kraków",
          country: "Poland"
        }
      }

      raw_event2 = %{
        external_id: external_id,
        movie_slug: "test-movie",
        cinema_slug: "kino-plaza",
        movie_title: "Test Movie",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z],
        runtime: 120,
        cinema_data: %{
          name: "Kino Kraków Plaza",
          city: "Kraków",
          country: "Poland"
        }
      }

      {:ok, transformed1} = Transformer.transform_event(raw_event1)
      {:ok, transformed2} = Transformer.transform_event(raw_event2)

      # External ID is preserved from input
      assert transformed1.external_id == external_id
      assert transformed2.external_id == external_id
      assert transformed1.external_id == transformed2.external_id
    end

    test "calculates end time based on runtime" do
      raw_event = %{
        external_id: "repertuary_krakow_test-movie_kino-plaza_2025-10-15T18:00:00Z",
        movie_slug: "test-movie",
        cinema_slug: "kino-plaza",
        movie_title: "Test Movie",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z],
        runtime: 120,
        cinema_data: %{
          name: "Kino Kraków Plaza",
          city: "Kraków",
          country: "Poland"
        }
      }

      {:ok, transformed} = Transformer.transform_event(raw_event)

      # Should add 120 minutes to start time
      assert transformed.ends_at == ~U[2025-10-15 20:00:00Z]
    end

    test "rejects events without external_id" do
      raw_event = %{
        movie_slug: "test-movie",
        cinema_slug: "kino-plaza",
        movie_title: "Test Movie",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z],
        cinema_data: %{
          name: "Kino Kraków Plaza",
          city: "Kraków",
          country: "Poland"
        }
      }

      result = Transformer.transform_event(raw_event)

      # Should error on missing external_id
      assert {:error, "Missing external_id"} = result
    end

    test "rejects events without movie data" do
      raw_event = %{
        external_id: "repertuary_krakow_test_2025-10-15",
        datetime: ~U[2025-10-15 18:00:00Z],
        cinema_data: %{
          name: "Kino Kraków Plaza",
          city: "Kraków",
          country: "Poland"
        }
      }

      result = Transformer.transform_event(raw_event)

      # Should error on missing movie data
      assert {:error, _reason} = result
    end

    test "rejects events without cinema data" do
      raw_event = %{
        external_id: "repertuary_krakow_test_2025-10-15",
        movie_slug: "test-movie",
        movie_title: "Test Movie",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z]
      }

      result = Transformer.transform_event(raw_event)

      # Should error on missing cinema data
      assert {:error, _reason} = result
    end
  end

  describe "external_id stability" do
    test "external_id remains constant across multiple transformations" do
      external_id = "repertuary_krakow_test-movie_kino-plaza_2025-10-15T18:00:00Z"

      raw_event = %{
        external_id: external_id,
        movie_slug: "test-movie",
        cinema_slug: "kino-plaza",
        movie_title: "Test Movie",
        tmdb_id: 550,
        movie_id: 1,
        datetime: ~U[2025-10-15 18:00:00Z],
        runtime: 120,
        cinema_data: %{
          name: "Kino Kraków Plaza",
          city: "Kraków",
          country: "Poland"
        }
      }

      # Transform 10 times
      external_ids =
        1..10
        |> Enum.map(fn _ ->
          {:ok, transformed} = Transformer.transform_event(raw_event)
          transformed.external_id
        end)

      # All IDs should be identical (external_id is preserved from input)
      assert Enum.uniq(external_ids) |> length() == 1
      assert hd(external_ids) == external_id
    end
  end
end
