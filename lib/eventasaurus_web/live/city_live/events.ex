defmodule EventasaurusWeb.CityLive.Events do
  @moduledoc """
  LiveView for city events with timeframe filtering.
  """
  use EventasaurusWeb, :live_view

  # Temporary stub - redirects to index
  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/c/#{city_slug}")}
  end
end