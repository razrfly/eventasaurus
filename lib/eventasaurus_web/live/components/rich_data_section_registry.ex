defmodule EventasaurusWeb.Live.Components.RichDataSectionRegistry do
  @moduledoc """
  Registry for mapping rich data sections to their display components.

  This provides a configurable mapping between section names (like :hero, :details)
  and the LiveView components that render them. This enables the generic
  RichDataDisplayComponent to work with different content types by using
  appropriate section components.

  ## Section Types

  The registry supports these standard sections:
  - `:hero` - Primary display section with title, image, key info
  - `:overview` - Synopsis, description, summary content
  - `:details` - Technical details, contact info, specifications
  - `:cast` - People involved (cast, crew, staff)
  - `:media` - Photos, videos, galleries
  - `:reviews` - User reviews and ratings
  - `:photos` - Photo galleries (venues, products)
  - `:tracks` - Track listings (music albums)
  - `:related` - Related or recommended content

  ## Content Type Mappings

  Different content types can use different components for the same section:
  - Movies: hero -> MovieHeroComponent
  - Venues: hero -> VenueHeroComponent
  - Books: hero -> BookHeroComponent (future)

  """

  @type section_name :: atom()
  @type content_type :: atom()
  @type component_module :: module()

  # Content type to section component mappings
  @section_mappings %{
    # Movie/TV content sections
    movie: %{
      hero: EventasaurusWeb.Live.Components.MovieHeroComponent,
      overview: EventasaurusWeb.Live.Components.MovieOverviewComponent,
      cast: EventasaurusWeb.Live.Components.CastCarouselComponent,
      media: EventasaurusWeb.Live.Components.MovieMediaComponent,
      details: EventasaurusWeb.Live.Components.MovieDetailsComponent
    },
    tv: %{
      hero: EventasaurusWeb.Live.Components.MovieHeroComponent,
      overview: EventasaurusWeb.Live.Components.MovieOverviewComponent,
      cast: EventasaurusWeb.Live.Components.CastCarouselComponent,
      media: EventasaurusWeb.Live.Components.MovieMediaComponent,
      details: EventasaurusWeb.Live.Components.MovieDetailsComponent
    },

    # Venue/Restaurant/Activity content sections
    venue: %{
      hero: EventasaurusWeb.Live.Components.VenueHeroComponent,
      details: EventasaurusWeb.Live.Components.VenueDetailsComponent,
      reviews: EventasaurusWeb.Live.Components.VenueReviewsComponent,
      photos: EventasaurusWeb.Live.Components.VenuePhotosComponent
    },
    restaurant: %{
      hero: EventasaurusWeb.Live.Components.VenueHeroComponent,
      details: EventasaurusWeb.Live.Components.VenueDetailsComponent,
      reviews: EventasaurusWeb.Live.Components.VenueReviewsComponent,
      photos: EventasaurusWeb.Live.Components.VenuePhotosComponent
    },
    activity: %{
      hero: EventasaurusWeb.Live.Components.VenueHeroComponent,
      details: EventasaurusWeb.Live.Components.VenueDetailsComponent,
      reviews: EventasaurusWeb.Live.Components.VenueReviewsComponent,
      photos: EventasaurusWeb.Live.Components.VenuePhotosComponent
    },

    # Generic fallback components (for future content types)
    default: %{
      hero: EventasaurusWeb.Live.Components.GenericHeroComponent,
      details: EventasaurusWeb.Live.Components.GenericDetailsComponent,
      media: EventasaurusWeb.Live.Components.GenericMediaComponent
    }
  }

  @doc """
  Gets the component module for a given content type and section.

  Returns the appropriate LiveView component module that can render
  the specified section for the given content type.

  ## Examples

      iex> get_section_component(:movie, :hero)
      EventasaurusWeb.Live.Components.MovieHeroComponent

      iex> get_section_component(:venue, :details)
      EventasaurusWeb.Live.Components.VenueDetailsComponent

      iex> get_section_component(:unknown_type, :hero)
      EventasaurusWeb.Live.Components.GenericHeroComponent

  """
  @spec get_section_component(content_type(), section_name()) :: component_module() | nil
  def get_section_component(content_type, section_name) do
    content_mappings = @section_mappings[content_type] || @section_mappings[:default]
    content_mappings[section_name]
  end

  @doc """
  Gets all available sections for a content type.

  Returns a list of section names that are supported for the given content type.

  ## Examples

      iex> get_available_sections(:movie)
      [:hero, :overview, :cast, :media, :details]

      iex> get_available_sections(:venue)
      [:hero, :details, :reviews, :photos]

  """
  @spec get_available_sections(content_type()) :: [section_name()]
  def get_available_sections(content_type) do
    content_mappings = @section_mappings[content_type] || @section_mappings[:default]
    Map.keys(content_mappings)
  end

  @doc """
  Checks if a section is supported for a content type.

  ## Examples

      iex> has_section?(:movie, :cast)
      true

      iex> has_section?(:venue, :cast)
      false

  """
  @spec has_section?(content_type(), section_name()) :: boolean()
  def has_section?(content_type, section_name) do
    content_mappings = @section_mappings[content_type] || @section_mappings[:default]
    Map.has_key?(content_mappings, section_name)
  end

  @doc """
  Registers a new section component for a content type.

  This allows for dynamic registration of new section components,
  useful for plugins or custom content types.

  Note: This updates the module attribute at runtime and changes
  are not persistent across application restarts.
  """
  @spec register_section_component(content_type(), section_name(), component_module()) :: :ok
  def register_section_component(content_type, section_name, component_module) do
    # This is a simplified implementation - in a real application,
    # you might want to use ETS or a GenServer for dynamic registration
    Process.put({__MODULE__, content_type, section_name}, component_module)
    :ok
  end

  @doc """
  Gets a dynamically registered section component.

  This checks for components registered via register_section_component/3
  before falling back to the static mappings.
  """
  @spec get_dynamic_section_component(content_type(), section_name()) :: component_module() | nil
  def get_dynamic_section_component(content_type, section_name) do
    case Process.get({__MODULE__, content_type, section_name}) do
      nil -> get_section_component(content_type, section_name)
      component_module -> component_module
    end
  end

  @doc """
  Gets the default sections to display for a content type in normal mode.
  """
  @spec get_default_sections(content_type()) :: [section_name()]
  def get_default_sections(content_type) do
    case content_type do
      type when type in [:movie, :tv] -> [:hero, :overview, :cast, :media, :details]
      type when type in [:venue, :restaurant, :activity] -> [:hero, :details, :reviews, :photos]
      _ -> [:hero, :details]
    end
  end

  @doc """
  Gets the default sections to display for a content type in compact mode.
  """
  @spec get_compact_sections(content_type()) :: [section_name()]
  def get_compact_sections(content_type) do
    case content_type do
      type when type in [:movie, :tv] -> [:hero, :overview]
      type when type in [:venue, :restaurant, :activity] -> [:hero, :details]
      _ -> [:hero]
    end
  end

  @doc """
  Gets all registered content types.
  """
  @spec get_content_types() :: [content_type()]
  def get_content_types do
    @section_mappings
    |> Map.keys()
    |> Enum.reject(&(&1 == :default))
  end

  @doc """
  Validates if a content type is supported.
  """
  @spec supported_content_type?(content_type()) :: boolean()
  def supported_content_type?(content_type) do
    Map.has_key?(@section_mappings, content_type)
  end
end
