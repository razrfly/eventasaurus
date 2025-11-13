defmodule EventasaurusWeb.Services.CocktailDbRichDataProvider do
  @moduledoc """
  CocktailDB provider for rich data integration.

  Implements the RichDataProviderBehaviour for cocktail data.
  Wraps the existing CocktailDbService with the standardized provider interface.
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  alias EventasaurusWeb.Services.CocktailDbService
  require Logger

  # ============================================================================
  # Provider Behaviour Implementation
  # ============================================================================

  @impl true
  def provider_id, do: :cocktaildb

  @impl true
  def provider_name, do: "The CocktailDB"

  @impl true
  def supported_types, do: [:cocktail]

  @impl true
  def search(query, options \\ %{}) do
    limit = Map.get(options, :limit, 10)

    case CocktailDbService.search_cocktails(query) do
      {:ok, results} ->
        # Apply limit to results
        limited_results =
          results
          |> Enum.take(limit)
          |> Enum.map(&normalize_search_result/1)

        {:ok, limited_results}

      {:error, reason} ->
        Logger.error("CocktailDB search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_details(id, _type, _options \\ %{}) do
    case CocktailDbService.get_cocktail_details(id) do
      {:ok, cocktail_data} ->
        {:ok, normalize_cocktail_details(cocktail_data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_cached_details(id, _type, _options \\ %{}) do
    case CocktailDbService.get_cached_cocktail_details(id) do
      {:ok, cocktail_data} ->
        {:ok, normalize_cocktail_details(cocktail_data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def validate_config do
    # CocktailDB has a free tier with API key "1"
    # Optionally check for a custom API key for Patreon supporters
    :ok
  end

  @impl true
  def config_schema do
    %{
      api_key: %{
        type: :string,
        required: false,
        default: "1",
        description: "CocktailDB API key (use '1' for free tier, Patreon key for premium)"
      },
      base_url: %{
        type: :string,
        required: false,
        default: "https://www.thecocktaildb.com/api/json/v1",
        description: "CocktailDB API base URL"
      },
      rate_limit: %{
        type: :integer,
        required: false,
        default: 1,
        description: "Maximum requests per second (conservative for free tier)"
      },
      cache_ttl: %{
        type: :integer,
        required: false,
        # 24 hours in seconds
        default: 86400,
        description: "Cache time-to-live in seconds"
      }
    }
  end

  # ============================================================================
  # Private Functions - Data Normalization
  # ============================================================================

  defp normalize_search_result(result) do
    %{
      id: result.id,
      type: :cocktail,
      title: result.name,
      description: build_short_description(result),
      image_url: result.thumbnail,
      images: build_images_list(result.thumbnail),
      metadata: %{
        category: result.category,
        alcoholic: result.alcoholic,
        glass: result.glass,
        ingredients: result.ingredients || []
      }
    }
  end

  defp normalize_cocktail_details(cocktail_data) do
    %{
      id: cocktail_data.cocktail_id,
      type: :cocktail,
      title: cocktail_data.name,
      description: cocktail_data.instructions || "",
      image_url: cocktail_data.thumbnail,
      images: build_images_list(cocktail_data.thumbnail),
      metadata: %{
        category: cocktail_data.category,
        alcoholic: cocktail_data.alcoholic,
        glass: cocktail_data.glass,
        iba_category: cocktail_data.iba_category,
        tags: cocktail_data.tags || [],
        video: cocktail_data.video,
        date_modified: cocktail_data.date_modified
      },
      ingredients: cocktail_data.ingredients || [],
      instructions: %{
        en: cocktail_data.instructions,
        es: cocktail_data.instructions_es,
        de: cocktail_data.instructions_de,
        fr: cocktail_data.instructions_fr,
        it: cocktail_data.instructions_it
      },
      external_urls: %{
        cocktaildb: "https://www.thecocktaildb.com/drink/#{cocktail_data.cocktail_id}"
      },
      additional_data: %{
        source: "cocktaildb",
        image_source: cocktail_data.image_source,
        image_attribution: cocktail_data.image_attribution,
        creative_commons: cocktail_data.creative_commons_confirmed
      }
    }
  end

  defp build_short_description(result) do
    parts = []

    parts =
      if result.category do
        [result.category | parts]
      else
        parts
      end

    parts =
      if result.alcoholic do
        [result.alcoholic | parts]
      else
        parts
      end

    parts =
      if result.glass do
        ["Served in #{result.glass}" | parts]
      else
        parts
      end

    if length(parts) > 0 do
      Enum.join(parts, " • ")
    else
      result.instructions || ""
    end
  end

  defp build_images_list(thumbnail_url) when is_binary(thumbnail_url) do
    [
      %{
        url: thumbnail_url,
        type: :thumbnail,
        size: "large"
      }
    ]
  end

  defp build_images_list(_), do: []
end
