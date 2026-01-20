defmodule EventasaurusWeb.Admin.CardTypes.PerformerCard do
  @moduledoc """
  Performer card type implementation for social card previews.

  Performer cards use fixed Rose brand colors.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  alias EventasaurusWeb.Admin.CardTypes.Helpers

  import EventasaurusWeb.SocialCardView, only: [render_performer_card_svg: 1]

  @impl true
  def card_type, do: :performer

  @impl true
  def generate_mock_data do
    %{
      id: 1,
      name: "The Jazz Quartet",
      slug: "the-jazz-quartet",
      event_count: 8,
      image_url: "/images/events/abstract/abstract1.png",
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    render_performer_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :name, label: "Performer Name", type: :text, path: [:name]},
      %{
        name: :event_count,
        label: "Upcoming Events",
        type: :number,
        path: [:event_count],
        min: 0
      },
      %{name: :image_url, label: "Image URL", type: :text, path: [:image_url]}
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | name: Map.get(params, "name", current.name),
        event_count: Helpers.parse_int(Map.get(params, "event_count"), current.event_count),
        image_url: Map.get(params, "image_url", current.image_url)
    }
  end

  @impl true
  def update_event_name, do: "update_mock_performer"

  @impl true
  def form_param_key, do: "performer"
end
