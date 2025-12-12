defmodule EventasaurusWeb.Live.Components.MovieOverviewComponent do
  @moduledoc """
  Overview section component for movie/TV show display.

  Displays the overview/synopsis and key personnel information
  like director, writers, and key crew members.

  ## Props

  - `rich_data` - Movie data from TMDB (required)
  - `variant` - `:card` | `:dark` (default: `:card`)
  - `compact` - Boolean for compact display mode (default: false)
  - `show_links` - Boolean to show external links section (default: true)
  - `show_personnel` - Boolean to show key personnel section (default: true)
  - `tmdb_id` - TMDB ID for Cinegraph link (optional)
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent
  alias EventasaurusWeb.Live.Components.CinegraphLink

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:variant, fn -> :card end)
     |> assign_new(:show_links, fn -> true end)
     |> assign_new(:show_personnel, fn -> true end)
     |> assign_new(:tmdb_id, fn -> nil end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={section_container_classes(@variant, @compact)}>
      <!-- Overview Section -->
      <%= if @overview do %>
        <div>
          <h2 class={section_title_classes(@variant, @compact)}>Overview</h2>
          <p class={overview_text_classes(@variant, @compact)}><%= @overview %></p>
        </div>
      <% end %>

      <!-- Key Personnel -->
      <%= if @show_personnel && @has_key_personnel do %>
        <div>
          <h3 class={subsection_title_classes(@variant)}>Key Personnel</h3>
          <div class={personnel_grid_classes(@compact)}>
            <%= if @director do %>
              <.person_card
                person={@director}
                role="Director"
                compact={@compact}
                variant={@variant}
              />
            <% end %>

            <%= for writer <- @writers do %>
              <.person_card
                person={writer}
                role={writer["job"]}
                compact={@compact}
                variant={@variant}
              />
            <% end %>

            <%= for producer <- @producers do %>
              <.person_card
                person={producer}
                role={producer["job"]}
                compact={@compact}
                variant={@variant}
              />
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- External Links -->
      <%= if @show_links && ((@external_links && map_size(@external_links) > 0) || @tmdb_id) do %>
        <div>
          <h3 class={subsection_title_classes(@variant)}>Links</h3>
          <div class="flex flex-wrap gap-3">
            <%= if @tmdb_id do %>
              <CinegraphLink.cinegraph_link
                tmdb_id={@tmdb_id}
                variant={if @variant == :dark, do: :dark, else: :pill}
              />
            <% end %>
            <%= for {type, url} <- @external_links || %{} do %>
              <%= if url && url != "" do %>
                <.external_link_button type={type} url={url} variant={@variant} />
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp person_card(assigns) do
    assigns = assign_new(assigns, :initials, fn -> get_initials(assigns.person["name"]) end)

    ~H"""
    <div class={person_card_classes(@variant)}>
      <%= if @person["profile_path"] do %>
        <img
          src={RichDataDisplayComponent.tmdb_image_url(@person["profile_path"], "w185")}
          alt={@person["name"]}
          class={person_image_classes(@variant)}
          loading="lazy"
        />
      <% else %>
        <div class={person_placeholder_classes(@variant)}>
          <span class={person_initials_classes(@variant)}><%= @initials %></span>
        </div>
      <% end %>

      <div class="min-w-0 flex-1">
        <p class={person_name_classes(@variant)}>
          <%= @person["name"] %>
        </p>
        <p class={person_role_classes(@variant)}>
          <%= @role %>
        </p>
      </div>
    </div>
    """
  end

  defp external_link_button(assigns) do
    ~H"""
    <a
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      class={external_link_classes(@variant)}
    >
      <.link_icon type={@type} variant={@variant} />
      <span class="ml-2"><%= format_link_text(@type) %></span>
      <.icon name="hero-arrow-top-right-on-square" class="ml-2 h-3 w-3 opacity-60" />
    </a>
    """
  end

  defp link_icon(%{type: :tmdb_url} = assigns) do
    ~H"""
    <svg class="h-4 w-4" viewBox="0 0 24 24" fill="#01b4e4">
      <path d="M11.42 2c-4.05 0-7.34 3.28-7.34 7.33 0 4.05 3.29 7.33 7.34 7.33 4.05 0 7.33-3.28 7.33-7.33C18.75 5.28 15.47 2 11.42 2zM8.85 14.4l-1.34-2.8 2.59-5.4h1.93l-2.17 4.52L12.4 8.4h1.8l-2.59 5.4H9.68l2.17-4.52L9.31 11.6H7.51L8.85 14.4z"/>
    </svg>
    """
  end

  defp link_icon(%{type: :imdb_url} = assigns) do
    ~H"""
    <svg class="h-4 w-4" viewBox="0 0 24 24" fill="#f5c518">
      <path d="M14.31 9.588l.937 3.85c.096.39.12.723.073 1-.047.276-.165.51-.355.702s-.44.335-.756.423c-.316.088-.69.087-1.12-.003-.43-.09-.773-.24-1.028-.45s-.43-.47-.527-.783-.12-.673-.073-1.08l.96-3.93h1.89zm-4.81 4.05c.093.385.117.715.073.99-.044.276-.16.507-.348.693s-.434.327-.744.413c-.31.086-.683.084-1.118-.006-.435-.09-.782-.242-1.04-.456s-.435-.48-.534-.8-.125-.687-.082-1.1l.976-4h1.91l-.93 3.82c-.044.18-.037.33.02.45.058.12.154.18.29.18.136 0 .24-.06.31-.18s.12-.27.164-.45l.93-3.82h1.91l-.937 3.85c-.096.39-.12.723-.073 1-.047.276-.165.51-.355.702s-.44.335-.756.423c-.316.088-.69.087-1.12-.003zm7.52-4.05h1.91v4.65h-1.91V9.588zm-9.52 0h1.91v4.65H7.51V9.588z"/>
    </svg>
    """
  end

  defp link_icon(%{type: :homepage} = assigns) do
    ~H"<.icon name='hero-home' class='h-4 w-4' />"
  end

  defp link_icon(%{type: :facebook_url} = assigns) do
    ~H"<.icon name='hero-globe-alt' class='h-4 w-4 text-blue-600' />"
  end

  defp link_icon(%{type: :twitter_url} = assigns) do
    ~H"<.icon name='hero-globe-alt' class='h-4 w-4 text-blue-400' />"
  end

  defp link_icon(%{type: :instagram_url} = assigns) do
    ~H"<.icon name='hero-globe-alt' class='h-4 w-4 text-pink-600' />"
  end

  defp link_icon(assigns) do
    ~H"<.icon name='hero-globe-alt' class='h-4 w-4' />"
  end

  # CSS class helpers for variants

  defp section_container_classes(:card, false), do: "bg-white rounded-lg p-6 space-y-6 shadow-sm"
  defp section_container_classes(:card, true), do: "bg-white rounded-lg p-4 space-y-4 shadow-sm"

  defp section_container_classes(:dark, false),
    do: "bg-gray-900/50 backdrop-blur-sm rounded-lg p-6 space-y-6"

  defp section_container_classes(:dark, true),
    do: "bg-gray-900/50 backdrop-blur-sm rounded-lg p-4 space-y-4"

  defp section_title_classes(:card, false), do: "text-2xl font-bold text-gray-900 mb-4"
  defp section_title_classes(:card, true), do: "text-xl font-bold text-gray-900 mb-3"
  defp section_title_classes(:dark, false), do: "text-2xl font-bold text-white mb-4"
  defp section_title_classes(:dark, true), do: "text-xl font-bold text-white mb-3"

  defp overview_text_classes(:card, false), do: "text-gray-700 leading-relaxed text-lg"
  defp overview_text_classes(:card, true), do: "text-gray-700 leading-relaxed text-base"
  defp overview_text_classes(:dark, false), do: "text-gray-300 leading-relaxed text-lg"
  defp overview_text_classes(:dark, true), do: "text-gray-300 leading-relaxed text-base"

  defp subsection_title_classes(:card), do: "text-xl font-semibold text-gray-900 mb-4"
  defp subsection_title_classes(:dark), do: "text-xl font-semibold text-white mb-4"

  defp personnel_grid_classes(false),
    do: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"

  defp personnel_grid_classes(true), do: "grid grid-cols-1 sm:grid-cols-2 gap-3"

  defp person_card_classes(:card), do: "flex items-center space-x-3 p-3 bg-gray-50 rounded-lg"
  defp person_card_classes(:dark), do: "flex items-center space-x-3 p-3 bg-white/5 rounded-lg"

  defp person_image_classes(:card), do: "w-12 h-12 rounded-full object-cover flex-shrink-0"

  defp person_image_classes(:dark),
    do: "w-12 h-12 rounded-full object-cover flex-shrink-0 ring-1 ring-white/10"

  defp person_placeholder_classes(:card) do
    "w-12 h-12 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0"
  end

  defp person_placeholder_classes(:dark) do
    "w-12 h-12 rounded-full bg-gray-700 flex items-center justify-center flex-shrink-0"
  end

  defp person_initials_classes(:card), do: "text-sm font-bold text-gray-500"
  defp person_initials_classes(:dark), do: "text-sm font-bold text-gray-400"

  defp person_name_classes(:card), do: "text-sm font-medium text-gray-900 truncate"
  defp person_name_classes(:dark), do: "text-sm font-medium text-white truncate"

  defp person_role_classes(:card), do: "text-sm text-gray-500 truncate"
  defp person_role_classes(:dark), do: "text-sm text-gray-400 truncate"

  defp external_link_classes(:card) do
    [
      "inline-flex items-center px-3 py-2",
      "border border-gray-300 shadow-sm",
      "text-sm leading-4 font-medium rounded-md",
      "text-gray-700 bg-white hover:bg-gray-50",
      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500",
      "transition-colors"
    ]
  end

  defp external_link_classes(:dark) do
    [
      "inline-flex items-center px-3 py-2",
      "border border-white/20 bg-white/5 backdrop-blur-sm",
      "text-sm leading-4 font-medium rounded-md",
      "text-white hover:bg-white/10 hover:border-white/30",
      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500",
      "transition-colors"
    ]
  end

  # Private functions

  defp get_initials(nil), do: "?"

  defp get_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp get_initials(_), do: "?"

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    socket
    |> assign(:overview, rich_data["overview"])
    |> assign(:director, rich_data["director"])
    |> assign(:writers, get_writers(rich_data["crew"]))
    |> assign(:producers, get_producers(rich_data["crew"]))
    |> assign(:has_key_personnel, has_key_personnel?(rich_data))
    |> assign(:external_links, get_filtered_external_links(rich_data["external_links"]))
  end

  defp get_writers(nil), do: []

  defp get_writers(crew) when is_list(crew) do
    crew
    |> Enum.filter(&(&1["job"] in ["Writer", "Screenplay", "Story"]))
    # Limit to 3 writers
    |> Enum.take(3)
  end

  defp get_writers(_), do: []

  defp get_producers(nil), do: []

  defp get_producers(crew) when is_list(crew) do
    crew
    |> Enum.filter(&(&1["job"] in ["Producer", "Executive Producer"]))
    # Limit to 2 producers
    |> Enum.take(2)
  end

  defp get_producers(_), do: []

  defp has_key_personnel?(rich_data) do
    director = rich_data["director"]
    crew = rich_data["crew"] || []

    director != nil ||
      Enum.any?(
        crew,
        &(&1["job"] in ["Writer", "Screenplay", "Story", "Producer", "Executive Producer"])
      )
  end

  defp get_filtered_external_links(nil), do: %{}

  defp get_filtered_external_links(links) when is_map(links) do
    # Only include non-empty links, prioritize the most relevant ones
    links
    |> Enum.filter(fn {_key, value} -> value && value != "" end)
    |> Enum.into(%{})
  end

  defp get_filtered_external_links(_), do: %{}

  defp format_link_text(:tmdb_url), do: "TMDB"
  defp format_link_text(:imdb_url), do: "IMDb"
  defp format_link_text(:homepage), do: "Official Site"
  defp format_link_text(:facebook_url), do: "Facebook"
  defp format_link_text(:twitter_url), do: "Twitter"
  defp format_link_text(:instagram_url), do: "Instagram"
  defp format_link_text(_), do: "Website"
end
