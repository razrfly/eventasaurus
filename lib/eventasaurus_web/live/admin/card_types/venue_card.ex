defmodule EventasaurusWeb.Admin.CardTypes.VenueCard do
  @moduledoc """
  Venue card type implementation for social card previews.

  Venue cards use fixed Emerald brand colors.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  import EventasaurusWeb.SocialCardView, only: [render_venue_card_svg: 1]

  @impl true
  def card_type, do: :venue

  @impl true
  def generate_mock_data do
    %{
      id: 1,
      name: "Blue Note Jazz Club",
      slug: "blue-note-jazz-club",
      address: "ul. Nowy Świat 22, 00-373 Warszawa",
      city_ref: %{
        name: "Warsaw",
        slug: "warsaw"
      },
      event_count: 24,
      cover_image_url: "/images/events/abstract/abstract3.png",
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    render_venue_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :name, label: "Venue Name", type: :text, path: [:name]},
      %{name: :city_name, label: "City Name", type: :text, path: [:city_ref, :name]},
      %{name: :address, label: "Address", type: :text, path: [:address]},
      %{name: :event_count, label: "Upcoming Events", type: :number, path: [:event_count], min: 0},
      %{name: :cover_image_url, label: "Cover Image URL", type: :text, path: [:cover_image_url]}
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | name: Map.get(params, "name", current.name),
        address: Map.get(params, "address", current.address),
        event_count: parse_int(Map.get(params, "event_count"), current.event_count),
        cover_image_url: Map.get(params, "cover_image_url", current.cover_image_url),
        city_ref: %{
          current.city_ref
          | name: Map.get(params, "city_name", current.city_ref.name)
        }
    }
  end

  @impl true
  def update_event_name, do: "update_mock_venue"

  @impl true
  def form_param_key, do: "venue"

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
