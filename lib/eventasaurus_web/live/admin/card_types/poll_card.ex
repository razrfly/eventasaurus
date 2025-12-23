defmodule EventasaurusWeb.Admin.CardTypes.PollCard do
  @moduledoc """
  Poll card type implementation for social card previews.

  Poll cards support user-selectable themes and inherit styling from their parent event.
  """

  @behaviour EventasaurusWeb.Admin.CardTypeBehaviour

  alias EventasaurusWeb.SocialCardView

  @impl true
  def card_type, do: :poll

  @impl true
  def generate_mock_data do
    # Polls require an event, so generate with default event
    event = EventasaurusWeb.Admin.CardTypes.EventCard.generate_mock_data()
    generate_mock_data(%{mock_event: event})
  end

  @impl true
  def generate_mock_data(%{mock_event: event}) do
    %{
      id: 999,
      title: "What movie should we watch for our next movie night?",
      poll_type: "movie",
      phase: "voting",
      event: event,
      event_id: 1,
      updated_at: DateTime.utc_now()
    }
  end

  @impl true
  def render_svg(mock_data) do
    SocialCardView.render_poll_card_svg(mock_data)
  end

  @impl true
  def form_fields do
    [
      %{name: :title, label: "Poll Title", type: :text, path: [:title]},
      %{
        name: :poll_type,
        label: "Poll Type",
        type: :select,
        path: [:poll_type],
        options: [
          {"movie", "Movie"},
          {"places", "Places"},
          {"venue", "Venue"},
          {"date_selection", "Date Selection"},
          {"time", "Time"},
          {"music_track", "Music Track"},
          {"custom", "Custom"}
        ]
      }
    ]
  end

  @impl true
  def update_mock_data(current, params) do
    %{
      current
      | title: Map.get(params, "title", current.title),
        poll_type: Map.get(params, "poll_type", current.poll_type)
    }
  end

  @impl true
  def update_event_name, do: "update_mock_poll"

  @impl true
  def form_param_key, do: "poll"
end
