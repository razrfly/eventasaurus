defmodule EventasaurusWeb.Services.CocktailDataService do
  @moduledoc """
  Shared service for preparing cocktail data consistently across all interfaces.
  Ensures admin and public interfaces save identical data structures.
  """

  import Phoenix.HTML.SimplifiedHelpers.Truncate
  require Logger

  @doc """
  Prepares cocktail option data in a consistent format for both admin and public interfaces.
  """
  def prepare_cocktail_option_data(cocktail_id, rich_data) do
    # Debug logging to see what we're working with
    Logger.debug("CocktailDataService.prepare_cocktail_option_data called with:")

    Logger.debug(
      "  cocktail_id type: #{inspect(__MODULE__.get_type(cocktail_id))}, value: #{inspect(cocktail_id)}"
    )

    Logger.debug("  rich_data type: #{inspect(__MODULE__.get_type(rich_data))}")

    Logger.debug(
      "  rich_data keys: #{inspect(if is_map(rich_data), do: Map.keys(rich_data), else: :not_a_map)}"
    )

    # Check each field we're trying to extract
    if is_map(rich_data) do
      Logger.debug(
        "  rich_data['title'] type: #{inspect(__MODULE__.get_type(rich_data["title"]))}, value: #{inspect(rich_data["title"])}"
      )

      Logger.debug(
        "  rich_data[:title] type: #{inspect(__MODULE__.get_type(rich_data[:title]))}, value: #{inspect(rich_data[:title])}"
      )
    end

    # Handle both string and atom keys for title
    # Check normalized provider data first (title), then raw API data (name/strDrink)
    title =
      cond do
        is_map(rich_data) and Map.has_key?(rich_data, "title") ->
          to_string_safe(rich_data["title"])

        is_map(rich_data) and Map.has_key?(rich_data, :title) ->
          to_string_safe(rich_data[:title])

        is_map(rich_data) and Map.has_key?(rich_data, "name") ->
          to_string_safe(rich_data["name"])

        is_map(rich_data) and Map.has_key?(rich_data, :name) ->
          to_string_safe(rich_data[:name])

        is_map(rich_data) and Map.has_key?(rich_data, "strDrink") ->
          to_string_safe(rich_data["strDrink"])

        true ->
          ""
      end

    # Handle both normalized and raw data for image URL
    image_url =
      cond do
        is_map(rich_data) and Map.has_key?(rich_data, "image_url") ->
          rich_data["image_url"]

        is_map(rich_data) and Map.has_key?(rich_data, :image_url) ->
          rich_data[:image_url]

        is_map(rich_data) and Map.has_key?(rich_data, "thumbnail") ->
          rich_data["thumbnail"]

        is_map(rich_data) and Map.has_key?(rich_data, :thumbnail) ->
          rich_data[:thumbnail]

        is_map(rich_data) and Map.has_key?(rich_data, "strDrinkThumb") ->
          rich_data["strDrinkThumb"]

        true ->
          nil
      end

    # Handle both normalized and raw data for description
    base_description =
      cond do
        is_map(rich_data) and Map.has_key?(rich_data, "description") ->
          to_string_safe(rich_data["description"]) || ""

        is_map(rich_data) and Map.has_key?(rich_data, :description) ->
          to_string_safe(rich_data[:description]) || ""

        true ->
          to_string_safe(get_instructions(rich_data, "en")) || ""
      end

    # Extract metadata for enhancement (works with both normalized and raw data)
    # Ensure all values are strings or nil
    category =
      to_string_safe(
        get_field(rich_data, ["category", "strCategory"]) ||
          get_in(rich_data, [:metadata, :category])
      )

    alcoholic =
      to_string_safe(
        get_field(rich_data, ["alcoholic", "strAlcoholic"]) ||
          get_in(rich_data, [:metadata, :alcoholic])
      )

    glass =
      to_string_safe(
        get_field(rich_data, ["glass", "strGlass"]) || get_in(rich_data, [:metadata, :glass])
      )

    Logger.debug(
      "  Extracted metadata - category: #{inspect(category)}, alcoholic: #{inspect(alcoholic)}, glass: #{inspect(glass)}"
    )

    # Build enhanced description
    enhanced_description =
      build_enhanced_description(base_description, category, alcoholic, glass, rich_data)

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
      "external_id" => to_string_safe(cocktail_id),
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
            # Ensure ingredient and measure are strings
            ingredient_str =
              to_string_safe(Map.get(ing, :ingredient) || Map.get(ing, "ingredient"))

            measure_str = to_string_safe(Map.get(ing, :measure) || Map.get(ing, "measure"))

            # Guard against missing ingredient to prevent "nil" strings in output
            case {ingredient_str, measure_str} do
              {ing, meas} when ing in [nil, ""] and meas in [nil, ""] -> nil
              {ing, _} when ing in [nil, ""] -> nil
              {ing, meas} when meas in [nil, ""] -> ing
              {ing, meas} -> "#{meas} #{ing}"
            end
          end)
          |> Enum.reject(&(&1 == "" || is_nil(&1)))
          |> Enum.join(", ")

        if ingredients_text != "" do
          ["Ingredients: #{ingredients_text}" | parts]
        else
          parts
        end
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
        is_map(data) and Map.has_key?(data, key) ->
          Map.get(data, key)

        is_map(data) and is_atom(key) and Map.has_key?(data, to_string(key)) ->
          Map.get(data, to_string(key))

        is_map(data) and is_binary(key) and Map.has_key?(data, String.to_atom(key)) ->
          Map.get(data, String.to_atom(key))

        true ->
          nil
      end
    end)
  end

  defp get_field(_data, _keys), do: nil

  # Private helper to safely convert values to strings
  # Returns nil for nil, empty string for empty strings, and converts other types to strings
  defp to_string_safe(nil), do: nil
  defp to_string_safe(""), do: ""
  defp to_string_safe(value) when is_binary(value), do: value
  defp to_string_safe(value) when is_integer(value), do: Integer.to_string(value)
  defp to_string_safe(value) when is_float(value), do: Float.to_string(value)
  defp to_string_safe(value) when is_atom(value), do: Atom.to_string(value)

  defp to_string_safe(%{} = _map) do
    Logger.warning("Attempted to convert a Map to string, returning nil")
    nil
  end

  defp to_string_safe(value) do
    Logger.warning("Unexpected type for string conversion: #{inspect(value)}")
    nil
  end

  # Helper function for debugging types
  @spec get_type(any()) :: atom() | tuple()
  def get_type(nil), do: :nil
  def get_type(value) when is_binary(value), do: :binary
  def get_type(value) when is_integer(value), do: :integer
  def get_type(value) when is_float(value), do: :float
  def get_type(value) when is_atom(value), do: :atom
  def get_type(value) when is_list(value), do: :list
  def get_type(%{}), do: :map
  def get_type(value), do: {:unknown, inspect(value)}
end
