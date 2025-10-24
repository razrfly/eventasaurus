defmodule EventasaurusDiscovery.Admin.SourceHealthCalculator do
  @moduledoc """
  Calculates health scores and status for discovery sources based on their
  run statistics from Oban jobs.

  Health is determined by success rate over total runs:
  - Healthy (🟢): ≥90% success rate
  - Warning (🟡): 70-89% success rate
  - Error (🔴): <70% success rate
  - No Data (⚪): No runs available (e.g., city-scoped source in city with no jobs)
  """

  @doc """
  Calculate the health status for a source based on its statistics.

  Returns one of: `:healthy`, `:warning`, `:error`, `:no_data`

  Supports both old job-level stats (run_count/success_count) and new metadata-based stats
  (events_processed/events_succeeded). Metadata-based stats are preferred when available.

  ## Examples

      iex> calculate_health_score(%{run_count: 100, success_count: 95})
      :healthy

      iex> calculate_health_score(%{events_processed: 100, events_succeeded: 95})
      :healthy

      iex> calculate_health_score(%{run_count: 100, success_count: 75})
      :warning

      iex> calculate_health_score(%{run_count: 100, success_count: 50})
      :error

      iex> calculate_health_score(%{run_count: 0, success_count: 0})
      :no_data

      iex> calculate_health_score(%{events_processed: 0})
      :no_data
  """
  # Metadata-based stats (preferred)
  def calculate_health_score(%{events_processed: 0}), do: :no_data

  def calculate_health_score(%{events_processed: processed, events_succeeded: succeeded})
      when is_integer(processed) and is_integer(succeeded) and processed > 0 do
    success_rate = succeeded / processed

    cond do
      success_rate >= 0.90 -> :healthy
      success_rate >= 0.70 -> :warning
      true -> :error
    end
  end

  # Legacy job-level stats (backward compatibility)
  def calculate_health_score(%{run_count: 0}), do: :no_data

  def calculate_health_score(%{run_count: run_count, success_count: success_count})
      when is_integer(run_count) and is_integer(success_count) and run_count > 0 do
    success_rate = success_count / run_count

    cond do
      success_rate >= 0.90 -> :healthy
      success_rate >= 0.70 -> :warning
      true -> :error
    end
  end

  def calculate_health_score(_), do: :error

  @doc """
  Calculate the overall health score percentage across all sources.

  Returns an integer percentage (0-100).

  Supports both old job-level stats (run_count/success_count) and new metadata-based stats
  (events_processed/events_succeeded). Metadata-based stats are preferred when available.

  ## Examples

      iex> stats = %{
      ...>   "bandsintown" => %{run_count: 100, success_count: 98},
      ...>   "ticketmaster" => %{run_count: 50, success_count: 45}
      ...> }
      iex> overall_health_score(stats)
      87

      iex> stats = %{
      ...>   "bandsintown" => %{events_processed: 100, events_succeeded: 98},
      ...>   "ticketmaster" => %{events_processed: 50, events_succeeded: 45}
      ...> }
      iex> overall_health_score(stats)
      87
  """
  def overall_health_score(all_source_stats) when is_map(all_source_stats) do
    source_stats_list = Map.values(all_source_stats)

    if Enum.empty?(source_stats_list) do
      0
    else
      {total_success, total_runs} =
        Enum.reduce(source_stats_list, {0, 0}, fn stats, {success_acc, run_acc} ->
          # Prefer metadata-based stats
          {processed, succeeded} =
            cond do
              Map.has_key?(stats, :events_processed) ->
                {Map.get(stats, :events_processed, 0), Map.get(stats, :events_succeeded, 0)}

              Map.has_key?(stats, :run_count) ->
                {Map.get(stats, :run_count, 0), Map.get(stats, :success_count, 0)}

              true ->
                {0, 0}
            end

          {success_acc + succeeded, run_acc + processed}
        end)

      if total_runs > 0 do
        (total_success / total_runs * 100)
        |> round()
      else
        0
      end
    end
  end

  def overall_health_score(_), do: 0

  @doc """
  Get the success rate percentage for a source.

  Returns an integer percentage (0-100).

  Supports both old job-level stats (run_count/success_count) and new metadata-based stats
  (events_processed/events_succeeded). Metadata-based stats are preferred when available.

  ## Examples

      iex> success_rate_percentage(%{run_count: 100, success_count: 95})
      95

      iex> success_rate_percentage(%{events_processed: 100, events_succeeded: 95})
      95

      iex> success_rate_percentage(%{run_count: 0, success_count: 0})
      0

      iex> success_rate_percentage(%{events_processed: 0})
      0
  """
  # Metadata-based stats (preferred)
  def success_rate_percentage(%{events_processed: 0}), do: 0

  def success_rate_percentage(%{events_processed: processed, events_succeeded: succeeded})
      when is_integer(processed) and is_integer(succeeded) and processed > 0 do
    (succeeded / processed * 100)
    |> round()
  end

  # Legacy job-level stats (backward compatibility)
  def success_rate_percentage(%{run_count: 0}), do: 0

  def success_rate_percentage(%{run_count: run_count, success_count: success_count})
      when is_integer(run_count) and is_integer(success_count) and run_count > 0 do
    (success_count / run_count * 100)
    |> round()
  end

  def success_rate_percentage(_), do: 0

  @doc """
  Get the status emoji for a health status.

  ## Examples

      iex> status_emoji(:healthy)
      "🟢"

      iex> status_emoji(:warning)
      "🟡"

      iex> status_emoji(:error)
      "🔴"

      iex> status_emoji(:no_data)
      "⚪"
  """
  def status_emoji(:healthy), do: "🟢"
  def status_emoji(:warning), do: "🟡"
  def status_emoji(:error), do: "🔴"
  def status_emoji(:no_data), do: "⚪"
  def status_emoji(_), do: "⚪"

  @doc """
  Get the status text for a health status.

  ## Examples

      iex> status_text(:healthy)
      "Healthy"

      iex> status_text(:warning)
      "Warning"

      iex> status_text(:error)
      "Error"

      iex> status_text(:no_data)
      "No Data"
  """
  def status_text(:healthy), do: "Healthy"
  def status_text(:warning), do: "Warning"
  def status_text(:error), do: "Error"
  def status_text(:no_data), do: "No Data"
  def status_text(_), do: "Unknown"

  @doc """
  Get CSS classes for a health status badge.

  ## Examples

      iex> status_classes(:healthy)
      "bg-green-100 text-green-800"

      iex> status_classes(:warning)
      "bg-yellow-100 text-yellow-800"

      iex> status_classes(:error)
      "bg-red-100 text-red-800"

      iex> status_classes(:no_data)
      "bg-gray-100 text-gray-800"
  """
  def status_classes(:healthy), do: "bg-green-100 text-green-800"
  def status_classes(:warning), do: "bg-yellow-100 text-yellow-800"
  def status_classes(:error), do: "bg-red-100 text-red-800"
  def status_classes(:no_data), do: "bg-gray-100 text-gray-800"
  def status_classes(_), do: "bg-gray-100 text-gray-800"
end
