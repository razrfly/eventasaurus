defmodule EventasaurusWeb.PerformerSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for performer pages.

  This controller generates social cards with Wombie branding for performer pages,
  showing performer name, event count, and performer image.

  Route: GET /social-cards/performer/:slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :performer

  alias EventasaurusApp.Images.PerformerImages
  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  import EventasaurusWeb.SocialCardView,
    only: [sanitize_performer: 1, render_performer_card_svg: 1]

  @impl true
  def lookup_entity(%{"slug" => slug}) do
    case PerformerStore.get_performer_by_slug(slug, preload_events: true) do
      nil -> {:error, :not_found, "Performer not found for slug: #{slug}"}
      performer -> {:ok, performer}
    end
  end

  @impl true
  def build_card_data(performer) do
    event_count = count_upcoming_events(performer)

    # Get cached image URL (prefer CDN, fallback to original)
    image_url =
      PerformerImages.get_url_with_fallback(performer.id, performer.image_url)

    %{
      name: performer.name,
      slug: performer.slug,
      event_count: event_count,
      image_url: image_url,
      updated_at: performer.updated_at
    }
  end

  @impl true
  def build_slug(%{"slug" => slug}, _data), do: slug

  @impl true
  def sanitize(data), do: sanitize_performer(data)

  @impl true
  def render_svg(data), do: render_performer_card_svg(data)

  # Count upcoming events for a performer
  # Uses PublicEvent.next_occurrence_date/1 to check if event has future occurrences
  defp count_upcoming_events(performer) do
    now = DateTime.utc_now()

    performer.public_events
    |> Enum.count(fn event ->
      next_date = PublicEvent.next_occurrence_date(event)
      next_date != nil and DateTime.compare(next_date, now) != :lt
    end)
  end
end
