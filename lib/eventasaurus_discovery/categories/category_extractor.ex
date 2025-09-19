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
    classifications = tm_event["classifications"] || []

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
        [{"ticketmaster", "subGenre", subgenre} | entries]
      else
        entries
      end

      entries
    end)

    # Map to internal categories
    map_to_categories("ticketmaster", classifications_list)
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

    # Map to internal categories
    map_to_categories("bandsintown", category_values)
  end

  @doc """
  Map external category classifications to internal category IDs.
  Returns a list of {category_id, is_primary} tuples with highest priority first.
  """
  def map_to_categories(_source, []), do: []

  def map_to_categories(_source, classifications) do
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

    # Now build the query with the combined condition
    query = from m in CategoryMapping,
      join: c in assoc(m, :category),
      where: c.is_active == true,
      where: ^combined_condition,
      order_by: [desc: m.priority],
      select: {c.id, m.priority}

    # Get all matched categories with their priorities
    matched_categories = Repo.all(query)

    # Group by category ID and take the highest priority for each
    category_priorities = matched_categories
    |> Enum.group_by(fn {cat_id, _} -> cat_id end)
    |> Enum.map(fn {cat_id, priorities} ->
      max_priority = priorities
      |> Enum.map(fn {_, p} -> p end)
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

    %{
      ticketmaster_mappings: tm_count,
      karnet_mappings: karnet_count,
      total_mappings: tm_count + karnet_count
    }
  end
end