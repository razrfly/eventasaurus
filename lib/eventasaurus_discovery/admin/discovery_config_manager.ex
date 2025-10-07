defmodule EventasaurusDiscovery.Admin.DiscoveryConfigManager do
  @moduledoc """
  Helper functions for managing city discovery configurations.

  Provides a clean API to work with the JSONB discovery_config field
  and manage automated event discovery for cities.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.City.DiscoveryConfig

  @doc """
  Enable discovery for a city with default configuration.

  ## Examples

      iex> enable_city(1)
      {:ok, %City{discovery_enabled: true}}

      iex> enable_city(999)
      {:error, :not_found}
  """
  def enable_city(city_id) do
    case Repo.get(City, city_id) do
      nil ->
        {:error, :not_found}

      city ->
        city
        |> City.enable_discovery_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Disable discovery for a city.

  ## Examples

      iex> disable_city(1)
      {:ok, %City{discovery_enabled: false}}
  """
  def disable_city(city_id) do
    case Repo.get(City, city_id) do
      nil ->
        {:error, :not_found}

      city ->
        city
        |> City.disable_discovery_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Enable a specific discovery source for a city.

  ## Examples

      iex> enable_source(1, "bandsintown", %{limit: 100, radius: 50})
      {:ok, %City{}}

      iex> enable_source(1, "invalid-source", %{})
      {:error, :invalid_source}
  """
  def enable_source(city_id, source_name, settings \\ %{}) do
    with {:ok, city} <- get_city(city_id),
         true <- valid_source?(source_name) do
      config = city.discovery_config || %{
        "schedule" => %{"cron" => "0 0 * * *", "timezone" => "UTC", "enabled" => true},
        "sources" => []
      }

      # Convert to map format if needed
      config_map =
        if is_struct(config) do
          Jason.encode!(config) |> Jason.decode!()
        else
          config
        end

      # Find existing source or create new one
      sources = config_map["sources"] || []
      existing_index = Enum.find_index(sources, &(&1["name"] == source_name))

      new_source = %{
        "name" => source_name,
        "enabled" => true,
        "frequency_hours" => 24,
        "settings" => settings,
        "stats" => %{
          "run_count" => 0,
          "success_count" => 0,
          "error_count" => 0
        }
      }

      updated_sources =
        if existing_index do
          List.update_at(sources, existing_index, fn source ->
            Map.merge(source, %{"enabled" => true, "settings" => settings})
          end)
        else
          sources ++ [new_source]
        end

      updated_config = Map.put(config_map, "sources", updated_sources)

      city
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:discovery_config, updated_config)
      |> Repo.update()
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_source}
    end
  end

  @doc """
  Disable a specific discovery source for a city.

  ## Examples

      iex> disable_source(1, "bandsintown")
      {:ok, %City{}}
  """
  def disable_source(city_id, source_name) do
    with {:ok, city} <- get_city(city_id),
         config when not is_nil(config) <- city.discovery_config do
      # Convert to map format if needed
      config_map =
        if is_struct(config) do
          Jason.encode!(config) |> Jason.decode!()
        else
          config
        end

      sources = config_map["sources"] || []
      source_index = Enum.find_index(sources, &(&1["name"] == source_name))

      if source_index do
        updated_sources =
          List.update_at(sources, source_index, fn source ->
            Map.put(source, "enabled", false)
          end)

        updated_config = Map.put(config_map, "sources", updated_sources)

        city
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:discovery_config, updated_config)
        |> Repo.update()
      else
        {:error, :source_not_found}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :discovery_not_configured}
    end
  end

  @doc """
  Delete a specific discovery source from a city.

  ## Examples

      iex> delete_source(1, "bandsintown")
      {:ok, %City{}}
  """
  def delete_source(city_id, source_name) do
    with {:ok, city} <- get_city(city_id),
         config when not is_nil(config) <- city.discovery_config do
      # Convert to map format if needed
      config_map =
        if is_struct(config) do
          Jason.encode!(config) |> Jason.decode!()
        else
          config
        end

      sources = config_map["sources"] || []
      source_index = Enum.find_index(sources, &(&1["name"] == source_name))

      if source_index do
        # Remove the source from the list
        updated_sources = List.delete_at(sources, source_index)
        updated_config = Map.put(config_map, "sources", updated_sources)

        city
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:discovery_config, updated_config)
        |> Repo.update()
      else
        {:error, :source_not_found}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :discovery_not_configured}
    end
  end

  @doc """
  Update settings for a specific discovery source.

  ## Examples

      iex> update_source_settings(1, "bandsintown", %{limit: 200})
      {:ok, %City{}}
  """
  def update_source_settings(city_id, source_name, settings) do
    with {:ok, city} <- get_city(city_id),
         config when not is_nil(config) <- city.discovery_config do
      # Convert to map format if needed
      config_map =
        if is_struct(config) do
          Jason.encode!(config) |> Jason.decode!()
        else
          config
        end

      sources = config_map["sources"] || []
      source_index = Enum.find_index(sources, &(&1["name"] == source_name))

      if source_index do
        updated_sources =
          List.update_at(sources, source_index, fn source ->
            current_settings = source["settings"] || %{}
            Map.put(source, "settings", Map.merge(current_settings, settings))
          end)

        updated_config = Map.put(config_map, "sources", updated_sources)

        city
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:discovery_config, updated_config)
        |> Repo.update()
      else
        {:error, :source_not_found}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :discovery_not_configured}
    end
  end

  @doc """
  Update statistics for a source after a discovery run.

  ## Examples

      iex> update_source_stats(1, "bandsintown", :success)
      {:ok, %City{}}

      iex> update_source_stats(1, "bandsintown", {:error, "timeout"})
      {:ok, %City{}}
  """
  def update_source_stats(city_id, source_name, result) do
    with {:ok, city} <- get_city(city_id),
         config when not is_nil(config) <- city.discovery_config do
      # Convert to map if needed
      config_map =
        if is_struct(config) do
          Jason.encode!(config) |> Jason.decode!()
        else
          config
        end

      sources = config_map["sources"] || []
      source_index = Enum.find_index(sources, &(&1["name"] == source_name))

      if source_index do
        now = DateTime.utc_now()

        updated_sources =
          List.update_at(sources, source_index, fn source ->
            stats = source["stats"] || %{"run_count" => 0, "success_count" => 0, "error_count" => 0}
            frequency_hours = source["frequency_hours"] || 24
            next_run = DateTime.add(now, frequency_hours * 3600, :second)

            updated_stats =
              case result do
                :success ->
                  %{
                    "run_count" => (stats["run_count"] || 0) + 1,
                    "success_count" => (stats["success_count"] || 0) + 1,
                    "error_count" => stats["error_count"] || 0,
                    "last_error" => nil
                  }

                {:error, error} ->
                  %{
                    "run_count" => (stats["run_count"] || 0) + 1,
                    "success_count" => stats["success_count"] || 0,
                    "error_count" => (stats["error_count"] || 0) + 1,
                    "last_error" => to_string(error)
                  }
              end

            Map.merge(source, %{
              "stats" => updated_stats,
              "last_run_at" => DateTime.to_iso8601(now),
              "next_run_at" => DateTime.to_iso8601(next_run)
            })
          end)

        updated_config = Map.put(config_map, "sources", updated_sources)

        city
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:discovery_config, updated_config)
        |> Repo.update()
      else
        {:error, :source_not_found}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :discovery_not_configured}
    end
  end

  @doc """
  Get all cities with discovery enabled.

  ## Examples

      iex> list_discovery_enabled_cities()
      [%City{discovery_enabled: true}, ...]
  """
  def list_discovery_enabled_cities do
    import Ecto.Query

    Repo.all(
      from c in City,
        where: c.discovery_enabled == true,
        preload: :country,
        order_by: c.name
    )
  end

  @doc """
  Get all sources that are due to run for a city.

  ## Examples

      iex> get_due_sources(city)
      [%{"name" => "bandsintown", ...}, ...]
  """
  def get_due_sources(%City{discovery_config: config}) when not is_nil(config) do
    now = DateTime.utc_now()

    # Handle both map and struct formats
    sources =
      cond do
        is_map(config) && Map.has_key?(config, "sources") -> config["sources"] || []
        is_struct(config) -> config.sources || []
        true -> []
      end

    Enum.filter(sources, fn source ->
      enabled = if is_map(source), do: source["enabled"], else: source.enabled
      enabled && source_due_to_run?(source, now)
    end)
  end

  def get_due_sources(_city), do: []

  # Private helpers

  defp get_city(city_id) do
    case Repo.get(City, city_id) |> Repo.preload(:country) do
      nil -> {:error, :not_found}
      city -> {:ok, city}
    end
  end

  defp valid_source?(source_name) do
    source_name in DiscoveryConfig.valid_source_names()
  end

  defp source_due_to_run?(source, now) do
    next_run_at =
      if is_map(source) do
        source["next_run_at"]
      else
        source.next_run_at
      end

    case next_run_at do
      nil ->
        true  # Never run before

      next_run_str when is_binary(next_run_str) ->
        case DateTime.from_iso8601(next_run_str) do
          {:ok, next_run, _} -> DateTime.compare(now, next_run) in [:gt, :eq]
          _ -> true  # Invalid date, run it
        end

      %DateTime{} = next_run ->
        DateTime.compare(now, next_run) in [:gt, :eq]

      _ ->
        true  # Unknown format, run it
    end
  end
end
