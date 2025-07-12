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

  @impl true
  def update(assigns, socket) do
    event = assigns.event
    user = assigns.current_user
    poll = assigns.poll

    if poll do
      # Load poll options with suggested_by user
      poll_options = Events.list_poll_options(poll)
      |> Repo.preload(:suggested_by)

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:current_user, user)
       |> assign(:poll, poll)
       |> assign(:poll_options, poll_options)
       |> assign(:showing_add_form, false)
       |> assign(:option_title, "")
       |> assign(:option_description, "")
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
     |> assign(:option_title, "")
     |> assign(:option_description, "")}
  end

  def handle_event("update_option_field", %{"field" => "title", "value" => value}, socket) do
    {:noreply, assign(socket, :option_title, value)}
  end

  def handle_event("update_option_field", %{"field" => "description", "value" => value}, socket) do
    {:noreply, assign(socket, :option_description, value)}
  end

  def handle_event("add_option", _params, socket) do
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
        title = String.trim(socket.assigns.option_title)
        description = String.trim(socket.assigns.option_description)

        if title == "" do
          {:noreply,
           socket
           |> put_flash(:error, "Title is required.")
           |> assign(:adding_option, false)}
        else
          # Set adding_option to true to prevent multiple requests
          socket = assign(socket, :adding_option, true)

          option_params = %{
            "title" => title,
            "description" => description,
            "poll_id" => socket.assigns.poll.id,
            "suggested_by_id" => user.id,
            "status" => "active"
          }

          case Events.create_poll_option(option_params) do
            {:ok, _option} ->
              # Reload poll options to show the new option immediately
              updated_poll_options = Events.list_poll_options(socket.assigns.poll)
              |> Repo.preload(:suggested_by)

              {:noreply,
               socket
               |> put_flash(:info, "Option added successfully!")
               |> assign(:adding_option, false)
               |> assign(:showing_add_form, false)
               |> assign(:option_title, "")
               |> assign(:option_description, "")
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-generic-poll">
      <%= if @poll do %>
        <div class="mb-6">
          <div class="mb-4">
            <h3 class="text-lg font-semibold text-gray-900">
              <%= get_poll_emoji(@poll.poll_type) %> <%= get_poll_title(@poll.poll_type) %>
            </h3>
            <p class="text-sm text-gray-600">
              <%= if @poll.phase == "list_building" do %>
                Help build the <%= @poll.poll_type %> list! Add your suggestions below.
              <% else %>
                Vote on your favorite <%= get_poll_type_text(@poll.poll_type) %> below.
              <% end %>
            </p>
          </div>

          <!-- Poll Options List -->
          <%= if length(@poll_options) > 0 do %>
            <div class="space-y-3">
              <%= for option <- @poll_options do %>
                <div class="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                  <div class="flex">
                    <div class="flex-1 min-w-0">
                      <h4 class="font-medium text-gray-900 mb-1"><%= option.title %></h4>

                      <%= if option.description && String.length(option.description) > 0 do %>
                        <p class="text-sm text-gray-600 line-clamp-3 mb-2"><%= option.description %></p>
                      <% end %>

                      <!-- Show who suggested this option -->
                      <%= if option.suggested_by do %>
                        <p class="text-xs text-gray-500 mb-2">
                          Suggested by <%= option.suggested_by.name || option.suggested_by.email %>
                        </p>
                      <% end %>

                      <%= if @poll.phase == "voting" do %>
                        <!-- Voting buttons will go here -->
                        <div class="flex items-center space-x-2 mt-2">
                          <button class="px-3 py-1 text-xs bg-green-100 text-green-800 rounded-full hover:bg-green-200">
                            👍 Yes
                          </button>
                          <button class="px-3 py-1 text-xs bg-red-100 text-red-800 rounded-full hover:bg-red-200">
                            👎 No
                          </button>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="text-center py-8 text-gray-500">
              <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M9 5H7a2 2 0 00-2 2v6a2 2 0 002 2h6a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
              </svg>
              <p class="font-medium">No <%= get_poll_type_text(@poll.poll_type) %> suggested yet</p>
              <p class="text-sm">Be the first to add a suggestion!</p>
            </div>
          <% end %>

          <!-- Add Option Button/Form -->
          <%= if @poll.phase == "list_building" do %>
            <%= if @current_user do %>
              <%= if @showing_add_form do %>
                <!-- Inline Add Option Form -->
                <div class="mt-4 p-4 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50">
                  <div class="mb-4">
                    <h4 class="text-md font-medium text-gray-900 mb-2">Add <%= get_suggestion_title(@poll.poll_type) %></h4>
                    <p class="text-sm text-gray-600">Share your suggestion with the group</p>
                  </div>

                  <div class="space-y-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        <%= get_title_label(@poll.poll_type) %> <span class="text-red-500">*</span>
                      </label>
                      <input
                        type="text"
                        placeholder={get_title_placeholder(@poll.poll_type)}
                        value={@option_title}
                        phx-keyup="update_option_field"
                        phx-value-field="title"
                        phx-target={@myself}
                        class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                      />
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Description (optional)
                      </label>
                      <textarea
                        placeholder={get_description_placeholder(@poll.poll_type)}
                        value={@option_description}
                        phx-keyup="update_option_field"
                        phx-value-field="description"
                        phx-target={@myself}
                        rows="3"
                        class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                      ></textarea>
                    </div>
                  </div>

                  <div class="flex justify-end space-x-3 mt-4">
                    <button
                      phx-click="hide_add_form"
                      phx-target={@myself}
                      class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                    >
                      Cancel
                    </button>
                    <button
                      phx-click="add_option"
                      phx-target={@myself}
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
                    Add <%= get_suggestion_title(@poll.poll_type) %>
                  </button>
                </div>
              <% end %>
            <% else %>
              <!-- Show login prompt for anonymous users -->
              <div class="mt-4">
                <p class="text-sm text-gray-500 text-center py-4 bg-gray-50 rounded-lg">
                  Please log in to suggest options.
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
  defp get_poll_emoji(poll_type) do
    case poll_type do
      "places" -> "📍"
      "activity" -> "🎯"
      "custom" -> "📝"
      _ -> "📊"
    end
  end

  defp get_poll_title(poll_type) do
    case poll_type do
      "places" -> "Place Suggestions"
      "activity" -> "Activity Suggestions"
      "custom" -> "Poll Options"
      _ -> "Suggestions"
    end
  end

  defp get_poll_type_text(poll_type) do
    case poll_type do
      "places" -> "places"
      "activity" -> "activities"
      "custom" -> "options"
      _ -> "options"
    end
  end

  defp get_suggestion_title(poll_type) do
    case poll_type do
      "places" -> "Place Suggestion"
      "activity" -> "Activity Suggestion"
      "custom" -> "Option"
      _ -> "Suggestion"
    end
  end

  defp get_title_label(poll_type) do
    case poll_type do
      "places" -> "Place Name"
      "activity" -> "Activity Name"
      "custom" -> "Option Title"
      _ -> "Title"
    end
  end

  defp get_title_placeholder(poll_type) do
    case poll_type do
      "places" -> "Enter place name..."
      "activity" -> "Enter activity name..."
      "custom" -> "Enter your option..."
      _ -> "Enter title..."
    end
  end

  defp get_description_placeholder(poll_type) do
    case poll_type do
      "places" -> "Cuisine type, location, special notes..."
      "activity" -> "Location, duration, what makes it fun..."
      "custom" -> "Additional details or context..."
      _ -> "Additional details..."
    end
  end
end
