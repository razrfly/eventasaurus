defmodule EventasaurusWeb.Components.Activity.TriviaHeroCard do
  @moduledoc """
  Specialized hero card for trivia/quiz night events on activity pages.

  Displays trivia event information with a focus on the social, team-based
  nature of pub quizzes. Optimized for SocialEvent schema types with
  trivia/quiz categorization.

  ## Features

  - Teal/cyan gradient theme (brain/knowledge themed)
  - Quizmaster/host name display
  - Recurring schedule indicator (e.g., "Every Wednesday")
  - Team-oriented messaging
  - Venue and location information
  - Free entry badge (when applicable)
  - Contact info for reservations
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias EventasaurusWeb.Components.Activity.{
    HeroCardBadge,
    HeroCardBackground,
    HeroCardHelpers,
    HeroCardIcons,
    HeroCardTheme
  }

  @doc """
  Renders the trivia hero card for quiz/trivia events.

  ## Attributes

    * `:event` - Required. The public event struct with title, venue, etc.
    * `:cover_image_url` - Optional. Cover image URL for the hero background.
    * `:ticket_url` - Optional. URL for more info or registration.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :event, :map,
    required: true,
    doc: "PublicEvent struct with display_title, venue, sources, etc."

  attr :cover_image_url, :string, default: nil, doc: "Cover image URL for the hero background"
  attr :ticket_url, :string, default: nil, doc: "URL to event page or registration"
  attr :class, :string, default: "", doc: "Additional CSS classes for the container"

  def trivia_hero_card(assigns) do
    # Extract trivia-specific metadata from sources
    trivia_metadata = extract_trivia_metadata(assigns.event)

    assigns =
      assigns
      |> assign(:host, trivia_metadata.host)
      |> assign(:schedule_text, trivia_metadata.schedule_text)
      |> assign(:phone, trivia_metadata.phone)
      |> assign(:is_free, trivia_metadata.is_free)
      |> assign(:source_description, trivia_metadata.description)

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background -->
      <HeroCardBackground.background image_url={@cover_image_url} theme={:trivia} />

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Badges Row -->
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <!-- Trivia Badge -->
            <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", HeroCardTheme.badge_class(:trivia)]}>
              <HeroCardIcons.icon type={:trivia} class="w-4 h-4 mr-1.5" />
              <%= HeroCardTheme.label(:trivia) %>
            </span>

            <!-- Free Badge -->
            <%= if @is_free do %>
              <HeroCardBadge.success_badge>
                <Heroicons.gift class="w-4 h-4 mr-1.5" />
                <%= gettext("Free Entry") %>
              </HeroCardBadge.success_badge>
            <% end %>

            <!-- Recurring Badge -->
            <%= if @schedule_text do %>
              <HeroCardBadge.muted_badge>
                <Heroicons.arrow_path class="w-4 h-4 mr-1.5" />
                <%= format_schedule(@schedule_text) %>
              </HeroCardBadge.muted_badge>
            <% end %>
          </div>

          <!-- Title -->
          <h1 class="text-2xl md:text-4xl font-bold text-white tracking-tight mb-3">
            <%= @event.display_title || @event.title %>
          </h1>

          <!-- Host/Quizmaster -->
          <%= if @host do %>
            <div class="flex items-center text-white/90 mb-3">
              <Heroicons.microphone class="w-5 h-5 mr-2" />
              <span class="text-lg">
                <%= gettext("Hosted by") %> <span class="font-semibold"><%= @host %></span>
              </span>
            </div>
          <% end %>

          <!-- Date & Time -->
          <%= if @event.starts_at do %>
            <div class="flex items-center text-white/90 mb-3">
              <Heroicons.calendar class="w-5 h-5 mr-2" />
              <span class="text-lg">
                <%= HeroCardHelpers.format_datetime(@event.starts_at, "%A, %B %d · %I:%M %p") %>
              </span>
            </div>
          <% end %>

          <!-- Venue -->
          <%= if @event.venue do %>
            <div class="flex items-center text-white/80 mb-4">
              <Heroicons.map_pin class="w-5 h-5 mr-2" />
              <span>
                <%= @event.venue.name %>
                <%= if city_name = HeroCardHelpers.get_city_name(@event.venue) do %>
                  <span class="text-white/60">· <%= city_name %></span>
                <% end %>
              </span>
            </div>
          <% end %>

          <!-- Description -->
          <%= if @source_description && @source_description != "" do %>
            <p class="text-white/90 leading-relaxed line-clamp-2 max-w-2xl mb-6">
              <%= HeroCardHelpers.truncate_text(@source_description, 200) %>
            </p>
          <% else %>
            <%= if @event.display_description do %>
              <p class="text-white/90 leading-relaxed line-clamp-2 max-w-2xl mb-6">
                <%= HeroCardHelpers.truncate_text(@event.display_description, 200) %>
              </p>
            <% end %>
          <% end %>

          <!-- Team CTA Banner -->
          <div class="bg-white/10 rounded-lg p-4 mb-6 border border-white/20">
            <div class="flex items-start gap-3">
              <div class="flex-shrink-0 w-10 h-10 bg-teal-500/30 rounded-lg flex items-center justify-center">
                <Heroicons.user_group class="w-5 h-5 text-teal-200" />
              </div>
              <div>
                <h3 class="font-semibold text-white mb-1">
                  <%= gettext("Gather Your Team!") %>
                </h3>
                <p class="text-sm text-white/70">
                  <%= gettext("Grab some friends and test your knowledge. Teams typically 2-6 players.") %>
                </p>
              </div>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="flex flex-wrap items-center gap-3">
            <%= if @ticket_url do %>
              <a
                href={@ticket_url}
                target="_blank"
                rel="noopener noreferrer"
                class={["inline-flex items-center px-5 py-2.5 text-sm font-semibold rounded-lg transition shadow-md", HeroCardTheme.button_class(:trivia)]}
              >
                <Heroicons.information_circle class="w-5 h-5 mr-2" />
                <%= gettext("More Info") %>
              </a>
            <% end %>

            <!-- Phone Contact -->
            <%= if @phone do %>
              <a
                href={"tel:#{@phone}"}
                class="inline-flex items-center px-4 py-2.5 bg-white/10 border border-white/30 text-white text-sm font-medium rounded-lg hover:bg-white/20 transition"
              >
                <Heroicons.phone class="w-5 h-5 mr-2" />
                <%= @phone %>
              </a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp extract_trivia_metadata(event) do
    # Get metadata from the first source that has trivia-related data
    source_data =
      case event.sources do
        sources when is_list(sources) and length(sources) > 0 ->
          Enum.find_value(sources, %{}, fn source ->
            case source.metadata do
              %{"host" => _} = metadata -> metadata
              %{"schedule_text" => _} = metadata -> metadata
              _ -> nil
            end
          end) || %{}

        _ ->
          %{}
      end

    is_free =
      case event.sources do
        sources when is_list(sources) ->
          Enum.any?(sources, fn source -> source.is_free == true end)

        _ ->
          false
      end

    %{
      host: Map.get(source_data, "host"),
      schedule_text: Map.get(source_data, "schedule_text"),
      phone: Map.get(source_data, "phone"),
      description: Map.get(source_data, "description"),
      is_free: is_free
    }
  end

  defp format_schedule(schedule_text) when is_binary(schedule_text) do
    # Try to make the schedule more readable
    # Polish day names to English
    schedule_text
    |> String.replace("poniedziałek", "Monday")
    |> String.replace("wtorek", "Tuesday")
    |> String.replace("środa", "Wednesday")
    |> String.replace("czwartek", "Thursday")
    |> String.replace("piątek", "Friday")
    |> String.replace("sobota", "Saturday")
    |> String.replace("niedziela", "Sunday")
    |> then(fn text ->
      if String.contains?(text, [
           "Monday",
           "Tuesday",
           "Wednesday",
           "Thursday",
           "Friday",
           "Saturday",
           "Sunday"
         ]) do
        "Every " <> text
      else
        text
      end
    end)
  end

  defp format_schedule(_), do: nil
end
