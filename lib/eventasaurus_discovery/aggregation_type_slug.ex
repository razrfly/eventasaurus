defmodule EventasaurusDiscovery.AggregationTypeSlug do
  @moduledoc """
  Bidirectional mapping between schema.org event types (stored in database)
  and URL-friendly slugs (used in routes).

  This keeps semantic schema.org types internally while presenting
  clean, SEO-friendly URLs to users.

  ## Examples

      iex> AggregationTypeSlug.to_slug("SocialEvent")
      "social"

      iex> AggregationTypeSlug.from_slug("social")
      "SocialEvent"

      iex> AggregationTypeSlug.from_slug("SOCIAL")
      "SocialEvent"
  """

  @schema_to_slug %{
    "SocialEvent" => "social",
    "FoodEvent" => "food",
    "ScreeningEvent" => "movies",
    "MusicEvent" => "music",
    "Event" => "events",
    "ComedyEvent" => "comedy",
    "DanceEvent" => "dance",
    "EducationEvent" => "classes",
    "Festival" => "festivals",
    "SportsEvent" => "sports",
    "TheaterEvent" => "theater"
  }

  @slug_to_schema Map.new(@schema_to_slug, fn {k, v} -> {v, k} end)

  # Compile-time validation: ensure no duplicate slugs
  if length(Map.values(@schema_to_slug)) != length(Enum.uniq(Map.values(@schema_to_slug))) do
    raise "Duplicate URL slugs detected in aggregation type mapping!"
  end

  @doc """
  Convert a schema.org event type to a URL-friendly slug.

  Returns the input unchanged if no mapping exists.
  Returns nil if input is nil.
  """
  def to_slug(nil), do: nil

  def to_slug(schema_type) when is_binary(schema_type) do
    Map.get(@schema_to_slug, schema_type, schema_type)
  end

  @doc """
  Convert a URL slug to its corresponding schema.org event type.

  Performs case-insensitive matching for user-friendly URLs.
  Returns the input unchanged if no mapping exists.
  Returns nil if input is nil.
  """
  def from_slug(nil), do: nil

  def from_slug(slug) when is_binary(slug) do
    # Normalize to lowercase for case-insensitive matching
    normalized = String.downcase(slug)
    Map.get(@slug_to_schema, normalized, slug)
  end

  @doc """
  Returns all valid URL slugs.
  """
  def all_slugs, do: Map.values(@schema_to_slug)

  @doc """
  Returns all schema.org event types that have slug mappings.
  """
  def all_schema_types, do: Map.keys(@schema_to_slug)
end
