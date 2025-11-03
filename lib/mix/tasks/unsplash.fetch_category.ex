defmodule Mix.Tasks.Unsplash.FetchCategory do
  @moduledoc """
  Fetch Unsplash images for a specific category for a city.

  Usage:
    mix unsplash.fetch_category <city_name> <category>
    mix unsplash.fetch_category Warsaw general
    mix unsplash.fetch_category "Warsaw" architecture
    mix unsplash.fetch_category Warsaw all  # Fetch all core categories

  Available categories:
    - general: Default, most popular city images
    - architecture: Buildings, modern structures, architectural details
    - historic: Historic buildings, monuments, heritage sites
    - old_town: Medieval areas, old town squares, traditional architecture
    - city_landmarks: Famous landmarks, tourist attractions, iconic views
    - all: Fetch all core categories (general, architecture, historic, old_town, city_landmarks)
  """
  use Mix.Task

  @shortdoc "Fetch Unsplash images for a specific category"

  # Core category definitions with search terms
  @category_definitions %{
    "general" => %{
      description: "Default, most popular city images",
      search_terms_template: ["{city}", "{city} cityscape", "{city} skyline"]
    },
    "architecture" => %{
      description: "Buildings, modern structures, architectural details",
      search_terms_template: ["{city} architecture", "{city} buildings", "{city} modern"]
    },
    "historic" => %{
      description: "Historic buildings, monuments, heritage sites",
      search_terms_template: ["{city} historic", "{city} monument", "{city} heritage"]
    },
    "old_town" => %{
      description: "Medieval areas, old town squares, traditional architecture",
      search_terms_template: ["{city} old town", "{city} medieval", "{city} traditional"]
    },
    "city_landmarks" => %{
      description: "Famous landmarks, tourist attractions, iconic views",
      search_terms_template: ["{city} landmarks", "{city} famous", "{city} attractions"]
    }
  }

  @core_categories ["general", "architecture", "historic", "old_town", "city_landmarks"]

  def run(args) do
    Mix.Task.run("app.start")

    case parse_args(args) do
      {:ok, city_name, "all"} ->
        fetch_all_categories(city_name)

      {:ok, city_name, category} ->
        fetch_single_category(city_name, category)

      {:error, :invalid_args} ->
        IO.puts("\n❌ Error: Invalid arguments")
        IO.puts("\nUsage:")
        IO.puts("  mix unsplash.fetch_category <city_name> <category>")
        IO.puts("  mix unsplash.fetch_category Warsaw general")
        IO.puts("  mix unsplash.fetch_category Warsaw all")
        IO.puts("\nAvailable categories:")
        print_available_categories()

      {:error, :invalid_category, category} ->
        IO.puts("\n❌ Error: Invalid category '#{category}'")
        IO.puts("\nAvailable categories:")
        print_available_categories()
    end
  end

  defp parse_args([]), do: {:error, :invalid_args}
  defp parse_args([_city]), do: {:error, :invalid_args}

  defp parse_args(args) do
    # Join all args except last as city name (handles multi-word cities)
    {city_parts, [category]} = Enum.split(args, -1)
    city_name = Enum.join(city_parts, " ")

    category_lower = String.downcase(category)

    cond do
      city_name == "" or category_lower == "" ->
        {:error, :invalid_args}

      category_lower == "all" ->
        {:ok, city_name, "all"}

      Map.has_key?(@category_definitions, category_lower) ->
        {:ok, city_name, category_lower}

      true ->
        {:error, :invalid_category, category}
    end
  end

  defp fetch_all_categories(city_name) do
    IO.puts("\n🌆 Fetching all core categories for: #{city_name}")
    IO.puts(String.duplicate("=", 60))

    # Verify city exists first
    city = EventasaurusApp.Repo.get_by(EventasaurusDiscovery.Locations.City, name: city_name)

    cond do
      is_nil(city) ->
        IO.puts("❌ City not found: #{city_name}")

      !city.discovery_enabled ->
        IO.puts("❌ City #{city_name} is not active (discovery_enabled = false)")

      true ->
        Enum.each(@core_categories, fn category ->
          IO.puts("\n📍 Fetching category: #{category}")

          case fetch_single_category(city_name, category, false) do
            :ok ->
              IO.puts("  ✅ Success!")

            :error ->
              IO.puts("  ❌ Failed")
          end

          # Rate limiting
          throttle_ms = System.get_env("UNSPLASH_TEST_THROTTLE_MS", "1000") |> String.to_integer()
          Process.sleep(throttle_ms)
        end)

        IO.puts("\n✨ Done! Fetched all #{length(@core_categories)} categories.")
    end
  end

  defp fetch_single_category(city_name, category, verbose \\ true) do
    if verbose do
      IO.puts("\n🌆 Fetching category '#{category}' for: #{city_name}")
      IO.puts(String.duplicate("=", 60))
    end

    # Get category definition
    category_def = @category_definitions[category]

    if is_nil(category_def) do
      IO.puts("❌ Invalid category: #{category}")
      :error
    else
      # Build search terms by replacing {city} with actual city name
      search_terms =
        Enum.map(category_def.search_terms_template, fn template ->
          String.replace(template, "{city}", city_name)
        end)

      if verbose do
        IO.puts("\nCategory: #{category}")
        IO.puts("Description: #{category_def.description}")
        IO.puts("Search terms: #{Enum.join(search_terms, ", ")}")
      end

      # Fetch category images
      case EventasaurusApp.Services.UnsplashImageFetcher.fetch_category_images(
             city_name,
             category,
             search_terms
           ) do
        {:ok, category_data} ->
          # Store the category
          city =
            EventasaurusApp.Repo.get_by(EventasaurusDiscovery.Locations.City, name: city_name)

          case EventasaurusApp.Services.UnsplashImageFetcher.store_category(
                 city,
                 category,
                 category_data
               ) do
            {:ok, _gallery} ->
              image_count = length(category_data["images"])

              if verbose do
                IO.puts("\n✅ Success! Fetched #{image_count} images for category '#{category}'")
                IO.puts("\nFirst image sample:")
                IO.inspect(List.first(category_data["images"]), pretty: true, limit: :infinity)
              end

              :ok

            {:error, reason} ->
              IO.puts("❌ Error storing category: #{inspect(reason)}")
              :error
          end

        {:error, reason} ->
          IO.puts("❌ Error fetching images: #{inspect(reason)}")
          :error
      end
    end
  end

  defp print_available_categories do
    Enum.each(@category_definitions, fn {name, def} ->
      IO.puts("  - #{name}: #{def.description}")
    end)

    IO.puts("  - all: Fetch all core categories")
  end
end
