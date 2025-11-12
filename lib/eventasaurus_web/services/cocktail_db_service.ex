defmodule EventasaurusWeb.Services.CocktailDbService do
  @moduledoc """
  Service for interacting with The CocktailDB API.
  Supports cocktail search and detailed data fetching with caching.

  API Documentation: https://www.thecocktaildb.com/api.php
  """

  use GenServer
  require Logger

  @base_url "https://www.thecocktaildb.com/api/json/v1"
  @cache_table :cocktail_db_cache
  # Cache for 24 hours (cocktails don't change often)
  @cache_ttl :timer.hours(24)
  @rate_limit_table :cocktail_db_rate_limit
  # 1 second window
  @rate_limit_window :timer.seconds(1)
  # Conservative rate limit for free tier
  @rate_limit_max_requests 1

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get cached cocktail details or fetch from API if not cached.
  This is the recommended way to get cocktail details for performance.
  """
  def get_cached_cocktail_details(cocktail_id) do
    GenServer.call(__MODULE__, {:get_cached_cocktail_details, cocktail_id}, 30_000)
  end

  @doc """
  Get detailed cocktail information including ingredients and instructions.
  This bypasses the cache and always fetches fresh data.
  """
  def get_cocktail_details(cocktail_id) do
    with :ok <- check_rate_limit(),
         {:ok, api_key} <- get_api_key() do
      fetch_cocktail_details(cocktail_id, api_key)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for cocktails by name.
  Returns a list of cocktail maps with basic information.

  ## Examples

      iex> search_cocktails("margarita")
      {:ok, [%{id: "11007", name: "Margarita", ...}]}
  """
  def search_cocktails(query) when is_binary(query) do
    # Handle nil or empty queries
    if String.trim(query) == "" do
      {:ok, []}
    else
      with :ok <- check_rate_limit(),
           {:ok, api_key} <- get_api_key() do
        fetch_cocktails_by_name(query, api_key)
      else
        {:error, :rate_limited} ->
          {:error, "Rate limit exceeded, please try again later"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get popular cocktails by category.
  Returns list of cocktails with basic info.

  Categories: Ordinary Drink, Cocktail, Shot, Coffee / Tea, Beer, etc.
  """
  def get_cocktails_by_category(category \\ "Cocktail") do
    with :ok <- check_rate_limit(),
         {:ok, api_key} <- get_api_key() do
      fetch_cocktails_by_category(category, api_key)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a random cocktail.
  Useful for suggestions or discovery features.
  """
  def get_random_cocktail do
    with :ok <- check_rate_limit(),
         {:ok, api_key} <- get_api_key() do
      fetch_random_cocktail(api_key)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl true
  def init(_state) do
    # Initialize cache and rate limit tables
    :ets.new(@cache_table, [:named_table, :public, :set])
    :ets.new(@rate_limit_table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_cached_cocktail_details, cocktail_id}, _from, state) do
    result =
      case get_from_cache(cocktail_id) do
        {:ok, cached_data} ->
          {:ok, cached_data}

        {:error, :not_found} ->
          fetch_and_cache_cocktail_details(cocktail_id)
      end

    {:reply, result, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_api_key do
    # TheCocktailDB uses "1" for free tier testing
    # Users can get a Patreon key for better limits
    case System.get_env("COCKTAILDB_API_KEY") do
      nil ->
        {:ok, "1"}

      "" ->
        {:ok, "1"}

      key ->
        {:ok, key}
    end
  end

  defp check_rate_limit do
    current_time = System.monotonic_time(:millisecond)
    window_start = current_time - @rate_limit_window

    # Clean old entries
    :ets.select_delete(@rate_limit_table, [{{:"$1", :"$2"}, [{:<, :"$2", window_start}], [true]}])

    # Count current requests in window
    count = :ets.info(@rate_limit_table, :size)

    if count < @rate_limit_max_requests do
      :ets.insert(@rate_limit_table, {make_ref(), current_time})
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp get_from_cache(cocktail_id) do
    cache_key = "cocktail_#{cocktail_id}"

    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, data, timestamp}] ->
        if cache_valid?(timestamp) do
          {:ok, data}
        else
          :ets.delete(@cache_table, cache_key)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp put_in_cache(cocktail_id, data) do
    cache_key = "cocktail_#{cocktail_id}"
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(@cache_table, {cache_key, data, timestamp})
  end

  defp cache_valid?(timestamp) do
    current_time = System.monotonic_time(:millisecond)
    current_time - timestamp < @cache_ttl
  end

  defp fetch_and_cache_cocktail_details(cocktail_id) do
    case get_cocktail_details(cocktail_id) do
      {:ok, cocktail_data} ->
        put_in_cache(cocktail_id, cocktail_data)
        {:ok, cocktail_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_cocktails_by_name(query, api_key) do
    url = "#{@base_url}/#{api_key}/search.php?s=#{URI.encode(query)}"
    headers = [{"Accept", "application/json"}]

    Logger.debug("CocktailDB search URL: #{@base_url}/#{api_key}/search.php?s=#{URI.encode(query)}")

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"drinks" => drinks}} when is_list(drinks) ->
            formatted_cocktails = Enum.map(drinks, &format_cocktail_search_result/1)
            {:ok, formatted_cocktails}

          {:ok, %{"drinks" => nil}} ->
            {:ok, []}

          {:error, decode_error} ->
            Logger.error("Failed to decode CocktailDB search response: #{inspect(decode_error)}")
            {:error, "Failed to decode cocktail data"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("CocktailDB search error: #{code} - #{body}")
        {:error, "CocktailDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("CocktailDB search HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_cocktail_details(cocktail_id, api_key) do
    url = "#{@base_url}/#{api_key}/lookup.php?i=#{cocktail_id}"
    headers = [{"Accept", "application/json"}]

    Logger.debug("CocktailDB details URL: #{@base_url}/#{api_key}/lookup.php?i=#{cocktail_id}")

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"drinks" => [cocktail_data | _]}} ->
            {:ok, format_detailed_cocktail_data(cocktail_data)}

          {:ok, %{"drinks" => nil}} ->
            {:error, "Cocktail not found"}

          {:error, decode_error} ->
            Logger.error("Failed to decode CocktailDB details response: #{inspect(decode_error)}")
            {:error, "Failed to decode cocktail data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Cocktail not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("CocktailDB details error: #{code} - #{body}")
        {:error, "CocktailDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("CocktailDB details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_cocktails_by_category(category, api_key) do
    url = "#{@base_url}/#{api_key}/filter.php?c=#{URI.encode(category)}"
    headers = [{"Accept", "application/json"}]

    Logger.debug(
      "CocktailDB category URL: #{@base_url}/#{api_key}/filter.php?c=#{URI.encode(category)}"
    )

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"drinks" => drinks}} when is_list(drinks) ->
            # Filter endpoint returns limited data, just ids and names
            formatted_cocktails = Enum.map(drinks, &format_cocktail_list_item/1)
            {:ok, formatted_cocktails}

          {:ok, %{"drinks" => nil}} ->
            {:ok, []}

          {:error, decode_error} ->
            Logger.error(
              "Failed to decode CocktailDB category response: #{inspect(decode_error)}"
            )

            {:error, "Failed to decode cocktail data"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("CocktailDB category error: #{code} - #{body}")
        {:error, "CocktailDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("CocktailDB category HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_random_cocktail(api_key) do
    url = "#{@base_url}/#{api_key}/random.php"
    headers = [{"Accept", "application/json"}]

    Logger.debug("CocktailDB random URL: #{@base_url}/#{api_key}/random.php")

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"drinks" => [cocktail_data | _]}} ->
            {:ok, format_detailed_cocktail_data(cocktail_data)}

          {:ok, %{"drinks" => nil}} ->
            {:error, "No random cocktail found"}

          {:error, decode_error} ->
            Logger.error("Failed to decode CocktailDB random response: #{inspect(decode_error)}")
            {:error, "Failed to decode cocktail data"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("CocktailDB random error: #{code} - #{body}")
        {:error, "CocktailDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("CocktailDB random HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  # Format search result (has most fields)
  defp format_cocktail_search_result(cocktail) do
    %{
      id: cocktail["idDrink"],
      name: cocktail["strDrink"],
      category: cocktail["strCategory"],
      alcoholic: cocktail["strAlcoholic"],
      glass: cocktail["strGlass"],
      instructions: cocktail["strInstructions"],
      thumbnail: cocktail["strDrinkThumb"],
      # Extract ingredients (API uses strIngredient1-15 format)
      ingredients: extract_ingredients(cocktail)
    }
  end

  # Format list item (limited data from filter endpoint)
  defp format_cocktail_list_item(cocktail) do
    %{
      id: cocktail["idDrink"],
      name: cocktail["strDrink"],
      thumbnail: cocktail["strDrinkThumb"]
    }
  end

  # Format detailed cocktail data
  defp format_detailed_cocktail_data(cocktail) do
    %{
      source: "cocktaildb",
      type: "cocktail",
      cocktail_id: cocktail["idDrink"],
      name: cocktail["strDrink"],
      category: cocktail["strCategory"],
      alcoholic: cocktail["strAlcoholic"],
      glass: cocktail["strGlass"],
      instructions: cocktail["strInstructions"],
      thumbnail: cocktail["strDrinkThumb"],
      ingredients: extract_ingredients(cocktail),
      tags: extract_tags(cocktail["strTags"]),
      iba_category: cocktail["strIBA"],
      # Store alternate instructions for different languages
      instructions_es: cocktail["strInstructionsES"],
      instructions_de: cocktail["strInstructionsDE"],
      instructions_fr: cocktail["strInstructionsFR"],
      instructions_it: cocktail["strInstructionsIT"],
      video: cocktail["strVideo"],
      image_source: cocktail["strImageSource"],
      image_attribution: cocktail["strImageAttribution"],
      creative_commons_confirmed: cocktail["strCreativeCommonsConfirmed"],
      date_modified: cocktail["dateModified"]
    }
  end

  # Extract ingredients and measurements from the API response
  # TheCocktailDB uses strIngredient1-15 and strMeasure1-15 fields
  defp extract_ingredients(cocktail) do
    1..15
    |> Enum.map(fn i ->
      ingredient = cocktail["strIngredient#{i}"]
      measure = cocktail["strMeasure#{i}"]

      if ingredient && ingredient != "" do
        %{
          ingredient: String.trim(ingredient),
          measure: if(measure && measure != "", do: String.trim(measure), else: nil)
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Extract tags from comma-separated string
  defp extract_tags(nil), do: []
  defp extract_tags(""), do: []

  defp extract_tags(tags_string) when is_binary(tags_string) do
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_tags(_), do: []
end
