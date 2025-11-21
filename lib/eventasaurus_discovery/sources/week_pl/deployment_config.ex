defmodule EventasaurusDiscovery.Sources.WeekPl.DeploymentConfig do
  @moduledoc """
  Deployment configuration for week.pl source rollout.

  Supports phased deployment:
  - Pilot: Kraków only
  - Expansion: Major cities (Warszawa, Wrocław, Gdańsk)
  - Full: All 13 supported cities

  Configuration via environment variables or application config.
  """

  alias EventasaurusDiscovery.Sources.WeekPl.Source

  @pilot_cities ["1"]  # Kraków
  @expansion_cities ["1", "5", "4", "3"]  # Kraków, Warszawa, Wrocław, Gdańsk
  @full_cities Enum.map(Source.supported_cities(), & &1.id)

  @doc """
  Gets the current deployment phase from configuration.

  Environment variable: WEEK_PL_DEPLOYMENT_PHASE
  Application config: config :eventasaurus, week_pl_deployment_phase: :pilot

  Phases:
  - :pilot - Kraków only (region_id: "1")
  - :expansion - Kraków, Warszawa, Wrocław, Gdańsk
  - :full - All 13 cities
  - :disabled - Source disabled

  Defaults to :disabled for safety.
  """
  def deployment_phase do
    case System.get_env("WEEK_PL_DEPLOYMENT_PHASE") do
      phase when phase in ["pilot", "expansion", "full", "disabled"] ->
        String.to_atom(phase)

      _ ->
        Application.get_env(:eventasaurus, :week_pl_deployment_phase, :disabled)
    end
  end

  @doc """
  Gets list of enabled city IDs based on current deployment phase.

  Returns list of region IDs that should be actively synced.
  """
  def enabled_cities do
    case deployment_phase() do
      :pilot -> @pilot_cities
      :expansion -> @expansion_cities
      :full -> @full_cities
      :disabled -> []
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
