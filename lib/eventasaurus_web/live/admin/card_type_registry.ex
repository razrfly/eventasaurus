defmodule EventasaurusWeb.Admin.CardTypeRegistry do
  @moduledoc """
  Registry for card type implementations.

  Provides auto-discovery of card types from modules implementing CardTypeBehaviour.
  Adding new card types becomes plug-and-play: just implement the behaviour and
  add to the registry.
  """

  alias EventasaurusWeb.Admin.CardTypes.{
    EventCard,
    PollCard,
    CityCard,
    ActivityCard,
    MovieCard,
    VenueCard,
    PerformerCard,
    SourceAggregationCard
  }

  @card_type_modules %{
    event: EventCard,
    poll: PollCard,
    city: CityCard,
    activity: ActivityCard,
    movie: MovieCard,
    venue: VenueCard,
    performer: PerformerCard,
    source_aggregation: SourceAggregationCard
  }

  @doc """
  Returns the module implementing the given card type.
  """
  @spec get_module(atom()) :: module() | nil
  def get_module(card_type) when is_atom(card_type) do
    Map.get(@card_type_modules, card_type)
  end

  @doc """
  Returns all registered card types.
  """
  @spec all_types() :: [atom()]
  def all_types do
    Map.keys(@card_type_modules)
  end

  @doc """
  Returns all registered card type modules.
  """
  @spec all_modules() :: [module()]
  def all_modules do
    Map.values(@card_type_modules)
  end

  @doc """
  Generates mock data for a card type.
  """
  @spec generate_mock_data(atom()) :: map()
  def generate_mock_data(card_type) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> %{}
      module -> module.generate_mock_data()
    end
  end

  @doc """
  Generates mock data for a card type with dependencies.
  """
  @spec generate_mock_data(atom(), map()) :: map()
  def generate_mock_data(card_type, dependencies) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> %{}
      module -> module.generate_mock_data(dependencies)
    end
  end

  @doc """
  Renders SVG for a card type with the given mock data.
  """
  @spec render_svg(atom(), map()) :: String.t()
  def render_svg(card_type, mock_data) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> ""
      module -> module.render_svg(mock_data)
    end
  end

  @doc """
  Returns form field definitions for a card type.
  """
  @spec form_fields(atom()) :: [map()]
  def form_fields(card_type) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> []
      module -> module.form_fields()
    end
  end

  @doc """
  Updates mock data from form params for a card type.
  """
  @spec update_mock_data(atom(), map(), map()) :: map()
  def update_mock_data(card_type, current, params) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> current
      module -> module.update_mock_data(current, params)
    end
  end

  @doc """
  Returns the update event name for a card type.
  """
  @spec update_event_name(atom()) :: String.t()
  def update_event_name(card_type) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> "update_mock_#{card_type}"
      module -> module.update_event_name()
    end
  end

  @doc """
  Returns the form param key for a card type.
  """
  @spec form_param_key(atom()) :: String.t()
  def form_param_key(card_type) when is_atom(card_type) do
    case get_module(card_type) do
      nil -> Atom.to_string(card_type)
      module -> module.form_param_key()
    end
  end
end
