defmodule EventasaurusWeb.PublicGenericPollComponent do
  @moduledoc """
  Simple public interface for generic polling (non-movie polls).

  Shows existing poll options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  """

  use EventasaurusWeb, :live_component

  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Utils.TimeUtils
  alias EventasaurusWeb.Utils.PollPhaseUtils

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay

  @impl true
  def update(assigns, socket) do
    event = assigns.event
    user = assigns.current_user
    poll = assigns.poll

    if poll do
      # Load poll options with suggested_by user
      poll_options = Events.list_poll_options(poll)
      |> Repo.preload(:suggested_by)
      
      # Load poll statistics for voter count display
      poll_stats = try do
        Events.get_poll_voting_stats(poll)
      rescue
        _ -> %{options: [], total_unique_voters: 0}
      end
      
      # Load user votes for this poll
      user_votes = if user do
        Events.list_user_poll_votes(poll, user)
      else
        []
      end
      
      # Get temp votes from assigns or default to empty
      temp_votes = Map.get(assigns, :temp_votes, %{})

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:current_user, user)
       |> assign(:poll, poll)
       |> assign(:poll_options, poll_options)
       |> assign(:poll_stats, poll_stats)
       |> assign(:user_votes, user_votes)
       |> assign(:temp_votes, temp_votes)
       |> assign(:showing_add_form, false)
       |> assign(:option_title, "")
       |> assign(:adding_option, false)}
    else
      {:ok, assign(socket, :poll, nil)}
    end
  end

  @impl true
  def handle_event("show_add_form", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :showing_add_form, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_add_form, false)
     |> assign(:option_title, "")}
  end

  def handle_event("update_option_field", %{"field" => "title", "value" => value}, socket) do
    {:noreply, assign(socket, :option_title, value)}
  end

  # Handle the select element's event structure (for time selector)
  def handle_event("update_option_field", %{"_target" => ["time_selector"], "time_selector" => value}, socket) do
    {:noreply, assign(socket, :option_title, value)}
  end

  # Handle the case where the select element event structure is different (fallback)
  def handle_event("update_option_field", %{"_target" => ["undefined"]}, socket) do
    # This happens when the select element doesn't have a proper name attribute
    # Just return the socket without changes
    {:noreply, socket}
  end

  # Handle form changes (for the new input name structure)
  def handle_event("validate", %{"poll_option" => %{"title" => title}}, socket) do
    {:noreply, assign(socket, :option_title, title)}
  end

  def handle_event("add_option", %{"poll_option" => poll_option_params} = _params, socket) do
    if socket.assigns.adding_option do
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      # Check if user is authenticated
      if is_nil(user) do
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to add suggestions.")
         |> assign(:adding_option, false)}
      else
        # Extract title from poll_option_params (from form) or fallback to assigns
        title = String.trim(poll_option_params["title"] || socket.assigns.option_title || "")

        if title == "" do
          {:noreply,
           socket
           |> put_flash(:error, "Title is required.")
           |> assign(:adding_option, false)}
        else
          # Set adding_option to true to prevent multiple requests
          socket = assign(socket, :adding_option, true)

          # Process poll option data using the SAME logic as manager area
          option_params = prepare_option_params(socket, poll_option_params, title, user)

          case Events.create_poll_option(option_params) do
            {:ok, _option} ->
              # Reload poll options to show the new option immediately
              updated_poll_options = Events.list_poll_options(socket.assigns.poll)
              |> Repo.preload(:suggested_by)

              # Notify the parent LiveView to reload polls for all users
              send(self(), {:poll_stats_updated, socket.assigns.poll.id, %{}})

              {:noreply,
               socket
               |> put_flash(:info, "Option added successfully!")
               |> assign(:adding_option, false)
               |> assign(:showing_add_form, false)
               |> assign(:option_title, "")
               |> assign(:poll_options, updated_poll_options)}

            {:error, changeset} ->
              require Logger
              Logger.error("Failed to create poll option: #{inspect(changeset)}")
              {:noreply,
               socket
               |> put_flash(:error, "Failed to add option. Please try again.")
               |> assign(:adding_option, false)}
          end
        end
      end
    end
  end

  # Handle the case where params don't match the expected structure (fallback)
  def handle_event("add_option", params, socket) do
    # Convert to the expected format and retry
    poll_option_params = %{
      "title" => socket.assigns.option_title,
      "external_id" => params["external_id"],
      "external_data" => params["external_data"],
      "image_url" => params["image_url"]
    }

    handle_event("add_option", %{"poll_option" => poll_option_params}, socket)
  end

  # Process poll option parameters using the SAME logic as manager area (OptionSuggestionComponent)
  defp prepare_option_params(socket, poll_option_params, title, user) do
    require Logger
    alias EventasaurusWeb.Services.PlacesDataService

    # Start with base parameters
    option_params = Map.merge(poll_option_params, %{
      "title" => title,
      "poll_id" => socket.assigns.poll.id,
      "suggested_by_id" => user.id,
      "status" => "active"
    })

    # Apply the EXACT SAME processing as the manager area for places
    if socket.assigns.poll.poll_type == "places" &&
       Map.has_key?(option_params, "external_data") &&
       not is_nil(option_params["external_data"]) do

      Logger.debug("Processing places option with PlacesDataService (public interface)")

      # Parse external_data if it's a JSON string (SAME AS MANAGER)
      external_data = case option_params["external_data"] do
        data when is_binary(data) ->
          case Jason.decode(data) do
            {:ok, decoded} -> decoded
            {:error, _} -> option_params["external_data"]
          end
        data -> data
      end

      if external_data && is_map(external_data) do
        # Use PlacesDataService to prepare data (SAME AS MANAGER)
        prepared_data = PlacesDataService.prepare_place_option_data(external_data)

        # Preserve any user-provided custom title/description over generated ones (SAME AS MANAGER)
        final_data = prepared_data
        |> maybe_preserve_user_input("title", option_params["title"])
        |> maybe_preserve_user_input("description", option_params["description"])

        # CRITICAL: Ensure required fields are preserved after PlacesDataService processing
        final_data = Map.merge(final_data, %{
          "poll_id" => option_params["poll_id"],
          "suggested_by_id" => option_params["suggested_by_id"],
          "status" => option_params["status"]
        })

        Logger.debug("PlacesDataService applied successfully for place: #{final_data["title"]} (public interface)")
        Logger.debug("Final data poll_id: #{final_data["poll_id"]}, suggested_by_id: #{final_data["suggested_by_id"]}")
        final_data
      else
        Logger.debug("PlacesDataService skipped - invalid external_data (public interface)")
        option_params
      end
    else
      # Non-places options or manual entry
      option_params
    end
  end

  # Helper to preserve user input over generated content (SAME AS MANAGER)
  defp maybe_preserve_user_input(prepared_data, key, user_value) when is_binary(user_value) and user_value != "" do
    Map.put(prepared_data, key, user_value)
  end
  defp maybe_preserve_user_input(prepared_data, _key, _user_value), do: prepared_data

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-generic-poll">
      <%= if @poll do %>
        <div class="mb-6">
          <div class="mb-4">
            <h3 class="text-lg font-semibold text-gray-900">
              <%= poll_emoji(@poll.poll_type) %> <%= get_poll_title(@poll.poll_type) %>
            </h3>
            <p class="text-sm text-gray-600">
              <%= PollPhaseUtils.get_phase_description(@poll.phase, @poll.poll_type) %>
            </p>
            <.voter_count poll_stats={@poll_stats} poll_phase={@poll.phase} class="mt-1" />
          </div>

          <!-- Poll Options List with Voting -->
          <%= if length(@poll_options) > 0 do %>
            <%= if PollPhaseUtils.voting_allowed?(@poll.phase) do %>
              <!-- Voting Interface -->
              <div class="mb-6">
                <.live_component
                  module={EventasaurusWeb.VotingInterfaceComponent}
                  id={"voting-interface-#{@poll.id}"}
                  poll={@poll}
                  user={@current_user}
                  user_votes={@user_votes}
                  loading={false}
                  temp_votes={@temp_votes}
                  anonymous_mode={is_nil(@current_user)}
                />
              </div>
            <% else %>
              <!-- List Building Phase - Show Options Without Voting -->
              <div class="space-y-3">
                <%= for option <- sort_options_by_time(@poll_options, @poll.poll_type) do %>
                <div class="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                  <div class="flex">
                    <!-- Option Image (same as manager area) -->
                    <%= if option.image_url do %>
                      <img
                        src={option.image_url}
                        alt={"#{option.title} image"}
                        class="w-16 h-24 object-cover rounded-md shadow-sm mr-4 flex-shrink-0"
                        loading="lazy"
                      />
                    <% end %>

                    <div class="flex-1 min-w-0">
                      <h4 class="font-medium text-gray-900 mb-1">
                        <%= if @poll.poll_type == "time" do %>
                          <%= format_time_for_display(option.title) %>
                        <% else %>
                          <%= option.title %>
                        <% end %>
                      </h4>

                      <%= if option.description && String.length(option.description) > 0 do %>
                        <p class="text-sm text-gray-600 line-clamp-3 mb-2"><%= option.description %></p>
                      <% end %>

                      <!-- Show who suggested this option -->
                      <%= if option.suggested_by do %>
                        <p class="text-xs text-gray-500 mb-2">
                          Suggested by <%= option.suggested_by.name || option.suggested_by.email %>
                        </p>
                      <% end %>

                      <!-- Voting buttons removed - handled by VotingInterfaceComponent in public_event_live.ex -->
                    </div>
                  </div>
                </div>
              <% end %>
              </div>
            <% end %>
          <% else %>
            <div class="text-center py-8 text-gray-500">
              <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M9 5H7a2 2 0 00-2 2v6a2 2 0 002 2h6a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
              </svg>
              <% {title, subtitle} = PollPhaseUtils.get_empty_state_message(@poll.poll_type) %>
              <p class="font-medium"><%= title %></p>
              <p class="text-sm"><%= subtitle %></p>
            </div>
          <% end %>

          <!-- Add Option Button/Form -->
          <%= if PollPhaseUtils.suggestions_allowed?(@poll.phase) do %>
            <%= if @current_user do %>
              <%= if @showing_add_form do %>
                <!-- Inline Add Option Form -->
                <div class="mt-4 p-4 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50"
                     data-event-venue-lat={@event && @event.venue && @event.venue.latitude}
                     data-event-venue-lng={@event && @event.venue && @event.venue.longitude}
                     data-event-venue-name={@event && @event.venue && @event.venue.name}
                     data-poll-options-data={Jason.encode!(extract_poll_options_coordinates(@poll_options))}>
                  <div class="mb-4">
                    <h4 class="text-md font-medium text-gray-900 mb-2">Add <%= get_suggestion_title(@poll.poll_type) %></h4>
                    <p class="text-sm text-gray-600">Share your suggestion with the group</p>
                  </div>

                  <!-- Location Context Indicator -->
                  <div class="location-context-indicator hidden mb-3 text-xs text-gray-600 bg-blue-50 px-3 py-1 rounded-full flex items-center">
                    <span class="location-icon mr-1">🌍</span>
                    <span>Searching globally</span>
                  </div>

                  <form phx-submit="add_option" phx-change="validate" phx-target={@myself}>
                    <div class="space-y-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-1">
                          <%= get_title_label(@poll.poll_type) %> <span class="text-red-500">*</span>
                        </label>
                        <%= if @poll.poll_type == "time" do %>
                          <!-- Use a hidden input for form submission along with the time selector -->
                          <input
                            type="hidden"
                            name="poll_option[title]"
                            value={@option_title}
                          />
                          <select
                            id={"time-selector-#{@poll.id}"}
                            name="time_selector"
                            phx-change="update_option_field"
                            phx-value-field="title"
                            phx-target={@myself}
                            class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                            required
                          >
                            <option value="" disabled selected={@option_title == ""}>Select a time...</option>
                            <%= for time_option <- time_options() do %>
                              <option value={time_option.value} selected={@option_title == time_option.value}>
                                <%= time_option.display %>
                              </option>
                            <% end %>
                          </select>
                        <% else %>
                          <%= if @poll.poll_type == "places" do %>
                            <input
                              type="text"
                              name="poll_option[title]"
                              id="option_title"
                              value={@option_title}
                              placeholder={get_title_placeholder(@poll.poll_type)}
                              phx-debounce="300"
                              phx-hook="PlacesSuggestionSearch"
                              autocomplete="off"
                              class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                            />
                          <% else %>
                            <input
                              type="text"
                              id={"input-#{@poll.id}"}
                              name="poll_option[title]"
                              placeholder={get_title_placeholder(@poll.poll_type)}
                              value={@option_title}
                              phx-keyup="update_option_field"
                              phx-value-field="title"
                              phx-target={@myself}
                              class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                              required
                            />
                          <% end %>
                        <% end %>
                      </div>

                      <!-- Hidden fields for rich data (will be populated by JavaScript hook for places) -->
                      <%= if @poll.poll_type == "places" do %>
                        <!-- These will be dynamically added by PlacesSuggestionSearch hook -->
                        <div class="hidden-metadata-fields"></div>
                      <% end %>
                    </div>

                    <div class="flex justify-end space-x-3 mt-4">
                      <button
                        type="button"
                        phx-click="hide_add_form"
                        phx-target={@myself}
                        class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                      >
                        Cancel
                      </button>
                      <button
                        type="submit"
                        disabled={@adding_option || String.trim(@option_title) == ""}
                        class="px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <%= if @adding_option do %>
                          <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 714 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          Adding...
                        <% else %>
                          Add Suggestion
                        <% end %>
                      </button>
                    </div>
                  </form>
                </div>
              <% else %>
                <!-- Add Option Button -->
                <div class="mt-4">
                  <button
                    phx-click="show_add_form"
                    phx-target={@myself}
                    class="w-full flex items-center justify-center px-4 py-3 border border-gray-300 border-dashed rounded-lg text-sm font-medium text-gray-600 hover:text-gray-900 hover:border-gray-400 transition-colors"
                  >
                    <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    <%= PollPhaseUtils.get_add_button_text(@poll.poll_type) %>
                  </button>
                </div>
              <% end %>
            <% else %>
              <!-- Show login prompt for anonymous users -->
              <div class="mt-4">
                <p class="text-sm text-gray-500 text-center py-4 bg-gray-50 rounded-lg">
                  Please <.link href="/login" class="text-blue-600 hover:underline">log in</.link> to suggest options.
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No poll found for this event.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions for poll type customization

  defp get_poll_title(poll_type) do
    case poll_type do
      "places" -> "Place Suggestions"
      "time" -> "Time Suggestions"
      "date_selection" -> "DateTime Selection"
      "custom" -> "General Options"
      _ -> "Suggestions"
    end
  end


  defp get_suggestion_title(poll_type) do
    case poll_type do
      "places" -> "Place Suggestion"
      "time" -> "Time"
      "date_selection" -> "DateTime"
      "custom" -> "Option"
      _ -> "Suggestion"
    end
  end

  defp get_title_label(poll_type) do
    case poll_type do
      "places" -> "Place Name"
      "time" -> "Time"
      "date_selection" -> "DateTime"
      "custom" -> "Option Title"
      _ -> "Title"
    end
  end

  defp get_title_placeholder(poll_type) do
    case poll_type do
      "places" -> "Enter place name..."
      "time" -> "Select a time..."
      "date_selection" -> "Select a DateTime..."
      "custom" -> "Enter your option..."
      _ -> "Enter title..."
    end
  end

  defp extract_poll_options_coordinates(poll_options) when is_list(poll_options) do
    poll_options
    |> Enum.map(fn option ->
      case option.external_data do
        %{"latitude" => lat, "longitude" => lng} when is_number(lat) and is_number(lng) ->
          %{latitude: lat, longitude: lng}
        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp extract_poll_options_coordinates(_), do: []

  defp time_options() do
    # Start at 10:00 AM (10:00) and go through 11:30 PM (23:30)
    # 30-minute increments
    10..23
    |> Enum.flat_map(fn hour ->
      [
        %{value: TimeUtils.format_time_value(hour, 0), display: TimeUtils.format_time_display(hour, 0)},
        %{value: TimeUtils.format_time_value(hour, 30), display: TimeUtils.format_time_display(hour, 30)}
      ]
    end)
  end



  defp format_time_for_display(time_value) do
    # This function is used to display the time value in a user-friendly format.
    # It expects a string like "HH:MM" or "HH:MM:SS" and converts it to "HH:MM AM/PM".
    # For example, "10:00" becomes "10:00 AM", "14:30" becomes "2:30 PM".
    case TimeUtils.parse_time_string(time_value) do
      {:ok, {hour, minute}} ->
        TimeUtils.format_time_display(hour, minute)
      {:error, _} ->
        time_value # Return original if parsing fails
    end
  end

  defp sort_options_by_time(options, poll_type) do
    if poll_type == "time" do
      # For time polls, sort by the time value (e.g., "10:00", "10:30", "11:00")
      Enum.sort_by(options, fn option ->
        TimeUtils.parse_time_for_sort(option.title)
      end)
    else
      # For non-time polls, sort by title (alphabetically)
      Enum.sort_by(options, fn option -> option.title end)
    end
  end

end
