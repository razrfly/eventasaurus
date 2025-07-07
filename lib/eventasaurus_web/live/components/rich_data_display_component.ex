defmodule EventasaurusWeb.Live.Components.RichDataDisplayComponent do
  @moduledoc """
  A reusable LiveView component for displaying rich external data (movies, TV shows).

  Inspired by TMDB's movie page design, this component provides a comprehensive
  view of movie/TV data including hero section, cast, crew, media, and details.

  ## Attributes:
  - rich_data: Map containing the rich external data from TMDB
  - show_sections: List of sections to display (default: all)
  - compact: Boolean for compact display mode (default: false)
  - loading: Boolean for loading state (default: false)
  - error: String for error message (default: nil)
  - class: Additional CSS classes

  ## Usage:
      <.live_component
        module={EventasaurusWeb.RichDataDisplayComponent}
        id="rich-data-display"
        rich_data={@event.rich_external_data["tmdb"]}
        show_sections={[:hero, :overview, :cast, :media, :details]}
        compact={false}
      />
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

  @default_sections [:hero, :overview, :cast, :media, :details]

  @impl true
  def update(assigns, socket) do
    require Logger
    Logger.debug("RichDataDisplayComponent update called with rich_data: #{inspect(assigns[:rich_data])}")

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show_sections, fn -> @default_sections end)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:error, fn -> nil end)
     |> assign_new(:class, fn -> "" end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["rich-data-display", @class]}>
      <%= if @loading do %>
        <div class="animate-pulse">
          <.loading_skeleton />
        </div>
      <% end %>

      <%= if @error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <div class="flex">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-red-400" />
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">Error Loading Data</h3>
              <p class="mt-1 text-sm text-red-700"><%= @error %></p>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @rich_data && !@loading && !@error do %>
        <div class="space-y-8">
          <%= if :hero in @show_sections do %>
            <.live_component
              module={EventasaurusWeb.Live.Components.MovieHeroComponent}
              id="movie-hero"
              rich_data={@rich_data}
              compact={@compact}
            />
          <% end %>

          <%= if :overview in @show_sections do %>
            <.live_component
              module={EventasaurusWeb.Live.Components.MovieOverviewComponent}
              id="movie-overview"
              rich_data={@rich_data}
              compact={@compact}
            />
          <% end %>

          <%= if :cast in @show_sections and @rich_data["cast"] do %>
            <.live_component
              module={EventasaurusWeb.Live.Components.MovieCastComponent}
              id="movie-cast"
              cast={@rich_data["cast"]}
              crew={@rich_data["crew"]}
              director={@rich_data["director"]}
              compact={@compact}
            />
          <% end %>

          <%= if :media in @show_sections and (@rich_data["videos"] || @rich_data["images"]) do %>
            <.live_component
              module={EventasaurusWeb.Live.Components.MovieMediaComponent}
              id="movie-media"
              videos={@rich_data["videos"] || []}
              images={@rich_data["images"] || %{}}
              compact={@compact}
            />
          <% end %>

          <%= if :details in @show_sections do %>
            <.live_component
              module={EventasaurusWeb.Live.Components.MovieDetailsComponent}
              id="movie-details"
              rich_data={@rich_data}
              compact={@compact}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Hero skeleton -->
      <div class="relative aspect-video bg-gray-200 rounded-lg overflow-hidden">
        <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent" />
        <div class="absolute bottom-6 left-6 right-6">
          <div class="h-8 bg-gray-300 rounded w-3/4 mb-4" />
          <div class="h-4 bg-gray-300 rounded w-1/2" />
        </div>
      </div>

      <!-- Content skeleton -->
      <div class="space-y-4">
        <div class="h-6 bg-gray-200 rounded w-1/4" />
        <div class="space-y-2">
          <div class="h-4 bg-gray-200 rounded w-full" />
          <div class="h-4 bg-gray-200 rounded w-3/4" />
        </div>
      </div>

      <!-- Cast skeleton -->
      <div class="space-y-4">
        <div class="h-6 bg-gray-200 rounded w-1/4" />
        <div class="flex space-x-4">
          <%= for _ <- 1..4 do %>
            <div class="flex-shrink-0">
              <div class="w-16 h-16 bg-gray-200 rounded-full" />
              <div class="h-3 bg-gray-200 rounded w-12 mt-2" />
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Public helper functions

    @doc """
  Generates a TMDB image URL for the given path and size.

  ## Examples

      iex> RichDataDisplayComponent.tmdb_image_url("/abc123.jpg", "w500")
      "https://image.tmdb.org/t/p/w500/abc123.jpg"
  """
  def tmdb_image_url(path, size \\ "w500")
  def tmdb_image_url(nil, _size), do: nil
  def tmdb_image_url("", _size), do: nil
  def tmdb_image_url(path, size) when is_binary(path) and is_binary(size) do
    "https://image.tmdb.org/t/p/#{size}#{path}"
  end
  def tmdb_image_url(_, _), do: nil

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns[:rich_data]

    socket
    |> assign(:has_backdrop, has_backdrop_image?(rich_data))
    |> assign(:has_poster, has_poster_image?(rich_data))
    |> assign(:media_type, get_media_type(rich_data))
  end

  defp has_backdrop_image?(nil), do: false
  defp has_backdrop_image?(rich_data) do
    backdrop_path = rich_data["backdrop_path"]
    is_binary(backdrop_path) && backdrop_path != ""
  end

  defp has_poster_image?(nil), do: false
  defp has_poster_image?(rich_data) do
    poster_path = rich_data["poster_path"]
    is_binary(poster_path) && poster_path != ""
  end

  defp get_media_type(nil), do: :unknown
  defp get_media_type(rich_data) do
    case rich_data["type"] do
      "movie" -> :movie
      "tv" -> :tv
      _ -> :unknown
    end
  end


end
