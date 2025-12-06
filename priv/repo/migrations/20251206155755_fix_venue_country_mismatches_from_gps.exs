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

      # Log start
      IO.puts("[Migration] Starting venue country mismatch fix...")

      # Query all venues with GPS coordinates using raw SQL
      # We can't use Ecto.Query in migrations because the Repo isn't started as a GenServer
      {:ok, result} = repo().query("""
        SELECT v.id, v.name, v.latitude, v.longitude, v.city_id,
               c.name as city_name, co.id as country_id, co.code as country_code, co.name as country_name
        FROM venues v
        JOIN cities c ON c.id = v.city_id
        JOIN countries co ON co.id = c.country_id
        WHERE v.latitude IS NOT NULL AND v.longitude IS NOT NULL
      """)

      venues = Enum.map(result.rows, fn row ->
        [id, name, lat, lng, city_id, city_name, country_id, country_code, country_name] = row
        %{
          id: id,
          name: name,
          latitude: lat,
          longitude: lng,
          city_id: city_id,
          city_name: city_name,
          country_id: country_id,
          country_code: country_code,
          country_name: country_name
        }
      end)

      IO.puts("[Migration] Checking #{length(venues)} venues with GPS coordinates...")

      # Process each venue
      stats = %{checked: 0, fixed: 0, errors: 0, skipped: 0}

      stats =
        Enum.reduce(venues, stats, fn venue, acc ->
          case check_and_fix_venue(venue) do
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

  defp check_and_fix_venue(venue) do
    lat = venue.latitude
    lng = venue.longitude

    # Use CityResolver to get expected country from GPS
    case EventasaurusDiscovery.Helpers.CityResolver.resolve_city_and_country(lat, lng) do
      {:ok, {_expected_city, expected_code}} ->
        current_code = String.upcase(venue.country_code || "")
        expected_code_upper = String.upcase(expected_code || "")

        if current_code != expected_code_upper do
          # Mismatch found - try to fix
          fix_venue_country(venue, expected_code_upper)
        else
          :ok
        end

      {:error, _reason} ->
        # Couldn't resolve GPS - skip
        :skipped
    end
  end

  defp fix_venue_country(venue, expected_country_code) do
    # Find a city in the expected country
    # Prefer a city with similar name, or fall back to capital/major city
    target_city =
      find_target_city(venue.city_name, expected_country_code) ||
      find_major_city(expected_country_code)

    case target_city do
      nil ->
        IO.puts("[Migration] WARNING: No city found in #{expected_country_code} for venue #{venue.id} (#{venue.name})")
        :error

      city ->
        # Update the venue's city_id using raw SQL
        repo().query(
          "UPDATE venues SET city_id = $1, updated_at = $2 WHERE id = $3",
          [city.id, DateTime.utc_now(), venue.id]
        )

        IO.puts("[Migration] Fixed venue #{venue.id} (#{venue.name}): #{venue.country_code} -> #{expected_country_code}")
        :fixed
    end
  end

  # Try to find a city with the same name in the target country
  defp find_target_city(city_name, country_code) do
    {:ok, result} = repo().query("""
      SELECT c.id, c.name
      FROM cities c
      JOIN countries co ON co.id = c.country_id
      WHERE co.code = $1 AND LOWER(c.name) = LOWER($2)
      LIMIT 1
    """, [country_code, city_name])

    case result.rows do
      [[id, name] | _] -> %{id: id, name: name}
      [] -> nil
    end
  end

  # Find a major city in the target country (fallback)
  defp find_major_city(country_code) do
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
    found = Enum.find_value(cities_to_try, fn city_name ->
      {:ok, result} = repo().query("""
        SELECT c.id, c.name
        FROM cities c
        JOIN countries co ON co.id = c.country_id
        WHERE co.code = $1 AND c.name ILIKE $2
        LIMIT 1
      """, [country_code, "%#{city_name}%"])

      case result.rows do
        [[id, name] | _] -> %{id: id, name: name}
        [] -> nil
      end
    end)

    found ||
      # Last resort: just get any city in that country
      (fn ->
        {:ok, result} = repo().query("""
          SELECT c.id, c.name
          FROM cities c
          JOIN countries co ON co.id = c.country_id
          WHERE co.code = $1
          LIMIT 1
        """, [country_code])

        case result.rows do
          [[id, name] | _] -> %{id: id, name: name}
          [] -> nil
        end
      end).()
  end
end
