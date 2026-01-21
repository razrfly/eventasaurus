defmodule EventasaurusWeb.Admin.CardTypes.SourceAggregationCard do
  @moduledoc """
  Source Aggregation card type implementation for social card previews.

  Source Aggregation cards use fixed Indigo brand colors.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  alias EventasaurusWeb.Admin.CardTypes.Helpers

  import EventasaurusWeb.SocialCardView, only: [render_source_aggregation_card_svg: 1]

  @impl true
  def card_type, do: :source_aggregation

  @impl true
  def generate_mock_data do
    %{
      city: %{
        id: 1,
        name: "Kraków",
        slug: "krakow",
        country: %{
          name: "Poland",
          code: "PL"
        }
      },
      content_type: "SocialEvent",
      identifier: "pubquiz-pl",
      source_name: "PubQuiz Poland",
      total_event_count: 42,
      location_count: 15,
      hero_image: "/images/events/abstract/abstract1.png",
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    render_source_aggregation_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :source_name, label: "Source Name", type: :text, path: [:source_name]},
      %{name: :city_name, label: "City Name", type: :text, path: [:city, :name]},
      %{name: :identifier, label: "Identifier (slug)", type: :text, path: [:identifier]},
      %{
        name: :total_event_count,
        label: "Event Count",
        type: :number,
        path: [:total_event_count],
        min: 0
      },
      %{
        name: :location_count,
        label: "Locations",
        type: :number,
        path: [:location_count],
        min: 0
      },
      %{
        name: :content_type,
        label: "Content Type",
        type: :select,
        path: [:content_type],
        options: [
          {"SocialEvent", "Social Event"},
          {"FoodEvent", "Food Event"},
          {"Festival", "Festival"},
          {"MusicEvent", "Music Event"},
          {"TheaterEvent", "Theater Event"},
          {"ComedyEvent", "Comedy Event"},
          {"ScreeningEvent", "Screening Event"}
        ]
      },
      %{name: :hero_image, label: "Hero Image URL", type: :text, path: [:hero_image]}
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | source_name: Map.get(params, "source_name", current.source_name),
        identifier: Map.get(params, "identifier", current.identifier),
        content_type: Map.get(params, "content_type", current.content_type),
        total_event_count:
          Helpers.parse_int(Map.get(params, "total_event_count"), current.total_event_count),
        location_count:
          Helpers.parse_int(Map.get(params, "location_count"), current.location_count),
        hero_image: Map.get(params, "hero_image", current.hero_image),
        city: %{
          current.city
          | name: Map.get(params, "city_name", current.city.name)
        }
    }
  end

  @impl true
  def update_event_name, do: "update_mock_source_aggregation"

  @impl true
  def form_param_key, do: "aggregation"
end
