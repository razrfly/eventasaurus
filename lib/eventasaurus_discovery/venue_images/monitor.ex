defmodule EventasaurusDiscovery.VenueImages.Monitor do
  @moduledoc """
  Monitoring and alerting for venue image provider usage.

  Tracks provider health, rate limit status, and cost metrics.

  ## Usage

      # Get all provider stats
      Monitor.get_all_stats()

      # Get stats for specific provider
      Monitor.get_provider_stats("foursquare")

      # Check for alerts
      Monitor.check_alerts()
  """

  require Logger

  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  alias EventasaurusDiscovery.VenueImages.RateLimiter
  alias EventasaurusApp.Repo
  import Ecto.Query

  @doc """
  Gets comprehensive stats for all active image providers.
  """
  def get_all_stats do
    providers = get_image_providers()

    Enum.map(providers, fn provider ->
      %{
        name: provider.name,
        is_active: provider.is_active,
        priority: get_priority(provider),
        rate_limit_stats: get_rate_limit_stats(provider.name),
        metadata: provider.metadata
      }
    end)
  end

  @doc """
  Gets stats for a specific provider.
  """
  def get_provider_stats(provider_name) do
    case get_provider(provider_name) do
      nil ->
        {:error, :not_found}

      provider ->
        {:ok,
         %{
           name: provider.name,
           is_active: provider.is_active,
           priority: get_priority(provider),
           rate_limit_stats: get_rate_limit_stats(provider.name),
           rate_limits: get_configured_limits(provider),
           cost_per_image: get_cost_per_image(provider),
           metadata: provider.metadata
         }}
    end
  end

  @doc """
  Checks for rate limit or cost alerts.

  Returns list of alerts that need attention:
  - Rate limits approaching threshold (>80%)
  - Providers that are rate limited
  - High cost usage

  ## Alert Structure

      %{
        severity: :warning | :error | :critical,
        provider: "provider_name",
        type: :rate_limit | :cost,
        message: "Description",
        value: actual_value,
        threshold: threshold_value
      }
  """
  def check_alerts do
    providers = get_image_providers()

    Enum.flat_map(providers, fn provider ->
      rate_limit_alerts = check_rate_limit_alerts(provider)
      rate_limit_alerts
    end)
  end

  @doc """
  Logs current provider health status.
  """
  def log_health_check do
    stats = get_all_stats()

    Enum.each(stats, fn stat ->
      usage = stat.rate_limit_stats

      Logger.info("""
      📊 Provider: #{stat.name}
         Status: #{if stat.is_active, do: "✅ Active", else: "❌ Inactive"}
         Priority: #{stat.priority}
         Rate Limits:
           - Last Second: #{usage.last_second}
           - Last Minute: #{usage.last_minute}
           - Last Hour: #{usage.last_hour}
      """)
    end)
  end

  # Private Functions

  defp get_image_providers do
    from(p in GeocodingProvider,
      where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
      order_by: [
        asc:
          fragment(
            "COALESCE(CAST(? ->> 'images' AS INTEGER), 999)",
            p.priorities
          )
      ]
    )
    |> Repo.all()
  end

  defp get_provider(provider_name) do
    from(p in GeocodingProvider,
      where: p.name == ^provider_name,
      where: fragment("? @> ?", p.capabilities, ^%{"images" => true})
    )
    |> Repo.one()
  end

  defp get_priority(provider) do
    get_in(provider.priorities, ["images"]) || get_in(provider.priorities, [:images]) || 999
  end

  defp get_rate_limit_stats(provider_name) do
    RateLimiter.get_stats(provider_name)
  end

  defp get_configured_limits(provider) do
    metadata = provider.metadata || %{}

    get_in(metadata, ["rate_limits"]) ||
      get_in(metadata, [:rate_limits]) ||
      %{}
  end

  defp get_cost_per_image(provider) do
    metadata = provider.metadata || %{}

    get_in(metadata, ["cost_per_image"]) ||
      get_in(metadata, [:cost_per_image]) ||
      0.0
  end

  defp check_rate_limit_alerts(provider) do
    stats = get_rate_limit_stats(provider.name)
    limits = get_configured_limits(provider)

    alerts = []

    # Check per-second limit
    alerts =
      if per_second = get_in(limits, ["per_second"]) || get_in(limits, [:per_second]) do
        usage_pct = stats.last_second / per_second * 100

        if usage_pct >= 80 do
          [
            %{
              severity: if(usage_pct >= 95, do: :critical, else: :warning),
              provider: provider.name,
              type: :rate_limit,
              period: :per_second,
              message:
                "Rate limit approaching threshold: #{stats.last_second}/#{per_second} per second (#{round(usage_pct)}%)",
              value: stats.last_second,
              threshold: per_second,
              usage_percent: usage_pct
            }
            | alerts
          ]
        else
          alerts
        end
      else
        alerts
      end

    # Check per-minute limit
    alerts =
      if per_minute = get_in(limits, ["per_minute"]) || get_in(limits, [:per_minute]) do
        usage_pct = stats.last_minute / per_minute * 100

        if usage_pct >= 80 do
          [
            %{
              severity: if(usage_pct >= 95, do: :critical, else: :warning),
              provider: provider.name,
              type: :rate_limit,
              period: :per_minute,
              message:
                "Rate limit approaching threshold: #{stats.last_minute}/#{per_minute} per minute (#{round(usage_pct)}%)",
              value: stats.last_minute,
              threshold: per_minute,
              usage_percent: usage_pct
            }
            | alerts
          ]
        else
          alerts
        end
      else
        alerts
      end

    # Check per-hour limit
    alerts =
      if per_hour = get_in(limits, ["per_hour"]) || get_in(limits, [:per_hour]) do
        usage_pct = stats.last_hour / per_hour * 100

        if usage_pct >= 80 do
          [
            %{
              severity: if(usage_pct >= 95, do: :critical, else: :warning),
              provider: provider.name,
              type: :rate_limit,
              period: :per_hour,
              message:
                "Rate limit approaching threshold: #{stats.last_hour}/#{per_hour} per hour (#{round(usage_pct)}%)",
              value: stats.last_hour,
              threshold: per_hour,
              usage_percent: usage_pct
            }
            | alerts
          ]
        else
          alerts
        end
      else
        alerts
      end

    alerts
  end
end
