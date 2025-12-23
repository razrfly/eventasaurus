defmodule EventasaurusWeb.Admin.CardTypes.ActivityCard do
  @moduledoc """
  Activity card type implementation for social card previews.

  Activity cards represent public events and use fixed Teal brand colors.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  import EventasaurusWeb.SocialCardView, only: [render_activity_card_svg: 1]

  @impl true
  def card_type, do: :activity

  @impl true
  def generate_mock_data do
    %{
      id: 1,
      title: "Jazz Night at Blue Note",
      slug: "jazz-night-blue-note",
      cover_image_url: "/images/events/abstract/abstract3.png",
      venue: %{
        name: "Blue Note Jazz Club",
        city_ref: %{
          name: "Warsaw"
        }
      },
      occurrence_list: [
        %{
          datetime: DateTime.add(DateTime.utc_now(), 2, :day),
          date: Date.add(Date.utc_today(), 2),
          time: ~T[20:00:00]
        }
      ],
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    render_activity_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :title, label: "Title", type: :text, path: [:title]},
      %{name: :cover_image_url, label: "Cover Image URL", type: :text, path: [:cover_image_url]},
      %{name: :venue_name, label: "Venue Name", type: :text, path: [:venue, :name]},
      %{name: :city_name, label: "City Name", type: :text, path: [:venue, :city_ref, :name]}
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | title: Map.get(params, "title", current.title),
        cover_image_url: Map.get(params, "cover_image_url", current.cover_image_url),
        venue: %{
          current.venue
          | name: Map.get(params, "venue_name", current.venue.name),
            city_ref: %{
              current.venue.city_ref
              | name: Map.get(params, "city_name", current.venue.city_ref.name)
            }
        }
    }
  end

  @impl true
  def update_event_name, do: "update_mock_activity"

  @impl true
  def form_param_key, do: "activity"
end
