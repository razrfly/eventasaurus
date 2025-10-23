defmodule EventasaurusDiscovery.VenueImages.QualityStats do
  @moduledoc """
  Provides venue image quality statistics and metrics for administrative dashboards.

  This module helps track:
  - Total venues and image coverage per city
  - Image source breakdown (Foursquare, Google Places, etc.)
  - Recent enrichment activity
  - Venues needing image backfilling

  ## Usage

      # Get overall venue stats for a city
      QualityStats.get_city_venue_stats(city_id)
      #=> %{
      #     total_venues: 423,
      #     venues_with_images: 347,
      #     venues_without_images: 76,
      #     coverage_percentage: 82.03
      #   }

      # Get breakdown by image source provider
      QualityStats.get_venue_image_sources(city_id)
      #=> %{
      #     foursquare: 245,
      #     google_places: 189,
      #     multiple_sources: 87,
      #     unknown: 13
      #   }

      # Get recent enrichment activity
      QualityStats.get_recent_enrichments(city_id, 7)
      #=> %{
      #     venues_enriched: 23,
      #     images_added: 87,
      #     by_provider: %{foursquare: 15, google_places: 8}
      #   }
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City

  @doc """
  Returns aggregate venue image statistics for a city.

  ## Parameters
    - `city_id` - Integer city ID to get stats for

  ## Returns
    Map with venue counts and coverage percentage:
    - `:total_venues` - Total number of venues in city
    - `:venues_with_images` - Number of venues with at least one image
    - `:venues_without_images` - Number of venues with no images
    - `:coverage_percentage` - Percentage of venues with images (0.0 - 100.0)
    - `:venues_missing_address` - Number of venues with missing/empty address
    - `:address_coverage_percentage` - Percentage of venues with addresses (0.0 - 100.0)
    - `:venues_missing_coordinates` - Number of venues with missing lat/lng
    - `:coordinates_coverage_percentage` - Percentage of venues with coordinates (0.0 - 100.0)

  ## Examples

      iex> QualityStats.get_city_venue_stats(1)
      %{
        total_venues: 423,
        venues_with_images: 347,
        venues_without_images: 76,
        coverage_percentage: 82.03,
        venues_missing_address: 12,
        address_coverage_percentage: 97.16,
        venues_missing_coordinates: 0,
        coordinates_coverage_percentage: 100.0
      }

      iex> QualityStats.get_city_venue_stats(999)
      %{
        total_venues: 0,
        venues_with_images: 0,
        venues_without_images: 0,
        coverage_percentage: 0.0,
        venues_missing_address: 0,
        address_coverage_percentage: 0.0,
        venues_missing_coordinates: 0,
        coordinates_coverage_percentage: 0.0
      }
  """
  def get_city_venue_stats(city_id) when is_integer(city_id) do
    # Query all venues for this city
    total_query =
      from v in Venue,
        where: v.city_id == ^city_id,
        select: count(v.id)

    # Query venues with images (venue_images JSONB array length > 0)
    with_images_query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("COALESCE(jsonb_array_length(?), 0) > 0", v.venue_images),
        select: count(v.id)

    # Query venues with missing address (NULL or empty string)
    missing_address_query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where: is_nil(v.address) or v.address == "",
        select: count(v.id)

    # Query venues with missing coordinates (either latitude or longitude is NULL)
    missing_coordinates_query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where: is_nil(v.latitude) or is_nil(v.longitude),
        select: count(v.id)

    total_venues = Repo.one(total_query) || 0
    venues_with_images = Repo.one(with_images_query) || 0
    venues_without_images = total_venues - venues_with_images
    venues_missing_address = Repo.one(missing_address_query) || 0
    venues_missing_coordinates = Repo.one(missing_coordinates_query) || 0

    coverage_percentage =
      if total_venues > 0 do
        Float.round(venues_with_images / total_venues * 100, 2)
      else
        0.0
      end

    address_coverage_percentage =
      if total_venues > 0 do
        venues_with_address = total_venues - venues_missing_address
        Float.round(venues_with_address / total_venues * 100, 2)
      else
        0.0
      end

    coordinates_coverage_percentage =
      if total_venues > 0 do
        venues_with_coordinates = total_venues - venues_missing_coordinates
        Float.round(venues_with_coordinates / total_venues * 100, 2)
      else
        0.0
      end

    %{
      total_venues: total_venues,
      venues_with_images: venues_with_images,
      venues_without_images: venues_without_images,
      coverage_percentage: coverage_percentage,
      venues_missing_address: venues_missing_address,
      address_coverage_percentage: address_coverage_percentage,
      venues_missing_coordinates: venues_missing_coordinates,
      coordinates_coverage_percentage: coordinates_coverage_percentage
    }
  end

  @doc """
  Returns breakdown of venue images by provider source.

  Analyzes the `venue_images` JSONB array to count how many venues
  have images from each provider (Foursquare, Google Places, etc.).

  ## Parameters
    - `city_id` - Integer city ID to get source breakdown for

  ## Returns
    Map with provider counts:
    - `:foursquare` - Venues with Foursquare images
    - `:google_places` - Venues with Google Places images
    - `:multiple_sources` - Venues with images from 2+ providers
    - `:unknown` - Venues with images from unrecognized sources
    - `:provider_details` - List of maps with provider breakdown

  ## Examples

      iex> QualityStats.get_venue_image_sources(1)
      %{
        foursquare: 245,
        google_places: 189,
        multiple_sources: 87,
        unknown: 13,
        provider_details: [
          %{provider: "foursquare", count: 245, percentage: 70.6},
          %{provider: "google_places", count: 189, percentage: 54.5}
        ]
      }
  """
  def get_venue_image_sources(city_id) when is_integer(city_id) do
    # Query venues with images and extract provider information
    # venue_images structure: [%{"url" => "...", "provider" => "foursquare"}, ...]
    query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("COALESCE(jsonb_array_length(?), 0) > 0", v.venue_images),
        select: %{
          venue_id: v.id,
          venue_images: v.venue_images
        }

    venues_with_images = Repo.all(query)

    # Count by provider
    provider_counts =
      Enum.reduce(venues_with_images, %{}, fn venue, acc ->
        providers = extract_providers_from_images(venue.venue_images)

        Enum.reduce(providers, acc, fn provider, inner_acc ->
          Map.update(inner_acc, provider, 1, &(&1 + 1))
        end)
      end)

    # Count venues with multiple sources
    multiple_sources_count =
      Enum.count(venues_with_images, fn venue ->
        providers = extract_providers_from_images(venue.venue_images)
        length(providers) > 1
      end)

    foursquare_count = Map.get(provider_counts, "foursquare", 0)
    google_places_count = Map.get(provider_counts, "google_places", 0)
    total_with_images = length(venues_with_images)

    # Calculate unknown sources (images with no provider or unrecognized provider)
    known_count = foursquare_count + google_places_count
    unknown_count = max(0, total_with_images - known_count + multiple_sources_count)

    # Build provider details with percentages
    provider_details =
      provider_counts
      |> Enum.map(fn {provider, count} ->
        percentage =
          if total_with_images > 0 do
            Float.round(count / total_with_images * 100, 1)
          else
            0.0
          end

        %{
          provider: provider,
          count: count,
          percentage: percentage
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    %{
      foursquare: foursquare_count,
      google_places: google_places_count,
      multiple_sources: multiple_sources_count,
      unknown: unknown_count,
      provider_details: provider_details
    }
  end

  @doc """
  Returns recent venue enrichment activity for a city.

  Tracks venues that have been enriched with images in the last N days
  based on the `image_enrichment_metadata` JSONB field.

  ## Parameters
    - `city_id` - Integer city ID to get enrichment stats for
    - `days` - Number of days to look back (default: 7)

  ## Returns
    Map with enrichment activity:
    - `:venues_enriched` - Count of venues enriched in period
    - `:images_added` - Total images added in period
    - `:by_provider` - Map of provider names to enrichment counts
    - `:period_days` - Number of days in the reporting period

  ## Examples

      iex> QualityStats.get_recent_enrichments(1, 7)
      %{
        venues_enriched: 23,
        images_added: 87,
        by_provider: %{foursquare: 15, google_places: 8},
        period_days: 7
      }
  """
  def get_recent_enrichments(city_id, days \\ 7)
      when is_integer(city_id) and is_integer(days) and days > 0 do
    cutoff_date =
      DateTime.utc_now()
      |> DateTime.add(-days, :day)
      |> DateTime.to_naive()

    # Query venues enriched since cutoff date
    # image_enrichment_metadata structure: %{"last_enriched_at" => "2025-01-15T10:30:00", ...}
    query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where:
          fragment(
            "(? ->> 'last_enriched_at')::timestamp >= ?::timestamp",
            v.image_enrichment_metadata,
            ^cutoff_date
          ),
        select: %{
          venue_id: v.id,
          venue_images: v.venue_images,
          enrichment_metadata: v.image_enrichment_metadata
        }

    enriched_venues = Repo.all(query)

    venues_enriched = length(enriched_venues)

    # Count total images added
    images_added =
      Enum.reduce(enriched_venues, 0, fn venue, acc ->
        image_count =
          case venue.venue_images do
            images when is_list(images) -> length(images)
            _ -> 0
          end

        acc + image_count
      end)

    # Count by provider (based on current images, not historical)
    by_provider =
      Enum.reduce(enriched_venues, %{}, fn venue, acc ->
        providers = extract_providers_from_images(venue.venue_images)

        Enum.reduce(providers, acc, fn provider, inner_acc ->
          Map.update(inner_acc, String.to_atom(provider), 1, &(&1 + 1))
        end)
      end)

    %{
      venues_enriched: venues_enriched,
      images_added: images_added,
      by_provider: by_provider,
      period_days: days
    }
  end

  @doc """
  Lists venues with images to display in admin UI.

  Returns venues with their images and enrichment metadata for gallery display.

  ## Parameters
    - `city_id` - Integer city ID to get venues for
    - `limit` - Maximum number of venues to return (default: 20)

  ## Returns
    List of Venue structs with preloaded images and metadata

  ## Examples

      iex> QualityStats.list_venues_with_images(1, 10)
      [%Venue{venue_images: [...], image_enrichment_metadata: %{...}}, ...]
  """
  def list_venues_with_images(city_id, limit \\ 20)
      when is_integer(city_id) and is_integer(limit) and limit > 0 do
    query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("jsonb_array_length(?) > 0", v.venue_images),
        order_by: [desc: fragment("jsonb_array_length(?)", v.venue_images), asc: v.id],
        limit: ^limit

    Repo.all(query)
  end

  @doc """
  Lists venues without images that need backfilling.

  Returns venues in priority order (prioritizing those with provider IDs
  already available, making them easier to backfill).

  ## Parameters
    - `city_id` - Integer city ID to get venues for
    - `limit` - Maximum number of venues to return (default: 20)

  ## Returns
    List of maps with venue information:
    - `:id` - Venue ID
    - `:name` - Venue name
    - `:address` - Venue address
    - `:has_coordinates` - Boolean, true if lat/lng present
    - `:has_provider_ids` - Boolean, true if has any provider IDs
    - `:provider_ids` - Map of available provider IDs
    - `:priority_score` - Integer score for backfill priority (higher = more ready)

  ## Examples

      iex> QualityStats.list_venues_without_images(1, 10)
      [
        %{
          id: 123,
          name: "Jazz Club Kraków",
          address: "ul. Floriańska 45",
          has_coordinates: true,
          has_provider_ids: true,
          provider_ids: %{"foursquare" => "abc123"},
          priority_score: 3
        },
        ...
      ]
  """
  def list_venues_without_images(city_id, limit \\ 20)
      when is_integer(city_id) and is_integer(limit) and limit > 0 do
    # Query venues without images, ordered by priority
    # Priority scoring:
    # +2 for having coordinates
    # +1 for having at least one provider ID
    query =
      from v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("COALESCE(jsonb_array_length(?), 0) = 0", v.venue_images),
        select: %{
          id: v.id,
          name: v.name,
          address: v.address,
          latitude: v.latitude,
          longitude: v.longitude,
          provider_ids: v.provider_ids
        },
        order_by: [
          desc:
            fragment(
              "CASE WHEN ? IS NOT NULL AND ? IS NOT NULL THEN 2 ELSE 0 END",
              v.latitude,
              v.longitude
            ),
          desc:
            fragment(
              "CASE WHEN jsonb_typeof(?) = 'object' AND (SELECT COUNT(*) FROM jsonb_object_keys(?)) > 0 THEN 1 ELSE 0 END",
              v.provider_ids,
              v.provider_ids
            ),
          asc: v.id
        ],
        limit: ^limit

    venues = Repo.all(query)

    Enum.map(venues, fn venue ->
      has_coordinates = not is_nil(venue.latitude) and not is_nil(venue.longitude)

      has_provider_ids =
        case venue.provider_ids do
          map when is_map(map) and map_size(map) > 0 -> true
          _ -> false
        end

      priority_score =
        (if has_coordinates, do: 2, else: 0) +
          (if has_provider_ids, do: 1, else: 0)

      %{
        id: venue.id,
        name: venue.name,
        address: venue.address,
        has_coordinates: has_coordinates,
        has_provider_ids: has_provider_ids,
        provider_ids: venue.provider_ids || %{},
        priority_score: priority_score
      }
    end)
  end

  @doc """
  Returns a summary of venue image quality across all cities.

  Useful for system-wide monitoring and reporting.

  ## Returns
    Map with overall statistics:
    - `:total_venues` - Total venues across all cities
    - `:venues_with_images` - Total venues with images
    - `:coverage_percentage` - Overall image coverage percentage
    - `:cities_analyzed` - Number of cities included
    - `:top_cities` - Top 5 cities by venue count

  ## Examples

      iex> QualityStats.get_overall_stats()
      %{
        total_venues: 1250,
        venues_with_images: 980,
        coverage_percentage: 78.4,
        cities_analyzed: 12,
        top_cities: [...]
      }
  """
  def get_overall_stats do
    # Total venues
    total_venues = Repo.aggregate(Venue, :count, :id)

    # Venues with images
    venues_with_images =
      Repo.one(
        from v in Venue,
          where: fragment("COALESCE(jsonb_array_length(?), 0) > 0", v.venue_images),
          select: count(v.id)
      ) || 0

    coverage_percentage =
      if total_venues > 0 do
        Float.round(venues_with_images / total_venues * 100, 2)
      else
        0.0
      end

    # Count cities with venues
    cities_analyzed =
      Repo.one(
        from v in Venue,
          where: not is_nil(v.city_id),
          select: count(v.city_id, :distinct)
      ) || 0

    # Get top 5 cities by venue count
    top_cities =
      from(v in Venue,
        join: c in City,
        on: c.id == v.city_id,
        group_by: [c.id, c.name, c.slug],
        select: %{
          city_id: c.id,
          city_name: c.name,
          city_slug: c.slug,
          venue_count: count(v.id)
        },
        order_by: [desc: count(v.id)],
        limit: 5
      )
      |> Repo.all()

    %{
      total_venues: total_venues,
      venues_with_images: venues_with_images,
      coverage_percentage: coverage_percentage,
      cities_analyzed: cities_analyzed,
      top_cities: top_cities
    }
  end

  # Private Helpers

  # Extracts unique provider names from venue_images JSONB array
  # Returns list of provider strings, e.g., ["foursquare", "google_places"]
  defp extract_providers_from_images(venue_images) do
    case venue_images do
      images when is_list(images) ->
        images
        |> Enum.map(fn
          %{"provider" => provider} when is_binary(provider) -> provider
          _ -> "unknown"
        end)
        |> Enum.uniq()

      _ ->
        []
    end
  end
end
