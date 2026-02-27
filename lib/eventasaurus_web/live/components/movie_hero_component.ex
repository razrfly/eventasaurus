defmodule EventasaurusWeb.Live.Components.MovieHeroComponent do
  @moduledoc """
  Hero section component for movie/TV show display.

  Features a full-bleed backdrop image with overlaid poster, title, tagline,
  ratings, and key metadata. Inspired by Cinegraph's movie page design.

  ## Variants

  - `:full` (default) - Full-bleed hero with large backdrop (h-96 to h-[500px])
  - `:compact` - Smaller hero for embedded contexts (h-64 to h-80)
  - `:card` - Light-themed card variant for light backgrounds

  ## Props

  - `rich_data` - Movie data from TMDB (required)
  - `variant` - `:full` | `:compact` | `:card` (default: `:full`)
  - `show_poster` - Boolean to show/hide poster (default: true)
  - `show_director` - Boolean to show director credits (default: true for :full)
  - `show_overview` - Boolean to show overview text in hero (default: false)
  - `show_links` - Boolean to show external links in hero (default: false)
  - `tmdb_id` - TMDB ID for external links (optional)
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Utils.MovieUtils

  @impl true
  def update(assigns, socket) do
    # Resolve variant first so we can use it for dependent defaults
    resolved_variant = assigns[:variant] || socket.assigns[:variant] || :full

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:variant, fn -> :full end)
     |> assign_new(:show_poster, fn -> true end)
     |> assign_new(:show_director, fn -> resolved_variant != :compact end)
     |> assign_new(:show_overview, fn -> false end)
     |> assign_new(:show_links, fn -> false end)
     |> assign_new(:tmdb_id, fn -> nil end)
     |> assign_new(:cinegraph_data, fn -> nil end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={root_wrapper_classes(@variant, @has_backdrop)}>
      <%= if @has_backdrop do %>
        <!-- Full-bleed Backdrop Hero -->
        <div class={hero_container_classes(@variant)}>
          <img
            src={@backdrop_url}
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
            aria-hidden="true"
          />
          <!-- Gradient overlay - strong darkness for text readability on any backdrop -->
          <div class="absolute inset-0 bg-gradient-to-t from-black via-black/70 to-black/40" />
        </div>

        <!-- Hero Content - positioned over backdrop -->
        <div class={hero_content_wrapper_classes(@variant)}>
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex flex-col md:flex-row gap-6 lg:gap-8 items-start">
              <!-- Poster -->
              <%= if @show_poster && @has_poster do %>
                <div class="flex-shrink-0">
                  <img
                    src={@poster_url}
                    alt={"#{@title} poster"}
                    class={poster_classes(@variant)}
                    loading="lazy"
                  />
                </div>
              <% end %>

              <!-- Movie Info -->
              <div class={["flex-1 min-w-0", content_text_classes(@variant)]}>
                <.hero_content
                  title={@title}
                  tagline={@tagline}
                  release_info={@release_info}
                  rating={@rating}
                  runtime={@runtime}
                  genres={@genres}
                  director={@director}
                  variant={@variant}
                  show_director={@show_director}
                  overview={@overview}
                  show_overview={@show_overview}
                  show_links={@show_links}
                  tmdb_id={@tmdb_id}
                  cinegraph_data={@cinegraph_data}
                />
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <!-- No backdrop fallback - gradient background -->
        <div class={fallback_container_classes(@variant)}>
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 lg:py-12">
            <div class="flex flex-col md:flex-row gap-6 lg:gap-8 items-start">
              <%= if @show_poster && @has_poster do %>
                <div class="flex-shrink-0">
                  <img
                    src={@poster_url}
                    alt={"#{@title} poster"}
                    class={poster_classes(@variant)}
                    loading="lazy"
                  />
                </div>
              <% end %>

              <div class={["flex-1 min-w-0", content_text_classes(@variant)]}>
                <.hero_content
                  title={@title}
                  tagline={@tagline}
                  release_info={@release_info}
                  rating={@rating}
                  runtime={@runtime}
                  genres={@genres}
                  director={@director}
                  variant={@variant}
                  show_director={@show_director}
                  overview={@overview}
                  show_overview={@show_overview}
                  show_links={@show_links}
                  tmdb_id={@tmdb_id}
                  cinegraph_data={@cinegraph_data}
                />
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp hero_content(assigns) do
    awards = get_in(assigns[:cinegraph_data] || %{}, ["awards"]) || %{}
    oscar_wins = awards["oscarWins"] || 0
    total_wins = awards["totalWins"] || 0
    total_nominations = awards["totalNominations"] || 0
    raw_summary = awards["summary"]

    awards_summary =
      cond do
        is_binary(raw_summary) and raw_summary != "" -> raw_summary
        total_wins > 0 && total_nominations > 0 -> "#{total_wins} wins & #{total_nominations} nominations"
        total_wins > 0 -> "#{total_wins} wins"
        total_nominations > 0 -> "#{total_nominations} nominations"
        true -> nil
      end

    assigns = assign(assigns, oscar_wins: oscar_wins, awards_summary: awards_summary)

    ~H"""
    <div class="space-y-4">
      <!-- Title -->
      <h1 class={title_classes(@variant)}>
        <%= @title %>
        <%= if @release_info[:year] do %>
          <span class={year_text_classes(@variant)}>(<%= @release_info[:year] %>)</span>
        <% end %>
      </h1>

      <!-- Tagline -->
      <%= if @tagline && @tagline != "" do %>
        <p class={tagline_classes(@variant)}>
          "<%= @tagline %>"
        </p>
      <% end %>

      <!-- Metadata Pills (year removed - already in title) -->
      <div class="flex flex-wrap items-center gap-3">
        <%= if @runtime do %>
          <.metadata_pill variant={@variant}><%= format_runtime(@runtime) %></.metadata_pill>
        <% end %>

        <.cinegraph_ratings_row cinegraph_data={@cinegraph_data} rating={@rating} variant={@variant} />
      </div>

      <!-- Genres -->
      <%= if @genres && length(@genres) > 0 do %>
        <div class="flex flex-wrap gap-2">
          <%= for genre <- Enum.take(@genres, 4) do %>
            <span class={genre_pill_classes(@variant)}>
              <%= genre %>
            </span>
          <% end %>
        </div>
      <% end %>

      <!-- Overview -->
      <%= if @show_overview && @overview && @overview != "" do %>
        <div class="pt-2">
          <p class={overview_classes(@variant)}>
            <%= @overview %>
          </p>
        </div>
      <% end %>

      <!-- External Links -->
      <%= if @show_links do %>
        <% cinegraph_url = cinegraph_movie_url(@cinegraph_data, @tmdb_id) %>
        <%= if cinegraph_url || @tmdb_id do %>
          <div class="flex flex-wrap gap-3 pt-2">
            <%= if cinegraph_url do %>
              <.hero_link_button
                href={cinegraph_url}
                icon={:cinegraph}
                label="Cinegraph"
                variant={@variant}
              />
            <% end %>
            <%= if @tmdb_id do %>
              <.hero_link_button
                href={"https://www.themoviedb.org/movie/#{@tmdb_id}"}
                icon={:tmdb}
                label="TMDB"
                variant={@variant}
              />
            <% end %>
          </div>
        <% end %>
      <% end %>

      <!-- Director + Awards inline -->
      <%= if @show_director && @director do %>
        <div class="pt-2">
          <p class={director_label_classes(@variant)}>Directed by</p>
          <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <p class={director_name_classes(@variant)}><%= @director %></p>
            <%= if @oscar_wins > 0 do %>
              <span class="text-sm text-white/70">
                · 🏆 <%= if @oscar_wins == 1, do: "1 Oscar Win", else: "#{@oscar_wins} Oscar Wins" %>
              </span>
            <% end %>
            <%= if @awards_summary do %>
              <span class="text-sm text-white/50">
                <%= if @oscar_wins == 0, do: "· " %><%= @awards_summary %>
              </span>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp metadata_pill(assigns) do
    ~H"""
    <span class={metadata_pill_classes(@variant)}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp cinegraph_ratings_row(assigns) do
    ratings = get_in(assigns[:cinegraph_data] || %{}, ["ratings"]) || %{}
    tmdb_score = ratings["tmdb"]
    imdb_score = ratings["imdb"]
    rt_score = ratings["rottenTomatoes"]
    meta_score = ratings["metacritic"]
    has_cinegraph_ratings = !is_nil(tmdb_score) || !is_nil(imdb_score) || !is_nil(rt_score) || !is_nil(meta_score)

    assigns =
      assign(assigns,
        tmdb_score: tmdb_score,
        imdb_score: imdb_score,
        rt_score: rt_score,
        meta_score: meta_score,
        has_cinegraph_ratings: has_cinegraph_ratings
      )

    ~H"""
    <%= if @has_cinegraph_ratings do %>
      <%= if @tmdb_score do %>
        <span class={metadata_pill_classes(@variant)}>
          <span class="flex items-center gap-1">⭐ <%= format_rating(@tmdb_score) %> TMDB</span>
        </span>
      <% end %>
      <%= if @imdb_score do %>
        <span class={metadata_pill_classes(@variant)}>
          <span class="flex items-center gap-1">🎬 <%= format_rating(@imdb_score) %> IMDb</span>
        </span>
      <% end %>
      <%= if @rt_score do %>
        <span class={metadata_pill_classes(@variant)}>
          <span class="flex items-center gap-1">🍅 <%= @rt_score %>% RT</span>
        </span>
      <% end %>
      <%= if @meta_score do %>
        <span class={metadata_pill_classes(@variant)}>
          <span class="flex items-center gap-1">📰 <%= @meta_score %> MC</span>
        </span>
      <% end %>
    <% else %>
      <%= if @rating do %>
        <span class={metadata_pill_classes(@variant)}>
          <span class="flex items-center gap-1">
            <.icon name="hero-star-solid" class="h-3.5 w-3.5 text-yellow-400" />
            <%= format_rating(@rating) %>/10
          </span>
        </span>
      <% end %>
    <% end %>
    """
  end

  defp hero_link_button(assigns) do
    ~H"""
    <a
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      class={hero_link_button_classes(@variant)}
    >
      <.link_icon type={@icon} />
      <span><%= @label %></span>
    </a>
    """
  end

  defp link_icon(%{type: :cinegraph} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M18 4l2 4h-3l-2-4h-2l2 4h-3l-2-4H8l2 4H7L5 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4h-4z" />
    </svg>
    """
  end

  defp link_icon(%{type: :tmdb} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>
    </svg>
    """
  end

  defp hero_link_button_classes(:card) do
    [
      "inline-flex items-center gap-2 px-4 py-2",
      "bg-white/20 backdrop-blur-sm border border-white/30",
      "text-white font-medium rounded-lg text-sm",
      "hover:bg-white/30 hover:border-white/40",
      "transition-all"
    ]
  end

  defp hero_link_button_classes(_) do
    [
      "inline-flex items-center gap-2 px-4 py-2",
      "bg-white/20 backdrop-blur-sm border border-white/30",
      "text-white font-medium rounded-lg text-sm",
      "hover:bg-white/30 hover:border-white/40",
      "transition-all"
    ]
  end

  # CSS class helpers

  # Root wrapper controls outer card treatment. For :card with a backdrop, we want
  # rounded corners, subtle border, and overflow clipping so the backdrop respects radius.
  defp root_wrapper_classes(:card, true),
    do: "relative rounded-2xl border border-gray-200 shadow-sm overflow-hidden"

  # For other variants or when there's no backdrop, rely on inner container styling.
  defp root_wrapper_classes(_, _), do: "relative"

  defp hero_container_classes(:full) do
    "absolute inset-0 h-96 md:h-[450px] lg:h-[500px]"
  end

  defp hero_container_classes(:compact) do
    "absolute inset-0 h-64 md:h-72 lg:h-80"
  end

  defp hero_container_classes(:card) do
    "absolute inset-0"
  end

  defp hero_container_classes(_), do: hero_container_classes(:full)

  defp hero_content_wrapper_classes(:full) do
    "relative z-10 pt-16 pb-8 md:pt-24 lg:pt-32"
  end

  defp hero_content_wrapper_classes(:compact) do
    "relative z-10 pt-12 pb-6 md:pt-16"
  end

  defp hero_content_wrapper_classes(:card) do
    "relative z-10 pt-12 pb-6 md:pt-16"
  end

  defp hero_content_wrapper_classes(_), do: hero_content_wrapper_classes(:full)

  defp fallback_container_classes(:full) do
    "bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 min-h-[400px]"
  end

  defp fallback_container_classes(:compact) do
    "bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 min-h-[280px]"
  end

  defp fallback_container_classes(:card) do
    "bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 rounded-2xl shadow-sm min-h-[280px]"
  end

  defp fallback_container_classes(_), do: fallback_container_classes(:full)

  defp poster_classes(:full) do
    "w-48 md:w-56 lg:w-64 h-auto rounded-lg shadow-2xl ring-1 ring-white/10"
  end

  defp poster_classes(:compact) do
    "w-32 md:w-40 h-auto rounded-lg shadow-xl ring-1 ring-white/10"
  end

  defp poster_classes(:card) do
    "w-40 md:w-48 h-auto rounded-lg shadow-lg ring-1 ring-white/10"
  end

  defp poster_classes(_), do: poster_classes(:full)

  defp title_classes(:full) do
    "text-3xl md:text-4xl lg:text-5xl font-bold tracking-tight leading-tight drop-shadow-lg"
  end

  defp title_classes(:compact) do
    "text-2xl md:text-3xl font-bold tracking-tight leading-tight drop-shadow-lg"
  end

  defp title_classes(:card) do
    "text-2xl md:text-3xl lg:text-4xl font-bold tracking-tight leading-tight text-white drop-shadow-lg"
  end

  defp title_classes(_), do: title_classes(:full)

  defp tagline_classes(:full) do
    "text-lg md:text-xl italic text-white/80"
  end

  defp tagline_classes(:compact) do
    "text-base italic text-white/80"
  end

  defp tagline_classes(:card) do
    "text-base md:text-lg italic text-white/80"
  end

  defp tagline_classes(_), do: tagline_classes(:full)

  # For :card variant WITH backdrop, use white text for readability
  # For :card variant WITHOUT backdrop (fallback), use dark text
  defp content_text_classes(:card), do: "text-white"
  defp content_text_classes(_), do: "text-white"

  defp year_text_classes(:card), do: "font-normal text-white/80"
  defp year_text_classes(_), do: "font-normal text-white/80"

  defp metadata_pill_classes(:card) do
    "px-3 py-1.5 bg-white/20 backdrop-blur-sm rounded-full text-sm font-medium text-white"
  end

  defp metadata_pill_classes(_) do
    "px-3 py-1.5 bg-white/20 backdrop-blur-sm rounded-full text-sm font-medium text-white"
  end

  defp genre_pill_classes(:card) do
    "px-3 py-1 bg-white/10 border border-white/20 rounded-full text-sm font-medium text-white/90"
  end

  defp genre_pill_classes(_) do
    "px-3 py-1 bg-white/10 border border-white/20 rounded-full text-sm font-medium text-white/90"
  end

  defp director_label_classes(:card),
    do: "text-sm text-white/60 uppercase tracking-wide font-semibold mb-1"

  defp director_label_classes(_),
    do: "text-sm text-white/60 uppercase tracking-wide font-semibold mb-1"

  defp director_name_classes(:card), do: "text-lg text-white font-medium"
  defp director_name_classes(_), do: "text-lg text-white font-medium"

  defp overview_classes(:card),
    do: "text-white/90 text-base lg:text-lg leading-relaxed line-clamp-3 drop-shadow-md"

  defp overview_classes(_),
    do: "text-white/90 text-base lg:text-lg leading-relaxed line-clamp-3 drop-shadow-md"

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    socket
    |> assign(:title, MovieUtils.get_title(rich_data))
    |> assign(:tagline, get_tagline(rich_data))
    |> assign(:has_backdrop, has_backdrop?(rich_data))
    |> assign(:backdrop_url, MovieUtils.get_backdrop_url(rich_data))
    |> assign(:has_poster, has_poster?(rich_data))
    |> assign(:poster_url, MovieUtils.get_poster_url(rich_data))
    |> assign(:rating, get_rating(rich_data))
    |> assign(:runtime, get_runtime(rich_data))
    |> assign(:genres, MovieUtils.get_genres(rich_data))
    |> assign(:release_info, get_release_info(rich_data))
    |> assign(:director, MovieUtils.get_director(rich_data))
    |> assign(:overview, get_overview(rich_data))
  end

  defp has_backdrop?(rich_data) do
    backdrop_path =
      rich_data["backdrop_path"] ||
        get_in(rich_data, ["metadata", "backdrop_path"])

    is_binary(backdrop_path) && backdrop_path != ""
  end

  defp has_poster?(rich_data) do
    poster_path =
      rich_data["poster_path"] ||
        get_in(rich_data, ["metadata", "poster_path"])

    is_binary(poster_path) && poster_path != ""
  end

  defp get_tagline(rich_data) do
    rich_data["tagline"] ||
      get_in(rich_data, ["metadata", "tagline"])
  end

  defp get_rating(rich_data) do
    rich_data["vote_average"] ||
      get_in(rich_data, ["metadata", "vote_average"])
  end

  defp get_runtime(rich_data) do
    rich_data["runtime"] ||
      get_in(rich_data, ["metadata", "runtime"])
  end

  defp get_overview(rich_data) do
    rich_data["overview"] ||
      get_in(rich_data, ["metadata", "overview"]) ||
      rich_data["description"]
  end

  defp get_release_info(rich_data) do
    release_date =
      rich_data["release_date"] ||
        rich_data["first_air_date"] ||
        get_in(rich_data, ["metadata", "release_date"]) ||
        get_in(rich_data, ["metadata", "first_air_date"])

    case release_date do
      date_string when is_binary(date_string) and date_string != "" ->
        case Date.from_iso8601(date_string) do
          {:ok, date} ->
            %{
              year: date.year,
              formatted: Calendar.strftime(date, "%B %d, %Y")
            }

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp format_rating(nil), do: nil

  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating * 1.0, decimals: 1)
  end

  defp format_rating(_), do: nil

  defp cinegraph_movie_url(%{"slug" => slug}, _tmdb_id)
       when is_binary(slug) and slug != "",
       do: "https://cinegraph.org/movies/#{slug}"

  defp cinegraph_movie_url(_cinegraph_data, tmdb_id) when not is_nil(tmdb_id),
    do: "https://cinegraph.org/movies/tmdb/#{tmdb_id}"

  defp cinegraph_movie_url(_, _), do: nil

  defp format_runtime(nil), do: nil

  defp format_runtime(runtime) when is_integer(runtime) and runtime > 0 do
    hours = div(runtime, 60)
    minutes = rem(runtime, 60)

    case {hours, minutes} do
      {0, min} -> "#{min}m"
      {hr, 0} -> "#{hr}h"
      {hr, min} -> "#{hr}h #{min}m"
    end
  end

  defp format_runtime(_), do: nil
end
