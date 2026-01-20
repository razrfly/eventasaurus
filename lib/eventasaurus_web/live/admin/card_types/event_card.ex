defmodule EventasaurusWeb.Admin.CardTypes.EventCard do
  @moduledoc """
  Event card type implementation for social card previews.

  Event cards support user-selectable themes and are used for private group events.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  alias EventasaurusWeb.Admin.CardTypes.Helpers
  alias EventasaurusWeb.SocialCardView

  @impl true
  def card_type, do: :event

  @impl true
  def generate_mock_data do
    %{
      title: "Sample Event: Testing Social Card Design Across All Themes",
      cover_image_url: "/images/events/abstract/abstract1.png",
      theme: :minimal,
      slug: "mock-event-preview",
      description: "This is a mock event for testing social card designs",
      start_at: Helpers.sample_datetime(3, 20, 0),
      timezone: "Europe/Warsaw",
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    SocialCardView.render_social_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :title, label: "Event Title", type: :text, path: [:title]},
      %{
        name: :cover_image_url,
        label: "Cover Image URL",
        type: :text,
        path: [:cover_image_url],
        hint: "Use local paths like /images/events/abstract/abstract1.png or external URLs"
      }
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | title: Map.get(params, "title", current.title),
        cover_image_url: Map.get(params, "cover_image_url", current.cover_image_url)
    }
  end

  @impl true
  def update_event_name, do: "update_mock_event"

  @impl true
  def form_param_key, do: "event"
end
