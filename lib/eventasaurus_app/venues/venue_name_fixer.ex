defmodule EventasaurusApp.Venues.VenueNameFixer do
  @moduledoc """
  Fixes venue names by extracting better names from geocoding metadata.

  Used by city-specific venue name fixing to replace bad scraped names
  (like "ul. Marszałkowska 10 (pokaż na mapie)") with proper names from
  geocoding providers (like "La Lucy").
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Validation.VenueNameValidator

  @doc """
  Finds all venues in a city that have name quality issues.

  Returns list of venues with their quality assessment.
  """
  def find_venues_with_quality_issues(city_slug, severity \\ :all) do
    city = Repo.get_by!(City, slug: city_slug)

    query =
      from(v in Venue,
        where: v.city_id == ^city.id,
        where: not is_nil(v.metadata),
        preload: [:city_ref]
      )

    venues = Repo.all(query)

    venues
    |> Enum.map(&assess_venue_quality/1)
    |> Enum.filter(&should_fix?(&1, severity))
    |> Enum.sort_by(& &1.similarity)
  end

  @doc """
  Assesses the quality of a venue's name by comparing against geocoded name.
  """
  def assess_venue_quality(venue) do
    geocoded_name = VenueNameValidator.extract_geocoded_name(venue.metadata)

    case geocoded_name do
      nil ->
        %{
          venue: venue,
          current_name: venue.name,
          geocoded_name: nil,
          similarity: nil,
          severity: :no_geocoded_name,
          should_fix: false,
          reason: "No geocoded name available in metadata"
        }

      geocoded ->
        similarity = VenueNameValidator.calculate_similarity(venue.name, geocoded)

        %{
          venue: venue,
          current_name: venue.name,
          geocoded_name: geocoded,
          similarity: similarity,
          severity: determine_severity(similarity),
          should_fix: similarity < 0.7,
          reason: severity_reason(similarity)
        }
    end
  end

  @doc """
  Fixes a venue's name by extracting from geocoding metadata.

  Options:
  - dry_run: If true, only returns what would be done without applying
  - check_duplicates: If true, checks for duplicate venues after rename
  """
  def fix_venue_name(assessment, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    check_duplicates = Keyword.get(opts, :check_duplicates, true)

    venue = assessment.venue
    new_name = assessment.geocoded_name

    cond do
      !assessment.should_fix ->
        {:skip, "Quality is acceptable (similarity: #{format_similarity(assessment.similarity)})"}

      is_nil(new_name) ->
        {:skip, "No geocoded name available"}

      String.trim(new_name) == "" ->
        {:skip, "Geocoded name is empty"}

      venue.name == new_name ->
        {:skip, "Names are identical"}

      true ->
        if check_duplicates do
          check_and_apply_fix(venue, new_name, dry_run)
        else
          apply_rename(venue, new_name, dry_run)
        end
    end
  end

  # Private functions

  defp should_fix?(%{should_fix: false}, _severity), do: false
  defp should_fix?(%{severity: :no_geocoded_name}, _severity), do: false

  defp should_fix?(%{severity: severity}, filter) do
    case filter do
      :all -> true
      :severe -> severity == :severe
      :moderate -> severity in [:severe, :moderate]
    end
  end

  defp determine_severity(nil), do: :no_geocoded_name
  defp determine_severity(similarity) when similarity < 0.3, do: :severe
  defp determine_severity(similarity) when similarity < 0.7, do: :moderate
  defp determine_severity(_), do: :acceptable

  defp severity_reason(nil), do: "No geocoded name to compare"
  defp severity_reason(similarity) when similarity < 0.3, do: "Names very different (severe)"
  defp severity_reason(similarity) when similarity < 0.7, do: "Names moderately different"
  defp severity_reason(_), do: "Names similar enough"

  defp check_and_apply_fix(venue, new_name, dry_run) do
    # Check for potential duplicates before applying fix
    # Search for existing venue with same/similar name at same location
    duplicate = find_potential_duplicate(venue, new_name)

    case duplicate do
      nil ->
        apply_rename(venue, new_name, dry_run)

      existing_venue ->
        # Don't auto-merge - flag for manual review
        event_count = count_venue_events(venue)
        {:duplicate_detected, existing_venue, event_count}
    end
  end

  defp find_potential_duplicate(venue, new_name) do
    # Look for venues in same city with similar name and nearby location
    query =
      from(v in Venue,
        where: v.city_id == ^venue.city_id,
        where: v.id != ^venue.id,
        where: not is_nil(v.latitude) and not is_nil(v.longitude)
      )

    Repo.all(query)
    |> Enum.find(fn candidate ->
      # Check if names match after normalization
      name_similarity = VenueNameValidator.calculate_similarity(new_name, candidate.name)

      # Check if locations are close (within ~50 meters)
      distance_meters =
        calculate_distance_meters(
          {venue.latitude, venue.longitude},
          {candidate.latitude, candidate.longitude}
        )

      # It's a duplicate if names are very similar and locations are close
      name_similarity >= 0.8 && distance_meters < 50
    end)
  end

  defp calculate_distance_meters({lat1, lng1}, {lat2, lng2}) do
    # Haversine formula for accurate distance calculation on Earth's surface
    # Convert Decimal to float if needed
    lat1 = if is_struct(lat1, Decimal), do: Decimal.to_float(lat1), else: lat1
    lat2 = if is_struct(lat2, Decimal), do: Decimal.to_float(lat2), else: lat2
    lng1 = if is_struct(lng1, Decimal), do: Decimal.to_float(lng1), else: lng1
    lng2 = if is_struct(lng2, Decimal), do: Decimal.to_float(lng2), else: lng2

    earth_radius_m = 6_371_000
    lat1_rad = :math.pi() * lat1 / 180
    lat2_rad = :math.pi() * lat2 / 180
    delta_lat = lat2_rad - lat1_rad
    delta_lng = :math.pi() * (lng2 - lng1) / 180

    a =
      :math.pow(:math.sin(delta_lat / 2), 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) * :math.pow(:math.sin(delta_lng / 2), 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    earth_radius_m * c
  end

  defp apply_rename(venue, new_name, dry_run) do
    if dry_run do
      event_count = count_venue_events(venue)
      {:rename, new_name, event_count}
    else
      case Repo.update(Ecto.Changeset.change(venue, name: new_name)) do
        {:ok, updated_venue} ->
          event_count = count_venue_events(venue)
          {:renamed, updated_venue, event_count}

        {:error, changeset} ->
          {:error, "Failed to rename: #{inspect(changeset.errors)}"}
      end
    end
  end

  defp count_venue_events(venue) do
    Repo.one(
      from(e in PublicEvent,
        where: e.venue_id == ^venue.id,
        select: count(e.id)
      )
    )
  end

  defp format_similarity(nil), do: "N/A"
  defp format_similarity(score), do: Float.round(score, 2)
end
