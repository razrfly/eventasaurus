defmodule EventasaurusDiscovery.Admin.SourceHealthCalculator do
  @moduledoc """
  Calculates health scores and status for discovery sources based on their
  run statistics from Oban jobs.

  Health is determined by success rate over total runs:
  - Healthy (🟢): ≥90% success rate
  - Warning (🟡): 70-89% success rate
  - Error (🔴): <70% success rate or no runs
  """

  @doc """
  Calculate the health status for a source based on its statistics.

  Returns one of: `:healthy`, `:warning`, `:error`

  ## Examples

      iex> calculate_health_score(%{run_count: 100, success_count: 95})
      :healthy

      iex> calculate_health_score(%{run_count: 100, success_count: 75})
      :warning

      iex> calculate_health_score(%{run_count: 100, success_count: 50})
      :error

      iex> calculate_health_score(%{run_count: 0, success_count: 0})
      :error
  """
  def calculate_health_score(%{run_count: 0}), do: :error

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

  ## Examples

      iex> stats = %{
      ...>   "bandsintown" => %{run_count: 100, success_count: 98},
      ...>   "ticketmaster" => %{run_count: 50, success_count: 45}
      ...> }
      iex> overall_health_score(stats)
      87
  """
  def overall_health_score(all_source_stats) when is_map(all_source_stats) do
    source_stats_list = Map.values(all_source_stats)

    if Enum.empty?(source_stats_list) do
      0
    else
      total_success_rate =
        source_stats_list
        |> Enum.map(fn stats ->
          run_count = Map.get(stats, :run_count, 0)

          if run_count > 0 do
            Map.get(stats, :success_count, 0) / run_count * 100
          else
            0
          end
        end)
        |> Enum.sum()

      (total_success_rate / length(source_stats_list))
      |> round()
    end
  end

  def overall_health_score(_), do: 0

  @doc """
  Get the success rate percentage for a source.

  Returns an integer percentage (0-100).

  ## Examples

      iex> success_rate_percentage(%{run_count: 100, success_count: 95})
      95

      iex> success_rate_percentage(%{run_count: 0, success_count: 0})
      0
  """
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
  """
  def status_emoji(:healthy), do: "🟢"
  def status_emoji(:warning), do: "🟡"
  def status_emoji(:error), do: "🔴"
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
  """
  def status_text(:healthy), do: "Healthy"
  def status_text(:warning), do: "Warning"
  def status_text(:error), do: "Error"
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
  """
  def status_classes(:healthy), do: "bg-green-100 text-green-800"
  def status_classes(:warning), do: "bg-yellow-100 text-yellow-800"
  def status_classes(:error), do: "bg-red-100 text-red-800"
  def status_classes(_), do: "bg-gray-100 text-gray-800"
end
