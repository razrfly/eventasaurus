defmodule EventasaurusWeb.PublicCocktailPollComponent do
  @moduledoc """
  Simple public interface for cocktail polling.

  Shows existing cocktail options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  Supports both authenticated and anonymous voting.
  """

  use EventasaurusWeb, :live_component

  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.Services.CocktailDataService
  alias EventasaurusWeb.Utils.PollPhaseUtils

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Use the provided poll or fall back to searching for a cocktail poll
    cocktail_poll = assigns[:poll] || get_cocktail_poll(assigns.event)
    cocktail_options = if cocktail_poll, do: Events.list_poll_options(cocktail_poll), else: []

    # Load user votes for this poll
    user_votes =
      if assigns.current_user && cocktail_poll do
        Events.list_user_poll_votes(cocktail_poll, assigns.current_user)
      else
        []
      end

    # Preload suggested_by for all options using batch loading
    cocktail_options =
      if cocktail_poll && length(cocktail_options) > 0 do
        # Check if any options need preloading
        needs_preload =
          Enum.any?(cocktail_options, fn option ->
            match?(%Ecto.Association.NotLoaded{}, option.suggested_by)
          end)

        if needs_preload do
          # Get all option IDs and batch load them with suggested_by preloaded
          option_ids = Enum.map(cocktail_options, & &1.id)
          preloaded_options = Events.list_poll_options_by_ids(option_ids, [:suggested_by])

          # Create a map for quick lookup
          preloaded_map = Map.new(preloaded_options, fn option -> {option.id, option} end)

          # Return options with preloaded data, filtering out any that were deleted
          cocktail_options
          |> Enum.filter(fn option -> Map.has_key?(preloaded_map, option.id) end)
          |> Enum.map(fn option -> Map.get(preloaded_map, option.id, option) end)
        else
          # All options already have suggested_by loaded
          cocktail_options
        end
      else
        cocktail_options
      end

    # Get temp votes for this poll (for anonymous users)
    temp_votes = assigns[:temp_votes] || %{}

    # Load poll statistics for embedded display
    poll_stats =
      if cocktail_poll do
        try do
          Events.get_poll_voting_stats(cocktail_poll)
        rescue
          e ->
            Logger.error(Exception.format(:error, e, __STACKTRACE__))
            %{options: []}
        end
      else
        %{options: []}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:cocktail_poll, cocktail_poll)
     |> assign(:cocktail_options, cocktail_options)
     |> assign(:user_votes, user_votes)
     |> assign(:temp_votes, temp_votes)
     |> assign(:poll_stats, poll_stats)
     |> assign(:showing_add_form, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:adding_cocktail, false)}
  end

  @impl true
  def handle_event("show_add_form", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :showing_add_form, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_add_form, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("search_cocktails", %{"value" => query}, socket) do
    if socket.assigns.current_user do
      if String.length(query) >= 2 do
        # Use the centralized RichDataManager system (same as backend)
        search_options = %{
          providers: [:cocktaildb],
          limit: 5,
          content_type: :cocktail
        }

        case RichDataManager.search(query, search_options) do
          {:ok, results_by_provider} ->
            # Extract cocktail results from CocktailDB provider
            cocktail_results =
              case Map.get(results_by_provider, :cocktaildb) do
                {:ok, results} when is_list(results) -> results
                {:ok, result} -> [result]
                _ -> []
              end

            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, cocktail_results)}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, [])}
        end
      else
        {:noreply,
         socket
         |> assign(:search_query, query)
         |> assign(:search_results, [])}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_cocktail", %{"cocktail" => cocktail_id}, socket) do
    require Logger
    Logger.debug("add_cocktail handler called with cocktail_id=#{inspect(cocktail_id)}")
    Logger.debug("  adding_cocktail=#{inspect(socket.assigns.adding_cocktail)}")
    Logger.debug("  search_results count=#{length(socket.assigns.search_results)}")

    if socket.assigns.adding_cocktail do
      Logger.debug("  EARLY EXIT: adding_cocktail is already true")
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      # Check if user is authenticated
      if is_nil(user) do
        Logger.debug("  EARLY EXIT: user is nil")
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to add cocktails.")
         |> assign(:adding_cocktail, false)}
      else
        # Find the cocktail in search results
        Logger.debug("  Searching for cocktail_id=#{inspect(cocktail_id)} in #{length(socket.assigns.search_results)} results")
        Logger.debug("  Search results IDs: #{inspect(Enum.map(socket.assigns.search_results, & &1.id))}")

        cocktail_data =
          socket.assigns.search_results
          |> Enum.find(fn cocktail ->
            # Compare as strings to handle type mismatches consistently
            to_string(cocktail.id) == to_string(cocktail_id)
          end)

        Logger.debug("  cocktail_data found: #{inspect(cocktail_data != nil)}")

        if cocktail_data do
          # Set adding_cocktail to true to prevent multiple requests
          socket = assign(socket, :adding_cocktail, true)

          # Use the centralized RichDataManager to get detailed cocktail data (same as backend)
          case RichDataManager.get_cached_details(:cocktaildb, cocktail_data.id, :cocktail) do
            {:ok, rich_cocktail_data} ->
              Logger.debug("  rich_cocktail_data keys: #{inspect(Map.keys(rich_cocktail_data))}")
              Logger.debug("  rich_cocktail_data name field: #{inspect(Map.get(rich_cocktail_data, :name))}")
              Logger.debug("  rich_cocktail_data instructions type: #{inspect(Map.get(rich_cocktail_data, :instructions))}")

              # Use the shared CocktailDataService to prepare cocktail data consistently
              option_params =
                CocktailDataService.prepare_cocktail_option_data(
                  cocktail_data.id,
                  rich_cocktail_data
                )
                |> Map.merge(%{
                  "poll_id" => socket.assigns.cocktail_poll.id,
                  "suggested_by_id" => user.id
                })

              case Events.create_poll_option(option_params) do
                {:ok, _option} ->
                  # Reload cocktail options to show the new cocktail immediately
                  updated_cocktail_options =
                    Events.list_poll_options(socket.assigns.cocktail_poll)
                    |> Repo.preload(:suggested_by)

                  # Notify the parent LiveView to reload polls for all users
                  send(self(), {:poll_stats_updated, socket.assigns.cocktail_poll.id, %{}})

                  {:noreply,
                   socket
                   |> put_flash(:info, "Cocktail added successfully!")
                   |> assign(:adding_cocktail, false)
                   |> assign(:showing_add_form, false)
                   |> assign(:search_query, "")
                   |> assign(:search_results, [])
                   |> assign(:cocktail_options, updated_cocktail_options)}

                {:error, changeset} ->
                  require Logger
                  Logger.error("Failed to create poll option: #{inspect(changeset)}")

                  {:noreply,
                   socket
                   |> put_flash(:error, "Failed to add cocktail. Please try again.")
                   |> assign(:adding_cocktail, false)}
              end

            {:error, reason} ->
              require Logger
              Logger.error("Failed to fetch rich cocktail data: #{inspect(reason)}")

              {:noreply,
               socket
               |> put_flash(:error, "Failed to fetch cocktail details. Please try again.")
               |> assign(:adding_cocktail, false)}
          end
        else
          Logger.debug("  EARLY EXIT: cocktail_data is nil - not found in search results")
          {:noreply,
           socket
           |> put_flash(:error, "Cocktail not found in search results.")
           |> assign(:adding_cocktail, false)}
        end
      end
    end
  end

  @impl true
  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    with {option_id_int, _} <- Integer.parse(option_id),
         option when not is_nil(option) <-
           Enum.find(socket.assigns.cocktail_options, &(&1.id == option_id_int)),
         user when not is_nil(user) <- socket.assigns.current_user,
         true <- Events.can_delete_option_based_on_poll_settings?(option, user) do
      case Events.delete_poll_option(option) do
        {:ok, _} ->
          # Reload cocktail options with proper preloading
          updated_cocktail_options =
            Events.list_poll_options(socket.assigns.cocktail_poll)
            |> Repo.preload(:suggested_by)

          # Notify parent to reload
          send(self(), {:poll_stats_updated, socket.assigns.cocktail_poll.id, %{}})

          {:noreply,
           socket
           |> put_flash(:info, "Cocktail removed successfully.")
           |> assign(:cocktail_options, updated_cocktail_options)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove cocktail.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "You are not authorized to remove this cocktail.")}
    end
  end

  # Helper function to get cocktail poll for an event
  defp get_cocktail_poll(event) do
    Events.list_polls(event)
    |> Enum.find(&(&1.poll_type == "cocktail"))
  end

  # Helper to get image URL from cocktail option
  defp get_cocktail_image_url(option) do
    cond do
      is_map(option.external_data) and Map.has_key?(option.external_data, "image_url") ->
        option.external_data["image_url"]

      is_map(option.external_data) and Map.has_key?(option.external_data, "thumbnail") ->
        option.external_data["thumbnail"]

      is_map(option.external_data) and Map.has_key?(option.external_data, :image_url) ->
        option.external_data[:image_url]

      is_map(option.external_data) and Map.has_key?(option.external_data, :thumbnail) ->
        option.external_data[:thumbnail]

      true ->
        option.image_url
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-cocktail-poll">
      <%= if @cocktail_poll do %>
        <div class="mb-6">
          <div class="mb-4">
            <div class="flex items-center justify-between">
              <div>
                <div class="flex items-center">
                  <h3 class="text-lg font-semibold text-gray-900">
                    <%= poll_emoji("cocktail") %> Cocktail Suggestions
                  </h3>
                  <.voter_count poll_stats={@poll_stats} poll_phase={@cocktail_poll.phase} class="ml-4" />
                </div>
                <p class="text-sm text-gray-600 mt-1">
                  <%= PollPhaseUtils.get_phase_description(@cocktail_poll.phase, "cocktail") %>
                </p>
              </div>
            </div>
          </div>
          <!-- Voting Interface for cocktail polls -->
          <%= if PollPhaseUtils.voting_allowed?(@cocktail_poll.phase) do %>
            <div class="mb-6">
              <.live_component
                module={EventasaurusWeb.VotingInterfaceComponent}
                id={"voting-interface-cocktail-#{@cocktail_poll.id}"}
                poll={@cocktail_poll}
                user={@current_user}
                user_votes={@user_votes}
                loading={false}
                temp_votes={@temp_votes}
                anonymous_mode={is_nil(@current_user)}
                mode={:content}
              />
            </div>
          <% else %>
            <!-- List Building Phase - Show Cocktail Options Without Voting -->
            <%= if length(@cocktail_options) > 0 do %>
              <div class="space-y-3">
                <%= for option <- @cocktail_options do %>
                  <div class="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                    <div class="flex">
                      <% image_url = get_cocktail_image_url(option) %>
                      <%= if image_url do %>
                        <img
                          src={image_url}
                          alt={"#{option.title} image"}
                          class="w-16 h-24 object-cover rounded-lg mr-4 flex-shrink-0"
                          loading="lazy"
                        />
                      <% else %>
                        <div class="w-16 h-24 bg-gray-200 rounded-lg mr-4 flex-shrink-0 flex items-center justify-center">
                          <span class="text-2xl">🍹</span>
                        </div>
                      <% end %>

                      <div class="flex-1 min-w-0">
                        <h4 class="font-medium text-gray-900 mb-1"><%= option.title %></h4>

                        <%= if option.description do %>
                          <p class="text-sm text-gray-600 mb-2 line-clamp-2">
                            <%= option.description %>
                          </p>
                        <% end %>
                        <!-- Show who suggested this cocktail -->
                        <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@cocktail_poll) and option.suggested_by do %>
                          <div class="flex items-center justify-between">
                            <p class="text-xs text-gray-500">
                              Suggested by <%= display_suggester_name(option.suggested_by) %>
                            </p>
                            <!-- Delete button for user's own suggestions -->
                            <%= if @current_user && Events.can_delete_option_based_on_poll_settings?(
                              option,
                              @current_user
                            ) do %>
                              <div class="flex items-center space-x-2">
                                <button
                                  type="button"
                                  phx-click="delete_option"
                                  phx-value-option-id={option.id}
                                  phx-target={@myself}
                                  data-confirm="Are you sure you want to remove this option? This action cannot be undone."
                                  class="text-red-600 hover:text-red-900 text-xs font-medium"
                                >
                                  Remove
                                </button>
                                <% time_remaining = get_deletion_time_remaining(option.inserted_at) %>
                                <%= if time_remaining > 0 do %>
                                  <span class="text-xs text-gray-500">
                                    (<%= format_deletion_time_remaining(time_remaining) %> left)
                                  </span>
                                <% end %>
                              </div>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-8 text-gray-500">
                <span class="text-6xl">🍹</span>
                <% {title, subtitle} = PollPhaseUtils.get_empty_state_message("cocktail") %>
                <p class="font-medium mt-4"><%= title %></p>
                <p class="text-sm"><%= subtitle %></p>
              </div>
            <% end %>
          <% end %>
          <!-- Add Cocktail Button/Form -->
          <%= if PollPhaseUtils.suggestions_allowed?(@cocktail_poll.phase) do %>
            <%= if @current_user do %>
              <%= if @showing_add_form do %>
                <!-- Inline Add Cocktail Form -->
                <div class="mt-4 p-4 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50">
                  <div class="mb-4">
                    <h4 class="text-md font-medium text-gray-900 mb-2">Add Cocktail Suggestion</h4>
                    <p class="text-sm text-gray-600">Search for a cocktail to add to the list</p>
                  </div>

                  <div class="mb-4">
                    <input
                      type="text"
                      placeholder="Search for a cocktail..."
                      value={@search_query}
                      phx-keyup="search_cocktails"
                      phx-target={@myself}
                      phx-debounce="300"
                      class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    />
                  </div>

                  <%= if length(@search_results) > 0 do %>
                    <div class="space-y-3 mb-4 max-h-64 overflow-y-auto">
                      <%= for cocktail <- @search_results do %>
                        <div
                          class="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-blue-50 hover:border-blue-300 cursor-pointer transition-all duration-200 bg-white"
                          phx-click="add_cocktail"
                          phx-value-cocktail={cocktail.id}
                          phx-target={@myself}
                        >
                          <%= if cocktail.image_url do %>
                            <img
                              src={cocktail.image_url}
                              alt={cocktail.title}
                              class="w-12 h-16 object-cover rounded mr-4 flex-shrink-0"
                            />
                          <% else %>
                            <div class="w-12 h-16 bg-gray-200 rounded mr-4 flex-shrink-0 flex items-center justify-center">
                              <span class="text-2xl">🍹</span>
                            </div>
                          <% end %>

                          <div class="flex-1 min-w-0">
                            <h4 class="font-medium text-gray-900 truncate"><%= cocktail.title %></h4>
                            <%= if cocktail.metadata do %>
                              <p class="text-sm text-gray-600">
                                <%= cocktail.metadata[:category] || cocktail.metadata["category"] %> • <%= cocktail.metadata[:alcoholic] ||
                                  cocktail.metadata["alcoholic"] %>
                              </p>
                            <% end %>
                            <%= if cocktail.description && String.length(cocktail.description) > 0 do %>
                              <p class="text-xs text-gray-500 mt-1 line-clamp-2">
                                <%= cocktail.description %>
                              </p>
                            <% end %>
                          </div>

                          <%= if @adding_cocktail do %>
                            <div class="ml-4 flex-shrink-0">
                              <svg
                                class="animate-spin h-5 w-5 text-blue-500"
                                fill="none"
                                viewBox="0 0 24 24"
                              >
                                <circle
                                  class="opacity-25"
                                  cx="12"
                                  cy="12"
                                  r="10"
                                  stroke="currentColor"
                                  stroke-width="4"
                                >
                                </circle>
                                <path
                                  class="opacity-75"
                                  fill="currentColor"
                                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                                >
                                </path>
                              </svg>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="flex justify-end space-x-3">
                    <button
                      phx-click="hide_add_form"
                      phx-target={@myself}
                      class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
              <% else %>
                <!-- Add Cocktail Button -->
                <div class="mt-4">
                  <button
                    phx-click="show_add_form"
                    phx-target={@myself}
                    class="w-full flex items-center justify-center px-4 py-3 border border-gray-300 border-dashed rounded-lg text-sm font-medium text-gray-600 hover:text-gray-900 hover:border-gray-400 transition-colors"
                  >
                    <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 4v16m8-8H4"
                      />
                    </svg>
                    <%= PollPhaseUtils.get_add_button_text("cocktail") %>
                  </button>
                </div>
              <% end %>
            <% else %>
              <!-- Show login prompt for anonymous users -->
              <div class="mt-4">
                <p class="text-sm text-gray-500 text-center py-4 bg-gray-50 rounded-lg">
                  Please <.link href="/login" class="text-blue-600 hover:underline">log in</.link>
                  to suggest options.
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No cocktail poll found for this event.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions for deletion time display
  defp get_deletion_time_remaining(inserted_at) when is_nil(inserted_at), do: 0

  defp get_deletion_time_remaining(inserted_at) do
    elapsed_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second)
    # 300 seconds = 5 minutes
    max(0, 300 - elapsed_seconds)
  end

  defp format_deletion_time_remaining(seconds) when seconds <= 0, do: ""

  defp format_deletion_time_remaining(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 -> "#{minutes}:#{String.pad_leading(to_string(remaining_seconds), 2, "0")}"
      true -> "#{remaining_seconds}s"
    end
  end

  # Helper function to display suggester name with proper blank value handling
  defp display_suggester_name(suggested_by) when is_nil(suggested_by), do: "Anonymous"
  defp display_suggester_name(%Ecto.Association.NotLoaded{}), do: "Anonymous"

  defp display_suggester_name(suggested_by) do
    name = Map.get(suggested_by, :name)
    username = Map.get(suggested_by, :username)
    email = Map.get(suggested_by, :email)

    cond do
      is_binary(name) and String.trim(name) != "" -> String.trim(name)
      is_binary(username) and String.trim(username) != "" -> String.trim(username)
      is_binary(email) and String.trim(email) != "" -> String.trim(email)
      true -> "Anonymous"
    end
  end
end
