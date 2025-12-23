defmodule EventasaurusWeb.EventSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for events.

  Route: GET /social-cards/event/:slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :event

  alias EventasaurusApp.Events
  import EventasaurusWeb.SocialCardView, only: [sanitize_event: 1, render_social_card_svg: 1]

  # Keep the old function name for route compatibility
  def generate_card_by_slug(conn, params) do
    generate_card(conn, params)
  end

  @impl true
  def lookup_entity(%{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil -> {:error, :not_found, "Event not found for slug: #{slug}"}
      event -> {:ok, event}
    end
  end

  @impl true
  def build_card_data(event), do: event

  @impl true
  def build_slug(%{"slug" => slug}, _data), do: slug

  @impl true
  def sanitize(data), do: sanitize_event(data)

  @impl true
  def render_svg(data), do: render_social_card_svg(data)
end
