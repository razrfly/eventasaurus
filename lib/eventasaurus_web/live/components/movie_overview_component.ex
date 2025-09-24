defmodule EventasaurusWeb.Live.Components.MovieOverviewComponent do
  @moduledoc """
  Overview section component for movie/TV show display.

  Displays the overview/synopsis and key personnel information
  like director, writers, and key crew members.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg p-6 space-y-6">
      <!-- Overview Section -->
      <%= if @overview do %>
        <div>
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Overview</h2>
          <p class="text-gray-700 leading-relaxed text-lg"><%= @overview %></p>
        </div>
      <% end %>

      <!-- Key Personnel -->
      <%= if @has_key_personnel do %>
        <div>
          <h3 class="text-xl font-semibold text-gray-900 mb-4">Key Personnel</h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= if @director do %>
              <.person_card
                person={@director}
                role="Director"
                compact={@compact}
              />
            <% end %>

            <%= for writer <- @writers do %>
              <.person_card
                person={writer}
                role={writer["job"]}
                compact={@compact}
              />
            <% end %>

            <%= for producer <- @producers do %>
              <.person_card
                person={producer}
                role={producer["job"]}
                compact={@compact}
              />
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- External Links -->
      <%= if @external_links && map_size(@external_links) > 0 do %>
        <div>
          <h3 class="text-xl font-semibold text-gray-900 mb-4">Links</h3>
          <div class="flex flex-wrap gap-3">
            <%= for {type, url} <- @external_links do %>
              <%= if url && url != "" do %>
                <.external_link_button type={type} url={url} />
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
    ~H"""
    <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
      <%= if @person["profile_path"] do %>
        <img
          src={RichDataDisplayComponent.tmdb_image_url(@person["profile_path"], "w185")}
          alt={@person["name"]}
          class="w-12 h-12 rounded-full object-cover flex-shrink-0"
          loading="lazy"
        />
      <% else %>
        <div class="w-12 h-12 rounded-full bg-gray-300 flex items-center justify-center flex-shrink-0">
          <.icon name="hero-user" class="w-6 h-6 text-gray-500" />
        </div>
      <% end %>

      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium text-gray-900 truncate">
          <%= @person["name"] %>
        </p>
        <p class="text-sm text-gray-500 truncate">
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
      class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
    >
      <.link_icon type={@type} />
      <span class="ml-2"><%= format_link_text(@type) %></span>
      <.icon name="hero-arrow-top-right-on-square" class="ml-2 h-3 w-3" />
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

  defp link_icon(%{type: type} = assigns)
       when type in [:facebook_url, :twitter_url, :instagram_url] do
    case type do
      :facebook_url -> ~H"<.icon name='hero-globe-alt' class='h-4 w-4 text-blue-600' />"
      :twitter_url -> ~H"<.icon name='hero-globe-alt' class='h-4 w-4 text-blue-400' />"
      :instagram_url -> ~H"<.icon name='hero-globe-alt' class='h-4 w-4 text-pink-600' />"
    end
  end

  defp link_icon(assigns) do
    ~H"<.icon name='hero-globe-alt' class='h-4 w-4' />"
  end

  # Private functions

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
