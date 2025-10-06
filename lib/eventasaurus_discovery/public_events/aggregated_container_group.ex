defmodule EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup do
  @moduledoc """
  Virtual struct representing a group of containerized events on the index page.

  Used when events belonging to a container (festival, conference, tour, etc.)
  should be displayed as a single aggregated card linking to the container detail view.

  Example: 10 Unsound events shown as one "Unsound Kraków 2025" festival card.

  Note: Unlike movies, individual events within containers are NOT hidden on the index.
  Both the container group AND the individual events are visible.
  """

  alias EventasaurusDiscovery.PublicEvents.PublicEventContainer

  @type t :: %__MODULE__{
          container_id: integer(),
          container_slug: String.t(),
          container_type: atom(),
          container_title: String.t(),
          description: String.t() | nil,
          start_date: DateTime.t(),
          end_date: DateTime.t() | nil,
          city_id: integer(),
          city: map(),
          event_count: integer(),
          venue_ids: list(integer()),
          venue_names: list(String.t()),
          cover_image_url: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :container_id,
    :container_slug,
    :container_type,
    :container_title,
    :description,
    :start_date,
    :end_date,
    :city_id,
    :city,
    :event_count,
    :venue_ids,
    :venue_names,
    :cover_image_url,
    :metadata
  ]

  @doc """
  Returns the path to the container detail view for this group.

  Uses container type to determine route segment (festivals, conferences, etc.)

  Examples:
    - Festival: "/krakow/festivals/unsound-krakow-2025"
    - Conference: "/krakow/conferences/techcrunch-disrupt-2025"
  """
  def path(%__MODULE__{} = group) do
    type_plural = PublicEventContainer.container_type_plural(group.container_type)
    "/c/#{group.city.slug}/#{type_plural}/#{group.container_slug}"
  end

  @doc """
  Returns the Tailwind ring color class for this container type.

  Examples:
    - Festival: "ring-purple-500"
    - Conference: "ring-orange-500"
  """
  def ring_color_class(%__MODULE__{} = group) do
    PublicEventContainer.container_type_ring_color(group.container_type)
  end

  @doc """
  Returns a human-readable title for the group.
  """
  def title(%__MODULE__{} = group) do
    group.container_title
  end

  @doc """
  Returns a human-readable description for the group.

  Example: "10 events across 3 venues"
  """
  def description(%__MODULE__{} = group) do
    venue_count = length(group.venue_ids)
    venue_text = if venue_count == 1, do: "venue", else: "venues"
    event_text = if group.event_count == 1, do: "event", else: "events"

    "#{group.event_count} #{event_text} across #{venue_count} #{venue_text}"
  end

  @doc """
  Returns the container type label for display.

  Example: "Festival", "Conference"
  """
  def type_label(%__MODULE__{container_type: type}) do
    PublicEventContainer.container_type_label(%PublicEventContainer{container_type: type})
  end

  @doc """
  Returns a formatted date range string.

  Examples:
    - "Oct 7-12, 2025"
    - "Dec 15, 2025" (single day)
  """
  def date_range_text(%__MODULE__{} = group) do
    if group.end_date do
      # Multi-day event
      start_month = Calendar.strftime(group.start_date, "%b")
      start_day = Calendar.strftime(group.start_date, "%d")
      end_month = Calendar.strftime(group.end_date, "%b")
      end_day = Calendar.strftime(group.end_date, "%d")
      year = Calendar.strftime(group.start_date, "%Y")

      if start_month == end_month do
        "#{start_month} #{String.trim_leading(start_day, "0")}-#{String.trim_leading(end_day, "0")}, #{year}"
      else
        "#{start_month} #{String.trim_leading(start_day, "0")} - #{end_month} #{String.trim_leading(end_day, "0")}, #{year}"
      end
    else
      # Single day
      Calendar.strftime(group.start_date, "%b %-d, %Y")
    end
  end
end
