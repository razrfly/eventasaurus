defmodule EventasaurusWeb.MoviesIndexLive do
  @moduledoc """
  Movies index page showing all movies currently in cinemas.

  Phase 1: Now Showing grid with hero section
  Phase 2: Coming Soon from TMDB (future)
  Phase 3: Search and filtering (future)
  Phase 4: Sitemap integration (future)
  """

  use EventasaurusWeb, :live_view
  use Gettext, backend: EventasaurusWeb.Gettext

  alias EventasaurusDiscovery.Movies.MovieStats
  alias EventasaurusWeb.Components.MovieCards
  alias EventasaurusWeb.JsonLd.MoviesIndexSchema
  alias EventasaurusWeb.Helpers.SEOHelpers

  @impl true
  def mount(_params, _session, socket) do
    # Load data in parallel for performance
    tasks = [
      Task.async(fn -> MovieStats.list_now_showing_movies(limit: 24) end),
      Task.async(fn -> MovieStats.list_cities_with_movies(limit: 8) end),
      Task.async(fn -> MovieStats.count_now_showing_movies() end),
      Task.async(fn -> MovieStats.count_upcoming_screenings() end),
      Task.async(fn ->
        case EventasaurusWeb.Services.TmdbService.get_upcoming_movies("PL", 1) do
          {:ok, movies} -> Enum.take(movies, 10)
          _ -> []
        end
      end)
    ]

    [now_showing, cities_with_movies, movie_count, screening_count, upcoming_movies] =
      Task.await_many(tasks)

    # Generate JSON-LD structured data for movie carousel
    json_ld = MoviesIndexSchema.generate(now_showing)

    socket =
      socket
      |> assign(:page_title, gettext("Movies Now Showing"))
      |> assign(:all_movies, now_showing)
      |> assign(:original_now_showing, now_showing)
      |> assign(:now_showing, now_showing)
      |> assign(:cities_with_movies, cities_with_movies)
      |> assign(:movie_count, movie_count)
      |> assign(:screening_count, screening_count)
      |> assign(:upcoming_movies, upcoming_movies)
      |> assign(:search_query, "")
      |> assign(:sort_by, "showing")
      |> SEOHelpers.assign_meta_tags(
        title: "Movies Now Showing | Wombie",
        description:
          "Discover #{movie_count} movies now showing in cinemas. " <>
            "#{screening_count} screenings available across #{length(cities_with_movies)} cities.",
        type: "website",
        canonical_path: "/movies",
        json_ld: json_ld
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    sort_by = params["sort"] || "showing"
    now_showing = apply_sort(socket.assigns.all_movies, sort_by)
    {:noreply, assign(socket, sort_by: sort_by, now_showing: now_showing)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    movies = MovieStats.list_now_showing_movies(limit: 24, search: query)
    sorted = apply_sort(movies, socket.assigns.sort_by)
    {:noreply, assign(socket, all_movies: movies, original_now_showing: movies, now_showing: sorted, search_query: query)}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_by}, socket) do
    {:noreply, push_patch(socket, to: ~p"/movies?#{[sort: sort_by]}")}
  end

  defp apply_sort(movies, "rt_score") do
    Enum.sort_by(
      movies,
      fn %{movie: m} ->
        get_in(m.cinegraph_data || %{}, ["ratings", "rottenTomatoes"]) || -1
      end,
      :desc
    )
  end

  defp apply_sort(movies, "imdb") do
    Enum.sort_by(
      movies,
      fn %{movie: m} ->
        get_in(m.cinegraph_data || %{}, ["ratings", "imdb"]) || -1
      end,
      :desc
    )
  end

  defp apply_sort(movies, "awards") do
    Enum.sort_by(
      movies,
      fn %{movie: m} ->
        get_in(m.cinegraph_data || %{}, ["awards", "oscarWins"]) || 0
      end,
      :desc
    )
  end

  defp apply_sort(movies, _showing), do: movies

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen pb-20">
      <!-- Hero Section -->
      <div class="relative bg-gray-900 text-white overflow-hidden">
        <div class="absolute inset-0">
          <img
            src="https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?ixlib=rb-4.0.3&auto=format&fit=crop&w=1600&q=80"
            alt="Cinema hero background"
            class="w-full h-full object-cover opacity-40"
          />
        </div>
      <div class="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16 md:py-24 text-center">
        <h1 class="text-3xl md:text-5xl font-extrabold tracking-tight mb-4">
          <%= gettext("Movies Now Showing") %>
        </h1>
        <p class="text-lg md:text-xl text-gray-300 max-w-2xl mx-auto mb-8">
          <%= gettext("Discover what's playing in cinemas near you") %>
        </p>

        <!-- Search Bar -->
        <div class="max-w-xl mx-auto mb-10">
          <form phx-change="search" phx-submit="search" class="relative">
            <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Heroicons.magnifying_glass class="h-5 w-5 text-gray-400" />
            </div>
            <input
              type="text"
              name="q"
              value={@search_query}
              placeholder={gettext("Search movies by title...")}
              class="block w-full pl-10 pr-3 py-3 border border-transparent rounded-lg leading-5 bg-white text-gray-900 placeholder-gray-500 focus:outline-none focus:bg-white focus:ring-0 focus:border-white sm:text-sm shadow-xl"
              autocomplete="off"
              phx-debounce="300"
            />
          </form>
        </div>
          <!-- Stats -->
          <div class="flex justify-center gap-8 text-sm md:text-base">
            <div class="text-center">
              <div class="text-2xl md:text-3xl font-bold text-white"><%= @movie_count %></div>
              <div class="text-gray-400"><%= ngettext("Movie", "Movies", @movie_count) %></div>
            </div>
            <div class="text-center">
              <div class="text-2xl md:text-3xl font-bold text-white"><%= @screening_count %></div>
              <div class="text-gray-400"><%= ngettext("Screening", "Screenings", @screening_count) %></div>
            </div>
            <div class="text-center">
              <div class="text-2xl md:text-3xl font-bold text-white"><%= length(@cities_with_movies) %></div>
              <div class="text-gray-400"><%= ngettext("City", "Cities", length(@cities_with_movies)) %></div>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 space-y-12 py-10">
        <!-- Section 1: Now Showing -->
        <section>
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold text-gray-900">
              <Heroicons.film class="w-7 h-7 inline-block mr-2 text-blue-600" />
              <%= gettext("Now Showing") %>
            </h2>
            <div class="flex items-center gap-2 text-sm">
              <span class="text-gray-500 hidden sm:inline"><%= gettext("Sort:") %></span>
              <button
                phx-click="sort"
                phx-value-by="showing"
                class={["px-3 py-1.5 rounded-full font-medium transition",
                  if(@sort_by == "showing", do: "bg-blue-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")]}
              >
                <%= gettext("Showing") %>
              </button>
              <button
                phx-click="sort"
                phx-value-by="rt_score"
                class={["px-3 py-1.5 rounded-full font-medium transition",
                  if(@sort_by == "rt_score", do: "bg-red-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")]}
              >
                🍅 <%= gettext("RT") %>
              </button>
              <button
                phx-click="sort"
                phx-value-by="imdb"
                class={["px-3 py-1.5 rounded-full font-medium transition",
                  if(@sort_by == "imdb", do: "bg-yellow-500 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")]}
              >
                <%= gettext("IMDb") %>
              </button>
              <button
                phx-click="sort"
                phx-value-by="awards"
                class={["px-3 py-1.5 rounded-full font-medium transition",
                  if(@sort_by == "awards", do: "bg-amber-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")]}
              >
                🏆 <%= gettext("Awards") %>
              </button>
            </div>
          </div>

          <%= if @now_showing == [] do %>
            <div class="text-center py-12 bg-white rounded-lg shadow-sm">
              <Heroicons.film class="w-16 h-16 text-gray-300 mx-auto mb-4" />
              <h3 class="text-lg font-medium text-gray-900 mb-2">
                <%= gettext("No movies currently showing") %>
              </h3>
              <p class="text-gray-500">
                <%= gettext("Check back soon for upcoming screenings!") %>
              </p>
            </div>
          <% else %>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
              <%= for %{movie: movie, city_count: city_count, screening_count: screening_count, next_screening: next_screening} <- @now_showing do %>
                <MovieCards.movie_card
                  movie={movie}
                  city_count={city_count}
                  screening_count={screening_count}
                  next_screening={next_screening}
                />
              <% end %>
            </div>
          <% end %>
        </section>

    <!-- Section: Coming Soon -->
    <%= if @upcoming_movies != [] do %>
      <section>
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-2xl font-bold text-gray-900">
            <Heroicons.calendar class="w-7 h-7 inline-block mr-2 text-blue-600" />
            <%= gettext("Coming Soon to Cinemas") %>
          </h2>
        </div>

        <div class="relative">
          <div class="flex overflow-x-auto pb-6 gap-4 snap-x snap-mandatory hide-scrollbar">
            <%= for movie <- @upcoming_movies do %>
              <MovieCards.coming_soon_card movie={movie} />
            <% end %>
          </div>
          <!-- Fade effect on the right -->
          <div class="absolute top-0 bottom-6 right-0 w-12 bg-gradient-to-l from-white to-transparent pointer-events-none"></div>
        </div>
      </section>
    <% end %>

        <!-- Section 2: Browse by City -->
        <%= if @cities_with_movies != [] do %>
          <section>
            <div class="flex items-center justify-between mb-6">
              <h2 class="text-2xl font-bold text-gray-900">
                <Heroicons.building_office_2 class="w-7 h-7 inline-block mr-2 text-blue-600" />
                <%= gettext("Browse by City") %>
              </h2>
              <.link navigate={~p"/cities"} class="text-blue-600 hover:text-blue-800 font-medium text-sm">
                <%= gettext("View all cities") %> &rarr;
              </.link>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              <%= for %{city: city, movie_count: movie_count, screening_count: screening_count} <- @cities_with_movies do %>
                <MovieCards.city_movie_card
                  city={city}
                  movie_count={movie_count}
                  screening_count={screening_count}
                />
              <% end %>
            </div>
          </section>
        <% end %>

        <!-- TMDB Attribution -->
        <section class="text-center">
          <p class="text-xs text-gray-500">
            <%= gettext("Movie data provided by") %>
            <a
              href="https://www.themoviedb.org/"
              target="_blank"
              rel="noopener noreferrer"
              class="text-blue-600 hover:text-blue-800 underline"
            >
              The Movie Database (TMDB)
            </a>.
            <%= gettext("This product uses the TMDB API but is not endorsed or certified by TMDB.") %>
          </p>
        </section>
      </div>
    </div>
    """
  end
end
