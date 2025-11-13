defmodule EventasaurusWeb.Services.CocktailDataService do
  @moduledoc """
  Shared service for preparing cocktail data consistently across all interfaces.
  Ensures admin and public interfaces save identical data structures.
  """

  import Phoenix.HTML.SimplifiedHelpers.Truncate

  @doc """
  Prepares cocktail option data in a consistent format for both admin and public interfaces.
  """
  def prepare_cocktail_option_data(cocktail_id, rich_data) do
    # Handle both string and atom keys for title
    # Check normalized provider data first (title), then raw API data (name/strDrink)
    title =
      cond do
        is_map(rich_data) and Map.has_key?(rich_data, "title") -> rich_data["title"]
        is_map(rich_data) and Map.has_key?(rich_data, :title) -> rich_data[:title]
        is_map(rich_data) and Map.has_key?(rich_data, "name") -> rich_data["name"]
        is_map(rich_data) and Map.has_key?(rich_data, :name) -> rich_data[:name]
        is_map(rich_data) and Map.has_key?(rich_data, "strDrink") -> rich_data["strDrink"]
        true -> ""
      end

    # Handle both normalized and raw data for image URL
    image_url =
      cond do
        is_map(rich_data) and Map.has_key?(rich_data, "image_url") -> rich_data["image_url"]
        is_map(rich_data) and Map.has_key?(rich_data, :image_url) -> rich_data[:image_url]
        is_map(rich_data) and Map.has_key?(rich_data, "thumbnail") -> rich_data["thumbnail"]
        is_map(rich_data) and Map.has_key?(rich_data, :thumbnail) -> rich_data[:thumbnail]
        is_map(rich_data) and Map.has_key?(rich_data, "strDrinkThumb") -> rich_data["strDrinkThumb"]
        true -> nil
      end

    # Handle both normalized and raw data for description
    base_description =
      cond do
        is_map(rich_data) and Map.has_key?(rich_data, "description") -> rich_data["description"]
        is_map(rich_data) and Map.has_key?(rich_data, :description) -> rich_data[:description]
        true -> get_instructions(rich_data, "en") || ""
      end

    # Extract metadata for enhancement (works with both normalized and raw data)
    category = get_field(rich_data, ["category", "strCategory"]) || get_in(rich_data, [:metadata, :category])
    alcoholic = get_field(rich_data, ["alcoholic", "strAlcoholic"]) || get_in(rich_data, [:metadata, :alcoholic])
    glass = get_field(rich_data, ["glass", "strGlass"]) || get_in(rich_data, [:metadata, :glass])

    # Build enhanced description
    enhanced_description = build_enhanced_description(base_description, category, alcoholic, glass, rich_data)

    # Truncate description to fit within 1000 character limit
    truncated_description =
      if is_binary(enhanced_description) do
        # Truncate at word boundary with 980 char limit to leave buffer
        truncate(enhanced_description, length: 980, separator: " ")
      else
        enhanced_description
      end

    %{
      "title" => title,
      "description" => truncated_description,
      "external_id" => to_string(cocktail_id),
      "external_data" => rich_data,
      "image_url" => image_url
    }
  end

  @doc """
  Builds an enhanced description with cocktail details.
  """
  def build_enhanced_description(base_instructions, category, alcoholic, glass, rich_data) do
    parts = []

    # Add category and type
    parts =
      if category || alcoholic do
        category_text =
          case {category, alcoholic} do
            {nil, alcoholic} -> alcoholic
            {category, nil} -> category
            {category, alcoholic} -> "#{category} • #{alcoholic}"
          end

        [category_text | parts]
      else
        parts
      end

    # Add glass type
    parts =
      if glass do
        ["Served in: #{glass}" | parts]
      else
        parts
      end

    # Add ingredients
    ingredients = extract_ingredients(rich_data)

    parts =
      if length(ingredients) > 0 do
        ingredients_text =
          ingredients
          |> Enum.map(fn ing ->
            if ing.measure do
              "#{ing.measure} #{ing.ingredient}"
            else
              ing.ingredient
            end
          end)
          |> Enum.join(", ")

        ["Ingredients: #{ingredients_text}" | parts]
      else
        parts
      end

    # Add instructions
    parts =
      if base_instructions && base_instructions != "" do
        [base_instructions | parts]
      else
        parts
      end

    # Combine all parts
    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  @doc """
  Extracts ingredients list from cocktail data.
  """
  def extract_ingredients(rich_data) do
    get_field(rich_data, ["ingredients"]) || []
  end

  @doc """
  Gets the cocktail category.
  """
  def get_category(rich_data) do
    get_field(rich_data, ["category", "strCategory"])
  end

  @doc """
  Gets the alcoholic/non-alcoholic status.
  """
  def get_alcoholic(rich_data) do
    get_field(rich_data, ["alcoholic", "strAlcoholic"])
  end

  @doc """
  Gets the glass type.
  """
  def get_glass(rich_data) do
    get_field(rich_data, ["glass", "strGlass"])
  end

  @doc """
  Gets the thumbnail/image URL.
  """
  def get_image_url(rich_data) do
    get_field(rich_data, ["thumbnail", "strDrinkThumb"])
  end

  @doc """
  Gets instructions in the specified language (defaults to English).
  """
  def get_instructions(rich_data, lang \\ "en") do
    instructions_field = get_field(rich_data, ["instructions", "strInstructions"])

    case instructions_field do
      # If it's a map with language keys (from CocktailDB provider), extract the specific language
      %{} = map ->
        lang_atom = if is_atom(lang), do: lang, else: String.to_atom(lang)
        Map.get(map, lang_atom) || Map.get(map, to_string(lang))

      # If it's already a string, return it
      text when is_binary(text) ->
        text

      # Otherwise return nil
      _ ->
        nil
    end
  end

  # Private helper to get field from map with multiple possible keys
  defp get_field(data, keys) when is_list(keys) do
    Enum.find_value(keys, fn key ->
      cond do
        is_map(data) and Map.has_key?(data, key) -> Map.get(data, key)
        is_map(data) and is_atom(key) and Map.has_key?(data, to_string(key)) -> Map.get(data, to_string(key))
        is_map(data) and is_binary(key) and Map.has_key?(data, String.to_atom(key)) -> Map.get(data, String.to_atom(key))
        true -> nil
      end
    end)
  end

  defp get_field(_data, _keys), do: nil
end
