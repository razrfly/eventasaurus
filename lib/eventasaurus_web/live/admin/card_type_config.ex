defmodule EventasaurusWeb.Admin.CardTypeConfig do
  @moduledoc """
  Centralized configuration for social card types.

  Card types are divided into two categories:
  - **Styled Cards** (Event, Poll): Support user-selectable themes with 7 style options
  - **Brand Cards** (City, Activity, Movie, Venue, Performer, Source Aggregation):
    Use fixed brand colors that visually distinguish content types

  This module provides metadata for each card type including labels, colors,
  grouping, and style information for the admin preview interface.
  """

  @type card_type ::
          :event | :poll | :city | :activity | :movie | :source_aggregation | :venue | :performer

  @styled_cards [:event, :poll]
  @brand_cards [:city, :activity, :movie, :venue, :performer, :source_aggregation]

  @card_configs %{
    # Styled Cards - support user-selectable themes
    event: %{
      label: "Event Card",
      group: :styled,
      group_label: "Styled Cards",
      supports_themes?: true,
      style_name: nil,
      colors: nil,
      mock_data_key: :mock_event
    },
    poll: %{
      label: "Poll Card",
      group: :styled,
      group_label: "Styled Cards",
      supports_themes?: true,
      style_name: nil,
      colors: nil,
      mock_data_key: :mock_poll
    },
    # Brand Cards - fixed colors that distinguish content types
    city: %{
      label: "City Card",
      group: :brand,
      group_label: "Brand Cards",
      supports_themes?: false,
      style_name: "Deep Blue",
      colors: %{primary: "#1e40af", secondary: "#3b82f6"},
      mock_data_key: :mock_city
    },
    activity: %{
      label: "Activity Card",
      group: :brand,
      group_label: "Brand Cards",
      supports_themes?: false,
      style_name: "Teal",
      colors: %{primary: "#0d9488", secondary: "#14b8a6"},
      mock_data_key: :mock_activity
    },
    movie: %{
      label: "Movie Card",
      group: :brand,
      group_label: "Brand Cards",
      supports_themes?: false,
      style_name: "Cinema Purple",
      colors: %{primary: "#7c3aed", secondary: "#a855f7"},
      mock_data_key: :mock_movie
    },
    venue: %{
      label: "Venue Card",
      group: :brand,
      group_label: "Brand Cards",
      supports_themes?: false,
      style_name: "Emerald",
      colors: %{primary: "#059669", secondary: "#10b981"},
      mock_data_key: :mock_venue
    },
    performer: %{
      label: "Performer Card",
      group: :brand,
      group_label: "Brand Cards",
      supports_themes?: false,
      style_name: "Rose",
      colors: %{primary: "#be185d", secondary: "#ec4899"},
      mock_data_key: :mock_performer
    },
    source_aggregation: %{
      label: "Source Aggregation Card",
      group: :brand,
      group_label: "Brand Cards",
      supports_themes?: false,
      style_name: "Indigo",
      colors: %{primary: "#4f46e5", secondary: "#6366f1"},
      mock_data_key: :mock_source_aggregation
    }
  }

  @doc """
  Returns configuration for a specific card type.
  """
  @spec get(card_type()) :: map() | nil
  def get(card_type) when is_atom(card_type) do
    Map.get(@card_configs, card_type)
  end

  @doc """
  Returns all card types in display order.
  """
  @spec all_types() :: [card_type()]
  def all_types do
    @styled_cards ++ @brand_cards
  end

  @doc """
  Returns styled card types (support user themes).
  """
  @spec styled_cards() :: [card_type()]
  def styled_cards, do: @styled_cards

  @doc """
  Returns brand card types (fixed colors).
  """
  @spec brand_cards() :: [card_type()]
  def brand_cards, do: @brand_cards

  @doc """
  Returns grouped card types for dropdown display.
  Format: [{group_label, [{value, label}, ...]}]
  """
  @spec grouped_for_select() :: [{String.t(), [{String.t(), String.t()}]}]
  def grouped_for_select do
    [
      {"Styled Cards",
       Enum.map(@styled_cards, fn type ->
         config = get(type)
         {Atom.to_string(type), config.label}
       end)},
      {"Brand Cards",
       Enum.map(@brand_cards, fn type ->
         config = get(type)
         {Atom.to_string(type), config.label}
       end)}
    ]
  end

  @doc """
  Returns whether a card type supports user-selectable themes.
  """
  @spec supports_themes?(card_type()) :: boolean()
  def supports_themes?(card_type) when is_atom(card_type) do
    case get(card_type) do
      %{supports_themes?: value} -> value
      _ -> false
    end
  end

  @doc """
  Returns whether a card type is a brand card (fixed colors).
  """
  @spec brand_card?(card_type()) :: boolean()
  def brand_card?(card_type) when is_atom(card_type) do
    card_type in @brand_cards
  end

  @doc """
  Returns the brand style name for a card type, or nil if it supports themes.
  """
  @spec style_name(card_type()) :: String.t() | nil
  def style_name(card_type) when is_atom(card_type) do
    case get(card_type) do
      %{style_name: name} -> name
      _ -> nil
    end
  end

  @doc """
  Returns the fixed colors for a brand card type.
  Returns nil for styled cards.
  """
  @spec colors(card_type()) :: %{primary: String.t(), secondary: String.t()} | nil
  def colors(card_type) when is_atom(card_type) do
    case get(card_type) do
      %{colors: colors} -> colors
      _ -> nil
    end
  end

  @doc """
  Returns the display label for a card type.
  """
  @spec label(card_type()) :: String.t()
  def label(card_type) when is_atom(card_type) do
    case get(card_type) do
      %{label: label} -> label
      _ -> card_type |> Atom.to_string() |> String.capitalize()
    end
  end

  @doc """
  Returns the mock data key for a card type.
  """
  @spec mock_data_key(card_type()) :: atom()
  def mock_data_key(card_type) when is_atom(card_type) do
    case get(card_type) do
      %{mock_data_key: key} -> key
      _ -> :"mock_#{card_type}"
    end
  end

  @doc """
  Returns colors formatted for preview display.
  Returns a map with "colors" key containing "primary" and "secondary" string keys.
  """
  @spec colors_for_preview(card_type()) :: map()
  def colors_for_preview(card_type) when is_atom(card_type) do
    case colors(card_type) do
      %{primary: primary, secondary: secondary} ->
        %{
          "colors" => %{
            "primary" => primary,
            "secondary" => secondary
          }
        }

      nil ->
        %{"colors" => %{"primary" => "#000000", "secondary" => "#333333"}}
    end
  end
end
