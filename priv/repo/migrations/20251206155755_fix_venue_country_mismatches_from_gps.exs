defmodule EventasaurusApp.Repo.Migrations.FixVenueCountryMismatchesFromGps do
  @moduledoc """
  One-time migration to fix venue country mismatches using GPS coordinates.

  This migration:
  1. Queries all venues with GPS coordinates
  2. Uses CityResolver to determine the correct country from GPS
  3. If the venue's assigned country differs from GPS-indicated country,
     reassigns the venue to a city in the correct country

  This fixes legacy data where scrapers (especially speed-quizzing) assigned
  Irish venues to UK incorrectly.
  """
  use Ecto.Migration

  import Ecto.Query

  # Can't use `change` because this is a data migration with complex logic
  def up do
    # Flush any pending schema changes first
    flush()

    try do
      # Start the geocoding application - it's needed for reverse geocoding
      # This handles environments where the app may not be available
      case Application.ensure_all_started(:geocoding) do
        {:ok, _} -> :ok
        {:error, reason} ->
          IO.puts("[Migration] Warning: Could not start geocoding app: #{inspect(reason)}")
          IO.puts("[Migration] Skipping migration - run manually when geocoding is available")
          throw(:skip_migration)
      end

      # Get repo module - we're in a migration so use the repo directly
      repo = EventasaurusApp.Repo

      # Log start
      IO.puts("[Migration] Starting venue country mismatch fix...")

      # Query all venues with GPS coordinates, preloading city and country
      venues =
        from(v in "venues",
          join: c in "cities", on: c.id == v.city_id,
          join: co in "countries", on: co.id == c.country_id,
          where: not is_nil(v.latitude) and not is_nil(v.longitude),
          select: %{
            id: v.id,
            name: v.name,
            latitude: v.latitude,
            longitude: v.longitude,
            city_id: v.city_id,
            city_name: c.name,
            country_id: co.id,
            country_code: co.code,
            country_name: co.name
          }
        )
        |> repo.all()

      IO.puts("[Migration] Checking #{length(venues)} venues with GPS coordinates...")

      # Process each venue
      stats = %{checked: 0, fixed: 0, errors: 0, skipped: 0}

      stats =
        Enum.reduce(venues, stats, fn venue, acc ->
          case check_and_fix_venue(repo, venue) do
            :ok -> %{acc | checked: acc.checked + 1}
            :fixed -> %{acc | checked: acc.checked + 1, fixed: acc.fixed + 1}
            :skipped -> %{acc | checked: acc.checked + 1, skipped: acc.skipped + 1}
            :error -> %{acc | checked: acc.checked + 1, errors: acc.errors + 1}
          end
        end)

      IO.puts("[Migration] Complete!")
      IO.puts("[Migration] Checked: #{stats.checked}")
      IO.puts("[Migration] Fixed: #{stats.fixed}")
      IO.puts("[Migration] Skipped: #{stats.skipped}")
      IO.puts("[Migration] Errors: #{stats.errors}")
    catch
      :skip_migration ->
        IO.puts("[Migration] Migration skipped - no changes made")
        :ok
    end
  end

  def down do
    # Data migration - can't be reversed automatically
    # The old country assignments are not stored anywhere to restore from
    IO.puts("[Migration] This migration cannot be reversed - venue country assignments are permanent")
  end

  defp check_and_fix_venue(repo, venue) do
    lat = venue.latitude
    lng = venue.longitude

    # Use CityResolver to get expected country from GPS
    case EventasaurusDiscovery.Helpers.CityResolver.resolve_city_and_country(lat, lng) do
      {:ok, {_expected_city, expected_code}} ->
        current_code = String.upcase(venue.country_code || "")
        expected_code_upper = String.upcase(expected_code || "")

        if current_code != expected_code_upper do
          # Mismatch found - try to fix
          fix_venue_country(repo, venue, expected_code_upper)
        else
          :ok
        end

      {:error, _reason} ->
        # Couldn't resolve GPS - skip
        :skipped
    end
  end

  defp fix_venue_country(repo, venue, expected_country_code) do
    # Find a city in the expected country
    # Prefer a city with similar name, or fall back to capital/major city
    target_city =
      find_target_city(repo, venue.city_name, expected_country_code) ||
      find_major_city(repo, expected_country_code)

    case target_city do
      nil ->
        IO.puts("[Migration] WARNING: No city found in #{expected_country_code} for venue #{venue.id} (#{venue.name})")
        :error

      city ->
        # Update the venue's city_id
        from(v in "venues", where: v.id == ^venue.id)
        |> repo.update_all(set: [city_id: city.id, updated_at: DateTime.utc_now()])

        IO.puts("[Migration] Fixed venue #{venue.id} (#{venue.name}): #{venue.country_code} -> #{expected_country_code}")
        :fixed
    end
  end

  # Try to find a city with the same name in the target country
  defp find_target_city(repo, city_name, country_code) do
    from(c in "cities",
      join: co in "countries", on: co.id == c.country_id,
      where: co.code == ^country_code,
      where: ilike(c.name, ^city_name),
      limit: 1,
      select: %{id: c.id, name: c.name}
    )
    |> repo.one()
  end

  # Find a major city in the target country (fallback)
  defp find_major_city(repo, country_code) do
    # Priority cities for common countries
    priority_cities = %{
      "IE" => ["Dublin", "Cork", "Galway", "Limerick"],
      "GB" => ["London", "Manchester", "Birmingham", "Edinburgh"],
      "US" => ["New York", "Los Angeles", "Chicago"],
      "DE" => ["Berlin", "Munich", "Hamburg"],
      "FR" => ["Paris", "Lyon", "Marseille"]
    }

    cities_to_try = Map.get(priority_cities, country_code, [])

    # Try each priority city
    Enum.find_value(cities_to_try, fn city_name ->
      from(c in "cities",
        join: co in "countries", on: co.id == c.country_id,
        where: co.code == ^country_code,
        where: ilike(c.name, ^"%#{city_name}%"),
        limit: 1,
        select: %{id: c.id, name: c.name}
      )
      |> repo.one()
    end) ||
    # Last resort: just get any city in that country
    from(c in "cities",
      join: co in "countries", on: co.id == c.country_id,
      where: co.code == ^country_code,
      limit: 1,
      select: %{id: c.id, name: c.name}
    )
    |> repo.one()
  end
end
