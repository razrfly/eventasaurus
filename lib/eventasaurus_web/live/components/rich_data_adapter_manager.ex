defmodule EventasaurusWeb.Live.Components.RichDataAdapterManager do
  @moduledoc """
  Manager for automatically selecting and applying data adapters to normalize
  rich content data into a standardized format.

  This module acts as the central coordinator for data adaptation, automatically
  detecting the appropriate adapter for incoming data and transforming it into
  the standardized format that the generic display components can understand.

  ## Registered Adapters

  The manager maintains a registry of available adapters and can automatically
  select the best one based on the input data characteristics.

  ## Usage

      # Automatically adapt raw data
      {:ok, standardized_data} = adapt_data(raw_tmdb_data)

      # Use specific adapter
      {:ok, standardized_data} = adapt_data(raw_data, :tmdb)

      # Check what adapters can handle data
      adapters = find_compatible_adapters(raw_data)

  """

  alias EventasaurusWeb.Live.Components.Adapters.{
    TmdbDataAdapter,
    GooglePlacesDataAdapter
  }

  @type adapter_module :: module()
  @type content_type :: atom()
  @type raw_data :: map()
  @type standardized_data :: map()
  @type adapter_result :: {:ok, standardized_data()} | {:error, String.t()}

  # Registry of available adapters
  @registered_adapters [
    TmdbDataAdapter,
    GooglePlacesDataAdapter
  ]

  @doc """
  Automatically adapts raw data using the most appropriate adapter.

  This function analyzes the input data and selects the best adapter
  to transform it into the standardized format.

  ## Examples

      iex> adapt_data(%{"id" => 123, "title" => "Movie", "vote_average" => 8.5})
      {:ok, %{id: "tmdb_123", type: :movie, title: "Movie", ...}}

      iex> adapt_data(%{"place_id" => "abc123", "name" => "Restaurant", "rating" => 4.2})
      {:ok, %{id: "places_abc123", type: :restaurant, title: "Restaurant", ...}}

  """
  @spec adapt_data(raw_data()) :: adapter_result()
  def adapt_data(raw_data) when is_map(raw_data) do
    case find_best_adapter(raw_data) do
      nil ->
        {:error, "No compatible adapter found for data"}

      adapter_module ->
        try do
          standardized_data = adapter_module.adapt(raw_data)
          {:ok, standardized_data}
        rescue
          error ->
            {:error, "Adapter error: #{inspect(error)}"}
        end
    end
  end

  def adapt_data(_), do: {:error, "Invalid data format"}

  @doc """
  Adapts raw data using a specific adapter type.

  This bypasses automatic adapter selection and uses the specified adapter.

  ## Examples

      iex> adapt_data(raw_data, :tmdb)
      {:ok, %{...}}

      iex> adapt_data(raw_data, :google_places)
      {:ok, %{...}}

  """
  @spec adapt_data(raw_data(), content_type()) :: adapter_result()
  def adapt_data(raw_data, adapter_type) when is_map(raw_data) and is_atom(adapter_type) do
    case get_adapter_by_type(adapter_type) do
      nil ->
        {:error, "Unknown adapter type: #{adapter_type}"}

      adapter_module ->
        try do
          standardized_data = adapter_module.adapt(raw_data)
          {:ok, standardized_data}
        rescue
          error ->
            {:error, "Adapter error: #{inspect(error)}"}
        end
    end
  end

  def adapt_data(_, _), do: {:error, "Invalid data format or adapter type"}

  @doc """
  Finds the best adapter for the given raw data.

  Returns the adapter module that can best handle the data,
  or nil if no suitable adapter is found.
  """
  @spec find_best_adapter(raw_data()) :: adapter_module() | nil
  def find_best_adapter(raw_data) when is_map(raw_data) do
    @registered_adapters
    |> Enum.find(& &1.handles?(raw_data))
  end

  def find_best_adapter(_), do: nil

  @doc """
  Finds all adapters that can handle the given raw data.

  Returns a list of adapter modules that claim they can process the data.
  """
  @spec find_compatible_adapters(raw_data()) :: [adapter_module()]
  def find_compatible_adapters(raw_data) when is_map(raw_data) do
    @registered_adapters
    |> Enum.filter(& &1.handles?(raw_data))
  end

  def find_compatible_adapters(_), do: []

  @doc """
  Gets an adapter module by its content type.

  ## Examples

      iex> get_adapter_by_type(:movie)
      EventasaurusWeb.Live.Components.Adapters.TmdbDataAdapter

      iex> get_adapter_by_type(:venue)
      EventasaurusWeb.Live.Components.Adapters.GooglePlacesDataAdapter

  """
  @spec get_adapter_by_type(content_type()) :: adapter_module() | nil
  def get_adapter_by_type(content_type) do
    @registered_adapters
    |> Enum.find(fn adapter ->
      try do
        adapter.content_type() == content_type ||
          content_type in adapter.supported_sections()
      rescue
        # Some adapters might not implement all callbacks
        _ -> false
      end
    end)
  end

  @doc """
  Gets display configuration for a content type.

  This queries the appropriate adapter to get display configuration
  like default sections, compact sections, etc.
  """
  @spec get_display_config(content_type()) :: map() | nil
  def get_display_config(content_type) do
    case get_adapter_by_type(content_type) do
      nil ->
        nil

      adapter_module ->
        try do
          adapter_module.display_config()
        rescue
          # Fallback if adapter doesn't implement display_config
          _ -> default_display_config(content_type)
        end
    end
  end

  @doc """
  Lists all registered adapters and their supported content types.
  """
  @spec list_adapters() :: [{adapter_module(), [content_type()]}]
  def list_adapters do
    @registered_adapters
    |> Enum.map(fn adapter ->
      content_types =
        try do
          [adapter.content_type()]
        rescue
          _ ->
            # Try to get from supported_sections or default to unknown
            try do
              adapter.supported_sections()
            rescue
              _ -> [:unknown]
            end
        end

      {adapter, content_types}
    end)
  end

  @doc """
  Registers a new adapter at runtime.

  Note: This is a simplified implementation for demonstration.
  In a production system, you might want to use a GenServer or ETS.
  """
  @spec register_adapter(adapter_module()) :: :ok | {:error, String.t()}
  def register_adapter(adapter_module) when is_atom(adapter_module) do
    # Validate that the module implements the required behavior
    behaviours = adapter_module.module_info(:attributes)[:behaviour] || []

    if EventasaurusWeb.Live.Components.RichDataAdapterBehaviour in behaviours do
      Process.put(
        {__MODULE__, :dynamic_adapters},
        [adapter_module | get_dynamic_adapters()]
      )

      :ok
    else
      {:error, "Module does not implement RichDataAdapterBehaviour"}
    end
  end

  @doc """
  Gets a list of dynamically registered adapters.
  """
  @spec get_dynamic_adapters() :: [adapter_module()]
  def get_dynamic_adapters do
    Process.get({__MODULE__, :dynamic_adapters}, [])
  end

  @doc """
  Gets all adapters (static + dynamic).
  """
  @spec get_all_adapters() :: [adapter_module()]
  def get_all_adapters do
    @registered_adapters ++ get_dynamic_adapters()
  end

  @doc """
  Validates that the standardized data conforms to the expected format.

  This is useful for testing and debugging adapter implementations.
  """
  @spec validate_standardized_data(standardized_data()) :: :ok | {:error, [String.t()]}
  def validate_standardized_data(data) when is_map(data) do
    required_fields = [:id, :type, :title]

    _optional_fields = [
      :description,
      :primary_image,
      :secondary_image,
      :rating,
      :year,
      :status,
      :categories,
      :tags,
      :external_urls,
      :sections
    ]

    errors = []

    # Check required fields
    errors =
      Enum.reduce(required_fields, errors, fn field, acc ->
        if Map.has_key?(data, field) and data[field] != nil do
          acc
        else
          ["Missing required field: #{field}" | acc]
        end
      end)

    # Validate data types
    errors =
      cond do
        not is_binary(data[:id]) ->
          ["id must be a string" | errors]

        not is_atom(data[:type]) ->
          ["type must be an atom" | errors]

        not is_binary(data[:title]) ->
          ["title must be a string" | errors]

        true ->
          errors
      end

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_standardized_data(_), do: {:error, ["Data must be a map"]}

  # Private helper functions

  defp default_display_config(content_type) do
    case content_type do
      type when type in [:movie, :tv] ->
        %{
          default_sections: [:hero, :overview, :cast, :media, :details],
          compact_sections: [:hero, :overview],
          required_fields: [:id, :title, :type],
          optional_fields: [:description, :rating, :year, :categories, :primary_image]
        }

      type when type in [:venue, :restaurant, :activity] ->
        %{
          default_sections: [:hero, :details, :reviews, :photos],
          compact_sections: [:hero, :details],
          required_fields: [:id, :title, :type],
          optional_fields: [:description, :rating, :categories, :primary_image]
        }

      _ ->
        %{
          default_sections: [:hero, :details],
          compact_sections: [:hero],
          required_fields: [:id, :title, :type],
          optional_fields: [:description, :primary_image]
        }
    end
  end
end
