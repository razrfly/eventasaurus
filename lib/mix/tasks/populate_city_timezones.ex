defmodule Mix.Tasks.PopulateCityTimezones do
  @moduledoc """
  Populate timezone column for all cities based on their coordinates.

  This is a one-time migration task to pre-compute timezones at the city level,
  eliminating runtime TzWorld calls. See Issue #3334 for full analysis.

  ## Usage

      # Populate all cities missing timezone
      mix populate_city_timezones

      # Force repopulate all cities (even those with timezone set)
      mix populate_city_timezones --force

      # Dry run - show what would be updated without making changes
      mix populate_city_timezones --dry-run

      # Populate specific city by ID
      mix populate_city_timezones --city-id=123

  ## How it works

  1. For cities WITH coordinates: Uses TzWorld.timezone_at() to determine timezone
  2. For cities WITHOUT coordinates: Uses TimezoneMapper country fallback
  3. Updates city.timezone field with IANA timezone identifier

  ## Production Usage

  Mix tasks aren't available in production releases. Use the release task instead,
  which enqueues Oban jobs to process cities in the background:

      # Enqueue jobs for cities missing timezone
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs()"

      # Force enqueue for ALL cities (even those with timezone set)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs(true)"

  Note: The release task enqueues background jobs rather than processing synchronously.
  Monitor progress in the Oban dashboard or logs.
  """

  use Mix.Task
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Helpers.TimezoneMapper

  require Logger

  @shortdoc "Populate city timezone column from coordinates"

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [
          city_id: :integer,
          force: :boolean,
          dry_run: :boolean
        ],
        aliases: [
          c: :city_id,
          f: :force,
          d: :dry_run
        ]
      )

    force = Keyword.get(parsed, :force, false)
    dry_run = Keyword.get(parsed, :dry_run, false)

    if dry_run do
      IO.puts("🔍 DRY RUN MODE - No changes will be made\n")
    end

    case Keyword.get(parsed, :city_id) do
      nil -> populate_all_cities(force, dry_run)
      city_id -> populate_single_city(city_id, force, dry_run)
    end
  end

  defp populate_all_cities(force, dry_run) do
    query =
      if force do
        from(c in City,
          left_join: country in assoc(c, :country),
          preload: [country: country],
          order_by: [asc: c.id]
        )
      else
        from(c in City,
          left_join: country in assoc(c, :country),
          where: is_nil(c.timezone),
          preload: [country: country],
          order_by: [asc: c.id]
        )
      end

    cities = Repo.all(query)

    if Enum.empty?(cities) do
      IO.puts("✅ All cities already have timezones populated!")

      return_stats(%{
        total: 0,
        updated: 0,
        skipped: 0,
        errors: 0,
        from_coords: 0,
        from_country: 0
      })
    else
      IO.puts("🌍 Populating timezones for #{length(cities)} cities...\n")

      stats =
        Enum.reduce(
          cities,
          %{total: 0, updated: 0, skipped: 0, errors: 0, from_coords: 0, from_country: 0},
          fn city, acc ->
            result = populate_city_timezone(city, dry_run)
            update_stats(acc, result)
          end
        )

      IO.puts("")
      return_stats(stats)
    end
  end

  defp populate_single_city(city_id, force, dry_run) do
    case Repo.get(City, city_id) |> Repo.preload(:country) do
      nil ->
        IO.puts("❌ City with ID #{city_id} not found")

      %{timezone: tz} = city when not is_nil(tz) and not force ->
        IO.puts("ℹ️  City #{city.name} already has timezone: #{tz}")
        IO.puts("   Use --force to overwrite")

      city ->
        IO.puts("🌍 Populating timezone for #{city.name}...")
        result = populate_city_timezone(city, dry_run)

        case result do
          {:updated, tz, source} ->
            IO.puts(
              "✅ #{if dry_run, do: "Would set", else: "Set"} timezone to #{tz} (from #{source})"
            )

          {:error, reason} ->
            IO.puts("❌ Error: #{reason}")
        end
    end
  end

  defp populate_city_timezone(city, dry_run) do
    case get_timezone_for_city(city) do
      {:ok, timezone, source} ->
        if dry_run do
          IO.write(".")
          {:updated, timezone, source}
        else
          case update_city_timezone(city, timezone) do
            {:ok, _} ->
              IO.write(".")
              {:updated, timezone, source}

            {:error, reason} ->
              IO.write("x")

              Logger.error(
                "Failed to update timezone for city #{city.id} (#{city.name}): #{inspect(reason)}"
              )

              {:error, inspect(reason)}
          end
        end

      {:error, reason} ->
        IO.write("x")

        Logger.warning(
          "Could not determine timezone for city #{city.id} (#{city.name}): #{reason}"
        )

        {:error, reason}
    end
  end

  defp get_timezone_for_city(%{latitude: lat, longitude: lng} = city)
       when not is_nil(lat) and not is_nil(lng) do
    # Convert Decimal to float if needed
    lat_float = to_float(lat)
    lng_float = to_float(lng)

    case TzWorld.timezone_at({lng_float, lat_float}) do
      {:ok, timezone} ->
        {:ok, timezone, :coordinates}

      {:error, :time_zone_not_found} ->
        # Fallback to country-level timezone
        get_timezone_from_country(city)

      {:error, reason} ->
        Logger.warning(
          "TzWorld error for city #{city.name}: #{inspect(reason)}, trying country fallback"
        )

        get_timezone_from_country(city)
    end
  end

  defp get_timezone_for_city(city) do
    # No coordinates - use country fallback
    get_timezone_from_country(city)
  end

  defp get_timezone_from_country(%{country: %{code: code}} = _city) when is_binary(code) do
    timezone = TimezoneMapper.get_timezone_for_country(code)

    if timezone == "Etc/UTC" do
      {:error, "No timezone mapping for country #{code}"}
    else
      {:ok, timezone, :country_fallback}
    end
  end

  defp get_timezone_from_country(_city) do
    {:error, "No coordinates and no country association"}
  end

  defp update_city_timezone(city, timezone) do
    city
    |> City.timezone_changeset(timezone)
    |> Repo.update()
  end

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp update_stats(acc, {:updated, _tz, :coordinates}) do
    %{acc | total: acc.total + 1, updated: acc.updated + 1, from_coords: acc.from_coords + 1}
  end

  defp update_stats(acc, {:updated, _tz, :country_fallback}) do
    %{acc | total: acc.total + 1, updated: acc.updated + 1, from_country: acc.from_country + 1}
  end

  defp update_stats(acc, {:error, _}) do
    %{acc | total: acc.total + 1, errors: acc.errors + 1}
  end

  defp return_stats(stats) do
    IO.puts("")
    IO.puts("📊 Results:")
    IO.puts("   Total processed: #{stats.total}")
    IO.puts("   Updated: #{stats.updated}")
    IO.puts("     - From coordinates: #{stats.from_coords}")
    IO.puts("     - From country fallback: #{stats.from_country}")
    IO.puts("   Errors: #{stats.errors}")

    if stats.errors > 0 do
      IO.puts("")
      IO.puts("⚠️  Some cities could not be updated. Check logs for details.")
    end

    stats
  end
end
