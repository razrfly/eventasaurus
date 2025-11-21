defmodule EventasaurusDiscovery.Sources.WeekPl.Source do
  @moduledoc """
  week.pl Restaurant Festival Integration

  Integrates RestaurantWeek, FineDiningWeek, and BreakfastWeek festivals
  across 13 Polish cities. Uses Next.js data API endpoints.

  ## Event Model
  - Occurrence Type: explicit (finite dates during festival)
  - Consolidation: Daily (one event per restaurant per day)
  - Consolidation Key: metadata.restaurant_date_id
  - External ID: week_pl_{restaurant_id}_{date}_{slot}

  See Issue #2328 for event model rationale.
  See Issue #2329 for implementation phases.
  """

  alias EventasaurusDiscovery.Sources.WeekPl.Config

  def name, do: "week.pl"
  def key, do: "week_pl"
  def priority, do: 45  # Regional Poland source

  def config do
    %{
      base_url: Config.base_url(),
      api_type: :rest_json,
      requires_auth: false,
      supports_api: true,
      supports_pagination: true,
      requires_geocoding: false,  # GPS coordinates included
      rate_limit: %{
        requests_per_second: 0.5,  # 2 seconds between requests
        max_concurrent: 2
      },
      metadata: %{
        description: "Restaurant festival platform for Poland (RestaurantWeek, FineDiningWeek)",
        coverage: "13 Polish cities",
        data_freshness: "Real-time availability during festival periods"
      }
    }
  end

  def supported_cities do
    [
      %{id: "1", name: "Kraków", country: "Poland"},
      %{id: "5", name: "Warszawa", country: "Poland"},
      %{id: "2", name: "Wrocław", country: "Poland"},
      %{id: "7", name: "Poznań", country: "Poland"},
      %{id: "12", name: "Trójmiasto", country: "Poland"},
      %{id: "9", name: "Śląsk", country: "Poland"},
      %{id: "11", name: "Łódź", country: "Poland"},
      %{id: "3", name: "Białystok", country: "Poland"},
      %{id: "4", name: "Bydgoszcz", country: "Poland"},
      %{id: "6", name: "Lubelskie", country: "Poland"},
      %{id: "8", name: "Rzeszów", country: "Poland"},
      %{id: "10", name: "Szczecin", country: "Poland"},
      %{id: "13", name: "Warmia i Mazury", country: "Poland"}
    ]
  end

  @doc """
  Festival periods (update annually)

  For testing/development, includes 2025 test festivals.
  Production festivals for 2026.
  """
  def active_festivals do
    [
      # 2025 Test Festivals (for development/testing)
      %{
        name: "RestaurantWeek Test Winter",
        code: "RWT25W",
        starts_at: ~D[2025-11-15],
        ends_at: ~D[2025-12-31],
        price: 63.0
      },
      # 2026 Production Festivals
      %{
        name: "RestaurantWeek Spring",
        code: "RWP26W",
        starts_at: ~D[2026-03-04],
        ends_at: ~D[2026-04-22],
        price: 63.0
      },
      %{
        name: "FineDiningWeek",
        code: "FDW26S",
        starts_at: ~D[2026-07-01],
        ends_at: ~D[2026-08-13],
        price: 161.0
      },
      %{
        name: "RestaurantWeek Fall",
        code: "RWF26",
        starts_at: ~D[2026-10-07],
        ends_at: ~D[2026-11-22],
        price: 63.0
      }
    ]
  end

  @doc """
  Check if any festival is currently active
  """
  def festival_active? do
    today = Date.utc_today()

    Enum.any?(active_festivals(), fn festival ->
      Date.compare(today, festival.starts_at) in [:eq, :gt] and
        Date.compare(today, festival.ends_at) in [:eq, :lt]
    end)
  end
end
