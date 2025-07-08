defmodule EventasaurusWeb.Live.Components.RichDataAdapterBehaviour do
  @moduledoc """
  Behavior for adapting different rich data sources into a standardized format
  for display components.

  This allows the rich content display system to work with heterogeneous data
  sources (TMDB, Google Places, future APIs) by normalizing them into a
  common structure that generic display components can understand.

  ## Standardized Data Format

  The adapter normalizes data into this structure:

      %{
        # Core identification
        id: "unique_id",
        type: :movie | :tv | :venue | :restaurant | :activity | :book | :music | :custom,
        title: "Display Title",
        description: "Brief description or tagline",

        # Primary media
        primary_image: %{url: "...", alt: "...", type: :poster | :backdrop | :photo},
        secondary_image: %{url: "...", alt: "...", type: :poster | :backdrop | :photo},

        # Core metadata
        rating: %{value: 4.5, scale: 5, count: 1234, display: "4.5/5"},
        year: 2023,
        status: "active" | "closed" | "coming_soon" | nil,

        # Categories and classification
        categories: ["Action", "Adventure"] | ["Restaurant", "Italian"],
        tags: ["Popular", "Award Winner"],

        # Links and external references
        external_urls: %{
          official: "...",
          source: "...",
          maps: "...",
          social: %{facebook: "...", twitter: "..."}
        },

        # Structured sections for display
        sections: %{
          hero: %{...},          # Data specific to hero display
          details: %{...},       # Contact info, technical details, etc.
          media: %{...},         # Photos, videos, galleries
          people: %{...},        # Cast, crew, staff
          reviews: %{...},       # User reviews and ratings
          related: %{...}        # Related items, recommendations
        }
      }

  ## Available Sections

  Different content types support different sections:
  - Movies/TV: :hero, :overview, :cast, :media, :details
  - Venues/Restaurants: :hero, :details, :reviews, :photos
  - Books: :hero, :details, :reviews, :related
  - Music: :hero, :details, :tracks, :related

  """

  @type content_type :: :movie | :tv | :venue | :restaurant | :activity | :book | :music | :custom
  @type section_name :: :hero | :overview | :details | :cast | :media | :reviews | :photos | :tracks | :related | :people

  @type standardized_data :: %{
    id: String.t(),
    type: content_type(),
    title: String.t(),
    description: String.t() | nil,
    primary_image: map() | nil,
    secondary_image: map() | nil,
    rating: map() | nil,
    year: integer() | nil,
    status: String.t() | nil,
    categories: [String.t()],
    tags: [String.t()],
    external_urls: map(),
    sections: map()
  }

  @doc """
  Adapts raw external data into the standardized format.

  Takes the original data from an API or provider and transforms it
  into the common structure that display components can understand.
  """
  @callback adapt(raw_data :: map()) :: standardized_data()

  @doc """
  Returns the content type that this adapter handles.
  """
  @callback content_type() :: content_type()

  @doc """
  Returns the list of sections this content type supports.
  """
  @callback supported_sections() :: [section_name()]

  @doc """
  Returns whether this adapter can handle the given raw data.

  Used for automatic adapter selection when the data type is ambiguous.
  """
  @callback handles?(raw_data :: map()) :: boolean()

  @doc """
  Returns display configuration for this content type.

  Includes default sections to show, compact mode behavior, etc.
  """
  @callback display_config() :: %{
    default_sections: [section_name()],
    compact_sections: [section_name()],
    required_fields: [atom()],
    optional_fields: [atom()]
  }
end
