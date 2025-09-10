defmodule EventasaurusWeb.OptionSuggestionFormComponent do
  @moduledoc """
  Form component for suggesting new poll options.
  
  Handles form display, validation, and submission for creating new poll options.
  Supports different poll types with appropriate form fields and validation.
  
  ## Attributes:
  - poll: Poll struct (required)
  - changeset: Form changeset (required)
  - loading: Loading state (default: false)
  - editing_option_id: ID of option being edited (optional)
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events.PollOption
  alias EventasaurusWeb.OptionSuggestionHelpers

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:loading, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-6 py-4 bg-gray-50 border-b border-gray-200 form-container-mobile suggestion-form">
      <.form for={@changeset} phx-submit="submit_suggestion" phx-target={@myself} phx-change="validate_suggestion">
        <div class="space-y-4">
          
          <!-- Option Title Field -->
          <div>
            <label for="title" class="block text-sm font-medium text-gray-700">
              <%= OptionSuggestionHelpers.option_title_label(@poll) %>
            </label>
            <div class="mt-1">
              <%= if @poll.poll_type == "date_selection" do %>
                <!-- Date selection polls use readonly title from calendar -->
                <input
                  type="text"
                  name="poll_option[title]"
                  id="title"
                  value={Phoenix.HTML.Form.input_value(@changeset, :title)}
                  readonly
                  class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md bg-gray-50"
                  placeholder="Select a date from the calendar below"
                />
              <% else %>
                <!-- Regular title input for other poll types -->
                <input
                  type="text"
                  name="poll_option[title]"
                  id="title"
                  value={Phoenix.HTML.Form.input_value(@changeset, :title)}
                  class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
                  placeholder={OptionSuggestionHelpers.option_title_placeholder(@poll)}
                  phx-debounce="300"
                  phx-keyup={if OptionSuggestionHelpers.should_use_api_search?(@poll.poll_type), do: get_search_event(@poll.poll_type), else: nil}
                  phx-target={@myself}
                />
              <% end %>
              
              <!-- Title validation errors -->
              <%= if @changeset.errors[:title] do %>
                <div class="mt-1 text-sm text-red-600">
                  <%= translate_error(@changeset.errors[:title]) %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Description Field -->
          <div>
            <label for="description" class="block text-sm font-medium text-gray-700">
              Description <span class="text-gray-400">(optional)</span>
            </label>
            <div class="mt-1">
              <textarea
                name="poll_option[description]"
                id="description"
                rows="3"
                class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
                placeholder={OptionSuggestionHelpers.option_description_placeholder(@poll.poll_type)}
                phx-debounce="300"
              ><%= Phoenix.HTML.Form.input_value(@changeset, :description) %></textarea>
              
              <!-- Description validation errors -->
              <%= if @changeset.errors[:description] do %>
                <div class="mt-1 text-sm text-red-600">
                  <%= translate_error(@changeset.errors[:description]) %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Hidden fields for rich data (populated by search components) -->
          <input type="hidden" name="poll_option[external_id]" value={Phoenix.HTML.Form.input_value(@changeset, :external_id)} />
          <input type="hidden" name="poll_option[external_data]" value={Phoenix.HTML.Form.input_value(@changeset, :external_data)} />
          <input type="hidden" name="poll_option[image_url]" value={Phoenix.HTML.Form.input_value(@changeset, :image_url)} />

          <!-- Form Actions -->
          <div class="flex items-center justify-between pt-2">
            <button
              type="button"
              phx-click="cancel_suggestion"
              phx-target={@myself}
              class="text-sm text-gray-500 hover:text-gray-700"
            >
              Cancel
            </button>
            
            <div class="flex items-center space-x-3">
              <%= if @loading do %>
                <div class="flex items-center text-sm text-gray-500">
                  <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-500" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Saving...
                </div>
              <% else %>
                <button
                  type="submit"
                  disabled={not @changeset.valid?}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:bg-gray-300 disabled:cursor-not-allowed"
                >
                  <%= if @editing_option_id, do: "Update", else: "Add" %> <%= OptionSuggestionHelpers.option_type_text(@poll.poll_type) %>
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </.form>

      <!-- Mobile loading overlay -->
      <%= if @loading do %>
        <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50 flex items-center justify-center">
          <div class="bg-white p-8 rounded-lg shadow-lg flex items-center">
            <svg class="animate-spin -ml-1 mr-3 h-6 w-6 text-indigo-600" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <span class="text-gray-700">Saving suggestion...</span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("validate_suggestion", %{"poll_option" => option_params}, socket) do
    changeset = create_changeset(socket.assigns.poll, option_params)
    send(self(), {:form_validated, changeset})
    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_suggestion", %{"poll_option" => option_params}, socket) do
    send(self(), {:form_submitted, option_params})
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_suggestion", _params, socket) do
    send(self(), {:form_cancelled})
    {:noreply, socket}
  end

  # Search event handlers - delegate to parent
  @impl true
  def handle_event("search_movies", params, socket) do
    send(self(), {:search_movies, params})
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_music_tracks", params, socket) do
    send(self(), {:search_music_tracks, params})
    {:noreply, socket}
  end

  # Helper functions

  defp create_changeset(poll, option_params) do
    %PollOption{}
    |> PollOption.changeset(Map.merge(option_params, %{"poll_id" => poll.id}))
  end

  defp get_search_event(poll_type) do
    case poll_type do
      "movie" -> "search_movies"
      "music" -> "search_music_tracks"
      _ -> nil
    end
  end

end