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

  def name, do: "Restaurant Week"
  def key, do: "week_pl"
  # Regional Poland source
  def priority, do: 45

  def config do
    %{
      base_url: Config.base_url(),
      api_type: :rest_json,
      requires_auth: false,
      supports_api: true,
      supports_pagination: true,
      # GPS coordinates included
      requires_geocoding: false,
      rate_limit: %{
        # 2 seconds between requests
        requests_per_second: 0.5,
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
  Fallback festival definitions.

  These are only used if the Week.pl API is unavailable or returns no festivals.
  The primary source of festival data is the Week.pl GraphQL API via Client.fetch_festival_editions/0.

  NOTE: Update these annually if needed, but prefer using the API as the source of truth.
  """
  def fallback_festivals do
    [
      # Fallback festivals (only used if API fails)
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
  Check if any festival is currently active.

  First tries to fetch ongoing festivals from the Week.pl API.
  If API is unavailable, falls back to checking fallback_festivals().
  """
  def festival_active? do
    case EventasaurusDiscovery.Sources.WeekPl.Client.fetch_festival_editions() do
      {:ok, editions} when editions != [] ->
        # API returned festivals - at least one is ongoing
        true

      {:ok, []} ->
        # API returned empty list - no ongoing festivals
        false

      {:error, _reason} ->
        # API failed - fall back to checking hardcoded festivals
        today = Date.utc_today()

        Enum.any?(fallback_festivals(), fn festival ->
          Date.compare(today, festival.starts_at) in [:eq, :gt] and
            Date.compare(today, festival.ends_at) in [:eq, :lt]
        end)
    end
  end
end
