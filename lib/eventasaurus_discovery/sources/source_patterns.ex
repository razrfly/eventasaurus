defmodule EventasaurusDiscovery.Sources.SourcePatterns do
  @moduledoc """
  Shared worker patterns for CLI mix tasks, derived from SourceRegistry.

  This module provides worker pattern strings used for querying job execution
  data in mix tasks. All patterns are generated dynamically from SourceRegistry
  to ensure CLI tools support all registered sources.

  ## Usage

      # Get pattern for all jobs from a source
      iex> SourcePatterns.get_worker_pattern("cinema_city")
      {:ok, "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%"}

      # Get exact SyncJob worker name
      iex> SourcePatterns.get_sync_worker("cinema_city")
      {:ok, "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"}

      # List all CLI source keys
      iex> SourcePatterns.all_cli_keys()
      ["bandsintown", "cinema_city", "geeks_who_drink", ...]

  ## CLI Key Convention

  CLI keys use underscores (e.g., "cinema_city") while SourceRegistry uses
  hyphens (e.g., "cinema-city"). This module handles the conversion automatically.
  """

  alias EventasaurusDiscovery.Sources.SourceRegistry

  @doc """
  Get the SQL LIKE pattern for querying all jobs from a source.

  The pattern ends with "%" to match all job types (SyncJob, DetailJob, etc.)

  ## Examples

      iex> get_worker_pattern("cinema_city")
      {:ok, "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%"}

      iex> get_worker_pattern("unknown")
      {:error, :not_found}
  """
  def get_worker_pattern(cli_key) when is_binary(cli_key) do
    case lookup_in_registry(cli_key) do
      {:ok, module} ->
        # Get base path without "SyncJob" and add "%"
        module_string = Module.split(module) |> Enum.join(".")
        base_path = String.replace(module_string, ~r/\.[^.]+$/, "")
        {:ok, "#{base_path}.%"}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get the exact SyncJob worker name for a source.

  ## Examples

      iex> get_sync_worker("cinema_city")
      {:ok, "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"}
  """
  def get_sync_worker(cli_key) when is_binary(cli_key) do
    case lookup_in_registry(cli_key) do
      {:ok, module} -> {:ok, Module.split(module) |> Enum.join(".")}
      error -> error
    end
  end

  @doc """
  Get a human-readable display name for a source.

  ## Examples

      iex> get_display_name("cinema_city")
      "Cinema City"

      iex> get_display_name("geeks_who_drink")
      "Geeks Who Drink"
  """
  def get_display_name(cli_key) when is_binary(cli_key) do
    cli_key
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Get all CLI source keys.

  Returns source keys in CLI format (underscores) sorted alphabetically.

  ## Examples

      iex> all_cli_keys()
      ["bandsintown", "cinema_city", "geeks_who_drink", ...]
  """
  def all_cli_keys do
    SourceRegistry.all_sources()
    |> Enum.map(&registry_key_to_cli_key/1)
    |> Enum.sort()
  end

  @doc """
  Get all sources as a map of cli_key => worker_pattern.

  Useful for mix tasks that need to iterate over all sources.

  ## Examples

      iex> all_patterns()
      %{
        "cinema_city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%",
        "bandsintown" => "EventasaurusDiscovery.Sources.Bandsintown.Jobs.%",
        ...
      }
  """
  def all_patterns do
    all_cli_keys()
    |> Enum.map(fn cli_key ->
      {:ok, pattern} = get_worker_pattern(cli_key)
      {cli_key, pattern}
    end)
    |> Map.new()
  end

  @doc """
  Get all sources as a map of cli_key => sync_worker_name.

  Useful for chain analysis tasks that need exact SyncJob names.

  ## Examples

      iex> all_sync_workers()
      %{
        "cinema_city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
        ...
      }
  """
  def all_sync_workers do
    all_cli_keys()
    |> Enum.map(fn cli_key ->
      {:ok, worker} = get_sync_worker(cli_key)
      {cli_key, worker}
    end)
    |> Map.new()
  end

  @doc """
  Check if a CLI key is valid (maps to a registered source).

  ## Examples

      iex> valid_source?("cinema_city")
      true

      iex> valid_source?("unknown")
      false
  """
  def valid_source?(cli_key) when is_binary(cli_key) do
    lookup_in_registry(cli_key) != {:error, :not_found}
  end

  @doc """
  Print available sources to stdout for CLI help messages.
  """
  def print_available_sources do
    IO.puts("\nAvailable sources:")

    all_cli_keys()
    |> Enum.each(fn cli_key ->
      IO.puts("  - #{cli_key}")
    end)
  end

  # Look up a CLI key in the registry, trying both hyphen-converted and original formats.
  # This handles edge cases like "week_pl" which uses underscore in SourceRegistry
  # instead of the standard hyphen format.
  defp lookup_in_registry(cli_key) do
    registry_key = cli_key_to_registry_key(cli_key)

    case SourceRegistry.get_sync_job(registry_key) do
      {:ok, _module} = result ->
        result

      {:error, :not_found} ->
        # Try the original key as-is (handles week_pl edge case)
        SourceRegistry.get_sync_job(cli_key)
    end
  end

  # Convert CLI key (underscores) to registry key (hyphens)
  defp cli_key_to_registry_key(cli_key) do
    String.replace(cli_key, "_", "-")
  end

  # Convert registry key (hyphens) to CLI key (underscores)
  defp registry_key_to_cli_key(registry_key) do
    String.replace(registry_key, "-", "_")
  end
end
