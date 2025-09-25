defmodule EventasaurusWeb.CityLive.Search do
  @moduledoc """
  LiveView for city-specific search.
  """
  use EventasaurusWeb, :live_view

  # Temporary stub - redirects to index
  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/c/#{city_slug}")}
  end
end