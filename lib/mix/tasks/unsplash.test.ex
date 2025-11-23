defmodule Mix.Tasks.Unsplash.Test do
  @moduledoc """
  Test task to fetch Unsplash images for active cities.

  Always fetches all 5 categories (general, architecture, historic, old_town, city_landmarks).

  Usage:
    mix unsplash.test                    # Fetch images for all active cities
    mix unsplash.test London              # Fetch images for specific city
  """
  use Mix.Task

  @shortdoc "Test Unsplash image fetching for active cities"

  def run(args) do
    Mix.Task.run("app.start")

    alias EventasaurusApp.Services.UnsplashImageFetcher
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Locations.City
    import Ecto.Query

    # Parse city name from arguments
    city_name =
      case Enum.map(args, &String.trim/1) |> Enum.reject(&(&1 == "")) do
        [] -> nil
        parts -> Enum.join(parts, " ")
      end

    if city_name do
      # Fetch for single city
      fetch_single_city(city_name)
    else
      # Fetch for all active cities
      IO.puts("\n🌆 Fetching Unsplash images for all active cities")
      IO.puts(String.duplicate("=", 60))

      query =
        from(c in City,
          where: c.discovery_enabled == true,
          order_by: c.name
        )

      active_cities = Repo.all(query)

      IO.puts(
        "Found #{length(active_cities)} active cities: #{Enum.join(Enum.map(active_cities, & &1.name), ", ")}"
      )

      Enum.each(active_cities, fn city ->
        IO.puts("\n📍 Fetching for #{city.name}...")

        case UnsplashImageFetcher.fetch_and_store_all_categories(city) do
          {:ok, updated_city} ->
            categories = get_in(updated_city.unsplash_gallery, ["categories"]) || %{}

            total_images =
              Enum.reduce(categories, 0, fn {_name, data}, acc ->
                acc + length(Map.get(data, "images", []))
              end)

            IO.puts(
              "  ✅ Success! Fetched #{map_size(categories)} categories with #{total_images} total images"
            )

          {:error, reason} ->
            IO.puts("  ❌ Error: #{inspect(reason)}")
        end

        # Rate limiting - configurable via env, defaults to production rate (5000/hour = ~1.4/sec = 720ms)
        # For dev environment (50/hour), set UNSPLASH_TEST_THROTTLE_MS=72000
        throttle_ms = System.get_env("UNSPLASH_TEST_THROTTLE_MS", "1000") |> String.to_integer()
        Process.sleep(throttle_ms)
      end)

      IO.puts("\n✨ Done!")
    end
  end

  # Helper function for single city
  defp fetch_single_city(city_name) do
    alias EventasaurusApp.Services.UnsplashImageFetcher
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Locations.City

    IO.puts("\n🌆 Fetching Unsplash images for: #{city_name}")
    IO.puts(String.duplicate("=", 60))

    IO.puts(
      "Fetching all 5 categories: general, architecture, historic, old_town, city_landmarks"
    )

    city = Repo.get_by(City, name: city_name)

    case city do
      nil ->
        IO.puts("❌ Error: City '#{city_name}' not found")

      city ->
        case UnsplashImageFetcher.fetch_and_store_all_categories(city) do
          {:ok, updated_city} ->
            categories = get_in(updated_city.unsplash_gallery, ["categories"]) || %{}
            IO.puts("✅ Success! Fetched #{map_size(categories)} categories")

            IO.puts("\nCategory breakdown:")

            Enum.each(categories, fn {category_name, category_data} ->
              images = Map.get(category_data, "images", [])
              search_terms = Map.get(category_data, "search_terms", [])

              IO.puts(
                "  • #{category_name}: #{length(images)} images (search: #{List.first(search_terms)})"
              )
            end)

          {:error, reason} ->
            IO.puts("❌ Error: #{inspect(reason)}")
        end
    end
  end
end
