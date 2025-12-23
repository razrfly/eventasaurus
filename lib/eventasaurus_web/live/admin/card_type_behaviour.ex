defmodule EventasaurusWeb.Admin.CardTypeBehaviour do
  @moduledoc """
  Behaviour for polymorphic social card type implementations.

  Each card type module implements this behaviour to provide:
  - Mock data generation for previews
  - SVG rendering for the card
  - Form fields definition for the edit modal
  - Event handling for form updates

  This enables plug-and-play addition of new card types while maintaining
  consistent interfaces across the admin preview tool.
  """

  @doc """
  Returns the card type atom identifier.

  ## Examples

      iex> MyCardType.card_type()
      :movie
  """
  @callback card_type() :: atom()

  @doc """
  Generates mock data for preview.

  Returns a map with the structure expected by the card's render function.
  """
  @callback generate_mock_data() :: map()

  @doc """
  Generates mock data with dependencies (e.g., poll needs event).

  Some card types depend on other mock data (polls inherit from events).
  Pass a map of available mock data for dependent generation.
  """
  @callback generate_mock_data(dependencies :: map()) :: map()

  @doc """
  Renders the SVG content for the card.

  Takes the mock data and returns an SVG string.
  """
  @callback render_svg(mock_data :: map()) :: String.t()

  @doc """
  Returns form field definitions for the edit modal.

  Each field is a map with:
  - `:name` - Field name (atom)
  - `:label` - Display label
  - `:type` - Input type (:text, :number, :select, :textarea)
  - `:path` - Path to value in mock data (list of keys)
  - `:options` - For select fields, list of {value, label} tuples

  ## Examples

      [
        %{name: :title, label: "Title", type: :text, path: [:title]},
        %{name: :year, label: "Year", type: :number, path: [:release_date, :year], min: 1900, max: 2100}
      ]
  """
  @callback form_fields() :: [map()]

  @doc """
  Updates mock data from form params.

  Takes current mock data and form params, returns updated mock data.
  """
  @callback update_mock_data(current :: map(), params :: map()) :: map()

  @doc """
  Returns the event name for form updates.

  ## Examples

      iex> MovieCardType.update_event_name()
      "update_mock_movie"
  """
  @callback update_event_name() :: String.t()

  @doc """
  Returns the form param key for updates.

  ## Examples

      iex> MovieCardType.form_param_key()
      "movie"
  """
  @callback form_param_key() :: String.t()

  @optional_callbacks generate_mock_data: 1
end
