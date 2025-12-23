defmodule EventasaurusWeb.Admin.CardTypes.CityCard do
  @moduledoc """
  City card type implementation for social card previews.

  City cards use fixed Deep Blue brand colors.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  alias EventasaurusWeb.SocialCardView

  @impl true
  def card_type, do: :city

  @impl true
  def generate_mock_data do
    %{
      id: 1,
      name: "Warsaw",
      slug: "warsaw",
      country: %{
        name: "Poland",
        code: "PL"
      },
      stats: %{
        events_count: 127,
        venues_count: 45,
        categories_count: 12
      },
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def generate_mock_data(_dependencies), do: generate_mock_data()

  @impl true
  def render_svg(mock_data) do
    stats = Map.get(mock_data, :stats, %{})
    SocialCardView.render_city_card_svg(mock_data, stats)
  end

  @impl true
  def form_fields do
    [
      %{name: :name, label: "City Name", type: :text, path: [:name]},
      %{name: :events_count, label: "Events Count", type: :number, path: [:stats, :events_count], min: 0},
      %{name: :venues_count, label: "Venues Count", type: :number, path: [:stats, :venues_count], min: 0},
      %{name: :categories_count, label: "Categories", type: :number, path: [:stats, :categories_count], min: 0}
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | name: Map.get(params, "name", current.name),
        stats: %{
          current.stats
          | events_count: parse_int(Map.get(params, "events_count"), current.stats.events_count),
            venues_count: parse_int(Map.get(params, "venues_count"), current.stats.venues_count),
            categories_count: parse_int(Map.get(params, "categories_count"), current.stats.categories_count)
        }
    }
  end

  @impl true
  def update_event_name, do: "update_mock_city"

  @impl true
  def form_param_key, do: "city"

  # Helper to parse integer with default
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
