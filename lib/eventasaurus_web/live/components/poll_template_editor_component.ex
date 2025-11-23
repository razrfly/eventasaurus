defmodule EventasaurusWeb.PollTemplateEditorComponent do
  @moduledoc """
  LiveComponent for creating polls from templates with intelligent option selection.

  This component allows users to:
  - Review pre-filled poll metadata from template
  - Select from common options used in previous polls
  - Edit selected options inline
  - Add custom options
  - Create poll with selected + custom options
  """
  use EventasaurusWeb, :live_component

  @impl true
  def update(assigns, socket) do
    suggestion = assigns.suggestion

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:poll_title, suggestion["suggested_title"])
     |> assign(:selected_voting_system, suggestion["voting_system"])
     |> assign(:selected_options, MapSet.new())
     |> assign(:edited_options, %{})
     |> assign(:custom_options, [])
     |> assign(:errors, [])}
  end

  @impl true
  def handle_event("toggle_option", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    selected = socket.assigns.selected_options

    new_selected =
      if MapSet.member?(selected, index) do
        MapSet.delete(selected, index)
      else
        MapSet.put(selected, index)
      end

    {:noreply, assign(socket, :selected_options, new_selected)}
  end

  @impl true
  def handle_event("edit_option", %{"index" => index_str, "value" => text}, socket) do
    index = String.to_integer(index_str)
    edited = socket.assigns.edited_options

    {:noreply, assign(socket, :edited_options, Map.put(edited, index, text))}
  end

  @impl true
  def handle_event("update_title", %{"value" => title}, socket) do
    {:noreply, assign(socket, :poll_title, title)}
  end

  @impl true
  def handle_event("update_voting_system", %{"voting_system" => voting_system}, socket) do
    {:noreply, assign(socket, :selected_voting_system, voting_system)}
  end

  @impl true
  def handle_event("add_custom_option", _params, socket) do
    custom_options = socket.assigns.custom_options ++ [""]
    {:noreply, assign(socket, :custom_options, custom_options)}
  end

  @impl true
  def handle_event("update_custom_option", %{"index" => index_str, "value" => text}, socket) do
    index = String.to_integer(index_str)
    custom_options = List.replace_at(socket.assigns.custom_options, index, text)
    {:noreply, assign(socket, :custom_options, custom_options)}
  end

  @impl true
  def handle_event("remove_custom_option", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    custom_options = List.delete_at(socket.assigns.custom_options, index)
    {:noreply, assign(socket, :custom_options, custom_options)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_indices =
      socket.assigns.suggestion["common_options"]
      |> Enum.with_index()
      |> Enum.map(fn {_opt, idx} -> idx end)
      |> MapSet.new()

    {:noreply, assign(socket, :selected_options, all_indices)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_options, MapSet.new())}
  end

  @impl true
  def handle_event("create_poll", _params, socket) do
    # Collect all selected and edited options with full metadata
    selected_options_with_metadata =
      socket.assigns.selected_options
      |> Enum.sort()
      |> Enum.map(fn index ->
        original = Enum.at(socket.assigns.suggestion["common_options"], index)

        # Handle both old string format and new map format
        if is_binary(original) do
          # Old format - just a string title
          edited_title = Map.get(socket.assigns.edited_options, index, original)
          %{title: edited_title}
        else
          # New format - full metadata map
          edited_title =
            Map.get(socket.assigns.edited_options, index, original["title"] || original[:title])

          %{
            title: edited_title,
            description: original["description"] || original[:description],
            image_url: original["image_url"] || original[:image_url],
            external_id: original["external_id"] || original[:external_id],
            external_data: original["external_data"] || original[:external_data],
            metadata: build_import_metadata(original)
          }
        end
      end)

    # Add custom options (filter out empty ones) - these have no metadata
    custom_options =
      socket.assigns.custom_options
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn title -> %{title: title} end)

    all_options = selected_options_with_metadata ++ custom_options

    # Extract titles for validation
    option_titles = Enum.map(all_options, & &1.title)

    # Validate
    errors = validate_poll(socket.assigns.poll_title, option_titles)

    if Enum.empty?(errors) do
      # Send message to parent component to create poll
      send(
        self(),
        {:create_poll_from_template,
         %{
           poll_type: socket.assigns.suggestion["poll_type"],
           voting_system: socket.assigns.selected_voting_system,
           title: socket.assigns.poll_title,
           options: all_options
         }}
      )

      {:noreply, socket}
    else
      {:noreply, assign(socket, :errors, errors)}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {:close_template_editor})
    {:noreply, socket}
  end

  # Helper to build import metadata from original option data
  defp build_import_metadata(original) when is_map(original) do
    base_metadata = original["metadata"] || original[:metadata] || %{}

    # Only add import info if we have source information
    if original["source_event"] || original[:source_event] ||
         original["source_poll_id"] || original[:source_poll_id] do
      Map.put(base_metadata, "import_info", %{
        "source_event_id" =>
          get_in(original, ["source_event", "id"]) || get_in(original, [:source_event, :id]),
        "source_event_title" =>
          get_in(original, ["source_event", "title"]) || get_in(original, [:source_event, :title]),
        "source_poll_id" => original["source_poll_id"] || original[:source_poll_id],
        "original_recommender_id" =>
          get_in(original, ["original_recommender", "id"]) ||
            get_in(original, [:original_recommender, :id]),
        "original_recommender_name" =>
          get_in(original, ["original_recommender", "name"]) ||
            get_in(original, [:original_recommender, :name]),
        "imported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })
    else
      base_metadata
    end
  end

  defp build_import_metadata(_), do: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="template-editor-modal" class="fixed inset-0 z-50 overflow-y-auto" phx-hook="ModalFocus">
      <div class="flex min-h-screen items-end justify-center px-4 pb-20 pt-4 text-center sm:block sm:p-0">
        <!-- Background overlay -->
        <div
          class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
          phx-click="cancel"
          phx-target={@myself}
        >
        </div>

        <!-- Center modal -->
        <span class="hidden sm:inline-block sm:h-screen sm:align-middle">​</span>

        <div class="inline-block transform overflow-hidden rounded-lg bg-white text-left align-bottom shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-3xl sm:align-middle">
          <div class="bg-white px-4 pb-4 pt-5 sm:p-6">
            <!-- Header -->
            <div class="mb-6">
              <div class="flex items-start justify-between">
                <div>
                  <h3 class="text-xl font-bold text-gray-900">Create Poll from Template</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    Customize your poll based on previous patterns
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="cancel"
                  phx-target={@myself}
                  class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                >
                  <span class="sr-only">Close</span>
                  <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              <!-- Template info banner -->
              <div class="mt-4 rounded-lg bg-indigo-50 p-4 border border-indigo-200">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <span class={"inline-flex items-center px-2.5 py-1 rounded-md text-xs font-semibold #{poll_type_badge_classes(@suggestion["poll_type"])}"}>
                      <%= format_poll_type_name(@suggestion["poll_type"]) %>
                    </span>
                    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-white text-gray-700 border border-gray-300">
                      <%= format_voting_system(@suggestion["voting_system"]) %>
                    </span>
                  </div>
                  <div class="flex items-center gap-1 text-sm text-indigo-700">
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                    </svg>
                    <span class="font-semibold"><%= Float.round(@suggestion["confidence"] * 100, 0) %>% match</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Errors -->
            <%= if !Enum.empty?(@errors) do %>
              <div class="mb-4 rounded-md bg-red-50 p-4 border border-red-200">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                    </svg>
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-red-800">Please fix the following errors:</h3>
                    <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
                      <%= for error <- @errors do %>
                        <li><%= error %></li>
                      <% end %>
                    </ul>
                  </div>
                </div>
              </div>
            <% end %>

            <div class="space-y-6">
              <!-- Poll Title -->
              <div>
                <label for="poll-title" class="block text-sm font-semibold text-gray-900 mb-2">
                  Poll Title
                </label>
                <input
                  id="poll-title"
                  type="text"
                  value={@poll_title}
                  phx-blur="update_title"
                  phx-target={@myself}
                  class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  placeholder="Enter poll title..."
                />
              </div>

              <!-- Voting System Selector -->
              <div>
                <label for="voting-system" class="block text-sm font-semibold text-gray-900 mb-2">
                  Voting System
                  <span class="ml-2 text-xs font-normal text-gray-500">
                    <%= if @selected_voting_system != @suggestion["voting_system"] do %>
                      (Changed from <%= format_voting_system(@suggestion["voting_system"]) %>)
                    <% else %>
                      (Original from template)
                    <% end %>
                  </span>
                </label>
                <form phx-change="update_voting_system" phx-target={@myself}>
                  <select
                    id="voting-system"
                    name="voting_system"
                    value={@selected_voting_system}
                    class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  >
                    <%= for voting_system <- available_voting_systems() do %>
                      <option value={voting_system} selected={@selected_voting_system == voting_system}>
                        <%= format_voting_system(voting_system) %> <%= if voting_system == @suggestion["voting_system"], do: "(Original)", else: "" %>
                      </option>
                    <% end %>
                  </select>
                </form>
                <p class="mt-1 text-xs text-gray-500">
                  <%= voting_system_description(@selected_voting_system) %>
                </p>
              </div>

              <!-- Options Selection -->
              <div>
                <div class="flex items-center justify-between mb-3">
                  <h4 class="text-sm font-semibold text-gray-900">Select Options from Template</h4>
                  <div class="flex gap-2">
                    <button
                      type="button"
                      phx-click="select_all"
                      phx-target={@myself}
                      class="text-xs font-medium text-indigo-600 hover:text-indigo-700 hover:underline"
                    >
                      Select All
                    </button>
                    <span class="text-gray-300">|</span>
                    <button
                      type="button"
                      phx-click="deselect_all"
                      phx-target={@myself}
                      class="text-xs font-medium text-gray-600 hover:text-gray-700 hover:underline"
                    >
                      Clear
                    </button>
                  </div>
                </div>

                <div class="space-y-2 max-h-96 overflow-y-auto border border-gray-200 rounded-lg p-3 bg-gray-50">
                  <%= for {option, index} <- Enum.with_index(@suggestion["common_options"]) do %>
                    <%
                      # Handle both old string format and new map format for backward compatibility
                      option_title = if is_binary(option), do: option, else: option["title"] || option[:title]
                      option_image = if is_map(option), do: option["image_url"] || option[:image_url], else: nil
                      option_recommender = if is_map(option), do: option["original_recommender"] || option[:original_recommender], else: nil
                      option_source_event = if is_map(option), do: option["source_event"] || option[:source_event], else: nil
                    %>
                    <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-gray-200 hover:border-indigo-300 transition-colors">
                      <input
                        type="checkbox"
                        id={"option-#{index}"}
                        checked={MapSet.member?(@selected_options, index)}
                        phx-click="toggle_option"
                        phx-value-index={index}
                        phx-target={@myself}
                        class="h-4 w-4 mt-1 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500 flex-shrink-0"
                      />

                      <%= if option_image do %>
                        <img
                          src={option_image}
                          alt={option_title}
                          class="w-12 h-12 rounded object-cover flex-shrink-0"
                          onerror="this.style.display='none'"
                        />
                      <% end %>

                      <div class="flex-1 min-w-0">
                        <input
                          type="text"
                          value={Map.get(@edited_options, index, option_title)}
                          phx-blur="edit_option"
                          phx-value-index={index}
                          phx-target={@myself}
                          disabled={!MapSet.member?(@selected_options, index)}
                          class="block w-full text-sm rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-50 disabled:text-gray-500"
                        />

                        <%= if option_recommender || option_source_event do %>
                          <div class="mt-1 flex items-center gap-2 text-xs text-gray-500">
                            <%= if option_recommender do %>
                              <span class="inline-flex items-center gap-1">
                                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                                </svg>
                                <%= option_recommender["name"] || option_recommender[:name] %>
                              </span>
                            <% end %>
                            <%= if option_source_event && (option_source_event["title"] || option_source_event[:title]) do %>
                              <span class="text-gray-300">•</span>
                              <span class="inline-flex items-center gap-1">
                                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                                </svg>
                                <%= option_source_event["title"] || option_source_event[:title] %>
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Custom Options -->
              <div>
                <div class="flex items-center justify-between mb-3">
                  <h4 class="text-sm font-semibold text-gray-900">Add Custom Options</h4>
                  <button
                    type="button"
                    phx-click="add_custom_option"
                    phx-target={@myself}
                    class="inline-flex items-center text-xs font-medium text-indigo-600 hover:text-indigo-700"
                  >
                    <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    Add Option
                  </button>
                </div>

                <%= if Enum.empty?(@custom_options) do %>
                  <div class="text-center py-6 text-sm text-gray-500 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
                    No custom options yet. Click "Add Option" to create one.
                  </div>
                <% else %>
                  <div class="space-y-2">
                    <%= for {custom, idx} <- Enum.with_index(@custom_options) do %>
                      <div class="flex items-center gap-2">
                        <input
                          type="text"
                          value={custom}
                          phx-blur="update_custom_option"
                          phx-value-index={idx}
                          phx-target={@myself}
                          placeholder="Enter option text..."
                          class="flex-1 text-sm rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        />
                        <button
                          type="button"
                          phx-click="remove_custom_option"
                          phx-value-index={idx}
                          phx-target={@myself}
                          class="p-2 text-red-600 hover:text-red-700 hover:bg-red-50 rounded-md"
                        >
                          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                          </svg>
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="bg-gray-50 px-4 py-3 sm:flex sm:flex-row-reverse sm:px-6">
            <button
              type="button"
              phx-click="create_poll"
              phx-target={@myself}
              class="inline-flex w-full justify-center rounded-lg bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 sm:ml-3 sm:w-auto"
            >
              Create Poll
            </button>
            <button
              type="button"
              phx-click="cancel"
              phx-target={@myself}
              class="mt-3 inline-flex w-full justify-center rounded-lg bg-white px-4 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp validate_poll(title, options) do
    errors = []

    errors =
      if String.trim(title) == "" do
        ["Poll title is required" | errors]
      else
        errors
      end

    errors =
      if Enum.empty?(options) do
        ["At least one option is required" | errors]
      else
        errors
      end

    Enum.reverse(errors)
  end

  defp format_poll_type_name("movie"), do: "Movie"
  defp format_poll_type_name("places"), do: "Places"
  defp format_poll_type_name("music_track"), do: "Music"
  defp format_poll_type_name("venue"), do: "Venue"
  defp format_poll_type_name("date_selection"), do: "Date"
  defp format_poll_type_name("time"), do: "Time"
  defp format_poll_type_name("general"), do: "General"
  defp format_poll_type_name("custom"), do: "Custom"
  defp format_poll_type_name(type), do: String.capitalize(type)

  defp poll_type_badge_classes("date_selection"),
    do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-200"

  defp poll_type_badge_classes("movie"),
    do: "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-200"

  defp poll_type_badge_classes("places"),
    do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200"

  defp poll_type_badge_classes("venue"),
    do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200"

  defp poll_type_badge_classes("music_track"),
    do: "bg-pink-100 text-pink-700 dark:bg-pink-900 dark:text-pink-200"

  defp poll_type_badge_classes("time"),
    do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-200"

  defp poll_type_badge_classes(_),
    do: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200"

  defp format_voting_system("binary"), do: "Yes/No"
  defp format_voting_system("approval"), do: "Select Multiple"
  defp format_voting_system("ranked"), do: "Ranked Choice"
  defp format_voting_system("star"), do: "Star Rating"
  defp format_voting_system(system), do: String.capitalize(system)

  defp available_voting_systems do
    ["binary", "approval", "ranked", "star"]
  end

  defp voting_system_description("binary"),
    do: "Voters can choose Yes, No, or Maybe for each option"

  defp voting_system_description("approval"),
    do: "Voters can select multiple options they approve of"

  defp voting_system_description("ranked"),
    do: "Voters rank options in order of preference"

  defp voting_system_description("star"),
    do: "Voters rate each option with 1-5 stars"

  defp voting_system_description(_), do: ""
end
