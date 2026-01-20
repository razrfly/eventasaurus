defmodule EventasaurusWeb.Admin.SocialCardsPreviewLive do
  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusApp.Themes
  alias EventasaurusWeb.SocialCardView
  alias EventasaurusWeb.Admin.CardTypeConfig
  alias EventasaurusWeb.Admin.CardTypeRegistry
  alias EventasaurusWeb.Admin.Components.CardTypeForm
  alias Eventasaurus.Services.SvgConverter

  # Card type modules for mock data generation (single source of truth)
  alias EventasaurusWeb.Admin.CardTypes.{
    ActivityCard,
    CityCard,
    EventCard,
    MovieCard,
    PerformerCard,
    PollCard,
    SourceAggregationCard,
    VenueCard
  }

  import EventasaurusWeb.SocialCardView,
    only: [
      render_activity_card_svg: 1,
      render_movie_card_svg: 1,
      render_performer_card_svg: 1,
      render_source_aggregation_card_svg: 1,
      render_venue_card_svg: 1
    ]

  @moduledoc """
  Admin design tool for previewing social card designs across all themes.

  This LiveView provides a visual preview of social cards without needing
  external tools like Facebook Sharing Debugger. Supports testing different
  themes, mock data, and design iterations.

  ## Phase 2 Features
  - PNG generation from SVG previews
  - Download functionality for generated PNGs
  - Editable mock data in real-time
  """

  @impl true
  def mount(_params, _session, socket) do
    # Use card type modules as single source of truth for mock data
    mock_event = EventCard.generate_mock_data()

    {:ok,
     socket
     |> assign(:page_title, "Social Card Design Preview")
     |> assign(:themes, Themes.valid_themes())
     |> assign(:selected_theme, :all)
     |> assign(:card_type, :event)
     |> assign(:card_type_config, CardTypeConfig.get(:event))
     |> assign(:grouped_card_types, CardTypeConfig.grouped_for_select())
     |> assign(:mock_event, mock_event)
     |> assign(:mock_poll, PollCard.generate_mock_data(%{mock_event: mock_event}))
     |> assign(:mock_city, CityCard.generate_mock_data())
     |> assign(:mock_activity, ActivityCard.generate_mock_data())
     |> assign(:mock_movie, MovieCard.generate_mock_data())
     |> assign(:mock_source_aggregation, SourceAggregationCard.generate_mock_data())
     |> assign(:mock_venue, VenueCard.generate_mock_data())
     |> assign(:mock_performer, PerformerCard.generate_mock_data())
     |> assign(:generating_png, nil)
     |> assign(:png_data, %{})
     |> assign(:edit_mode, false)
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
        "movie" -> :movie
        "source_aggregation" -> :source_aggregation
        "venue" -> :venue
        "performer" -> :performer
        _ -> socket.assigns.card_type
      end

    {:noreply,
     socket
     |> assign(:card_type, card_type)
     |> assign(:card_type_config, CardTypeConfig.get(card_type))
     |> assign(:png_data, %{})
     |> generate_previews()}
  end

  # Phase 2: Generate PNG from SVG
  @impl true
  def handle_event("generate_png", %{"theme" => theme_key}, socket) do
    # Find the preview for this theme
    preview = Enum.find(socket.assigns.previews, fn p -> to_string(p.theme) == theme_key end)

    if preview do
      # Mark as generating
      socket = assign(socket, :generating_png, theme_key)

      # Generate PNG using the SVG converter service
      case generate_png_from_svg(preview.svg, theme_key) do
        {:ok, png_binary} ->
          # Convert to base64 data URL for download
          base64_data = Base.encode64(png_binary)
          data_url = "data:image/png;base64,#{base64_data}"

          # Store PNG data for this theme
          png_data = Map.put(socket.assigns.png_data, theme_key, data_url)

          {:noreply,
           socket
           |> assign(:generating_png, nil)
           |> assign(:png_data, png_data)
           |> put_flash(:info, "PNG generated for #{preview.display_name} theme")}

        {:error, reason} ->
          Logger.error("Failed to generate PNG for #{theme_key}: #{inspect(reason)}")

          {:noreply,
           socket
           |> assign(:generating_png, nil)
           |> put_flash(:error, "Failed to generate PNG: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Preview not found for theme: #{theme_key}")}
    end
  end

  # Phase 2: Toggle edit mode
  @impl true
  def handle_event("toggle_edit_mode", _params, socket) do
    {:noreply, assign(socket, :edit_mode, !socket.assigns.edit_mode)}
  end

  # Consolidated mock data update handler using CardTypeRegistry
  # Delegates to the card type module's update_mock_data/2 callback
  @impl true
  def handle_event("update_mock_" <> card_type_str, params, socket) do
    # Safely map string to known card type atom to prevent crash from malicious input
    # Uses same validation pattern as change_card_type handler
    card_type =
      case card_type_str do
        "event" -> :event
        "poll" -> :poll
        "city" -> :city
        "activity" -> :activity
        "movie" -> :movie
        "source_aggregation" -> :source_aggregation
        "venue" -> :venue
        "performer" -> :performer
        _ -> nil
      end

    # Ignore unknown card types
    if is_nil(card_type) do
      {:noreply, socket}
    else
      config = CardTypeConfig.get(card_type)
      do_update_mock_data(socket, card_type, config, params)
    end
  end

  defp do_update_mock_data(socket, card_type, config, params) do
    form_key = CardTypeRegistry.form_param_key(card_type)

    case Map.get(params, form_key) do
      nil ->
        {:noreply, socket}

      form_params ->
        current_data = Map.get(socket.assigns, config.mock_data_key)
        updated_data = CardTypeRegistry.update_mock_data(card_type, current_data, form_params)

        socket =
          socket
          |> assign(config.mock_data_key, updated_data)
          |> assign(:png_data, %{})

        # Special case: when event is updated, also update the poll's event reference
        socket =
          if card_type == :event do
            updated_poll = %{socket.assigns.mock_poll | event: updated_data}
            assign(socket, :mock_poll, updated_poll)
          else
            socket
          end

        {:noreply, generate_previews(socket)}
    end
  end

  # Helper to generate PNG from SVG content
  defp generate_png_from_svg(svg_content, theme_key) do
    # Check if rsvg-convert is available
    case SvgConverter.verify_rsvg_available() do
      :ok ->
        # Create a mock entity for the hash generation
        mock_entity = %{
          title: "preview_#{theme_key}",
          updated_at: DateTime.utc_now()
        }

        # Convert SVG to PNG
        case SvgConverter.svg_to_png(svg_content, "preview_#{theme_key}", mock_entity) do
          {:ok, png_path} ->
            # Read the PNG file
            case File.read(png_path) do
              {:ok, png_data} ->
                # Clean up temp file
                SvgConverter.cleanup_temp_file(png_path)
                {:ok, png_data}

              {:error, reason} ->
                SvgConverter.cleanup_temp_file(png_path)
                {:error, {:read_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:conversion_failed, reason}}
        end

      {:error, :command_not_found} ->
        {:error, :rsvg_not_available}
    end
  end

  @doc """
  Gets mock data for the current card type from socket assigns.
  Used by CardTypeForm component in templates.
  """
  @spec get_mock_data(map()) :: map() | nil
  def get_mock_data(assigns) do
    config = CardTypeConfig.get(assigns.card_type)
    Map.get(assigns, config.mock_data_key)
  end

  # Generate preview data for all (or selected) themes
  # Uses CardTypeConfig for centralized lookup instead of scattered conditionals
  defp generate_previews(socket) do
    card_type = socket.assigns.card_type

    if CardTypeConfig.supports_themes?(card_type) do
      generate_themed_previews(socket)
    else
      generate_brand_preview(socket)
    end
  end

  # Generate previews for styled cards (event, poll) that support multiple themes
  defp generate_themed_previews(socket) do
    card_type = socket.assigns.card_type

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
          case card_type do
            :poll ->
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
          display_name: theme |> Atom.to_string() |> String.capitalize()
        }
      end)

    assign(socket, :previews, previews)
  end

  # Generate single preview for brand cards with fixed colors
  defp generate_brand_preview(socket) do
    card_type = socket.assigns.card_type
    config = CardTypeConfig.get(card_type)

    # Get mock data from socket assigns using config key
    mock_data = Map.get(socket.assigns, config.mock_data_key)

    # Generate SVG using the appropriate render function
    svg = render_brand_card_svg(card_type, mock_data)

    # Get colors from centralized config
    colors = CardTypeConfig.colors_for_preview(card_type)

    previews = [
      %{
        theme: card_type,
        svg: svg,
        colors: colors,
        display_name: config.label
      }
    ]

    assign(socket, :previews, previews)
  end

  # Render SVG for brand card types
  # Each brand card has a specific render function based on its data structure
  defp render_brand_card_svg(:city, city) do
    stats = Map.get(city, :stats, %{})
    SocialCardView.render_city_card_svg(city, stats)
  end

  defp render_brand_card_svg(:activity, activity) do
    render_activity_card_svg(activity)
  end

  defp render_brand_card_svg(:movie, movie) do
    render_movie_card_svg(movie)
  end

  defp render_brand_card_svg(:venue, venue) do
    render_venue_card_svg(venue)
  end

  defp render_brand_card_svg(:performer, performer) do
    render_performer_card_svg(performer)
  end

  defp render_brand_card_svg(:source_aggregation, aggregation) do
    render_source_aggregation_card_svg(aggregation)
  end
end
