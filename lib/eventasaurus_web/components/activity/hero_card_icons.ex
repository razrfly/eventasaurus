defmodule EventasaurusWeb.Components.Activity.HeroCardIcons do
  @moduledoc """
  Unified icon mappings for hero card components.

  Maps theme atoms, schema types, and container types to Heroicons.
  Consolidates icon logic from AggregatedHeroCard, ContainerHeroCard,
  and GenericHeroCard into a single source of truth.

  ## Usage

      alias EventasaurusWeb.Components.Activity.HeroCardIcons

      # In HEEx template
      <HeroCardIcons.icon type={:music} class="w-4 h-4" />
      <HeroCardIcons.icon type={:MusicEvent} />
      <HeroCardIcons.icon type={:conference} class="w-5 h-5" />
  """
  use Phoenix.Component

  @doc """
  Renders the appropriate Heroicon for a theme, schema type, or container type.

  ## Attributes

    * `:type` - Required. The theme atom, schema type, or container type.
    * `:class` - Optional. CSS classes for the icon. Defaults to "w-4 h-4".

  ## Supported Types

  ### Content Themes
  - `:music`, `:MusicEvent` - Musical note
  - `:trivia`, `:quiz` - Puzzle piece
  - `:social`, `:SocialEvent` - User group
  - `:food`, `:FoodEvent` - Cake
  - `:movies`, `:cinema`, `:screening`, `:ScreeningEvent` - Film
  - `:festival`, `:Festival` - Sparkles
  - `:comedy`, `:ComedyEvent` - Face smile
  - `:theater`, `:theatre`, `:TheaterEvent` - Ticket
  - `:sports`, `:SportsEvent` - Trophy

  ### Container Types
  - `:conference` - Academic cap
  - `:tour` - Map
  - `:series` - Queue list
  - `:exhibition` - Photo
  - `:tournament` - Trophy

  ### Schema Types
  - `:EducationEvent` - Academic cap
  - `:ChildrensEvent` - Puzzle piece
  - `:VisualArtsEvent` - Paint brush
  - `:BusinessEvent` - Briefcase

  ### Entity Types
  - `:venue` - Building storefront
  - `:performer`, `:artist` - Musical note

  ### Fallback
  - Any unrecognized type - Calendar
  """
  attr :type, :any, required: true, doc: "Atom or string representing the type"
  attr :class, :string, default: "w-4 h-4"

  def icon(assigns) do
    ~H"""
    <%= case normalize_type(@type) do %>
      <% :music -> %>
        <Heroicons.musical_note class={@class} />
      <% :trivia -> %>
        <Heroicons.puzzle_piece class={@class} />
      <% :social -> %>
        <Heroicons.user_group class={@class} />
      <% :food -> %>
        <Heroicons.cake class={@class} />
      <% :movies -> %>
        <Heroicons.film class={@class} />
      <% :festival -> %>
        <Heroicons.sparkles class={@class} />
      <% :comedy -> %>
        <Heroicons.face_smile class={@class} />
      <% :theater -> %>
        <Heroicons.ticket class={@class} />
      <% :sports -> %>
        <Heroicons.trophy class={@class} />
      <% :conference -> %>
        <Heroicons.academic_cap class={@class} />
      <% :tour -> %>
        <Heroicons.map class={@class} />
      <% :series -> %>
        <Heroicons.queue_list class={@class} />
      <% :exhibition -> %>
        <Heroicons.photo class={@class} />
      <% :tournament -> %>
        <Heroicons.trophy class={@class} />
      <% :education -> %>
        <Heroicons.academic_cap class={@class} />
      <% :childrens -> %>
        <Heroicons.puzzle_piece class={@class} />
      <% :visual_arts -> %>
        <Heroicons.paint_brush class={@class} />
      <% :business -> %>
        <Heroicons.briefcase class={@class} />
      <% :venue -> %>
        <Heroicons.building_storefront class={@class} />
      <% :performer -> %>
        <Heroicons.musical_note class={@class} />
      <% _ -> %>
        <Heroicons.calendar class={@class} />
    <% end %>
    """
  end

  # Normalize various type formats to canonical atoms
  defp normalize_type(type) when is_atom(type) do
    case type do
      # Music variations
      t when t in [:music, :MusicEvent, :concert] -> :music
      # Trivia variations
      t when t in [:trivia, :quiz] -> :trivia
      # Social variations
      t when t in [:social, :SocialEvent] -> :social
      # Food variations
      t when t in [:food, :FoodEvent, :restaurant] -> :food
      # Movies variations
      t when t in [:movies, :cinema, :screening, :ScreeningEvent] -> :movies
      # Festival variations
      t when t in [:festival, :Festival] -> :festival
      # Comedy variations
      t when t in [:comedy, :ComedyEvent] -> :comedy
      # Theater variations
      t when t in [:theater, :theatre, :TheaterEvent] -> :theater
      # Sports variations
      t when t in [:sports, :SportsEvent] -> :sports
      # Container types (pass through)
      t when t in [:conference, :tour, :series, :exhibition, :tournament] -> t
      # Schema types that map to specific icons
      :EducationEvent -> :education
      :ChildrensEvent -> :childrens
      :VisualArtsEvent -> :visual_arts
      :BusinessEvent -> :business
      # Entity types
      t when t in [:venue] -> :venue
      t when t in [:performer, :artist] -> :performer
      # Default fallback
      _ -> :default
    end
  end

  defp normalize_type(type) when is_binary(type) do
    # Handle string schema types (e.g., "MusicEvent", "SocialEvent")
    case type do
      "MusicEvent" -> :music
      "SocialEvent" -> :social
      "TheaterEvent" -> :theater
      "ComedyEvent" -> :comedy
      "SportsEvent" -> :sports
      "FoodEvent" -> :food
      "ScreeningEvent" -> :movies
      "Festival" -> :festival
      "EducationEvent" -> :education
      "ChildrensEvent" -> :childrens
      "VisualArtsEvent" -> :visual_arts
      "BusinessEvent" -> :business
      "Event" -> :default
      _ -> :default
    end
  end

  defp normalize_type(_), do: :default
end
