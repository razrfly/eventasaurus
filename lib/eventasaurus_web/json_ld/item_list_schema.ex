defmodule EventasaurusWeb.JsonLd.ItemListSchema do
  @moduledoc """
  Generates JSON-LD structured data for event list pages using schema.org ItemList.

  This module creates ItemList markup for aggregation pages (trivia, food, music, etc.)
  that helps search engines understand the collection of events on the page.

  ## Schema.org Types
  - ItemList: https://schema.org/ItemList
  - ListItem: https://schema.org/ListItem
  - Event subtypes: https://schema.org/Event

  ## References
  - Schema.org ItemList: https://schema.org/ItemList
  - Google Event Rich Results: https://developers.google.com/search/docs/appearance/structured-data/event
  """

  require Logger
  alias EventasaurusWeb.JsonLd.PublicEventSchema

  @doc """
  Generates JSON-LD ItemList structured data for an aggregation page.

  ## Parameters
    - events: List of PublicEvent structs (preloaded with associations)
    - schema_type: Schema.org event type (e.g., "SocialEvent", "FoodEvent")
    - identifier: Aggregation identifier (e.g., "trivia-nights")
    - city: City struct
    - opts: Optional configuration
      - :max_items - Maximum number of events to include (default: 20)

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> ItemListSchema.generate(events, "SocialEvent", "trivia-nights", city)
      "{\"@context\":\"https://schema.org\",\"@type\":\"ItemList\",...}"
  """
  def generate(events, schema_type, identifier, city, opts \\ []) do
    events
    |> build_item_list_schema(schema_type, identifier, city, opts)
    |> Jason.encode!()
  end

  @doc """
  Builds the ItemList schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_item_list_schema(events, schema_type, identifier, city, opts \\ []) do
    max_items = Keyword.get(opts, :max_items, 20)

    # Take only the specified number of events
    limited_events = Enum.take(events, max_items)

    %{
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => build_list_name(schema_type, identifier, city),
      "description" => build_list_description(schema_type, identifier, city, length(events)),
      "url" => build_canonical_url(schema_type, identifier, city),
      "numberOfItems" => length(limited_events),
      "itemListElement" =>
        limited_events
        |> Enum.with_index(1)
        |> Enum.map(fn {event, position} ->
          build_list_item(event, position)
        end)
    }
  end

  # Build a human-readable name for the list
  defp build_list_name(schema_type, identifier, city) do
    # Convert schema type to friendly name
    type_name = schema_type_to_friendly_name(schema_type)

    # Convert identifier to title case
    identifier_name =
      identifier
      |> String.replace("-", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    "#{identifier_name} - #{type_name} in #{city.name}"
  end

  # Build SEO-friendly description
  defp build_list_description(schema_type, identifier, city, total_count) do
    type_name = schema_type_to_friendly_name(schema_type)

    identifier_name =
      identifier
      |> String.replace("-", " ")

    "Discover #{identifier_name} and other #{type_name} in #{city.name}. " <>
      "#{total_count} #{pluralize("event", total_count)} available."
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"

  # Convert schema.org type to friendly name
  defp schema_type_to_friendly_name(schema_type) do
    case schema_type do
      "SocialEvent" -> "social events"
      "FoodEvent" -> "food events"
      "MusicEvent" -> "music events"
      "ComedyEvent" -> "comedy shows"
      "DanceEvent" -> "dance performances"
      "EducationEvent" -> "classes and workshops"
      "SportsEvent" -> "sports events"
      "TheaterEvent" -> "theater performances"
      "Festival" -> "festivals"
      "ScreeningEvent" -> "movie screenings"
      _ -> "events"
    end
  end

  # Build canonical URL for the aggregation page
  defp build_canonical_url(schema_type, identifier, city) do
    base_url = EventasaurusWeb.Layouts.get_base_url()

    # Convert schema.org type to URL slug
    content_type_slug = EventasaurusDiscovery.AggregationTypeSlug.to_slug(schema_type)

    "#{base_url}/c/#{city.slug}/#{content_type_slug}/#{identifier}"
  end

  # Build a ListItem for an event
  defp build_list_item(event, position) do
    %{
      "@type" => "ListItem",
      "position" => position,
      "item" => PublicEventSchema.build_event_schema(event)
    }
  end
end
