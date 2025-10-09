defmodule EventasaurusDiscovery.Sources.SourceRegistry do
  @moduledoc """
  Central registry for mapping source slugs to their job modules.

  This module provides the mapping between database source slugs and their
  corresponding Oban job modules, eliminating the need for hardcoded maps
  scattered throughout the codebase.

  ## Usage

      iex> SourceRegistry.get_sync_job("ticketmaster")
      {:ok, EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob}

      iex> SourceRegistry.get_worker_name("bandsintown")
      {:ok, "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob"}

      iex> SourceRegistry.get_scope("question-one")
      {:ok, :regional}
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query
  require Logger

  @source_to_job %{
    "ticketmaster" => EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob,
    "bandsintown" => EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob,
    "resident-advisor" => EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob,
    "karnet" => EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob,
    "kino-krakow" => EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob,
    "cinema-city" => EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob,
    "pubquiz-pl" => EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob,
    "question-one" => EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob,
    "geeks-who-drink" => EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob
  }

  @doc """
  Get the sync job module for a source slug.

  ## Examples

      iex> get_sync_job("ticketmaster")
      {:ok, EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob}

      iex> get_sync_job("unknown")
      {:error, :not_found}
  """
  def get_sync_job(source_slug) when is_binary(source_slug) do
    case Map.get(@source_to_job, source_slug) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Get the Oban worker name for a source slug (used in oban_jobs table).

  ## Examples

      iex> get_worker_name("ticketmaster")
      {:ok, "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob"}
  """
  def get_worker_name(source_slug) when is_binary(source_slug) do
    case get_sync_job(source_slug) do
      {:ok, module} -> {:ok, Module.split(module) |> Enum.join(".")}
      error -> error
    end
  end

  @doc """
  Get all registered source slugs.

  ## Examples

      iex> all_sources()
      ["ticketmaster", "bandsintown", "resident-advisor", ...]
  """
  def all_sources do
    Map.keys(@source_to_job)
  end

  @doc """
  Get all sources as a map of slug => job module.
  """
  def sources_map do
    @source_to_job
  end

  @doc """
  Get the scope for a source from the database.
  Returns :city, :country, or :regional

  ## Examples

      iex> get_scope("ticketmaster")
      {:ok, :city}

      iex> get_scope("pubquiz-pl")
      {:ok, :country}

      iex> get_scope("question-one")
      {:ok, :regional}
  """
  def get_scope(source_slug) when is_binary(source_slug) do
    query = from s in Source,
      where: s.slug == ^source_slug,
      select: s.metadata

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      metadata when is_map(metadata) ->
        scope =
          case metadata["scope"] do
            "city" -> :city
            "country" -> :country
            "regional" -> :regional
            nil -> :city
            other ->
              Logger.warning("Unknown scope #{inspect(other)} for #{source_slug}, defaulting to :city")
              :city
          end
        {:ok, scope}

      _ ->
        {:ok, :city}  # Default to city if no metadata
    end
  end

  @doc """
  Check if a source requires a city_id.
  Sources with scope "city" require a city_id.

  ## Examples

      iex> requires_city_id?("ticketmaster")
      true

      iex> requires_city_id?("pubquiz-pl")
      false

      iex> requires_city_id?("question-one")
      false
  """
  def requires_city_id?(source_slug) when is_binary(source_slug) do
    case get_scope(source_slug) do
      {:ok, :city} -> true
      {:ok, _} -> false
      {:error, _} -> true  # Default to requiring city for safety
    end
  end

  @doc """
  Get all sources grouped by scope.

  ## Examples

      iex> sources_by_scope()
      %{
        city: ["ticketmaster", "bandsintown", ...],
        country: ["pubquiz-pl"],
        regional: ["question-one"]
      }
  """
  def sources_by_scope do
    query = from s in Source,
      where: s.is_active == true,
      select: {s.slug, s.metadata}

    Repo.all(query)
    |> Enum.group_by(
      fn {_slug, metadata} ->
        scope_string = if is_map(metadata), do: metadata["scope"], else: nil
        case scope_string do
          "city" -> :city
          "country" -> :country
          "regional" -> :regional
          nil -> :city
          other ->
            Logger.warning("Unknown scope #{inspect(other)} in sources_by_scope, defaulting to :city")
            :city
        end
      end,
      fn {slug, _metadata} -> slug end
    )
  end
end
