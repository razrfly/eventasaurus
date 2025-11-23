defmodule EventasaurusDiscovery.PublicEvents.AggregatedEventGroup do
  @moduledoc """
  Virtual struct representing a group of aggregated events on the index page.

  Used when multiple events from the same source and content type should be
  displayed as a single card linking to an aggregated content view.

  Example: 14 PubQuiz events in Kraków shown as one "PubQuiz Poland" card.
  """

  alias EventasaurusDiscovery.AggregationTypeSlug

  @type t :: %__MODULE__{
          source_id: integer(),
          source_slug: String.t(),
          source_name: String.t(),
          aggregation_type: String.t(),
          city_id: integer(),
          city: map(),
          event_count: integer(),
          venue_count: integer(),
          categories: list(),
          cover_image_url: String.t() | nil,
          is_recurring: boolean()
        }

  defstruct [
    :source_id,
    :source_slug,
    :source_name,
    :aggregation_type,
    :city_id,
    :city,
    :event_count,
    :venue_count,
    :categories,
    :cover_image_url,
    :is_recurring
  ]

  @doc """
  Returns the path to the aggregated content view for this group.

  Uses URL-friendly slugs (e.g., "social", "food", "movies") instead of
  schema.org types (e.g., "SocialEvent", "FoodEvent", "ScreeningEvent").
  """
  def path(%__MODULE__{} = group) do
    slug = AggregationTypeSlug.to_slug(group.aggregation_type)
    "/c/#{group.city.slug}/#{slug}/#{group.source_slug}"
  end

  @doc """
  Returns a human-readable title for the group.
  """
  def title(%__MODULE__{} = group) do
    group.source_name
  end

  @doc """
  Returns a human-readable description for the group.
  """
  def description(%__MODULE__{} = group) do
    venue_text = if group.venue_count == 1, do: "venue", else: "venues"
    event_text = if group.event_count == 1, do: "event", else: "events"

    "#{group.event_count} #{event_text} across #{group.venue_count} #{venue_text}"
  end
end
