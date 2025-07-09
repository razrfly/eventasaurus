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
  alias EventasaurusWeb.Services.PollPubSubService

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:suggestion_form_visible, false)
     |> assign(:editing_option_id, nil)
     |> assign(:search_results, [])
     |> assign(:search_loading, false)
     |> assign(:search_query, "")
     |> assign(:show_search_dropdown, false)
     |> assign(:selected_result, nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Handle special actions first
    cond do
      assigns[:action] == :perform_search ->
        # Perform the search and update the socket
        parent_pid = self()
        Task.start(fn ->
          results = perform_search(assigns.search_query, assigns.poll_type)
          send_update(parent_pid, __MODULE__,
            id: socket.assigns.id,
            action: :search_complete,
            search_results: results,
            search_query: assigns.search_query
          )
        end)

        {:ok, assign(socket, :search_loading, true)}

      assigns[:action] == :search_complete ->
        # Update with search results
        {:ok,
         socket
         |> assign(:search_results, assigns.search_results)
         |> assign(:search_loading, false)
         |> assign(:show_search_dropdown, true)
         |> assign(:search_query, assigns.search_query)}

      true ->
        # Normal update flow
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
         |> assign_new(:editing_option_id, fn -> nil end)
         |> assign_new(:edit_changeset, fn -> nil end)
         |> assign_new(:search_results, fn -> [] end)
         |> assign_new(:search_loading, fn -> false end)
         |> assign_new(:search_query, fn -> "" end)
         |> assign_new(:show_search_dropdown, fn -> false end)
         |> assign_new(:selected_result, fn -> nil end)
         |> then(fn socket ->
           # Handle editing mode after all other assigns are set
           if Map.get(assigns, :editing_option_id) do
             option = Enum.find(assigns.poll.poll_options, fn opt -> opt.id == assigns.editing_option_id end)
             if option do
               edit_changeset = PollOption.changeset(option, %{})
               socket
               |> assign(:editing_option_id, assigns.editing_option_id)
               |> assign(:edit_changeset, edit_changeset)
             else
               socket |> assign(:editing_option_id, nil)
             end
           else
             socket
           end
         end)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Add Option Button Area -->
      <div class="px-6 py-3 bg-gray-50 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div class="text-sm text-gray-500">
            <%= @user_suggestion_count %>/<%= @max_options %> suggestions used
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
            <div class="text-sm text-gray-500 font-medium">
              Limit reached (<%= @max_options %> suggestions)
            </div>
          <% end %>
        </div>
      </div>

      <!-- Suggestion Form -->
      <%= if @suggestion_form_visible do %>
        <div class="px-6 py-4 bg-gray-50 border-b border-gray-200 form-container-mobile suggestion-form">
          <.form for={@changeset} phx-submit="submit_suggestion" phx-target={@myself} phx-change="validate_suggestion">
            <div class="space-y-4">
              <!-- Auto-complete title input -->
              <div class="relative">
                <label for="option_title" class="block text-sm font-medium text-gray-700">
                  <%= option_title_label(@poll.poll_type) %> <span class="text-red-500">*</span>
                </label>
                <div class="mt-1 relative">
                  <input
                    type="text"
                    name="poll_option[title]"
                    id="option_title"
                    value={Phoenix.HTML.Form.input_value(@form, :title)}
                    placeholder={option_title_placeholder(@poll.poll_type)}
                    phx-debounce="300"
                    phx-change="search_external_apis"
                    phx-target={@myself}
                    phx-focus="show_search_dropdown"
                    phx-blur="hide_search_dropdown"
                    autocomplete="off"
                    class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  />

                  <!-- Search loading indicator -->
                  <%= if @search_loading do %>
                    <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                      <svg class="animate-spin h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                    </div>
                  <% end %>
                </div>

                <!-- Search results dropdown -->
                <%= if @show_search_dropdown && length(@search_results) > 0 do %>
                  <!-- Mobile backdrop for dropdown -->
                  <div class="search-dropdown-backdrop md:hidden" phx-click="hide_search_dropdown" phx-target={@myself}></div>

                  <div class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm search-dropdown mobile-scroll-container">
                                          <%= for result <- @search_results do %>
                        <div
                          phx-click="select_search_result"
                          phx-value-result-id={result.id}
                          phx-target={@myself}
                          class="group cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-indigo-50 search-result-item interactive-element touch-active"
                        >
                        <div class="flex items-center">
                          <!-- Image thumbnail if available -->
                          <%= if get_result_image(result) do %>
                            <img class="flex-shrink-0 h-10 w-10 rounded object-cover" src={get_result_image(result)} alt="" />
                            <div class="ml-3 flex-1 min-w-0">
                              <div class="flex items-center">
                                <span class="font-medium text-gray-900 truncate"><%= result.title %></span>
                                <%= if result.metadata && result.metadata["release_date"] do %>
                                  <span class="ml-1 text-gray-500 text-sm">(<%= extract_year(result.metadata["release_date"]) %>)</span>
                                <% end %>
                                <%= if result.metadata && result.metadata["rating"] do %>
                                  <span class="ml-2 text-yellow-500 text-sm">⭐ <%= format_rating(result.metadata["rating"]) %></span>
                                <% end %>
                              </div>
                              <%= if result.description && result.description != "" do %>
                                <p class="text-gray-500 text-sm truncate"><%= String.slice(result.description, 0, 100) %><%= if String.length(result.description) > 100, do: "..." %></p>
                              <% end %>
                            </div>
                          <% else %>
                            <div class="flex-1 min-w-0">
                              <div class="flex items-center">
                                <span class="font-medium text-gray-900 truncate"><%= result.title %></span>
                                <%= if result.metadata && result.metadata["release_date"] do %>
                                  <span class="ml-1 text-gray-500 text-sm">(<%= extract_year(result.metadata["release_date"]) %>)</span>
                                <% end %>
                                <%= if result.metadata && result.metadata["rating"] do %>
                                  <span class="ml-2 text-yellow-500 text-sm">⭐ <%= format_rating(result.metadata["rating"]) %></span>
                                <% end %>
                              </div>
                              <%= if result.description && result.description != "" do %>
                                <p class="text-gray-500 text-sm truncate"><%= String.slice(result.description, 0, 100) %><%= if String.length(result.description) > 100, do: "..." %></p>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <!-- Manual entry option -->
                    <div
                      phx-click="select_manual_entry"
                      phx-target={@myself}
                      class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-gray-50 border-t border-gray-200"
                    >
                      <div class="flex items-center">
                        <svg class="h-5 w-5 text-gray-400 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                        </svg>
                        <span class="text-gray-700">Enter manually: "<%= @search_query %>"</span>
                      </div>
                    </div>
                  </div>
                <% end %>

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
                  placeholder={option_description_placeholder(@poll.poll_type)}
                  class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                ><%= Phoenix.HTML.Form.input_value(@form, :description) %></textarea>
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
                    class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 cancel-button touch-target"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={@loading}
                    class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 suggestion-button touch-target"
                  >
                    <%= if @loading do %>
                      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
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
            </div>
          </.form>

          <!-- Mobile loading overlay -->
          <%= if @loading do %>
            <div class="mobile-loading-overlay md:hidden">
              <div class="mobile-loading-spinner"></div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Options List -->
      <div
        class="divide-y divide-gray-200 min-h-[100px] relative"
        phx-hook="PollOptionDragDrop"
        data-can-reorder={@is_creator}
        id={"option-list-#{@id}"}
      >
        <%= if Enum.empty?(@poll.poll_options) do %>
          <!-- Enhanced Empty State -->
          <div class="px-6 py-16 text-center">
            <!-- Poll type specific icon -->
            <div class="mx-auto w-20 h-20 bg-indigo-100 rounded-full flex items-center justify-center mb-6">
              <%= case @poll.poll_type do %>
                <% "movie" -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2C7 1.45 7.45 1 8 1s1 .45 1 1v2h4V2c0-.55.45-1 1-1s1 .45 1 1v2h1c1.1 0 2 .9 2 2v14c0 1.1-.9 2-2 2H6c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2h1z"/>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                  </svg>
                <% "restaurant" -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
                  </svg>
                <% "activity" -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"/>
                  </svg>
                <% _ -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"/>
                  </svg>
              <% end %>
            </div>

            <h3 class="text-xl font-semibold text-gray-900 mb-2">
              <%= get_empty_state_title(@poll.poll_type) %>
            </h3>

            <p class="text-gray-600 mb-2 max-w-md mx-auto">
              <%= get_empty_state_description(@poll.poll_type, @poll.voting_system) %>
            </p>

            <!-- Contextual guidance -->
            <div class="text-sm text-gray-500 mb-8 max-w-lg mx-auto">
              <%= get_empty_state_guidance(@poll.poll_type) %>
            </div>

            <!-- Large Call-to-Action Button -->
            <%= if @can_suggest_more do %>
              <button
                type="button"
                phx-click="toggle_suggestion_form"
                phx-target={@myself}
                class="inline-flex items-center px-8 py-4 border border-transparent text-lg font-medium rounded-lg shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors duration-200"
              >
                <svg class="-ml-1 mr-3 h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                </svg>
                <%= get_empty_state_button_text(@poll.poll_type) %>
              </button>

              <!-- Secondary helpful text -->
              <p class="mt-4 text-sm text-gray-500">
                <%= get_empty_state_help_text(@poll.poll_type) %>
              </p>
            <% else %>
              <div class="text-center p-6 bg-gray-50 rounded-lg max-w-md mx-auto">
                <p class="text-gray-700 font-medium">You've reached your limit</p>
                <p class="text-sm text-gray-500 mt-1">
                  You can suggest up to <%= @max_options %> options. Ask others to add more suggestions!
                </p>
              </div>
            <% end %>
          </div>
        <% else %>
          <div data-role="options-container">
            <%= for option <- sort_options_by_order(@poll.poll_options) do %>
              <div
                class="px-6 py-4 transition-all duration-150 ease-out option-card mobile-optimized-animation"
                data-draggable={if @is_creator, do: "true", else: "false"}
                data-option-id={option.id}
              >
                <!-- Edit Form (only shown when editing this specific option) -->
                <%= if @editing_option_id == option.id && @edit_changeset do %>
                  <.form for={@edit_changeset} phx-submit="save_edit" phx-target={@myself} phx-change="validate_edit">
                    <div class="space-y-4">
                      <input type="hidden" name="option_id" value={option.id} />

                      <div>
                        <label for={"edit_title_#{option.id}"} class="block text-sm font-medium text-gray-700">
                          Title <span class="text-red-500">*</span>
                        </label>
                        <input
                          type="text"
                          name="poll_option[title]"
                          id={"edit_title_#{option.id}"}
                          value={@edit_changeset.changes[:title] || option.title}
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <%= if error = @edit_changeset.errors[:title] do %>
                          <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                        <% end %>
                      </div>

                      <div>
                        <label for={"edit_description_#{option.id}"} class="block text-sm font-medium text-gray-700">
                          Description (optional)
                        </label>
                        <textarea
                          name="poll_option[description]"
                          id={"edit_description_#{option.id}"}
                          rows="2"
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        ><%= @edit_changeset.changes[:description] || option.description || "" %></textarea>
                      </div>

                      <%= if @is_creator do %>
                        <div class="flex items-center">
                          <input
                            type="checkbox"
                            name="poll_option[status]"
                            id={"edit_hidden_#{option.id}"}
                            value="hidden"
                            checked={(@edit_changeset.changes[:status] || option.status) == "hidden"}
                            class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                          />
                          <label for={"edit_hidden_#{option.id}"} class="ml-2 block text-sm text-gray-900">
                            Hide this option from participants
                          </label>
                        </div>
                      <% end %>

                      <div class="flex space-x-3">
                        <button
                          type="submit"
                          class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit"
                          phx-target={@myself}
                          class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                <% else %>
                  <!-- Normal Option Display -->
                  <div class="flex items-start justify-between">
                    <!-- Drag handle for creators -->
                    <%= if @is_creator do %>
                      <div class="drag-handle mr-3 mt-1 flex-shrink-0 touch-target" title="Drag to reorder">
                        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
                          <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z"/>
                        </svg>
                      </div>
                    <% end %>

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

                    <!-- Rich data display -->
                    <%= if option.external_data && map_size(option.external_data) > 0 do %>
                      <div class="mt-3">
                        <.live_component
                          module={EventasaurusWeb.Live.Components.RichDataDisplayComponent}
                          id={"rich-data-#{option.id}"}
                          rich_data={option.external_data}
                          compact={true}
                          show_sections={[:hero]}
                          class="border-l-4 border-indigo-200 pl-3"
                        />
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
                  <div class="ml-4 flex-shrink-0 flex items-center space-x-2 option-card-actions">
                    <%= if @is_creator || option.suggested_by_id == @user.id do %>
                      <!-- Edit option button -->
                      <button
                        type="button"
                        phx-click="edit_option"
                        phx-value-option-id={option.id}
                        phx-target={@myself}
                        class="text-indigo-600 hover:text-indigo-900 text-sm font-medium touch-target interactive-element"
                      >
                        Edit
                      </button>
                    <% end %>

                    <%= if @is_creator do %>
                      <!-- Remove option button -->
                      <button
                        type="button"
                        phx-click="remove_option"
                        phx-value-option-id={option.id}
                        phx-target={@myself}
                        data-confirm="Are you sure you want to remove this option? This action cannot be undone."
                        class="text-red-600 hover:text-red-900 text-sm font-medium touch-target interactive-element"
                      >
                        Remove
                      </button>
                    <% end %>
                  </div>
                </div>
                <% end %>
              </div>
            <% end %>
          </div>
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
    {:noreply,
     socket
     |> assign(:suggestion_form_visible, !socket.assigns.suggestion_form_visible)
     |> assign(:search_results, [])
     |> assign(:search_query, "")
     |> assign(:show_search_dropdown, false)
     |> assign(:selected_result, nil)}
  end

  @impl true
  def handle_event("search_external_apis", %{"poll_option" => %{"title" => query}}, socket) do
    query = String.trim(query)

    # Update search query state
    socket = assign(socket, :search_query, query)

    # Only search if query is long enough
    if String.length(query) >= 2 do
      # Start loading state
      socket = assign(socket, :search_loading, true)

      # Perform async search
      send(self(), {:perform_external_search, query, socket.assigns.poll.poll_type})

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:search_loading, false)
       |> assign(:show_search_dropdown, false)}
    end
  end

  @impl true
  def handle_event("show_search_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_search_dropdown, true)}
  end

  @impl true
  def handle_event("hide_search_dropdown", _params, socket) do
    # Delay hiding to allow for clicks on dropdown items
    Process.send_after(self(), {:hide_dropdown, socket.assigns.id}, 150)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_search_result", %{"result-id" => result_id}, socket) do
    case find_result_by_id(socket.assigns.search_results, result_id) do
      nil ->
        {:noreply, socket}

      result ->
        # Populate form with selected result
        changeset = create_option_changeset(socket, %{
          "title" => result.title,
          "description" => result.description || "",
          "external_id" => to_string(result.id),
          "external_data" => build_external_data_from_result(result)
        })

        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> assign(:selected_result, result)
         |> assign(:search_results, [])
         |> assign(:show_search_dropdown, false)}
    end
  end

  @impl true
  def handle_event("select_manual_entry", _params, socket) do
    # Keep current form state but hide dropdown
    {:noreply,
     socket
     |> assign(:search_results, [])
     |> assign(:show_search_dropdown, false)
     |> assign(:selected_result, nil)}
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
        # Broadcast option suggestion via PubSub
        poll = socket.assigns.poll
        user = socket.assigns.user

        # Check for duplicates if the service is available
        duplicate_options = check_for_duplicates(poll, option)

        if length(duplicate_options) > 0 do
          PollPubSubService.broadcast_duplicate_detected(poll, option, duplicate_options, user)
        else
          PollPubSubService.broadcast_option_suggested(poll, option, user)
        end

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
  def handle_event("remove_option", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          nil ->
            send(self(), {:show_error, "Option not found"})
            {:noreply, socket}

          poll_option ->
            case Events.delete_poll_option(poll_option) do
              {:ok, _} ->
                # For option removal, we could broadcast a bulk moderation action
                # or handle it as a special case
                send(self(), {:option_removed, option_id})
                {:noreply, socket}

              {:error, _} ->
                send(self(), {:show_error, "Failed to remove option"})
                {:noreply, socket}
            end
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid option ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit_option", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        option = Enum.find(socket.assigns.poll.poll_options, fn opt -> opt.id == option_id_int end)
        if option do
          edit_changeset = PollOption.changeset(option, %{})
          {:noreply,
           socket
           |> assign(:editing_option_id, option_id_int)
           |> assign(:edit_changeset, edit_changeset)}
        else
          send(self(), {:show_error, "Option not found"})
          {:noreply, socket}
        end
      {:error, _reason} ->
        send(self(), {:show_error, "Invalid option ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_option_id, nil)}
  end

  @impl true
  def handle_event("validate_edit", %{"poll_option" => option_params}, socket) do
    # Add nil check before accessing editing_option_id
    if socket.assigns.editing_option_id do
      option = Enum.find(socket.assigns.poll.poll_options, fn opt -> opt.id == socket.assigns.editing_option_id end)
      if option do
        changeset = PollOption.changeset(option, option_params)
        {:noreply, assign(socket, :edit_changeset, changeset)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_edit", %{"poll_option" => option_params, "option_id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          %PollOption{} = option ->
            # Handle status field - checkbox sends "hidden" when checked, nothing when unchecked
            updated_params = case Map.get(option_params, "status") do
              "hidden" -> option_params
              _ -> Map.put(option_params, "status", "active")
            end

            case Events.update_poll_option(option, updated_params) do
              {:ok, updated_option} ->
                # Broadcast visibility change if status changed
                if option.status != updated_option.status do
                  status_atom = case updated_option.status do
                    "hidden" -> :hidden
                    "active" -> :shown
                    _ -> :shown
                  end

                  PollPubSubService.broadcast_option_visibility_changed(
                    socket.assigns.poll,
                    updated_option,
                    status_atom,
                    socket.assigns.user
                  )
                end

                send(self(), {:option_updated, updated_option})
                {:noreply, assign(socket, :editing_option_id, nil)}

              {:error, changeset} ->
                {:noreply, assign(socket, :edit_changeset, changeset)}
            end

          nil ->
            {:noreply, put_flash(socket, :error, "Option not found")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invalid option ID")}
    end
  end

  @impl true
  def handle_event("start_voting", _params, socket) do
    case Events.transition_poll_to_voting(socket.assigns.poll) do
      {:ok, poll} ->
        # Broadcast phase change via PubSub
        PollPubSubService.broadcast_poll_phase_changed(
          poll,
          "list_building",
          "voting",
          socket.assigns.user
        )

        send(self(), {:poll_phase_changed, poll, "Voting phase started!"})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to start voting phase"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reorder_option", params, socket) do
    %{
      "dragged_option_id" => dragged_id,
      "target_option_id" => target_id,
      "direction" => direction,
      "original_order" => _original_order
    } = params

    # Only allow reordering if user is creator
    if socket.assigns.is_creator do
      case Events.reorder_poll_option(dragged_id, target_id, direction) do
        {:ok, updated_poll} ->
          # Broadcast options reordered via PubSub
          PollPubSubService.broadcast_options_reordered(
            socket.assigns.poll,
            updated_poll.poll_options,
            socket.assigns.user
          )

          # Success - LiveView will receive poll update via PubSub
          send(self(), {:option_reordered, "Options reordered successfully"})
          {:noreply, socket}

        {:error, reason} ->
          # Send rollback command to JavaScript hook
          send(self(), {:js_push, "rollback_order", %{}, socket.assigns.id})
          send(self(), {:show_error, "Failed to reorder options: #{reason}"})
          {:noreply, socket}
      end
    else
      # Send rollback command since user can't reorder
      send(self(), {:js_push, "rollback_order", %{}, socket.assigns.id})
      send(self(), {:show_error, "You don't have permission to reorder options"})
      {:noreply, socket}
    end
  end

  # Handle async search results
  def handle_info({:search_results, query, results}, socket) do
    # Only update if this is for the current query
    if query == socket.assigns.search_query do
      {:noreply,
       socket
       |> assign(:search_results, results)
       |> assign(:search_loading, false)
       |> assign(:show_search_dropdown, length(results) > 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:search_error, query, _error}, socket) do
    # Only update if this is for the current query
    if query == socket.assigns.search_query do
      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:search_loading, false)
       |> assign(:show_search_dropdown, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:hide_dropdown, component_id}, socket) do
    if component_id == socket.assigns.id do
      {:noreply, assign(socket, :show_search_dropdown, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:perform_external_search, query, poll_type}, socket) do
    # Perform the search in the background
    parent_pid = self()
    Task.start(fn ->
      results = perform_search(query, poll_type)
      send(parent_pid, {:search_results, query, results})
    end)

    {:noreply, socket}
  end

  # Private helper functions

  defp perform_search(query, poll_type) do
    # Map poll type to provider search options
    search_options = get_search_options_for_poll_type(poll_type)

    case EventasaurusWeb.Services.RichDataManager.search(query, search_options) do
      {:ok, results_by_provider} ->
        # Flatten and limit results from all providers
        results_by_provider
        |> Map.values()
        |> List.flatten()
        |> Enum.take(8)  # Limit to 8 results for UI performance

      {:error, _reason} ->
        []
    end
  rescue
    _ -> []
  end

  defp get_search_options_for_poll_type(poll_type) do
    case poll_type do
      "movie" -> %{providers: [:tmdb], types: [:movie]}
      "restaurant" -> %{providers: [:google_places], types: [:restaurant]}
      "activity" -> %{providers: [:google_places], types: [:activity, :venue]}
      _ -> %{}
    end
  end

  defp find_result_by_id(results, target_id) do
    Enum.find(results, fn result ->
      to_string(result.id) == to_string(target_id)
    end)
  end

  defp build_external_data_from_result(result) do
    # Convert search result to external_data format for the poll option
    %{
      "type" => to_string(result.type),
      "external_id" => to_string(result.id),
      "title" => result.title,
      "description" => result.description,
      "metadata" => result.metadata || %{},
      "images" => result.images || []
    }
  end

  # Template helper functions

  defp sort_options_by_order(poll_options) do
    poll_options
    |> Enum.sort_by(fn option -> option.order_index || 0 end, :asc)
  end

  defp get_result_image(result) do
    case result.images do
      [first_image | _] -> first_image["url"] || first_image.url
      _ -> nil
    end
  end

  defp extract_year(date_string) when is_binary(date_string) do
    case String.split(date_string, "-") do
      [year | _] -> year
      _ -> ""
    end
  end
  defp extract_year(_), do: ""

  defp format_rating(rating) when is_number(rating) do
    Float.round(rating, 1)
  end
  defp format_rating(rating) when is_binary(rating) do
    case Float.parse(rating) do
      {float_val, _} -> Float.round(float_val, 1)
      _ -> rating
    end
  end
  defp format_rating(rating), do: rating

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

  defp suggest_button_text(poll_type) do
    case poll_type do
      "movie" -> "Suggest Movie"
      "restaurant" -> "Suggest Restaurant"
      "activity" -> "Suggest Activity"
      _ -> "Add Option"
    end
  end

  defp option_title_label(poll_type) do
    case poll_type do
      "movie" -> "Movie Title"
      "restaurant" -> "Restaurant Name"
      "activity" -> "Activity Name"
      _ -> "Option Title"
    end
  end

  defp option_title_placeholder(poll_type) do
    case poll_type do
      "movie" -> "e.g., The Matrix, Inception, Pulp Fiction"
      "restaurant" -> "e.g., Joe's Pizza, The French Laundry"
      "activity" -> "e.g., Hiking, Bowling, Museum Visit"
      _ -> "Enter your suggestion..."
    end
  end

  defp option_description_placeholder(poll_type) do
    case poll_type do
      "movie" -> "Brief plot summary or why you recommend it..."
      "restaurant" -> "Cuisine type, location, or special notes..."
      "activity" -> "Location, duration, or what makes it fun..."
      _ -> "Additional details or context..."
    end
  end

  defp option_type_text(poll_type) do
    case poll_type do
      "movie" -> "movies"
      "restaurant" -> "restaurants"
      "activity" -> "activities"
      _ -> "options"
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()

    # Convert NaiveDateTime to DateTime if needed
    datetime_utc = case datetime do
      %DateTime{} = dt -> dt
      %NaiveDateTime{} = ndt ->
        case DateTime.from_naive(ndt, "Etc/UTC") do
          {:ok, dt} -> dt
          {:error, _} -> DateTime.utc_now()
        end
      _ ->
        # Log unexpected type for debugging
        require Logger
        Logger.warning("Unexpected datetime type in format_relative_time: #{inspect(datetime)}")
        DateTime.utc_now()
    end

    diff = DateTime.diff(now, datetime_utc, :second)

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

  defp check_for_duplicates(_poll, _option) do
    # For now, return empty list - duplicate detection can be enhanced later
    # In a full implementation, this would use the DuplicateDetectionService
    []
  end

  defp safe_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp safe_string_to_integer(_), do: {:error, :invalid_input}

  # New helper functions for empty state
  defp get_empty_state_title(poll_type) do
    case poll_type do
      "movie" -> "No Movies Suggested Yet"
      "restaurant" -> "No Restaurants Suggested Yet"
      "activity" -> "No Activities Suggested Yet"
      _ -> "No Options Suggested Yet"
    end
  end

  defp get_empty_state_description(poll_type, voting_system) do
    type_text = option_type_text(poll_type)

    case voting_system do
      "binary" -> "Be the first to suggest #{type_text} for yes/no voting!"
      "approval" -> "Be the first to suggest #{type_text} for approval voting!"
      "ranked" -> "Be the first to suggest #{type_text} for ranked choice voting!"
      "star" -> "Be the first to suggest #{type_text} for star rating!"
      _ -> "Be the first to suggest #{type_text} to vote on!"
    end
  end

  defp get_empty_state_guidance(poll_type) do
    case poll_type do
      "movie" -> "Suggest movies that you love or think others would enjoy. Add a brief description for others to understand your choice."
      "restaurant" -> "Suggest restaurants that are popular or unique. Add details like cuisine, location, or special notes."
      "activity" -> "Suggest activities that are fun or interesting. Add location, duration, or what makes it unique."
      _ -> "Suggest options that you think are great. Add a description to help others understand your choice."
    end
  end

  defp get_empty_state_button_text(poll_type) do
    case poll_type do
      "movie" -> "Suggest a Movie"
      "restaurant" -> "Suggest a Restaurant"
      "activity" -> "Suggest an Activity"
      _ -> "Add an Option"
    end
  end

  defp get_empty_state_help_text(poll_type) do
    case poll_type do
      "movie" -> "You can suggest up to 3 movies. Encourage others to add more suggestions!"
      "restaurant" -> "You can suggest up to 3 restaurants. Encourage others to add more suggestions!"
      "activity" -> "You can suggest up to 3 activities. Encourage others to add more suggestions!"
      _ -> "You can suggest up to 3 options. Encourage others to add more suggestions!"
    end
  end
end
