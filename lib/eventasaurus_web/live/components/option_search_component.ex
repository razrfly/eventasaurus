defmodule EventasaurusWeb.OptionSearchComponent do
  @moduledoc """
  Search component for poll options with API integration.
  
  Handles search functionality for different poll types including:
  - Movie search via TMDB API
  - Music track search via Spotify API  
  - Places search via Google Places API
  - Real-time search results display
  - Result selection and data preparation
  
  ## Attributes:
  - poll: Poll struct (required)
  - search_query: Current search query string
  - search_results: List of search results
  - search_loading: Loading state for search operations
  - changeset: Form changeset for updating with selected data
  
  ## Events:
  - search_movies: Triggered when searching for movies
  - search_music_tracks: Triggered when searching for music tracks
  - select_movie: When a movie is selected from results
  - music_track_selected: When a music track is selected from results
  """

  use EventasaurusWeb, :live_component
  require Logger
  alias EventasaurusWeb.Services.{MovieDataService, RichDataManager}
  alias EventasaurusWeb.OptionSuggestionHelpers

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:search_query, fn -> "" end)
     |> assign_new(:search_results, fn -> [] end)
     |> assign_new(:search_loading, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="search-component">
      <!-- Search Input Field -->
      <div class="relative">
        <%= if should_use_api_search?(@poll.poll_type) do %>
          <%= if @poll.poll_type == "movie" do %>
            <input
              type="text"
              name="poll_option[title]"
              id="option_title_search"
              value={@search_query}
              placeholder={OptionSuggestionHelpers.option_title_placeholder(@poll)}
              phx-change="search_movies"
              phx-target={@myself}
              phx-debounce="300"
              autocomplete="off"
              class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
            />
          <% else %>
            <%= if @poll.poll_type == "music_track" do %>
              <input
                type="text"
                name="poll_option[title]"
                id="option_title_search"
                value={@search_query}
                placeholder={OptionSuggestionHelpers.option_title_placeholder(@poll)}
                phx-change="search_music_tracks"
                phx-target={@myself}
                phx-debounce="300"
                autocomplete="off"
                class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
              />
            <% else %>
              <%= if @poll.poll_type == "places" do %>
                <input
                  type="text"
                  name="poll_option[title]"
                  id="option_title_search"
                  value={@search_query}
                  placeholder={OptionSuggestionHelpers.option_title_placeholder(@poll)}
                  phx-debounce="300"
                  phx-hook="PlacesSuggestionSearch"
                  data-location-scope={OptionSuggestionHelpers.get_location_scope(@poll)}
                  data-search-location={OptionSuggestionHelpers.get_search_location_json(@poll)}
                  autocomplete="off"
                  class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                />
              <% end %>
            <% end %>
          <% end %>

          <!-- Loading indicators -->
          <%= if @search_loading do %>
            <div class="absolute right-3 top-3 flex items-center">
              <svg class="animate-spin h-4 w-4 text-indigo-600" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Search Results Dropdowns -->
      <%= if should_use_api_search?(@poll.poll_type) and length(@search_results) > 0 do %>
        <%= case @poll.poll_type do %>
          <% "movie" -> %>
            <%= render_movie_results(assigns) %>
          <% "music_track" -> %>
            <%= render_music_results(assigns) %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Movie search results dropdown
  defp render_movie_results(assigns) do
    ~H"""
    <div class="absolute z-50 mt-1 w-full bg-white border border-gray-300 rounded-md shadow-lg max-h-60 overflow-y-auto">
      <%= for movie <- @search_results do %>
        <div class="flex items-center p-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 last:border-b-0"
             phx-click="select_movie"
             phx-value-movie-id={movie.id}
             phx-target={@myself}>
          <% image_url = get_movie_poster_url(movie) %>
          <%= if image_url do %>
            <img src={image_url} alt={movie.title} class="w-10 h-14 object-cover rounded mr-3 flex-shrink-0" />
          <% else %>
            <div class="w-10 h-14 bg-gray-200 rounded mr-3 flex-shrink-0 flex items-center justify-center">
              <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
              </svg>
            </div>
          <% end %>
          <div class="flex-1 min-w-0">
            <h4 class="font-medium text-gray-900 truncate"><%= movie.title %></h4>
            <%= if movie.metadata && movie.metadata["release_date"] do %>
              <p class="text-sm text-gray-600"><%= String.slice(movie.metadata["release_date"], 0, 4) %></p>
            <% end %>
            <%= if is_binary(movie.description) && String.length(movie.description) > 0 do %>
              <p class="text-xs text-gray-500 mt-1 line-clamp-2"><%= movie.description %></p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Music search results dropdown
  defp render_music_results(assigns) do
    ~H"""
    <div class="absolute z-50 mt-1 w-full bg-white border border-gray-300 rounded-md shadow-lg max-h-60 overflow-y-auto">
      <%= for track <- @search_results do %>
        <div class="flex items-center p-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 last:border-b-0"
             phx-click="music_track_selected"
             phx-value-track={Jason.encode!(track)}
             phx-target={@myself}>
          <% image_url = track.image_url %>
          <%= if image_url do %>
            <img src={image_url} alt={track.title} class="w-10 h-10 object-cover rounded mr-3 flex-shrink-0" />
          <% else %>
            <div class="w-10 h-10 bg-gray-200 rounded mr-3 flex-shrink-0 flex items-center justify-center">
              <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
              </svg>
            </div>
          <% end %>
          <div class="flex-1 min-w-0">
            <h4 class="font-medium text-gray-900 truncate"><%= track.title %></h4>
            <%= if track.artist do %>
              <p class="text-sm text-gray-600 truncate"><%= track.artist %></p>
            <% end %>
            <%= if track.album do %>
              <p class="text-xs text-gray-500 truncate"><%= track.album %></p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("search_movies", %{"poll_option" => %{"title" => query}} = _params, socket) do
    # Only search if this is a movie poll
    if socket.assigns.poll.poll_type == "movie" do
      if String.length(String.trim(query)) >= 2 do
        # Set loading state
        socket = assign(socket, :search_loading, true)

        # Use the centralized RichDataManager system
        search_options = %{
          providers: [:tmdb],
          limit: 5,
          content_type: :movie
        }

        case RichDataManager.search(query, search_options) do
          {:ok, results_by_provider} ->
            # Extract movie results from TMDB provider
            movie_results = case Map.get(results_by_provider, :tmdb) do
              {:ok, results} when is_list(results) -> results
              {:ok, result} -> [result]
              _ -> []
            end

            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, movie_results)
             |> assign(:search_loading, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, [])
             |> assign(:search_loading, false)}
        end
      else
        {:noreply,
         socket
         |> assign(:search_query, query)
         |> assign(:search_results, [])
         |> assign(:search_loading, false)}
      end
    else
      {:noreply, socket}
    end
  end

  # Fallback handler for search_movies in case parameters don't match expected format
  @impl true
  def handle_event("search_movies", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_music_tracks", %{"poll_option" => %{"title" => query}} = _params, socket) do
    # Only search if this is a music_track poll
    if socket.assigns.poll.poll_type == "music_track" do
      if String.length(String.trim(query)) >= 2 do
        # Set loading state
        socket = assign(socket, :search_loading, true)
        
        # Use the centralized RichDataManager system
        search_options = %{
          providers: [:spotify],
          limit: 5,
          content_type: :track
        }

        case RichDataManager.search(query, search_options) do
          {:ok, provider_results} ->
            Logger.info("OptionSearchComponent received provider results: #{inspect(provider_results)}")
            
            # Extract tracks from Spotify provider results
            tracks = case Map.get(provider_results, :spotify) do
              {:ok, results} when is_list(results) -> results
              {:ok, result} -> [result]
              {:error, reason} -> 
                Logger.warning("Spotify search failed: #{inspect(reason)}")
                []
              nil -> 
                Logger.warning("No Spotify results found")
                []
            end
            
            search_results = Enum.map(tracks, fn track ->
              Logger.debug("Processing track: #{inspect(track)}")
              %{
                id: track.id,
                title: track.title || track.name,
                artist: track.artist,
                album: track.album,
                image_url: track.image_url,
                description: "#{track.artist} - #{track.album}"
              }
            end)

            {:noreply,
             socket
             |> assign(:search_results, search_results)
             |> assign(:search_query, query)
             |> assign(:search_loading, false)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:search_results, [])
             |> assign(:search_query, query)
             |> assign(:search_loading, false)}
        end
      else
        {:noreply,
         socket
         |> assign(:search_results, [])
         |> assign(:search_query, query)
         |> assign(:search_loading, false)}
      end
    else
      {:noreply, socket}
    end
  end

  # Fallback handler for search_music_tracks in case parameters don't match expected format
  @impl true
  def handle_event("search_music_tracks", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_movie", %{"movie-id" => movie_id}, socket) do
    # Find the selected movie in search results
    movie_data = socket.assigns.search_results
    |> Enum.find(fn movie ->
      # Handle both string and integer movie_id formats
      case Integer.parse(movie_id) do
        {id, _} -> movie.id == id
        :error -> to_string(movie.id) == movie_id
      end
    end)

    if movie_data do
      # Use the centralized RichDataManager to get detailed movie data
      case RichDataManager.get_cached_details(:tmdb, movie_data.id, :movie) do
        {:ok, rich_movie_data} ->
          # Prepare rich movie data for parent component
          prepared_data = MovieDataService.prepare_movie_option_data(
            movie_data.id,
            rich_movie_data
          )

          # Send selection to parent component
          send(self(), {:movie_selected, prepared_data})
          
          {:noreply,
           socket
           |> assign(:search_results, [])
           |> assign(:search_query, "")}

        {:error, _reason} ->
          # Fallback to basic movie data if rich data fetch fails
          fallback_data = %{
            "title" => movie_data.title,
            "description" => movie_data.description || "",
            "external_id" => to_string(movie_data.id)
          }

          send(self(), {:movie_selected, fallback_data})
          
          {:noreply,
           socket
           |> assign(:search_results, [])
           |> assign(:search_query, "")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("music_track_selected", %{"track" => track_data}, socket) do
    if socket.assigns.poll.poll_type == "music_track" do
      # Parse JSON string if needed
      parsed_track = case Jason.decode(track_data) do
        {:ok, data} -> data
        {:error, _} -> track_data  # Already a map
      end
      
      # Prepare music track data for the option
      prepared_data = %{
        "title" => parsed_track["title"],
        "description" => parsed_track["description"] || "",
        "external_id" => parsed_track["id"],
        "image_url" => parsed_track["image_url"],
        "external_data" => parsed_track
      }

      # Send selection to parent component
      send(self(), {:music_track_selected, prepared_data})

      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:search_query, "")}
    else
      {:noreply, socket}
    end
  end

  # Clear search results and query
  def clear_search(socket) do
    socket
    |> assign(:search_results, [])
    |> assign(:search_query, "")
    |> assign(:search_loading, false)
  end

  # Helper functions

  defp should_use_api_search?(poll_type) do
    OptionSuggestionHelpers.should_use_api_search?(poll_type)
  end

  defp get_movie_poster_url(movie) do
    OptionSuggestionHelpers.get_movie_poster_url(movie)
  end
end