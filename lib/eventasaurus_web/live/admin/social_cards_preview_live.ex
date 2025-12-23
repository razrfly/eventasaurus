defmodule EventasaurusWeb.Admin.SocialCardsPreviewLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Themes
  alias EventasaurusWeb.SocialCardView
  import EventasaurusWeb.SocialCardView, only: [render_activity_card_svg: 1]

  @moduledoc """
  Admin design tool for previewing social card designs across all themes.

  This LiveView provides a visual preview of social cards without needing
  external tools like Facebook Sharing Debugger. Supports testing different
  themes, mock data, and design iterations.
  """

  @impl true
  def mount(_params, _session, socket) do
    mock_event = generate_mock_event()

    {:ok,
     socket
     |> assign(:page_title, "Social Card Design Preview")
     |> assign(:themes, Themes.valid_themes())
     |> assign(:selected_theme, :all)
     |> assign(:card_type, :event)
     |> assign(:mock_event, mock_event)
     |> assign(:mock_poll, generate_mock_poll(mock_event))
     |> assign(:mock_city, generate_mock_city())
     |> assign(:mock_activity, generate_mock_activity())
     |> generate_previews()}
  end

  @impl true
  def handle_event("change_theme", %{"theme" => theme}, socket) do
    selected_theme =
      if theme == "all" do
        :all
      else
        # Safely map string to known theme atom to prevent crash from malicious input
        Enum.find(socket.assigns.themes, fn t -> Atom.to_string(t) == theme end) || :all
      end

    {:noreply, socket |> assign(:selected_theme, selected_theme) |> generate_previews()}
  end

  @impl true
  def handle_event("change_card_type", %{"type" => type}, socket) do
    # Safely map to allowed card types to prevent crash from malicious input
    card_type =
      case type do
        "event" -> :event
        "poll" -> :poll
        "city" -> :city
        "activity" -> :activity
        _ -> socket.assigns.card_type
      end

    {:noreply, socket |> assign(:card_type, card_type) |> generate_previews()}
  end

  # Generate preview data for all (or selected) themes
  defp generate_previews(socket) do
    # City and Activity cards don't use themes, so only generate one preview
    cond do
      socket.assigns.card_type == :city ->
        # Generate city card preview
        city = socket.assigns.mock_city
        stats = Map.get(city, :stats, %{})
        svg = SocialCardView.render_city_card_svg(city, stats)

        # City cards use fixed colors (deep blue theme)
        colors = %{
          "colors" => %{
            "primary" => "#1e40af",
            "secondary" => "#3b82f6"
          }
        }

        previews = [
          %{
            theme: :city,
            svg: svg,
            colors: colors,
            display_name: "City Card"
          }
        ]

        assign(socket, :previews, previews)

      socket.assigns.card_type == :activity ->
        # Generate activity card preview
        activity = socket.assigns.mock_activity
        svg = render_activity_card_svg(activity)

        # Activity cards use fixed Wombie teal theme
        colors = %{
          "colors" => %{
            "primary" => "#0d9488",
            "secondary" => "#14b8a6"
          }
        }

        previews = [
          %{
            theme: :activity,
            svg: svg,
            colors: colors,
            display_name: "Activity Card"
          }
        ]

        assign(socket, :previews, previews)

      true ->
      # Event and poll cards use themes
      themes =
        if socket.assigns.selected_theme == :all do
          socket.assigns.themes
        else
          [socket.assigns.selected_theme]
        end

      previews =
        Enum.map(themes, fn theme ->
          # Create event with the specified theme
          event = %{socket.assigns.mock_event | theme: theme}

          # Generate SVG based on card type
          svg =
            case socket.assigns.card_type do
              :poll ->
                # Create poll with event association
                poll = %{socket.assigns.mock_poll | event: event}
                SocialCardView.render_poll_card_svg(poll)

              :event ->
                SocialCardView.render_social_card_svg(event)
            end

          # Get theme colors for display
          colors = Themes.get_default_customizations(theme)

          %{
            theme: theme,
            svg: svg,
            colors: colors,
            # Format theme name for display
            display_name: theme |> Atom.to_string() |> String.capitalize()
          }
        end)

      assign(socket, :previews, previews)
    end
  end

  # Generate mock event data for preview
  defp generate_mock_event do
    %{
      title: "Sample Event: Testing Social Card Design Across All Themes",
      # Use a real image path that exists in the system
      cover_image_url: "/images/events/abstract/abstract1.png",
      theme: :minimal,
      slug: "mock-event-preview",
      # Add any other fields that render_social_card_svg might need
      description: "This is a mock event for testing social card designs",
      updated_at: DateTime.utc_now()
    }
  end

  # Generate mock poll data for preview
  defp generate_mock_poll(event) do
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

  # Generate mock city data for preview
  defp generate_mock_city do
    %{
      id: 1,
      name: "Warsaw",
      slug: "warsaw",
      country: %{
        name: "Poland",
        code: "PL"
      },
      stats: %{
        events_count: 127,
        venues_count: 45,
        categories_count: 12
      },
      updated_at: DateTime.utc_now()
    }
  end

  # Generate mock activity (public event) data for preview
  defp generate_mock_activity do
    %{
      id: 1,
      title: "Jazz Night at Blue Note",
      slug: "jazz-night-blue-note",
      cover_image_url: "/images/events/abstract/abstract3.png",
      venue: %{
        name: "Blue Note Jazz Club",
        city_ref: %{
          name: "Warsaw"
        }
      },
      occurrence_list: [
        %{
          datetime: DateTime.add(DateTime.utc_now(), 2, :day),
          date: Date.add(Date.utc_today(), 2),
          time: ~T[20:00:00]
        }
      ],
      updated_at: DateTime.utc_now()
    }
  end
end
