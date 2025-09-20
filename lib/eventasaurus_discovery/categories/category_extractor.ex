defmodule EventasaurusDiscovery.Categories.CategoryExtractor do
  @moduledoc """
  Helper module for extracting and mapping categories from external sources.
  Handles both Ticketmaster API classifications and Karnet scraped categories.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.Categories.CategoryMapping
  import Ecto.Query

  @doc """
  Extract and map categories from Ticketmaster event data.
  Returns a list of {category_id, is_primary} tuples.
  """
  def extract_ticketmaster_categories(tm_event) when is_map(tm_event) do
    # Handle case where tm_event is the full metadata or just ticketmaster_data
    ticketmaster_data = case tm_event do
      %{"ticketmaster_data" => data} -> data
      data -> data
    end

    classifications = ticketmaster_data["classifications"] || []

    # Extract all classification levels
    classifications_list = Enum.flat_map(classifications, fn class ->
      entries = []

      # Get segment (highest priority)
      entries = if segment = get_in(class, ["segment", "name"]) do
        [{"ticketmaster", "segment", segment} | entries]
      else
        entries
      end

      # Get genre
      entries = if genre = get_in(class, ["genre", "name"]) do
        [{"ticketmaster", "genre", genre} | entries]
      else
        entries
      end

      # Get subGenre
      entries = if subgenre = get_in(class, ["subGenre", "name"]) do
        [{"ticketmaster", "subgenre", subgenre} | entries]
      else
        entries
      end

      entries
    end)

    # Apply cross-classification rules to add more categories
    enhanced_classifications = apply_ticketmaster_cross_classification(classifications_list, ticketmaster_data)

    # Map to internal categories
    map_to_categories("ticketmaster", enhanced_classifications)
  end

  @doc """
  Extract and map categories from Karnet event data.
  Returns a list of {category_id, is_primary} tuples.
  """
  def extract_karnet_categories(event_data) when is_map(event_data) do
    # Karnet may have category in different fields
    category_values = []

    # Check main category field
    category_values = if category = event_data[:category] || event_data["category"] do
      [{"karnet", nil, String.downcase(category)} | category_values]
    else
      category_values
    end

    # Check for category in URL
    category_values = if url = event_data[:url] || event_data["url"] do
      extracted = extract_category_from_karnet_url(url)
      if extracted do
        [{"karnet", nil, extracted} | category_values]
      else
        category_values
      end
    else
      category_values
    end

    # Extract additional categories from title and description
    category_values = extract_karnet_secondary_categories(event_data, category_values)

    # Map to internal categories
    map_to_categories("karnet", category_values)
  end

  @doc """
  Extract categories from Bandsintown event data.
  All Bandsintown events are concerts/performances/music events.
  """
  def extract_bandsintown_categories(event_data) when is_map(event_data) do
    # Bandsintown events are all concerts/music events
    # We'll map them to the concerts category
    category_values = [{"bandsintown", nil, "concert"}]

    # Check if there are any genre hints in tags or metadata
    category_values = if tags = event_data[:tags] || event_data["tags"] do
      # Add any genre-specific tags
      additional_values = tags
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.map(fn tag -> {"bandsintown", nil, tag} end)

      category_values ++ additional_values
    else
      category_values
    end

    # Add additional categories based on artist/venue context
    category_values = extract_bandsintown_secondary_categories(event_data, category_values)

    # Map to internal categories
    map_to_categories("bandsintown", category_values)
  end

  @doc """
  Map external category classifications to internal category IDs.
  Returns a list of {category_id, is_primary} tuples with highest priority first.
  """
  def map_to_categories(_source, []), do: []

  def map_to_categories(source, classifications) do
    alias EventasaurusDiscovery.Categories.TranslationLearner

    # Build a dynamic where clause for all classifications
    # We need to build an OR condition between all the classifications
    conditions = Enum.map(classifications, fn {source, type, value} ->
      if type do
        dynamic([m, c],
          m.external_source == ^source and
          m.external_type == ^type and
          fragment("LOWER(?) = LOWER(?)", m.external_value, ^value)
        )
      else
        dynamic([m, c],
          m.external_source == ^source and
          is_nil(m.external_type) and
          fragment("LOWER(?) = LOWER(?)", m.external_value, ^value)
        )
      end
    end)

    # Combine all conditions with OR
    # Start with the first condition and then add the rest
    combined_condition = case conditions do
      [] -> dynamic([m, c], false)
      [first | rest] ->
        Enum.reduce(rest, first, fn condition, acc ->
          dynamic([m, c], ^acc or ^condition)
        end)
    end

    # Now build the query with the combined condition - also get mapping details for translation learning
    query = from m in CategoryMapping,
      join: c in assoc(m, :category),
      where: c.is_active == true,
      where: ^combined_condition,
      order_by: [desc: m.priority],
      select: {c.id, m.priority, m.external_value, m.external_locale, c.slug}

    # Get all matched categories with their priorities and learn translations
    matched_categories = Repo.all(query)

    # Learn translations dynamically from the mappings
    Enum.each(matched_categories, fn {_cat_id, _priority, external_value, external_locale, category_slug} ->
      if external_locale && external_locale != "en" do
        TranslationLearner.learn_translation(category_slug, external_value, external_locale, source)
      end
    end)

    # Group by category ID and take the highest priority for each
    category_priorities = matched_categories
    |> Enum.group_by(fn {cat_id, _, _, _, _} -> cat_id end)
    |> Enum.map(fn {cat_id, priorities} ->
      max_priority = priorities
      |> Enum.map(fn {_, p, _, _, _} -> p end)
      |> Enum.max()
      {cat_id, max_priority}
    end)
    |> Enum.sort_by(fn {_, priority} -> -priority end)

    # Return all categories - first is primary, rest are secondary
    case category_priorities do
      [] -> []
      [{primary_id, _} | rest] ->
        [{primary_id, true}] ++ Enum.map(rest, fn {id, _} -> {id, false} end)
    end
  end

  @doc """
  Assign categories to a public event based on external source data.
  """
  def assign_categories_to_event(event_id, source, external_data) do
    categories = case source do
      "ticketmaster" -> extract_ticketmaster_categories(external_data)
      "karnet" -> extract_karnet_categories(external_data)
      "bandsintown" -> extract_bandsintown_categories(external_data)
      _ -> []
    end

    if length(categories) > 0 do
      category_ids = Enum.map(categories, fn {id, _} -> id end)
      primary_id = case List.first(categories) do
        {id, true} -> id
        _ -> nil
      end

      Categories.assign_categories_to_event(
        event_id,
        category_ids,
        primary_id: primary_id,
        source: source
      )
    else
      {:ok, []}
    end
  end

  # Helper to extract category from Karnet URL patterns
  defp extract_category_from_karnet_url(url) when is_binary(url) do
    patterns = [
      {"festiwal", "festiwale"},
      {"koncert", "koncerty"},
      {"spektakl", "spektakle"},
      {"wystaw", "wystawy"},
      {"film", "film"},
      {"kino", "kino"},
      {"teatr", "teatr"},
      {"opera", "opera"},
      {"balet", "balet"},
      {"taniec", "taniec"}
    ]

    url_lower = String.downcase(url)

    Enum.find_value(patterns, fn {pattern, category} ->
      if String.contains?(url_lower, pattern), do: category, else: nil
    end)
  end

  defp extract_category_from_karnet_url(_), do: nil

  @doc """
  Get category statistics for debugging/monitoring.
  """
  def get_mapping_statistics do
    tm_count = Repo.one(from m in CategoryMapping,
      where: m.external_source == "ticketmaster",
      select: count(m.id))

    karnet_count = Repo.one(from m in CategoryMapping,
      where: m.external_source == "karnet",
      select: count(m.id))

    bandsintown_count = Repo.one(from m in CategoryMapping,
      where: m.external_source == "bandsintown",
      select: count(m.id))

    %{
      ticketmaster_mappings: tm_count,
      karnet_mappings: karnet_count,
      bandsintown_mappings: bandsintown_count,
      total_mappings: tm_count + karnet_count + bandsintown_count
    }
  end

  # Helper functions for extracting secondary categories

  # Apply cross-classification rules for Ticketmaster to add more categories
  defp apply_ticketmaster_cross_classification(classifications, event_data) do
    # Extract the classifications into easier to work with format
    segments = classifications |> Enum.filter(fn {_, type, _} -> type == "segment" end) |> Enum.map(fn {_, _, value} -> value end)
    genres = classifications |> Enum.filter(fn {_, type, _} -> type == "genre" end) |> Enum.map(fn {_, _, value} -> value end)
    subgenres = classifications |> Enum.filter(fn {_, type, _} -> type == "subgenre" end) |> Enum.map(fn {_, _, value} -> value end)

    additional = []

    # Cross-classification rules
    # Music + Jazz = also Arts
    additional = if "Music" in segments and "Jazz" in genres do
      [{"ticketmaster", nil, "arts"} | additional]
    else
      additional
    end

    # Arts & Theatre + any Festival = also Festivals
    additional = if "Arts & Theatre" in segments and ("Fairs & Festivals" in genres or "Festival" in subgenres) do
      [{"ticketmaster", nil, "festivals"} | additional]
    else
      additional
    end

    # Rock/Metal/Electronic = also Nightlife
    additional = if "Music" in segments and (
      "Rock" in genres or "Metal" in genres or "Electronic" in genres or
      "Hard Rock" in subgenres or "Heavy Metal" in subgenres or "Dance/Electronic" in subgenres
    ) do
      [{"ticketmaster", nil, "nightlife"} | additional]
    else
      additional
    end

    # Classical/Opera = also Arts
    additional = if "Music" in segments and (
      "Classical" in genres or "Opera" in genres or
      "Classical" in subgenres or "Opera" in subgenres
    ) do
      [{"ticketmaster", nil, "arts"} | additional]
    else
      additional
    end

    # Comedy = also Nightlife (comedy shows are often in clubs/bars)
    additional = if "Comedy" in genres or "Comedy" in subgenres do
      [{"ticketmaster", nil, "nightlife"} | additional]
    else
      additional
    end

    # Family shows = also Community
    additional = if "Family" in genres or "Children" in subgenres or "Family" in subgenres do
      [{"ticketmaster", nil, "community"} | additional]
    else
      additional
    end

    # Theatre + Music = also Concerts (musicals)
    additional = if "Arts & Theatre" in segments and "Musical" in subgenres do
      [{"ticketmaster", nil, "concerts"} | additional]
    else
      additional
    end

    # Check event title for additional hints
    title = event_data["name"] || ""
    title_lower = String.downcase(title)

    additional = cond do
      String.contains?(title_lower, "festival") -> [{"ticketmaster", nil, "festivals"} | additional]
      String.contains?(title_lower, "workshop") -> [{"ticketmaster", nil, "education"} | additional]
      String.contains?(title_lower, "conference") -> [{"ticketmaster", nil, "business"} | additional]
      String.contains?(title_lower, "gala") -> [{"ticketmaster", nil, "business"} | additional]
      true -> additional
    end

    classifications ++ additional
  end

  defp extract_karnet_secondary_categories(event_data, existing_categories) do
    title = event_data[:title] || event_data["title"] || ""
    description = event_data[:description] || event_data["description"] || ""
    text = "#{title} #{description}" |> String.downcase()

    # Enhanced patterns that can add multiple categories
    secondary_patterns = [
      {"festiwal", ["festival", "concerts"]},  # Festivals are usually also concerts
      {"koncert", ["concert", "nightlife"]},   # Concerts can be nightlife
      {"wystawa", ["exhibition", "arts"]},     # Exhibitions are arts
      {"spektakl", ["performance", "theatre"]},
      {"teatr", ["performance", "theatre", "arts"]},
      {"kino", ["film", "arts"]},
      {"opera", ["opera", "arts", "theatre"]},
      {"balet", ["dance", "arts", "theatre"]},
      {"taniec", ["dance", "nightlife"]},      # Dance events often nightlife
      {"muzyka", ["concert"]},
      {"jazz", ["concert", "arts"]},           # Jazz is both music and arts
      {"rock", ["concert", "nightlife"]},      # Rock concerts are nightlife
      {"dziecko", ["family", "community"]},    # Kids events are community
      {"dzieci", ["family", "community", "education"]},
      {"warsztaty", ["education", "community"]},
      {"konferencja", ["business", "education"]},
      {"spotkanie", ["community"]},
      {"kabaret", ["comedy", "nightlife", "theatre"]},
      {"komedia", ["comedy", "theatre"]},
      {"filmow", ["film", "festival"]},        # Film festivals
      {"muzyczn", ["concert", "festival"]},    # Music festivals
      {"plener", ["festival", "community"]},   # Outdoor events
      {"wernisaż", ["exhibition", "arts", "community"]},  # Art openings
      {"premiera", ["theatre", "arts"]},       # Premieres
    ]

    additional_categories = secondary_patterns
    |> Enum.filter(fn {pattern, _} -> String.contains?(text, pattern) end)
    |> Enum.flat_map(fn {_, categories} ->
      categories |> Enum.map(fn cat -> {"karnet", nil, cat} end)
    end)
    |> Enum.uniq()

    # Only add if not already present
    existing_values = existing_categories |> Enum.map(fn {_, _, value} -> value end)
    new_categories = additional_categories
    |> Enum.reject(fn {_, _, value} -> value in existing_values end)

    existing_categories ++ new_categories
  end

  defp extract_bandsintown_secondary_categories(event_data, existing_categories) do
    # Extract genres from artist data or venue information
    additional_categories = []

    # All Bandsintown events are concerts, so always add nightlife as secondary
    additional_categories = [{"bandsintown", nil, "nightlife"} | additional_categories]

    # Check venue type for more categories
    additional_categories = if venue = event_data[:venue] || event_data["venue"] do
      venue_name = venue[:name] || venue["name"] || ""
      venue_type = venue[:type] || venue["type"] || ""
      venue_text = "#{venue_name} #{venue_type}" |> String.downcase()

      venue_categories = cond do
        String.contains?(venue_text, "festival") -> [{"bandsintown", nil, "festival"}, {"bandsintown", nil, "community"}]
        String.contains?(venue_text, "theater") or String.contains?(venue_text, "theatre") -> [{"bandsintown", nil, "performance"}, {"bandsintown", nil, "arts"}]
        String.contains?(venue_text, "club") or String.contains?(venue_text, "bar") -> [{"bandsintown", nil, "nightlife"}]
        String.contains?(venue_text, "outdoor") or String.contains?(venue_text, "park") -> [{"bandsintown", nil, "festival"}, {"bandsintown", nil, "community"}]
        String.contains?(venue_text, "arena") or String.contains?(venue_text, "stadium") -> [{"bandsintown", nil, "sports"}]  # Large venues
        String.contains?(venue_text, "hall") or String.contains?(venue_text, "auditorium") -> [{"bandsintown", nil, "arts"}]
        true -> []
      end

      additional_categories ++ venue_categories
    else
      additional_categories
    end

    # Check artist genres
    additional_categories = if artist = event_data[:artist] || event_data["artist"] do
      genres = artist[:genres] || artist["genres"] || []

      genre_categories = genres
      |> Enum.filter(&is_binary/1)
      |> Enum.flat_map(fn genre ->
        genre_lower = String.downcase(genre)
        cond do
          String.contains?(genre_lower, "jazz") -> [{"bandsintown", nil, "arts"}, {"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "classical") -> [{"bandsintown", nil, "arts"}, {"bandsintown", nil, "theatre"}]
          String.contains?(genre_lower, "opera") -> [{"bandsintown", nil, "arts"}, {"bandsintown", nil, "theatre"}]
          String.contains?(genre_lower, "folk") -> [{"bandsintown", nil, "community"}, {"bandsintown", nil, "arts"}]
          String.contains?(genre_lower, "comedy") -> [{"bandsintown", nil, "comedy"}, {"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "electronic") -> [{"bandsintown", nil, "nightlife"}, {"bandsintown", nil, "festivals"}]
          String.contains?(genre_lower, "dance") -> [{"bandsintown", nil, "nightlife"}, {"bandsintown", nil, "arts"}]
          String.contains?(genre_lower, "rock") -> [{"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "metal") -> [{"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "punk") -> [{"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "hip") or String.contains?(genre_lower, "rap") -> [{"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "blues") -> [{"bandsintown", nil, "arts"}, {"bandsintown", nil, "nightlife"}]
          String.contains?(genre_lower, "country") -> [{"bandsintown", nil, "community"}]
          String.contains?(genre_lower, "reggae") -> [{"bandsintown", nil, "community"}, {"bandsintown", nil, "nightlife"}]
          true -> []
        end
      end)

      additional_categories ++ genre_categories
    else
      additional_categories
    end

    # Only add if not already present
    existing_values = existing_categories |> Enum.map(fn {_, _, value} -> value end)
    new_categories = additional_categories
    |> Enum.reject(fn {_, _, value} -> value in existing_values end)
    |> Enum.uniq()

    existing_categories ++ new_categories
  end
end