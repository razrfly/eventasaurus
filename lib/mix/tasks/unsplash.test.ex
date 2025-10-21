defmodule Mix.Tasks.Unsplash.Test do
  @moduledoc """
  Test task to fetch Unsplash images for active cities.

  Usage:
    mix unsplash.test
    mix unsplash.test London
  """
  use Mix.Task

  @shortdoc "Test Unsplash image fetching for active cities"

  def run(args) do
    Mix.Task.run("app.start")

    alias EventasaurusApp.Services.UnsplashImageFetcher
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Locations.City
    import Ecto.Query

    city_name = case args do
      [name] -> name
      _ -> nil
    end

    if city_name do
      # Test single city
      IO.puts("\n🌆 Testing Unsplash fetch for: #{city_name}")
      IO.puts(String.duplicate("=", 60))

      case UnsplashImageFetcher.fetch_and_store_city_images(city_name) do
        {:ok, gallery} ->
          IO.puts("✅ Success! Fetched #{length(gallery["images"])} images")
          IO.puts("\nGallery structure:")
          IO.inspect(Map.keys(gallery), label: "Keys")
          IO.puts("\nFirst image sample:")
          IO.inspect(List.first(gallery["images"]), pretty: true, limit: :infinity)

        {:error, reason} ->
          IO.puts("❌ Error: #{inspect(reason)}")
      end
    else
      # Test all active cities
      IO.puts("\n🌆 Testing Unsplash fetch for all active cities")
      IO.puts(String.duplicate("=", 60))

      query = from c in City,
        where: c.discovery_enabled == true,
        select: c.name

      active_cities = Repo.all(query)
      IO.puts("Found #{length(active_cities)} active cities: #{Enum.join(active_cities, ", ")}")

      Enum.each(active_cities, fn city_name ->
        IO.puts("\n📍 Fetching for #{city_name}...")

        case UnsplashImageFetcher.fetch_and_store_city_images(city_name) do
          {:ok, gallery} ->
            IO.puts("  ✅ Success! Fetched #{length(gallery["images"])} images")

          {:error, reason} ->
            IO.puts("  ❌ Error: #{inspect(reason)}")
        end

        # Rate limiting - 5000/hour = ~1.4 per second
        Process.sleep(1000)
      end)

      IO.puts("\n✨ Done!")
    end
  end
end
