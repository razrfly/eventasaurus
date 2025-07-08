defmodule EventasaurusWeb.OptionSuggestionComponent do
  @moduledoc """
  A reusable LiveView component for managing poll options during the list building phase.

  Allows users to suggest new options, view existing suggestions, and provides moderation
  controls for poll creators. Supports both text-based options and API-enriched content
  for different poll types (movies, books, restaurants, etc.).

  ## Attributes:
  - poll: Poll struct with preloaded options (required)
  - user: User struct (required)
  - is_creator: Boolean indicating if user is the poll creator
  - loading: Whether an operation is in progress
  - changeset: Ecto changeset for the option form
  - suggestion_form_visible: Whether to show the suggestion form

  ## Usage:
      <.live_component
        module={EventasaurusWeb.OptionSuggestionComponent}
        id="option-suggestions"
        poll={@poll}
        user={@user}
        is_creator={@is_creator}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.PollOption

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:suggestion_form_visible, false)
     |> assign(:editing_option_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Create changeset for new option
    changeset = PollOption.changeset(%PollOption{}, %{
      poll_id: assigns.poll.id,
      suggested_by_id: assigns.user.id,
      status: "active"
    })

    # Calculate user's suggestion count
    user_suggestion_count = Enum.count(assigns.poll.poll_options, fn option ->
      option.suggested_by_id == assigns.user.id && option.status == "active"
    end)

    # Check if user can suggest more options
    max_options = assigns.poll.max_options_per_user || 3
    can_suggest_more = user_suggestion_count < max_options

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:user_suggestion_count, user_suggestion_count)
     |> assign(:can_suggest_more, can_suggest_more)
     |> assign(:max_options, max_options)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:suggestion_form_visible, fn -> false end)
     |> assign_new(:editing_option_id, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-medium text-gray-900">
              <%= get_phase_title(@poll.poll_type) %>
            </h3>
            <p class="text-sm text-gray-500">
              <%= get_phase_description(@poll.poll_type, @poll.voting_system) %>
            </p>
          </div>

          <%= if @can_suggest_more do %>
            <button
              type="button"
              phx-click="toggle_suggestion_form"
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
              <%= suggest_button_text(@poll.poll_type) %>
            </button>
          <% else %>
            <div class="text-sm text-gray-500">
              You've reached your limit of <%= @max_options %> suggestions
            </div>
          <% end %>
        </div>
      </div>

      <!-- Suggestion Form -->
      <%= if @suggestion_form_visible do %>
        <div class="px-6 py-4 bg-gray-50 border-b border-gray-200">
          <.form for={@changeset} phx-submit="submit_suggestion" phx-target={@myself} phx-change="validate_suggestion">
            <div class="space-y-4">
              <div>
                <label for="option_title" class="block text-sm font-medium text-gray-700">
                  <%= option_title_label(@poll.poll_type) %> <span class="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  name="poll_option[title]"
                  id="option_title"
                  value={Phoenix.HTML.Form.input_value(@changeset, :title)}
                  placeholder={option_title_placeholder(@poll.poll_type)}
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                />
                <%= if error = @changeset.errors[:title] do %>
                  <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                <% end %>
              </div>

              <div>
                <label for="option_description" class="block text-sm font-medium text-gray-700">
                  Description (optional)
                </label>
                <textarea
                  name="poll_option[description]"
                  id="option_description"
                  rows="2"
                  value={Phoenix.HTML.Form.input_value(@changeset, :description)}
                  placeholder={option_description_placeholder(@poll.poll_type)}
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                ></textarea>
              </div>

              <div class="flex items-center justify-between">
                <div class="text-sm text-gray-500">
                  <%= @user_suggestion_count %>/<%= @max_options %> suggestions used
                </div>
                <div class="flex space-x-3">
                  <button
                    type="button"
                    phx-click="cancel_suggestion"
                    phx-target={@myself}
                    class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={@loading}
                    class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
                  >
                    <%= if @loading do %>
                      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Adding...
                    <% else %>
                      Add Suggestion
                    <% end %>
                  </button>
                </div>
              </div>
            </div>
          </.form>
        </div>
      <% end %>

      <!-- Options List -->
      <div class="divide-y divide-gray-200">
        <%= if Enum.empty?(@poll.poll_options) do %>
          <div class="px-6 py-12 text-center">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No options yet</h3>
            <p class="mt-1 text-sm text-gray-500">
              Be the first to suggest <%= option_type_text(@poll.poll_type) %>!
            </p>
          </div>
        <% else %>
          <%= for option <- @poll.poll_options do %>
            <div class="px-6 py-4">
              <div class="flex items-start justify-between">
                <div class="flex-1 min-w-0">
                  <div class="flex items-center">
                    <h4 class="text-sm font-medium text-gray-900 truncate">
                      <%= option.title %>
                    </h4>
                    <%= if option.status == "hidden" do %>
                      <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                        Hidden
                      </span>
                    <% end %>
                  </div>

                  <%= if option.description do %>
                    <p class="mt-1 text-sm text-gray-500"><%= option.description %></p>
                  <% end %>

                  <!-- API enriched data display -->
                  <%= if option.external_data && map_size(option.external_data) > 0 do %>
                    <div class="mt-2 flex items-center space-x-4 text-xs text-gray-500">
                      <%= if option.external_data["year"] do %>
                        <span>📅 <%= option.external_data["year"] %></span>
                      <% end %>
                      <%= if option.external_data["rating"] do %>
                        <span>⭐ <%= option.external_data["rating"] %></span>
                      <% end %>
                      <%= if option.external_data["genre"] do %>
                        <span>🎭 <%= option.external_data["genre"] %></span>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="mt-2 flex items-center text-xs text-gray-500">
                    <span>Suggested by <%= option.suggested_by.name || option.suggested_by.username %></span>
                    <span class="mx-1">•</span>
                    <span><%= format_relative_time(option.inserted_at) %></span>
                    <span class="mx-1">•</span>
                    <span>Order: <%= option.order_index %></span>
                  </div>
                </div>

                <!-- Option Actions -->
                <div class="ml-4 flex-shrink-0 flex items-center space-x-2">
                  <%= if @is_creator || option.suggested_by_id == @user.id do %>
                    <!-- Edit option button -->
                    <button
                      type="button"
                      phx-click="edit_option"
                      phx-value-option-id={option.id}
                      phx-target={@myself}
                      class="text-indigo-600 hover:text-indigo-900 text-sm font-medium"
                    >
                      Edit
                    </button>
                  <% end %>

                  <%= if @is_creator do %>
                    <!-- Hide/Show toggle for poll creator -->
                    <button
                      type="button"
                      phx-click={if option.status == "active", do: "hide_option", else: "show_option"}
                      phx-value-option-id={option.id}
                      phx-target={@myself}
                      class={if option.status == "active", do: "text-orange-600 hover:text-orange-900", else: "text-green-600 hover:text-green-900"}
                    >
                      <%= if option.status == "active", do: "Hide", else: "Show" %>
                    </button>

                    <!-- Remove option button -->
                    <button
                      type="button"
                      phx-click="remove_option"
                      phx-value-option-id={option.id}
                      phx-target={@myself}
                      data-confirm="Are you sure you want to remove this option? This action cannot be undone."
                      class="text-red-600 hover:text-red-900 text-sm font-medium"
                    >
                      Remove
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Phase Info Footer -->
      <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
        <div class="flex items-center justify-between">
          <div class="text-sm text-gray-500">
            <%= length(@poll.poll_options) %> <%= option_type_text(@poll.poll_type) %> suggested
            <%= if @poll.list_building_deadline do %>
              • Deadline: <%= format_deadline(@poll.list_building_deadline) %>
            <% end %>
          </div>

          <%= if @is_creator && length(@poll.poll_options) > 0 do %>
            <button
              type="button"
              phx-click="start_voting"
              phx-target={@myself}
              class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
            >
              <svg class="-ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Start Voting Phase
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_suggestion_form", _params, socket) do
    {:noreply, assign(socket, :suggestion_form_visible, !socket.assigns.suggestion_form_visible)}
  end

  @impl true
  def handle_event("cancel_suggestion", _params, socket) do
    changeset = PollOption.changeset(%PollOption{}, %{
      poll_id: socket.assigns.poll.id,
      suggested_by_id: socket.assigns.user.id,
      status: "active"
    })

    {:noreply,
     socket
     |> assign(:suggestion_form_visible, false)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate_suggestion", %{"poll_option" => option_params}, socket) do
    changeset = create_option_changeset(socket, option_params)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("submit_suggestion", %{"poll_option" => option_params}, socket) do
    socket = assign(socket, :loading, true)

    case save_option(socket, option_params) do
      {:ok, option} ->
        send(self(), {:option_suggested, option})

        # Reset form
        changeset = PollOption.changeset(%PollOption{}, %{
          poll_id: socket.assigns.poll.id,
          suggested_by_id: socket.assigns.user.id,
          status: "active"
        })

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:suggestion_form_visible, false)
         |> assign(:changeset, changeset)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:changeset, changeset)}
    end
  end

  @impl true
  def handle_event("hide_option", %{"option-id" => option_id}, socket) do
    case Events.update_poll_option_status(option_id, "hidden") do
      {:ok, option} ->
        send(self(), {:option_updated, option})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to hide option"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_option", %{"option-id" => option_id}, socket) do
    case Events.update_poll_option_status(option_id, "active") do
      {:ok, option} ->
        send(self(), {:option_updated, option})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to show option"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_option", %{"option-id" => option_id}, socket) do
    case Events.delete_poll_option(option_id) do
      {:ok, _} ->
        send(self(), {:option_removed, option_id})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to remove option"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit_option", %{"option-id" => option_id}, socket) do
    send(self(), {:edit_option, option_id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_voting", _params, socket) do
    case Events.transition_poll_to_voting(socket.assigns.poll) do
      {:ok, poll} ->
        send(self(), {:poll_phase_changed, poll, "Voting phase started!"})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to start voting phase"})
        {:noreply, socket}
    end
  end

  # Private helper functions

  defp create_option_changeset(socket, option_params) do
    option_params = Map.merge(option_params, %{
      "poll_id" => socket.assigns.poll.id,
      "suggested_by_id" => socket.assigns.user.id,
      "status" => "active"
    })

    PollOption.changeset(%PollOption{}, option_params)
  end

  defp save_option(socket, option_params) do
    option_params = Map.merge(option_params, %{
      "poll_id" => socket.assigns.poll.id,
      "suggested_by_id" => socket.assigns.user.id,
      "status" => "active"
    })

    Events.create_poll_option(option_params)
  end

  # UI helper functions

  defp get_phase_title(poll_type) do
    case poll_type do
      "movie" -> "Suggest Movies"
      "book" -> "Suggest Books"
      "restaurant" -> "Suggest Restaurants"
      "activity" -> "Suggest Activities"
      "music" -> "Suggest Music"
      _ -> "Suggest Options"
    end
  end

  defp get_phase_description(poll_type, voting_system) do
    type_text = option_type_text(poll_type)

    case voting_system do
      "binary" -> "Add #{type_text} for yes/no voting"
      "approval" -> "Add #{type_text} for approval voting"
      "ranked" -> "Add #{type_text} for ranked choice voting"
      "star" -> "Add #{type_text} for star rating"
      _ -> "Add #{type_text} to vote on"
    end
  end

  defp suggest_button_text(poll_type) do
    case poll_type do
      "movie" -> "Suggest Movie"
      "book" -> "Suggest Book"
      "restaurant" -> "Suggest Restaurant"
      "activity" -> "Suggest Activity"
      "music" -> "Suggest Music"
      _ -> "Add Option"
    end
  end

  defp option_title_label(poll_type) do
    case poll_type do
      "movie" -> "Movie Title"
      "book" -> "Book Title"
      "restaurant" -> "Restaurant Name"
      "activity" -> "Activity Name"
      "music" -> "Song/Album/Artist"
      _ -> "Option Title"
    end
  end

  defp option_title_placeholder(poll_type) do
    case poll_type do
      "movie" -> "e.g., The Matrix, Inception, Pulp Fiction"
      "book" -> "e.g., Dune, 1984, The Great Gatsby"
      "restaurant" -> "e.g., Joe's Pizza, The French Laundry"
      "activity" -> "e.g., Hiking, Bowling, Museum Visit"
      "music" -> "e.g., Bohemian Rhapsody, Abbey Road, Radiohead"
      _ -> "Enter your suggestion..."
    end
  end

  defp option_description_placeholder(poll_type) do
    case poll_type do
      "movie" -> "Brief plot summary or why you recommend it..."
      "book" -> "Genre, author, or why you recommend it..."
      "restaurant" -> "Cuisine type, location, or special notes..."
      "activity" -> "Location, duration, or what makes it fun..."
      "music" -> "Artist, genre, or why you recommend it..."
      _ -> "Additional details or context..."
    end
  end

  defp option_type_text(poll_type) do
    case poll_type do
      "movie" -> "movies"
      "book" -> "books"
      "restaurant" -> "restaurants"
      "activity" -> "activities"
      "music" -> "music"
      _ -> "options"
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_deadline(deadline) do
    case deadline do
      %DateTime{} = dt ->
        dt
        |> DateTime.to_date()
        |> Date.to_string()

      _ -> "Not set"
    end
  end
end
