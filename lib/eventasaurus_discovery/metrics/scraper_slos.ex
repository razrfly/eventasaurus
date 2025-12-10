defmodule EventasaurusDiscovery.Metrics.ScraperSLOs do
  @moduledoc """
  Service Level Objectives (SLOs) for job scrapers.

  Defines target success rates, average duration targets, and alert thresholds
  for each scraper to enable SLO-based monitoring and alerting.

  ## SLO Indicators

  - ✅ Green: Meets or exceeds target
  - ⚠️ Yellow: Below target but above alert threshold
  - ❌ Red: Below alert threshold (requires attention)

  ## Usage

      # Get SLOs for a specific scraper
      slo = ScraperSLOs.get_slo("cinema_city")

      # Check if metrics meet SLO
      status = ScraperSLOs.check_slo_status(slo, actual_success_rate, actual_avg_duration)

      # Get all configured SLOs
      all_slos = ScraperSLOs.all_slos()
  """

  @type slo_status :: :meets_target | :below_target | :critical

  @slos %{
    # Cinema City scraper - TMDB matching complexity means lower target
    "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob" => %{
      name: "Cinema City Sync",
      target_success_rate: 0.95,
      target_avg_duration_ms: 2000,
      alert_threshold: 0.85
    },
    "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob" => %{
      name: "Cinema City Date",
      target_success_rate: 0.95,
      target_avg_duration_ms: 3000,
      alert_threshold: 0.90
    },
    "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob" => %{
      name: "Cinema City Movie Detail",
      target_success_rate: 0.85,
      # Lower due to TMDB matching complexity
      target_avg_duration_ms: 2000,
      alert_threshold: 0.75
    },
    "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob" => %{
      name: "Cinema City Showtime Process",
      target_success_rate: 0.90,
      target_avg_duration_ms: 1500,
      alert_threshold: 0.80
    },

    # Repertuary scraper
    "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob" => %{
      name: "Repertuary Sync",
      target_success_rate: 0.95,
      target_avg_duration_ms: 2000,
      alert_threshold: 0.85
    },
    "EventasaurusDiscovery.Sources.Repertuary.Jobs.MoviePageJob" => %{
      name: "Repertuary Movie Page",
      target_success_rate: 0.90,
      target_avg_duration_ms: 15000,
      # Fetches 7 days
      alert_threshold: 0.80
    },
    "EventasaurusDiscovery.Sources.Repertuary.Jobs.DayPageJob" => %{
      name: "Repertuary Day Page",
      target_success_rate: 0.90,
      target_avg_duration_ms: 3000,
      alert_threshold: 0.80
    },
    "EventasaurusDiscovery.Sources.Repertuary.Jobs.MovieDetailJob" => %{
      name: "Repertuary Movie Detail",
      target_success_rate: 0.85,
      # Lower due to TMDB matching
      target_avg_duration_ms: 2000,
      alert_threshold: 0.75
    },
    "EventasaurusDiscovery.Sources.Repertuary.Jobs.ShowtimeProcessJob" => %{
      name: "Repertuary Showtime Process",
      target_success_rate: 0.90,
      target_avg_duration_ms: 1500,
      alert_threshold: 0.80
    },

    # Question One scraper - high reliability expected
    "EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob" => %{
      name: "Question One Sync",
      target_success_rate: 0.95,
      target_avg_duration_ms: 3000,
      alert_threshold: 0.90
    },

    # Week.pl scraper
    "EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob" => %{
      name: "Week.pl Sync",
      target_success_rate: 0.90,
      target_avg_duration_ms: 5000,
      alert_threshold: 0.80
    },

    # Default SLO for unspecified scrapers
    "_default" => %{
      name: "Default",
      target_success_rate: 0.85,
      target_avg_duration_ms: 3000,
      alert_threshold: 0.75
    }
  }

  @doc """
  Gets the SLO configuration for a specific worker.

  Falls back to default SLO if worker not configured.

  ## Examples

      iex> ScraperSLOs.get_slo("EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob")
      %{
        name: "Cinema City Sync",
        target_success_rate: 0.95,
        target_avg_duration_ms: 2000,
        alert_threshold: 0.85
      }
  """
  def get_slo(worker_name) do
    Map.get(@slos, worker_name, @slos["_default"])
  end

  @doc """
  Returns all configured SLOs.

  ## Examples

      iex> ScraperSLOs.all_slos()
      %{...}
  """
  def all_slos do
    @slos
  end

  @doc """
  Checks if metrics meet SLO targets.

  Returns one of:
  - `:meets_target` - Success rate >= target (✅ Green)
  - `:below_target` - Success rate < target but >= alert threshold (⚠️ Yellow)
  - `:critical` - Success rate < alert threshold (❌ Red)

  ## Examples

      iex> slo = ScraperSLOs.get_slo("cinema_city")
      iex> ScraperSLOs.check_slo_status(slo, 96.5, 1800)
      :meets_target

      iex> ScraperSLOs.check_slo_status(slo, 88.0, 2200)
      :below_target

      iex> ScraperSLOs.check_slo_status(slo, 75.0, 5000)
      :critical
  """
  @spec check_slo_status(map(), float(), float() | nil) :: slo_status()
  def check_slo_status(slo, actual_success_rate, _actual_avg_duration \\ nil) do
    # Convert percentages to decimals for comparison
    success_rate_decimal = actual_success_rate / 100
    target_rate = slo.target_success_rate
    alert_threshold = slo.alert_threshold

    cond do
      success_rate_decimal >= target_rate -> :meets_target
      success_rate_decimal >= alert_threshold -> :below_target
      true -> :critical
    end
  end

  @doc """
  Gets a visual indicator for SLO status.

  Returns emoji indicator based on status.

  ## Examples

      iex> ScraperSLOs.status_indicator(:meets_target)
      "✅"

      iex> ScraperSLOs.status_indicator(:below_target)
      "⚠️"

      iex> ScraperSLOs.status_indicator(:critical)
      "❌"
  """
  def status_indicator(status) do
    case status do
      :meets_target -> "✅"
      :below_target -> "⚠️"
      :critical -> "❌"
    end
  end

  @doc """
  Gets CSS badge class for SLO status.

  Returns Tailwind CSS classes for status badges.

  ## Examples

      iex> ScraperSLOs.status_badge_class(:meets_target)
      "bg-green-100 text-green-800"

      iex> ScraperSLOs.status_badge_class(:below_target)
      "bg-yellow-100 text-yellow-800"

      iex> ScraperSLOs.status_badge_class(:critical)
      "bg-red-100 text-red-800"
  """
  def status_badge_class(status) do
    case status do
      :meets_target -> "bg-green-100 text-green-800"
      :below_target -> "bg-yellow-100 text-yellow-800"
      :critical -> "bg-red-100 text-red-800"
    end
  end

  @doc """
  Enriches scraper metrics with SLO status.

  Takes a scraper metrics map and adds SLO-related fields.

  ## Examples

      iex> metrics = %{worker: "cinema_city", success_rate: 96.5, avg_duration_ms: 1800}
      iex> ScraperSLOs.enrich_with_slo(metrics)
      %{
        worker: "cinema_city",
        success_rate: 96.5,
        avg_duration_ms: 1800,
        slo: %{...},
        slo_status: :meets_target,
        slo_indicator: "✅"
      }
  """
  def enrich_with_slo(metrics) do
    slo = get_slo(metrics.worker)
    status = check_slo_status(slo, metrics.success_rate, metrics.avg_duration_ms)
    indicator = status_indicator(status)

    metrics
    |> Map.put(:slo, slo)
    |> Map.put(:slo_status, status)
    |> Map.put(:slo_indicator, indicator)
  end
end
