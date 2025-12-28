defmodule EventasaurusWeb.GenericMovieLive do
  @moduledoc """
  Generic movie page for cross-site linking.

  Accessible via `/movies/:slug` where slug is in the format `title-tmdb_id`:
  - `/movies/interstellar-157336` (canonical format)
  - `/movies/home-alone-771`

  Also supports legacy URLs and bare TMDB IDs with redirects:
  - `/movies/157336` (TMDB ID only) → redirects to canonical
  - `/movies/interstellar-499` (old random suffix) → redirects to canonical

  This page shows movie information and lists all cities with screenings,
  allowing users to navigate to city-specific screening pages.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Components.CountryFlag
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Live.Components.MovieHeroComponent
  alias EventasaurusWeb.Live.Components.CastCarouselComponent
  alias EventasaurusWeb.JsonLd.MovieSchema
  alias EventasaurusWeb.Services.TmdbService
  alias Eventasaurus.CDN
  alias EventasaurusApp.Images.MovieImages
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"identifier" => identifier}, _url, socket) do
    # Try to find movie by:
    # 1. Direct slug match (canonical: "home-alone-771")
    # 2. Legacy slug match (old format: "home-alone-499")
    # 3. TMDB ID only ("771")
    movie = find_movie(identifier)

    case movie do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Movie not found"))
         |> redirect(to: ~p"/activities")}

      movie ->
        # Redirect to canonical URL if not already there
        if identifier != movie.slug do
          {:noreply, redirect(socket, to: ~p"/movies/#{movie.slug}")}
        else
          # Fetch all cities with screenings for this movie
          cities_with_screenings = get_cities_with_screenings(movie.id)

          # Build breadcrumb navigation using BreadcrumbBuilder
          breadcrumb_items = BreadcrumbBuilder.build_generic_movie_breadcrumbs(movie)

          # Build rich_data map for movie components
          rich_data = build_rich_data_from_movie(movie)

          # Fetch cast/crew from TMDB if we have a tmdb_id
          {cast, crew} = fetch_cast_and_crew(movie.tmdb_id)

          # Enrich movie with TMDB metadata for JSON-LD generation
          # This populates the virtual tmdb_metadata field with credits data
          movie_with_metadata = enrich_movie_for_json_ld(movie, cast, crew)

          # Generate JSON-LD structured data
          json_ld = MovieSchema.generate_generic(movie_with_metadata, cities_with_screenings)

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
          show_overview={true}
          show_links={true}
          tmdb_id={@movie.tmdb_id}
        />

        <!-- Cast Section -->
        <%= if length(@cast) > 0 do %>
          <div class="mt-8 bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
            <.live_component
              module={CastCarouselComponent}
              id="movie-cast"
              cast={@cast}
              variant={:embedded}
              max_cast={10}
            />
          </div>
        <% end %>

        <!-- Where to Watch Section -->
        <div class="mt-8 bg-white rounded-2xl border border-gray-200 p-8 shadow-sm">
          <h2 class="text-2xl font-bold text-gray-900 mb-2">
            <%= gettext("Find Screenings Near You") %>
          </h2>
          <p class="text-gray-600 mb-6">
            <%= gettext("Select a city to see showtimes and venues") %>
          </p>

          <%= if @cities_with_screenings == [] do %>
            <div class="text-center py-12">
              <.icon name="hero-film" class="w-16 h-16 text-gray-300 mx-auto mb-4" />
              <p class="text-gray-600 text-lg mb-4">
                <%= gettext("No screenings currently available for this movie") %>
              </p>
              <p class="text-gray-500 text-sm">
                <%= gettext("Check back later or browse other movies") %>
              </p>
              <.link
                navigate={~p"/activities?category=film"}
                class="inline-flex items-center mt-6 px-6 py-3 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition"
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

      </div>
    </div>
    """
  end

  # Private function components

  defp city_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/c/#{@city_info.city.slug}/movies/#{@movie.slug}"}
      class="block p-6 bg-white border border-gray-200 rounded-xl hover:bg-gray-50 hover:border-gray-300 hover:shadow-md transition-all group"
    >
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <div class="flex items-center gap-2 mb-2">
            <%= if @city_info.city.country && @city_info.city.country.code do %>
              <CountryFlag.flag country_code={@city_info.city.country.code} size="md" />
            <% end %>
            <h3 class="text-lg font-semibold text-gray-900 group-hover:text-blue-600 transition-colors">
              <%= @city_info.city.name %>
            </h3>
          </div>

          <div class="space-y-1 text-sm text-gray-600">
            <p>
              <.icon name="hero-ticket" class="w-4 h-4 inline mr-1 text-gray-400" />
              <%= ngettext("1 screening", "%{count} screenings", @city_info.screening_count) %>
            </p>
            <p>
              <.icon name="hero-building-storefront" class="w-4 h-4 inline mr-1 text-gray-400" />
              <%= ngettext("1 venue", "%{count} venues", @city_info.venue_count) %>
            </p>
            <%= if @city_info.next_date do %>
              <p>
                <.icon name="hero-calendar" class="w-4 h-4 inline mr-1 text-gray-400" />
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

  # Find movie by identifier, trying multiple lookup strategies:
  # 1. Direct slug match (canonical: "home-alone-771")
  # 2. Legacy slug match (old format: "home-alone-499")
  # 3. TMDB ID only ("771")
  defp find_movie(identifier) when is_binary(identifier) do
    # Try canonical slug first
    movie = Repo.one(from(m in Movie, where: m.slug == ^identifier))

    cond do
      movie != nil ->
        movie

      # Try legacy slug (backwards compatibility)
      true ->
        movie = Repo.one(from(m in Movie, where: m.legacy_slug == ^identifier))

        if movie do
          movie
        else
          # Try parsing as TMDB ID
          case parse_tmdb_id(identifier) do
            nil -> nil
            tmdb_id -> Repo.one(from(m in Movie, where: m.tmdb_id == ^tmdb_id))
          end
        end
    end
  end

  defp find_movie(_), do: nil

  # Parse TMDB ID from identifier:
  # - "157336" -> 157336 (TMDB ID only)
  # - "interstellar-157336" -> 157336 (slug-tmdb_id format, extracts trailing ID)
  defp parse_tmdb_id(identifier) when is_binary(identifier) do
    cond do
      # Pure numeric - just TMDB ID
      Regex.match?(~r/^\d+$/, identifier) ->
        case Integer.parse(identifier) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      # slug-tmdb_id format (e.g., "interstellar-157336")
      # Extract the TMDB ID from the end after the last hyphen
      Regex.match?(~r/^.+-\d+$/, identifier) ->
        parts = String.split(identifier, "-")
        tmdb_part = List.last(parts)

        case Integer.parse(tmdb_part) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp parse_tmdb_id(_), do: nil

  defp get_cities_with_screenings(movie_id) do
    now = DateTime.utc_now()

    # Query for all cities that have future screenings for this movie
    # Events are considered "future" if they haven't ended yet, or if ends_at is nil
    # and starts_at is in the future (ongoing events without explicit end time)
    rows =
      from(pe in PublicEvent,
        join: em in "event_movies",
        on: pe.id == em.event_id,
        join: v in assoc(pe, :venue),
        join: c in assoc(v, :city_ref),
        where: em.movie_id == ^movie_id,
        where: pe.ends_at > ^now or (is_nil(pe.ends_at) and pe.starts_at > ^now),
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

    # Batch load all cities with countries in a single query (avoid N+1)
    city_ids = Enum.map(rows, & &1.city_id)

    cities_by_id =
      from(c in City,
        where: c.id in ^city_ids,
        preload: [:country]
      )
      |> Repo.all()
      |> Map.new(fn city -> {city.id, city} end)

    # Build result with preloaded cities
    rows
    |> Enum.map(fn row ->
      %{
        city: Map.get(cities_by_id, row.city_id),
        screening_count: row.screening_count,
        venue_count: row.venue_count,
        next_date: row.next_date
      }
    end)
    |> Enum.reject(fn row -> is_nil(row.city) end)
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
      ^today ->
        gettext("Today")

      ^tomorrow ->
        gettext("Tomorrow")

      _ ->
        month_abbr = Calendar.strftime(date, "%b") |> String.capitalize()
        "#{month_abbr} #{date.day}"
    end
  end

  # Build rich_data map from movie for use with movie components
  # Uses actual movie fields (poster_url, backdrop_url, etc.) and metadata map
  defp build_rich_data_from_movie(movie) do
    metadata = movie.metadata || %{}

    # Extract poster_path from full URL if present
    # movie.poster_url is like "https://image.tmdb.org/t/p/w500/onTSipZ8R3bliBdKfPtsDuHTdlL.jpg"
    # We need "/onTSipZ8R3bliBdKfPtsDuHTdlL.jpg" for the components
    poster_path = extract_tmdb_path(movie.poster_url)
    backdrop_path = extract_tmdb_path(movie.backdrop_url)

    # Build external links map
    external_links =
      %{}
      |> maybe_add_link(:tmdb_url, movie.tmdb_id, &"https://www.themoviedb.org/movie/#{&1}")

    %{
      "title" => movie.title,
      "overview" => movie.overview,
      "poster_path" => poster_path,
      "backdrop_path" => backdrop_path,
      "release_date" => format_release_date(movie.release_date),
      "runtime" => movie.runtime,
      "vote_average" => metadata["vote_average"],
      "vote_count" => metadata["vote_count"],
      "genres" => build_genres_list(metadata["genres"]),
      "director" => nil,
      "crew" => [],
      "external_links" => external_links
    }
  end

  # Extract the path portion from a full TMDB image URL
  # "https://image.tmdb.org/t/p/w500/abc123.jpg" -> "/abc123.jpg"
  defp extract_tmdb_path(nil), do: nil
  defp extract_tmdb_path(""), do: nil

  defp extract_tmdb_path(url) when is_binary(url) do
    case Regex.run(~r{/t/p/w\d+(/[^/]+\.\w+)$}, url) do
      [_, path] -> path
      _ -> nil
    end
  end

  # Format release_date for display
  defp format_release_date(nil), do: nil
  defp format_release_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_release_date(date) when is_binary(date), do: date

  # Build genres list - metadata may have string list or map list
  defp build_genres_list(nil), do: []

  defp build_genres_list(genres) when is_list(genres) do
    Enum.map(genres, fn
      %{"name" => name} -> %{"name" => name}
      name when is_binary(name) -> %{"name" => name}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_genres_list(_), do: []

  defp maybe_add_link(map, _key, nil, _builder), do: map
  defp maybe_add_link(map, _key, "", _builder), do: map

  defp maybe_add_link(map, key, value, builder) do
    Map.put(map, key, builder.(value))
  end

  # Build Open Graph meta tags for generic movie page
  defp build_movie_open_graph(movie, cities_with_screenings) do
    base_url = EventasaurusWeb.Layouts.get_base_url()

    # Get movie poster image - use cached URL with fallback to original
    poster_url = MovieImages.get_poster_url(movie.id, movie.poster_url)

    image_url =
      cond do
        poster_url && poster_url != "" ->
          poster_url

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
        url: "#{base_url}/movies/#{movie.slug}",
        site_name: "Wombie",
        locale: "en_US",
        twitter_card: "summary_large_image"
      })
    )
    |> IO.iodata_to_binary()
  end

  # Fetch cast and crew from TMDB API
  # Returns {cast, crew} tuple where each is a list of maps with string keys
  # (CastCarouselComponent expects string keys like "name", "character", "profile_path")
  defp fetch_cast_and_crew(nil), do: {[], []}

  defp fetch_cast_and_crew(tmdb_id) do
    case TmdbService.get_cached_movie_details(tmdb_id) do
      {:ok, movie_data} ->
        cast =
          (movie_data[:cast] || [])
          |> Enum.map(&stringify_keys/1)

        crew =
          (movie_data[:crew] || [])
          |> Enum.map(&stringify_keys/1)

        {cast, crew}

      {:error, _reason} ->
        # If TMDB fetch fails, return empty arrays
        {[], []}
    end
  end

  # Convert map with atom keys to string keys for component compatibility
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  # Enrich movie struct with TMDB metadata for JSON-LD generation
  # This populates the virtual tmdb_metadata field with credits data
  # so that director/actor fields can be extracted by MovieSchema
  defp enrich_movie_for_json_ld(movie, cast, crew) do
    # Build tmdb_metadata map with credits data for JSON-LD extraction
    tmdb_metadata = %{
      "credits" => %{
        "cast" => cast,
        "crew" => crew
      },
      "release_date" =>
        if(movie.release_date, do: Date.to_iso8601(movie.release_date), else: nil),
      "runtime" => movie.runtime
    }

    %{movie | tmdb_metadata: tmdb_metadata}
  end
end
