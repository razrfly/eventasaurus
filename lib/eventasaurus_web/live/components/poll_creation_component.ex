defmodule EventasaurusWeb.PollCreationComponent do
  @moduledoc """
  A reusable LiveView component for creating new polls.

  Provides a comprehensive form for poll creation with support for different poll types,
  voting systems, deadline management, and configuration options. Handles validation
  and integrates with the Events context for poll creation.

  ## Attributes:
  - event: Event struct (required)
  - user: User struct (required)
  - show: Boolean to show/hide the modal
  - poll: Poll struct for editing (optional, nil for new polls)
  - changeset: Ecto changeset for form state
  - loading: Whether a form submission is in progress

  ## Usage:
      <.live_component
        module={EventasaurusWeb.PollCreationComponent}
        id="poll-creation-modal"
        event={@event}
        user={@user}
        show={@show_poll_creation}
        poll={@editing_poll}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Poll
  import EventasaurusWeb.PollView, only: [poll_emoji: 1]

  @poll_types [
    {"custom", "General Poll", "Create a custom poll"},
    {"movie", "Movie", "Vote on movies to watch"},
    {"places", "Places", "Pick places to visit"},
    {"time", "Time/Schedule", "Schedule events"},
    {"date_selection", "Date Selection", "Vote on possible dates"}
  ]

  @voting_systems [
    {"binary", "Yes/Maybe/No", "Quick consensus on individual options - great for simple decisions where participants might be unsure"},
    {"approval", "Approval", "Select multiple acceptable options - perfect when you want to find all viable choices"},
    {"ranked", "Ranked Choice", "Rank options in order of preference - ideal for finding the most preferred single option"},
    {"star", "Star Rating", "Rate options from 1 to 5 stars - best for detailed feedback and comparison"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:show, false)
     |> assign(:poll, nil)
     |> assign(:show_advanced_options, false)
     |> assign(:show_voting_guidelines, false)
     |> assign(:showing_calendar, false)
     |> assign(:selected_dates, [])}
  end

  @impl true
  def update(assigns, socket) do
    # Determine if we're editing or creating
    poll = assigns[:poll]
    is_editing = poll != nil

    # Create changeset
    changeset = if is_editing do
      Poll.changeset(poll, %{})
    else
      Poll.changeset(%Poll{}, %{
        event_id: assigns.event.id,
        created_by_id: assigns.user.id,
        phase: "list_building",
        poll_type: "custom",
        voting_system: "binary"
      })
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:is_editing, is_editing)
     |> assign(:changeset, changeset)
     |> assign(:poll_types, @poll_types)
     |> assign(:voting_systems, @voting_systems)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:show, fn -> false end)
     |> assign_new(:show_voting_guidelines, fn -> false end)
     |> assign_new(:showing_calendar, fn -> false end)
     |> assign_new(:selected_dates, fn -> [] end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={if @show, do: "fixed inset-0 z-50 overflow-y-auto", else: "hidden"} aria-labelledby="modal-title" role="dialog" aria-modal="true">
        <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
          <!-- Background overlay -->
          <div
            class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
            phx-click="close_modal"
            phx-target={@myself}
          ></div>

          <!-- Modal panel -->
          <div class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
            <.form for={@changeset} phx-submit="submit_poll" phx-target={@myself} phx-change="validate" :let={f}>
              <div class="bg-white px-6 pt-6 pb-4">
                <div class="mb-4">
                  <h3 class="text-lg leading-6 font-medium text-gray-900" id="modal-title">
                    <%= if @is_editing, do: "Edit Poll", else: "Create New Poll" %>
                  </h3>
                  <p class="text-sm text-gray-500">
                    <%= if @is_editing, do: "Update poll details and settings", else: "Set up a new poll for your event participants" %>
                  </p>
                </div>

                <div class="space-y-6">
                  <!-- Poll Title -->
                  <div>
                    <label for="poll_title" class="block text-sm font-medium text-gray-700">
                      Poll Title <span class="text-red-500">*</span>
                    </label>
                    <input
                      type="text"
                      name="poll[title]"
                      id="poll_title"
                      value={Phoenix.HTML.Form.input_value(f, :title)}
                      class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      placeholder="What should participants vote on?"
                    />
                    <%= if error = @changeset.errors[:title] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>
                  </div>

                  <!-- Poll Description -->
                  <div>
                    <label for="poll_description" class="block text-sm font-medium text-gray-700">
                      Description
                    </label>
                    <textarea
                      name="poll[description]"
                      id="poll_description"
                      rows="3"
                      class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      placeholder="Provide additional context or instructions (optional)"
                    ><%= Phoenix.HTML.Form.input_value(f, :description) %></textarea>
                    <%= if error = @changeset.errors[:description] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>
                  </div>

                  <!-- Poll Type Selection -->
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-3">
                      Poll Type <span class="text-red-500">*</span>
                    </label>
                    <div class="grid grid-cols-2 gap-3">
                      <%= for {value, label, description} <- @poll_types do %>
                        <label class="relative">
                          <input
                            type="radio"
                            name="poll[poll_type]"
                            value={value}
                            checked={Phoenix.HTML.Form.input_value(f, :poll_type) == value}
                            class="sr-only peer"
                          />
                          <div class="p-3 border-2 border-gray-200 rounded-lg cursor-pointer transition-all peer-checked:border-indigo-500 peer-checked:bg-indigo-50 hover:border-gray-300">
                            <div class="flex items-center">
                              <span class="text-lg mr-2"><%= poll_emoji(value) %></span>
                              <div>
                                <div class="text-sm font-medium text-gray-900"><%= label %></div>
                                <div class="text-xs text-gray-500"><%= description %></div>
                              </div>
                            </div>
                          </div>
                        </label>
                      <% end %>
                    </div>
                    <%= if error = @changeset.errors[:poll_type] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>
                  </div>

                  <!-- Voting System Selection -->
                  <div>
                    <label for="voting_system" class="block text-sm font-medium text-gray-700 mb-2">
                      Voting System <span class="text-red-500">*</span>
                    </label>
                    <div class="relative">
                      <select
                        name="poll[voting_system]"
                        id="voting_system"
                        class="block w-full pl-3 pr-10 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm bg-white"
                        style="-webkit-appearance: none; -moz-appearance: none; appearance: none; background-image: none;"
                      >
                        <option value="" disabled={true} selected={Phoenix.HTML.Form.input_value(f, :voting_system) == nil}>Select a voting system...</option>
                        <%= for {value, label, description} <- @voting_systems do %>
                          <option
                            value={value}
                            selected={Phoenix.HTML.Form.input_value(f, :voting_system) == value}
                            title={description}
                          >
                            <%= label %>
                          </option>
                        <% end %>
                      </select>
                      <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
                        <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                        </svg>
                      </div>
                    </div>
                    <%= if error = @changeset.errors[:voting_system] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>

                    <!-- Voting System Guidelines Toggle -->
                    <div class="mt-3">
                      <button
                        type="button"
                        phx-click="toggle_voting_guidelines"
                        phx-target={@myself}
                        class="flex items-center text-sm text-blue-600 hover:text-blue-800 transition-colors"
                      >
                        <svg class={[
                          "w-4 h-4 mr-1 transition-transform",
                          if(@show_voting_guidelines, do: "rotate-90", else: "rotate-0")
                        ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                        </svg>
                        💡 Choosing the Right Voting System
                      </button>

                      <%= if @show_voting_guidelines do %>
                        <div class="mt-2 bg-blue-50 border border-blue-200 rounded-md p-4">
                          <div class="space-y-2 text-xs text-blue-800">
                            <div>
                              <strong>Yes/Maybe/No:</strong> Best for quick decisions where people might be uncertain. The "maybe" option captures neutral feelings and helps identify lukewarm support.
                            </div>
                            <div>
                              <strong>Approval:</strong> Use when you want to find all acceptable options. Great for gathering multiple venues, activities, or any scenario where several choices could work.
                            </div>
                            <div>
                              <strong>Ranked Choice:</strong> Perfect for finding the single most preferred option. Ideal for choosing one movie, one restaurant, or one date from multiple possibilities.
                            </div>
                            <div>
                              <strong>Star Rating:</strong> Best when you want detailed feedback and comparison. Use for rating experiences, evaluating options with nuanced opinions, or when quality assessment matters.
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <!-- Advanced Options Toggle -->
                  <div class="border-t pt-4">
                    <button
                      type="button"
                      phx-click="toggle_advanced_options"
                      phx-target={@myself}
                      class="flex items-center justify-between w-full text-left text-sm font-medium text-gray-700 hover:text-gray-900 transition-colors"
                    >
                      <span>Advanced Options</span>
                      <svg class={[
                        "w-4 h-4 transition-transform",
                        if(@show_advanced_options, do: "rotate-180", else: "rotate-0")
                      ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                      </svg>
                    </button>
                  </div>

                  <%= if @show_advanced_options do %>
                    <!-- Configuration Options -->
                    <div class="bg-gray-50 p-4 rounded-lg">
                      <h4 class="text-sm font-medium text-gray-900 mb-3">Configuration</h4>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <!-- Max Options Per User -->
                      <div>
                        <label for="max_options_per_user" class="block text-sm font-medium text-gray-700">
                          Max Options Per User
                        </label>
                        <input
                          type="number"
                          name="poll[max_options_per_user]"
                          id="max_options_per_user"
                          value={Phoenix.HTML.Form.input_value(f, :max_options_per_user) || 3}
                          min="1"
                          max="10"
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <p class="mt-1 text-xs text-gray-500">How many options each user can suggest</p>
                      </div>

                      <!-- Auto Finalize -->
                      <div class="flex items-center justify-between">
                        <div>
                          <label for="auto_finalize" class="text-sm font-medium text-gray-700">
                            Auto Finalize
                          </label>
                          <p class="text-xs text-gray-500">Automatically close poll after voting deadline</p>
                        </div>
                        <input
                          type="checkbox"
                          name="poll[auto_finalize]"
                          id="auto_finalize"
                          checked={Phoenix.HTML.Form.input_value(f, :auto_finalize)}
                          class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                        />
                      </div>
                    </div>
                  </div>

                  <!-- Deadlines -->
                  <div class="bg-blue-50 p-4 rounded-lg">
                    <h4 class="text-sm font-medium text-gray-900 mb-3">Deadlines (Optional)</h4>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <!-- List Building Deadline -->
                      <div>
                        <label for="list_building_deadline" class="block text-sm font-medium text-gray-700">
                          List Building Deadline
                        </label>
                        <input
                          type="datetime-local"
                          name="poll[list_building_deadline]"
                          id="list_building_deadline"
                          value={format_datetime_local(@changeset, :list_building_deadline)}
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <p class="mt-1 text-xs text-gray-500">When to stop accepting new options</p>
                      </div>

                      <!-- Voting Deadline -->
                      <div>
                        <label for="voting_deadline" class="block text-sm font-medium text-gray-700">
                          Voting Deadline
                        </label>
                        <input
                          type="datetime-local"
                          name="poll[voting_deadline]"
                          id="voting_deadline"
                          value={format_datetime_local(@changeset, :voting_deadline)}
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <p class="mt-1 text-xs text-gray-500">When to stop accepting votes</p>
                      </div>
                    </div>
                  </div>
                  <% end %>
                </div>
              </div>

              <!-- Date Selection Interface (conditional) -->
              <%= if Phoenix.HTML.Form.input_value(f, :poll_type) == "date_selection" do %>
                <div class="border-t pt-6">
                  <h4 class="text-sm font-medium text-gray-900 mb-4">
                    📅 Select Available Dates
                  </h4>
                  <p class="text-sm text-gray-600 mb-4">
                    Choose the dates that people can vote on. You can select multiple dates and add more later.
                  </p>

                  <!-- Calendar Component Integration -->
                  <div class="bg-gray-50 rounded-lg p-4" id="date-selection-preview">
                    <div class="flex items-center justify-between mb-3">
                      <span class="text-sm font-medium text-gray-700">Available Dates</span>
                      <button
                        type="button"
                        phx-click="toggle_calendar"
                        phx-target={@myself}
                        class="text-sm text-indigo-600 hover:text-indigo-800 font-medium"
                      >
                        <%= if @showing_calendar, do: "Hide Calendar", else: "Show Calendar" %>
                      </button>
                    </div>

                    <!-- Selected Dates Preview -->
                    <%= if length(@selected_dates) > 0 do %>
                      <div class="flex flex-wrap gap-2 mb-3">
                        <%= for date <- @selected_dates do %>
                          <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                            <%= format_date_for_display(date) %>
                            <button
                              type="button"
                              phx-click="remove_date"
                              phx-value-date={Date.to_iso8601(date)}
                              phx-target={@myself}
                              class="ml-2 text-indigo-600 hover:text-indigo-800"
                            >
                              ×
                            </button>
                          </span>
                        <% end %>
                      </div>
                    <% else %>
                      <p class="text-sm text-gray-500 mb-3">
                        No dates selected yet. Click "Show Calendar" to select dates.
                      </p>
                    <% end %>

                    <!-- Calendar Interface -->
                    <%= if @showing_calendar do %>
                      <div class="border border-gray-200 rounded-lg bg-white p-4">
                        <.live_component
                          module={EventasaurusWeb.CalendarComponent}
                          id="poll-creation-calendar"
                          selected_dates={@selected_dates}
                          year={Date.utc_today().year}
                          month={Date.utc_today().month}
                          compact={true}
                          allow_multiple={true}
                          min_date={Date.utc_today()}
                          on_date_select="calendar_date_selected"
                          target={@myself}
                        />
                      </div>
                    <% end %>

                    <!-- Quick Date Options -->
                    <div class="mt-3 pt-3 border-t border-gray-200">
                      <span class="text-xs font-medium text-gray-700 mb-2 block">Quick Add:</span>
                      <div class="flex flex-wrap gap-2">
                        <button
                          type="button"
                          phx-click="add_quick_date"
                          phx-value-type="tomorrow"
                          phx-target={@myself}
                          class="px-2 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                        >
                          Tomorrow
                        </button>
                        <button
                          type="button"
                          phx-click="add_quick_date"
                          phx-value-type="next_weekend"
                          phx-target={@myself}
                          class="px-2 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                        >
                          Next Weekend
                        </button>
                        <button
                          type="button"
                          phx-click="add_quick_date"
                          phx-value-type="next_week"
                          phx-target={@myself}
                          class="px-2 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                        >
                          Next Week
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>

              <!-- Form Actions -->
              <div class="bg-gray-50 px-6 py-4 flex flex-col sm:flex-row sm:space-x-3 space-y-3 sm:space-y-0 sm:justify-end">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="w-full sm:w-auto inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:text-sm"
                  disabled={@loading}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="w-full sm:w-auto inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                  disabled={@loading}
                >
                  <%= if @loading do %>
                    <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <%= if @is_editing, do: "Updating...", else: "Creating..." %>
                  <% else %>
                    <%= if @is_editing, do: "Update Poll", else: "Create Poll" %>
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </div>
    </div>
    """
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_poll_creation_modal})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_advanced_options", _params, socket) do
    {:noreply, assign(socket, :show_advanced_options, !socket.assigns.show_advanced_options)}
  end

  @impl true
  def handle_event("toggle_voting_guidelines", _params, socket) do
    {:noreply, assign(socket, :show_voting_guidelines, !socket.assigns.show_voting_guidelines)}
  end

  @impl true
  def handle_event("validate", %{"poll" => poll_params}, socket) do
    changeset = create_changeset(socket, poll_params)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  # Calendar functionality event handlers
  @impl true
  def handle_event("toggle_calendar", _params, socket) do
    {:noreply, assign(socket, :showing_calendar, !socket.assigns.showing_calendar)}
  end

  @impl true
  def handle_event("calendar_date_selected", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        updated_dates = if date in socket.assigns.selected_dates do
          List.delete(socket.assigns.selected_dates, date)
        else
          [date | socket.assigns.selected_dates] |> Enum.sort()
        end
        {:noreply, assign(socket, :selected_dates, updated_dates)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        updated_dates = List.delete(socket.assigns.selected_dates, date)
        {:noreply, assign(socket, :selected_dates, updated_dates)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_quick_date", %{"type" => type}, socket) do
    today = Date.utc_today()

    new_date = case type do
      "tomorrow" -> Date.add(today, 1)
      "next_weekend" ->
        # Find next Saturday
        days_until_saturday = case Date.day_of_week(today) do
          6 -> 7 # Saturday, get next Saturday
          7 -> 6 # Sunday, get next Saturday
          day_of_week -> 6 - day_of_week # Other days
        end
        Date.add(today, days_until_saturday)
      "next_week" -> Date.add(today, 7)
      _ -> today
    end

    updated_dates = if new_date in socket.assigns.selected_dates do
      socket.assigns.selected_dates
    else
      [new_date | socket.assigns.selected_dates] |> Enum.sort()
    end

    {:noreply, assign(socket, :selected_dates, updated_dates)}
  end

  @impl true
  def handle_event("submit_poll", %{"poll" => poll_params}, socket) do
    socket = assign(socket, :loading, true)

    case save_poll(socket, poll_params) do
      {:ok, poll} ->
        # If this is a date_selection poll, create the date options
        if poll_params["poll_type"] == "date_selection" and length(socket.assigns.selected_dates) > 0 do
          create_date_options_for_poll(poll, socket.assigns.selected_dates)
        end

        message = if socket.assigns.is_editing, do: "Poll updated successfully!", else: "Poll created successfully!"
        send(self(), {:poll_saved, poll, message})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:changeset, changeset)}
    end
  end

  # Private functions

  defp create_changeset(socket, poll_params) do
    poll = socket.assigns.poll || %Poll{}

    # Merge default values for new polls
    poll_params = if socket.assigns.is_editing do
      poll_params
    else
      Map.merge(%{
        "event_id" => socket.assigns.event.id,
        "created_by_id" => socket.assigns.user.id,
        "phase" => "list_building"
      }, poll_params)
    end

    Poll.changeset(poll, poll_params)
  end

  defp save_poll(socket, poll_params) do
    if socket.assigns.is_editing do
      Events.update_poll(socket.assigns.poll, poll_params)
    else
      # Ensure required fields for new polls
      poll_params = Map.merge(poll_params, %{
        "event_id" => socket.assigns.event.id,
        "created_by_id" => socket.assigns.user.id,
        "phase" => "list_building"
      })

      Events.create_poll(poll_params)
    end
  end

  defp format_datetime_local(changeset, field) do
    case Ecto.Changeset.get_field(changeset, field) do
      %DateTime{} = datetime ->
        datetime
        |> DateTime.to_naive()
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)  # Remove seconds for datetime-local input

      nil -> ""
      _ -> ""
    end
  end

  defp create_date_options_for_poll(poll, selected_dates) do
    # Create poll options for each selected date using our new date poll functions
    # Get the user who created the poll
    user = EventasaurusApp.Accounts.get_user!(poll.created_by_id)

    Enum.each(selected_dates, fn date ->
      Events.create_date_poll_option(poll, user, date, %{
        "source" => "poll_creation_calendar",
        "created_at" => DateTime.utc_now()
      })
    end)
  end

  defp format_date_for_display(date) do
    case date do
      %Date{} ->
        # Format as "Mon, Jan 15, 2024"
        day_name = day_of_week_name(Date.day_of_week(date))
        month_name = month_name(date.month)
        "#{day_name}, #{month_name} #{date.day}, #{date.year}"
      _ ->
        to_string(date)
    end
  end

  defp day_of_week_name(day) do
    case day do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
    end
  end

  defp month_name(month) do
    case month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
    end
  end
end
