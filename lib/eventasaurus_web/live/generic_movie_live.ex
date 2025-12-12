defmodule EventasaurusWeb.GenericMovieLive do
  @moduledoc """
  Generic movie page for cross-site linking.

  Accessible via `/movies/:identifier` where identifier can be:
  - TMDB ID only: `/movies/157336`
  - TMDB ID with slug: `/movies/157336-interstellar`

  This page shows movie information and lists all cities with screenings,
  allowing users to navigate to city-specific screening pages.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Live.Components.MovieHeroComponent
  alias EventasaurusWeb.Live.Components.MovieOverviewComponent
  alias EventasaurusWeb.Live.Components.MovieCastComponent
  alias EventasaurusWeb.Live.Components.CinegraphLink
  alias EventasaurusWeb.JsonLd.MovieSchema
  alias Eventasaurus.CDN
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"identifier" => identifier}, _url, socket) do
    # Parse TMDB ID from identifier (e.g., "157336" or "157336-interstellar")
    tmdb_id = parse_tmdb_id(identifier)

    case tmdb_id do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Invalid movie identifier"))
         |> redirect(to: ~p"/activities")}

      tmdb_id ->
        # Fetch movie by TMDB ID
        movie =
          from(m in Movie,
            where: m.tmdb_id == ^tmdb_id
          )
          |> Repo.one()

        case movie do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Movie not found"))
             |> redirect(to: ~p"/activities")}

          movie ->
            # Fetch all cities with screenings for this movie
            cities_with_screenings = get_cities_with_screenings(movie.id)

            # Build breadcrumb navigation
            breadcrumb_items = [
              %{label: gettext("Home"), path: ~p"/"},
              %{label: gettext("All Activities"), path: ~p"/activities"},
              %{label: gettext("Film"), path: ~p"/activities?category=film"},
              %{label: movie.title, path: nil}
            ]

            # Build rich_data map for movie components
            rich_data = build_rich_data_from_movie(movie)

            # Extract cast and crew from TMDB credits
            credits = movie.tmdb_metadata["credits"] || %{}
            cast = credits["cast"] || []
            crew = credits["crew"] || []

            # Generate JSON-LD structured data
            json_ld = MovieSchema.generate_generic(movie, cities_with_screenings)

            # Generate Open Graph meta tags
            og_tags = build_movie_open_graph(movie, cities_with_screenings)

            {:noreply,
             socket
             |> assign(:page_title, movie.title)
             |> assign(:movie, movie)
             |> assign(:rich_data, rich_data)
             |> assign(:cast, cast)
             |> assign(:crew, crew)
             |> assign(:cities_with_screenings, cities_with_screenings)
             |> assign(:breadcrumb_items, breadcrumb_items)
             |> assign(:json_ld, json_ld)
             |> assign(:open_graph, og_tags)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Breadcrumbs -->
        <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-6" />

        <!-- Movie Hero Section -->
        <.live_component
          module={MovieHeroComponent}
          id="movie-hero"
          rich_data={@rich_data}
          variant={:card}
          show_rating={true}
          show_metadata={true}
        />

        <!-- Movie Overview Section -->
        <div class="mt-8">
          <.live_component
            module={MovieOverviewComponent}
            id="movie-overview"
            rich_data={@rich_data}
            variant={:card}
            compact={false}
            show_links={true}
            show_personnel={true}
            tmdb_id={@movie.tmdb_id}
          />
        </div>

        <!-- Cast Section -->
        <%= if length(@cast) > 0 do %>
          <div class="mt-8">
            <.live_component
              module={MovieCastComponent}
              id="movie-cast"
              cast={@cast}
              crew={@crew}
              variant={:card}
              compact={false}
              show_badges={true}
              max_cast={12}
              show_crew={true}
            />
          </div>
        <% end %>

        <!-- Where to Watch Section -->
        <div class="mt-8 bg-white rounded-lg shadow-lg p-8">
          <h2 class="text-2xl font-bold text-gray-900 mb-2">
            <%= gettext("Find Screenings Near You") %>
          </h2>
          <p class="text-gray-600 mb-6">
            <%= gettext("Select a city to see showtimes and venues") %>
          </p>

          <%= if @cities_with_screenings == [] do %>
            <div class="text-center py-12">
              <.icon name="hero-film" class="w-16 h-16 text-gray-400 mx-auto mb-4" />
              <p class="text-gray-600 text-lg mb-4">
                <%= gettext("No screenings currently available for this movie") %>
              </p>
              <p class="text-gray-500 text-sm">
                <%= gettext("Check back later or browse other movies") %>
              </p>
              <.link
                navigate={~p"/activities?category=film"}
                class="inline-flex items-center mt-6 px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
              >
                <%= gettext("Browse All Movies") %>
                <.icon name="hero-arrow-right" class="w-4 h-4 ml-2" />
              </.link>
            </div>
          <% else %>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for city_info <- @cities_with_screenings do %>
                <.city_card city_info={city_info} movie={@movie} />
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Cinegraph Link -->
        <%= if @movie.tmdb_id do %>
          <div class="mt-8 text-center">
            <CinegraphLink.cinegraph_link
              tmdb_id={@movie.tmdb_id}
              title={@movie.title}
              variant={:button}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Private function components

  defp city_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/c/#{@city_info.city.slug}/movies/#{@movie.slug}"}
      class="block p-6 border border-gray-200 rounded-lg hover:border-blue-400 hover:shadow-md transition-all group"
    >
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <div class="flex items-center gap-2 mb-2">
            <%= if @city_info.city.country && @city_info.city.country.flag do %>
              <span class="text-xl"><%= @city_info.city.country.flag %></span>
            <% end %>
            <h3 class="text-lg font-semibold text-gray-900 group-hover:text-blue-600 transition-colors">
              <%= @city_info.city.name %>
            </h3>
          </div>

          <div class="space-y-1 text-sm text-gray-600">
            <p>
              <.icon name="hero-ticket" class="w-4 h-4 inline mr-1" />
              <%= ngettext("1 screening", "%{count} screenings", @city_info.screening_count) %>
            </p>
            <p>
              <.icon name="hero-building-storefront" class="w-4 h-4 inline mr-1" />
              <%= ngettext("1 venue", "%{count} venues", @city_info.venue_count) %>
            </p>
            <%= if @city_info.next_date do %>
              <p>
                <.icon name="hero-calendar" class="w-4 h-4 inline mr-1" />
                <%= gettext("Next: %{date}", date: format_date(@city_info.next_date)) %>
              </p>
            <% end %>
          </div>
        </div>

        <div class="ml-4 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
          <.icon name="hero-arrow-right" class="w-5 h-5 text-blue-600" />
        </div>
      </div>
    </.link>
    """
  end

  # Helper functions

  defp parse_tmdb_id(identifier) when is_binary(identifier) do
    # Extract leading numeric portion from identifier
    # e.g., "157336" -> 157336
    # e.g., "157336-interstellar" -> 157336
    case Integer.parse(identifier) do
      {id, _rest} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_tmdb_id(_), do: nil

  defp get_cities_with_screenings(movie_id) do
    now = DateTime.utc_now()

    # Query for all cities that have future screenings for this movie
    from(pe in PublicEvent,
      join: em in "event_movies", on: pe.id == em.event_id,
      join: v in assoc(pe, :venue),
      join: c in assoc(v, :city_ref),
      where: em.movie_id == ^movie_id,
      where: pe.ends_at > ^now or is_nil(pe.ends_at),
      group_by: [c.id, c.name, c.slug],
      select: %{
        city_id: c.id,
        city_name: c.name,
        city_slug: c.slug,
        screening_count: count(pe.id),
        venue_count: count(v.id, :distinct),
        next_date: min(pe.starts_at)
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      # Load full city with country for flag display
      city =
        from(c in City,
          where: c.id == ^row.city_id,
          preload: [:country]
        )
        |> Repo.one()

      %{
        city: city,
        screening_count: row.screening_count,
        venue_count: row.venue_count,
        next_date: row.next_date
      }
    end)
    |> Enum.sort_by(& &1.screening_count, :desc)
  end

  defp format_date(nil), do: ""

  defp format_date(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    format_date(date)
  end

  defp format_date(%Date{} = date) do
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    case date do
      ^today -> gettext("Today")
      ^tomorrow -> gettext("Tomorrow")
      _ ->
        month_abbr = Calendar.strftime(date, "%b") |> String.capitalize()
        "#{month_abbr} #{date.day}"
    end
  end

  # Build rich_data map from movie for use with movie components
  defp build_rich_data_from_movie(movie) do
    tmdb = movie.tmdb_metadata || %{}
    credits = tmdb["credits"] || %{}
    crew = credits["crew"] || []

    # Find director from crew
    director =
      crew
      |> Enum.find(fn member -> member["job"] == "Director" end)

    # Build external links map
    external_ids = tmdb["external_ids"] || %{}

    external_links =
      %{}
      |> maybe_add_link(:imdb_url, external_ids["imdb_id"], &"https://www.imdb.com/title/#{&1}")
      |> maybe_add_link(:tmdb_url, tmdb["id"], &"https://www.themoviedb.org/movie/#{&1}")
      |> maybe_add_link(:homepage, tmdb["homepage"], & &1)

    %{
      "title" => movie.title,
      "overview" => tmdb["overview"],
      "poster_path" => tmdb["poster_path"],
      "backdrop_path" => tmdb["backdrop_path"],
      "release_date" => tmdb["release_date"],
      "runtime" => tmdb["runtime"],
      "vote_average" => tmdb["vote_average"],
      "vote_count" => tmdb["vote_count"],
      "genres" => tmdb["genres"] || [],
      "director" => director,
      "crew" => crew,
      "external_links" => external_links
    }
  end

  defp maybe_add_link(map, _key, nil, _builder), do: map
  defp maybe_add_link(map, _key, "", _builder), do: map

  defp maybe_add_link(map, key, value, builder) do
    Map.put(map, key, builder.(value))
  end

  # Build Open Graph meta tags for generic movie page
  defp build_movie_open_graph(movie, cities_with_screenings) do
    base_url = EventasaurusWeb.Layouts.get_base_url()

    # Get movie poster image
    image_url =
      cond do
        movie.tmdb_metadata && movie.tmdb_metadata["poster_path"] ->
          "https://image.tmdb.org/t/p/w500#{movie.tmdb_metadata["poster_path"]}"

        movie.metadata && movie.metadata["poster"] ->
          movie.metadata["poster"]

        true ->
          movie_name_encoded = URI.encode(movie.title)
          "https://placehold.co/500x750/4ECDC4/FFFFFF?text=#{movie_name_encoded}"
      end

    # Wrap with CDN
    cdn_image_url = CDN.url(image_url)

    # Build description based on available cities
    description =
      case cities_with_screenings do
        [] ->
          "Watch #{movie.title}. Find showtimes and venues."

        cities ->
          city_count = length(cities)
          total_screenings = Enum.sum(Enum.map(cities, & &1.screening_count))

          "Watch #{movie.title}. #{total_screenings} screenings available in #{city_count} #{if city_count == 1, do: "city", else: "cities"}."
      end

    # Render Open Graph component
    Phoenix.HTML.Safe.to_iodata(
      EventasaurusWeb.Components.OpenGraphComponent.open_graph_tags(%{
        type: "video.movie",
        title: movie.title,
        description: description,
        image_url: cdn_image_url,
        image_width: 500,
        image_height: 750,
        url: "#{base_url}/movies/#{movie.tmdb_id}-#{movie.slug}",
        site_name: "Wombie",
        locale: "en_US",
        twitter_card: "summary_large_image"
      })
    )
    |> IO.iodata_to_binary()
  end
end
