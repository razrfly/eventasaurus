defmodule EventasaurusDiscovery.Sources.WeekPl.DeploymentConfig do
  @moduledoc """
  Deployment configuration for week.pl source.

  Syncs all 13 cities/regions that week.pl provides data for:
  Kraków, Warszawa, Wrocław, Poznań, Trójmiasto, Śląsk, Łódź,
  Białystok, Bydgoszcz, Lubelskie, Rzeszów, Szczecin, Warmia i Mazury

  Configuration via environment variables or application config.
  """

  alias EventasaurusDiscovery.Sources.WeekPl.Source

  @all_cities Enum.map(Source.supported_cities(), & &1.id)

  @doc """
  Gets the current deployment phase from configuration.

  Environment variable: WEEK_PL_DEPLOYMENT_PHASE
  Application config: config :eventasaurus, week_pl_deployment_phase: :enabled

  Phases:
  - :enabled - Sync all 13 cities (default)
  - :disabled - Source disabled

  Defaults to :enabled to get all available data.
  """
  def deployment_phase do
    phase = case System.get_env("WEEK_PL_DEPLOYMENT_PHASE") do
      "disabled" ->
        :disabled

      "enabled" ->
        :enabled

      nil ->
        Application.get_env(:eventasaurus, :week_pl_deployment_phase, :enabled)

      _ ->
        :enabled
    end

    phase
  end

  @doc """
  Gets list of enabled city IDs based on current deployment phase.

  Returns list of region IDs that should be actively synced.
  """
  def enabled_cities do
    case deployment_phase() do
      :enabled -> @all_cities
      :disabled -> []
      # Legacy phase values - treat as enabled for backwards compatibility
      :pilot -> @all_cities
      :expansion -> @all_cities
      :full -> @all_cities
    end
  end

  @doc """
  Filters supported cities to only those enabled in current phase.

  Returns list of city maps with :id, :name, :country fields.
  """
  def active_cities do
    enabled_ids = enabled_cities()

    Source.supported_cities()
    |> Enum.filter(fn city -> city.id in enabled_ids end)
  end

  @doc """
  Checks if source is enabled (deployment phase is not :disabled).
  """
  def enabled? do
    deployment_phase() != :disabled
  end

  @doc """
  Checks if a specific city is enabled in current deployment phase.
  """
  def city_enabled?(region_id) do
    region_id in enabled_cities()
  end

  @doc """
  Gets deployment status summary for logging and monitoring.
  """
  def status do
    phase = deployment_phase()
    cities = active_cities()

    %{
      phase: phase,
      enabled: enabled?(),
      active_cities: length(cities),
      city_names: Enum.map_join(cities, ", ", & &1.name),
      total_cities: length(Source.supported_cities())
    }
  end
end
