defmodule EventasaurusWeb.Admin.VenuePairReviewLive do
  @moduledoc """
  Pair-based duplicate venue review workflow.

  Features:
  - Review one duplicate pair at a time
  - Side-by-side venue comparison with confidence scoring
  - Merge in either direction or mark as not duplicates
  - Skip to defer decision
  - Progress tracking through pairs
  - Filter by confidence level
  """
  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusApp.Venues.VenueDeduplication
  alias EventasaurusApp.Repo

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Review Duplicate Pairs")
      |> assign(:city, nil)
      |> assign(:pairs, [])
      |> assign(:current_index, 0)
      |> assign(:current_pair, nil)
      |> assign(:total_pairs, 0)
      |> assign(:confidence_filter, "all")
      |> assign(:loading, true)
      |> assign(:recent_merges, [])
      |> assign(:current_user_id, get_user_id(session))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Only load data when connected (after WebSocket established)
    # During static render, just show loading state
    socket =
      if connected?(socket) do
        Logger.info("VenuePairReviewLive: Starting handle_params (connected)")

        socket
        |> load_city(params)
        |> apply_confidence_filter(params)
        |> load_pairs()
        |> apply_index(params)
      else
        socket
      end

    {:noreply, socket}
  end

  # Load city from slug parameter
  defp load_city(socket, %{"city" => city_slug}) when is_binary(city_slug) do
    case Repo.get_by(EventasaurusDiscovery.Locations.City, slug: city_slug) do
      nil ->
        socket
        |> put_flash(:error, "City '#{city_slug}' not found")
        |> assign(:city, nil)

      city ->
        assign(socket, :city, city)
    end
  end

  defp load_city(socket, _params) do
    socket
    |> put_flash(:error, "City parameter required")
    |> assign(:city, nil)
  end

  # Apply confidence filter from URL
  defp apply_confidence_filter(socket, %{"confidence" => filter})
       when filter in ["all", "high", "medium", "low"] do
    assign(socket, :confidence_filter, filter)
  end

  defp apply_confidence_filter(socket, _params), do: socket

  # Load pairs for the city
  defp load_pairs(%{assigns: %{city: nil}} = socket) do
    socket
    |> assign(:pairs, [])
    |> assign(:total_pairs, 0)
    |> assign(:loading, false)
  end

  defp load_pairs(%{assigns: %{city: city, confidence_filter: filter}} = socket) do
    pairs = VenueDeduplication.find_duplicate_pairs([city.id], limit: 100)

    # Preload city_ref for venue display - pairs from raw SQL don't have it loaded
    pairs_with_cities = preload_venue_cities(pairs)

    filtered_pairs = filter_by_confidence(pairs_with_cities, filter)

    socket
    |> assign(:pairs, filtered_pairs)
    |> assign(:total_pairs, length(filtered_pairs))
    |> assign(:loading, false)
    |> load_recent_merges()
  end

  # Preload city_ref for all venues in pairs (they come from raw SQL without associations)
  defp preload_venue_cities(pairs) do
    # Collect all unique city_ids
    city_ids =
      pairs
      |> Enum.flat_map(fn p -> [p.venue_a.city_id, p.venue_b.city_id] end)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    # Batch load cities
    cities_map =
      if Enum.empty?(city_ids) do
        %{}
      else
        import Ecto.Query
        from(c in EventasaurusDiscovery.Locations.City, where: c.id in ^city_ids)
        |> Repo.all()
        |> Map.new(fn city -> {city.id, city} end)
      end

    # Attach cities to venues
    Enum.map(pairs, fn pair ->
      venue_a = Map.put(pair.venue_a, :city_ref, Map.get(cities_map, pair.venue_a.city_id))
      venue_b = Map.put(pair.venue_b, :city_ref, Map.get(cities_map, pair.venue_b.city_id))
      %{pair | venue_a: venue_a, venue_b: venue_b}
    end)
  end

  defp filter_by_confidence(pairs, "all"), do: pairs

  defp filter_by_confidence(pairs, "high") do
    Enum.filter(pairs, &(&1.confidence >= 0.8))
  end

  defp filter_by_confidence(pairs, "medium") do
    Enum.filter(pairs, &(&1.confidence >= 0.5 and &1.confidence < 0.8))
  end

  defp filter_by_confidence(pairs, "low") do
    Enum.filter(pairs, &(&1.confidence < 0.5))
  end

  # Apply index from URL
  defp apply_index(%{assigns: %{pairs: pairs, total_pairs: total}} = socket, params) do
    index =
      case params["index"] do
        nil -> 0
        str -> min(max(String.to_integer(str), 0), max(total - 1, 0))
      end

    current_pair = Enum.at(pairs, index)

    socket
    |> assign(:current_index, index)
    |> assign(:current_pair, current_pair)
  end

  defp load_recent_merges(%{assigns: %{city: city}} = socket) when not is_nil(city) do
    merges = VenueDeduplication.list_recent_merges(limit: 5)
    assign(socket, :recent_merges, merges)
  end

  defp load_recent_merges(socket), do: socket

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("navigate", %{"direction" => direction}, socket) do
    %{current_index: index, total_pairs: total, city: city, confidence_filter: filter} =
      socket.assigns

    new_index =
      case direction do
        "next" -> min(index + 1, max(total - 1, 0))
        "prev" -> max(index - 1, 0)
        "first" -> 0
        "last" -> max(total - 1, 0)
      end

    {:noreply, push_patch(socket, to: review_path(city.slug, new_index, filter))}
  end

  @impl true
  def handle_event("filter_confidence", %{"confidence" => filter}, socket) do
    %{city: city} = socket.assigns
    {:noreply, push_patch(socket, to: review_path(city.slug, 0, filter))}
  end

  @impl true
  def handle_event("skip", _params, socket) do
    # Skip just moves to next pair
    handle_event("navigate", %{"direction" => "next"}, socket)
  end

  @impl true
  def handle_event("merge", %{"source_id" => source_id, "target_id" => target_id}, socket) do
    source_id = String.to_integer(source_id)
    target_id = String.to_integer(target_id)

    %{current_pair: pair, current_user_id: user_id} = socket.assigns

    opts = [
      user_id: user_id,
      reason: "pair_review_merge",
      similarity_score: pair && pair.similarity,
      distance_meters: pair && pair.distance
    ]

    case VenueDeduplication.merge_venues(source_id, target_id, opts) do
      {:ok, %{target_venue: target, audit: audit}} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Merged into #{target.name}. #{audit.events_reassigned} events transferred."
          )
          |> reload_and_advance()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Merge failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("exclude", _params, socket) do
    %{current_pair: pair, current_user_id: user_id} = socket.assigns

    case VenueDeduplication.exclude_pair(pair.venue_a.id, pair.venue_b.id,
           user_id: user_id,
           reason: "pair_review_not_duplicate"
         ) do
      {:ok, _exclusion} ->
        socket =
          socket
          |> put_flash(:info, "Marked as not duplicates. They won't appear again.")
          |> reload_and_advance()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to exclude: #{inspect(reason)}")}
    end
  end

  # Reload pairs after an action and advance to next pair
  defp reload_and_advance(socket) do
    %{city: city, confidence_filter: filter, current_index: index} = socket.assigns

    # Reload pairs
    pairs = VenueDeduplication.find_duplicate_pairs([city.id], limit: 100)
    filtered_pairs = filter_by_confidence(pairs, filter)
    total = length(filtered_pairs)

    # Stay at same index if there are still pairs, otherwise go back
    new_index = min(index, max(total - 1, 0))
    current_pair = Enum.at(filtered_pairs, new_index)

    socket
    |> assign(:pairs, filtered_pairs)
    |> assign(:total_pairs, total)
    |> assign(:current_index, new_index)
    |> assign(:current_pair, current_pair)
    |> load_recent_merges()
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp review_path(city_slug, index, filter) do
    params =
      %{city: city_slug, index: index}
      |> maybe_add_filter(filter)

    ~p"/admin/venues/duplicates/review?#{params}"
  end

  defp maybe_add_filter(params, "all"), do: params
  defp maybe_add_filter(params, filter), do: Map.put(params, :confidence, filter)

  defp get_user_id(session) do
    case session do
      %{"current_user_id" => id} -> id
      _ -> nil
    end
  end

  defp format_distance(nil), do: "Unknown"
  defp format_distance(meters) when meters < 1000, do: "#{round(meters)}m"
  defp format_distance(meters), do: "#{Float.round(meters / 1000, 1)}km"

  defp confidence_level(confidence) when confidence >= 0.8, do: :high
  defp confidence_level(confidence) when confidence >= 0.5, do: :medium
  defp confidence_level(_), do: :low

  defp confidence_color(:high), do: "text-red-600 bg-red-100"
  defp confidence_color(:medium), do: "text-yellow-600 bg-yellow-100"
  defp confidence_color(:low), do: "text-gray-600 bg-gray-100"

  defp confidence_label(:high), do: "High"
  defp confidence_label(:medium), do: "Medium"
  defp confidence_label(:low), do: "Low"

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6">
      <!-- Header -->
      <div class="mb-6">
        <%= if @city do %>
          <.link
            navigate={~p"/admin/cities/#{@city.slug}/health"}
            class="text-blue-600 hover:text-blue-800 flex items-center gap-1 mb-2"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to City Health
          </.link>
        <% else %>
          <.link
            navigate={~p"/admin/cities/health"}
            class="text-blue-600 hover:text-blue-800 flex items-center gap-1 mb-2"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Cities
          </.link>
        <% end %>

        <h1 class="text-2xl font-bold text-gray-900">
          <%= if @city, do: "#{@city.name} Duplicate Review", else: "Duplicate Review" %>
        </h1>
      </div>

      <%= if @loading do %>
        <div class="text-center py-12">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
          <p class="mt-2 text-gray-600">Loading pairs...</p>
        </div>
      <% else %>
        <%= if @city == nil do %>
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
            <p class="text-yellow-800">Please select a city to review duplicates.</p>
          </div>
        <% else %>
          <!-- Progress and Filters -->
          <div class="bg-white rounded-lg shadow-sm border p-4 mb-6">
            <div class="flex items-center justify-between flex-wrap gap-4">
              <!-- Progress -->
              <div class="flex items-center gap-4">
                <span class="text-gray-600">
                  <%= if @total_pairs > 0 do %>
                    Pair <span class="font-semibold"><%= @current_index + 1 %></span>
                    of <span class="font-semibold"><%= @total_pairs %></span>
                  <% else %>
                    No pairs to review
                  <% end %>
                </span>

                <%= if @total_pairs > 0 do %>
                  <div class="w-32 bg-gray-200 rounded-full h-2">
                    <div
                      class="bg-blue-600 h-2 rounded-full transition-all"
                      style={"width: #{(@current_index + 1) / @total_pairs * 100}%"}
                    >
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Confidence Filter -->
              <div class="flex items-center gap-2">
                <span class="text-sm text-gray-600">Filter:</span>
                <div class="flex rounded-lg border overflow-hidden">
                  <%= for {label, value} <- [{"All", "all"}, {"High", "high"}, {"Medium", "medium"}, {"Low", "low"}] do %>
                    <button
                      phx-click="filter_confidence"
                      phx-value-confidence={value}
                      class={"px-3 py-1 text-sm #{if @confidence_filter == value, do: "bg-blue-600 text-white", else: "bg-white text-gray-700 hover:bg-gray-50"}"}
                    >
                      <%= label %>
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <%= if @current_pair do %>
            <!-- Confidence Badge -->
            <div class="mb-4 flex items-center gap-4">
              <% level = confidence_level(@current_pair.confidence) %>
              <span class={"px-3 py-1 rounded-full text-sm font-medium #{confidence_color(level)}"}>
                <%= confidence_label(level) %> Confidence (<%= Float.round(@current_pair.confidence * 100, 0) %>%)
              </span>
              <span class="text-gray-600">
                Distance: <%= format_distance(@current_pair.distance) %>
              </span>
              <span class="text-gray-600">
                Similarity: <%= Float.round(@current_pair.similarity * 100, 0) %>%
              </span>
            </div>

            <!-- Side-by-side Comparison -->
            <div class="grid grid-cols-2 gap-6 mb-6">
              <!-- Venue A -->
              <.venue_card
                venue={@current_pair.venue_a}
                event_count={@current_pair.event_count_a}
                label="A"
              />

              <!-- Venue B -->
              <.venue_card
                venue={@current_pair.venue_b}
                event_count={@current_pair.event_count_b}
                label="B"
              />
            </div>

            <!-- Action Buttons -->
            <div class="bg-white rounded-lg shadow-sm border p-6">
              <div class="flex flex-wrap items-center justify-center gap-4">
                <!-- Merge B into A -->
                <button
                  phx-click="merge"
                  phx-value-source_id={@current_pair.venue_b.id}
                  phx-value-target_id={@current_pair.venue_a.id}
                  class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 flex items-center gap-2"
                  data-confirm={"Merge \"#{@current_pair.venue_b.name}\" into \"#{@current_pair.venue_a.name}\"? This will transfer #{@current_pair.event_count_b} events."}
                >
                  <.icon name="hero-arrow-left" class="w-4 h-4" />
                  Keep A, Merge B → A
                </button>

                <!-- Merge A into B -->
                <button
                  phx-click="merge"
                  phx-value-source_id={@current_pair.venue_a.id}
                  phx-value-target_id={@current_pair.venue_b.id}
                  class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 flex items-center gap-2"
                  data-confirm={"Merge \"#{@current_pair.venue_a.name}\" into \"#{@current_pair.venue_b.name}\"? This will transfer #{@current_pair.event_count_a} events."}
                >
                  Keep B, Merge A → B
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                </button>

                <div class="w-px h-8 bg-gray-300"></div>

                <!-- Not Duplicates -->
                <button
                  phx-click="exclude"
                  class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 flex items-center gap-2"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                  Not Duplicates
                </button>

                <!-- Skip -->
                <button
                  phx-click="skip"
                  class="px-4 py-2 bg-white border text-gray-600 rounded-lg hover:bg-gray-50 flex items-center gap-2"
                >
                  Skip for Now
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- Navigation -->
            <div class="flex items-center justify-between mt-6">
              <button
                phx-click="navigate"
                phx-value-direction="prev"
                disabled={@current_index == 0}
                class={"px-4 py-2 rounded-lg flex items-center gap-2 #{if @current_index == 0, do: "bg-gray-100 text-gray-400 cursor-not-allowed", else: "bg-white border text-gray-700 hover:bg-gray-50"}"}
              >
                <.icon name="hero-chevron-left" class="w-4 h-4" />
                Previous
              </button>

              <div class="flex items-center gap-2">
                <button
                  phx-click="navigate"
                  phx-value-direction="first"
                  disabled={@current_index == 0}
                  class={"px-3 py-1 text-sm rounded #{if @current_index == 0, do: "text-gray-400 cursor-not-allowed", else: "text-blue-600 hover:bg-blue-50"}"}
                >
                  First
                </button>
                <button
                  phx-click="navigate"
                  phx-value-direction="last"
                  disabled={@current_index >= @total_pairs - 1}
                  class={"px-3 py-1 text-sm rounded #{if @current_index >= @total_pairs - 1, do: "text-gray-400 cursor-not-allowed", else: "text-blue-600 hover:bg-blue-50"}"}
                >
                  Last
                </button>
              </div>

              <button
                phx-click="navigate"
                phx-value-direction="next"
                disabled={@current_index >= @total_pairs - 1}
                class={"px-4 py-2 rounded-lg flex items-center gap-2 #{if @current_index >= @total_pairs - 1, do: "bg-gray-100 text-gray-400 cursor-not-allowed", else: "bg-white border text-gray-700 hover:bg-gray-50"}"}
              >
                Next
                <.icon name="hero-chevron-right" class="w-4 h-4" />
              </button>
            </div>
          <% else %>
            <!-- No Pairs -->
            <div class="bg-green-50 border border-green-200 rounded-lg p-8 text-center">
              <.icon name="hero-check-circle" class="w-12 h-12 text-green-600 mx-auto mb-4" />
              <h2 class="text-lg font-semibold text-green-800 mb-2">All Done!</h2>
              <p class="text-green-700">
                <%= if @confidence_filter != "all" do %>
                  No <%= @confidence_filter %> confidence pairs remaining.
                  <button
                    phx-click="filter_confidence"
                    phx-value-confidence="all"
                    class="text-blue-600 hover:underline"
                  >
                    Show all pairs
                  </button>
                <% else %>
                  No duplicate pairs found for <%= @city.name %>.
                <% end %>
              </p>
            </div>
          <% end %>

          <!-- Recent Activity -->
          <%= if length(@recent_merges) > 0 do %>
            <div class="mt-8 bg-white rounded-lg shadow-sm border p-4">
              <h3 class="text-sm font-medium text-gray-700 mb-3">Recent Activity</h3>
              <ul class="space-y-2 text-sm text-gray-600">
                <%= for merge <- @recent_merges do %>
                  <li class="flex items-center gap-2">
                    <.icon name="hero-check-circle" class="w-4 h-4 text-green-500" />
                    Merged "<%= merge.source_venue_name %>" → "<%= merge.target_venue_name %>"
                    <span class="text-gray-400">
                      (<%= merge.events_reassigned %> events,
                      <%= Timex.from_now(merge.merged_at) %>)
                    </span>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Venue Card Component
  attr :venue, :map, required: true
  attr :event_count, :integer, required: true
  attr :label, :string, required: true

  defp venue_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border p-6">
      <div class="flex items-start justify-between mb-4">
        <span class="px-2 py-1 bg-gray-100 text-gray-600 text-xs font-medium rounded">
          VENUE <%= @label %>
        </span>
        <span class="text-sm text-gray-500">ID: <%= @venue.id %></span>
      </div>

      <h3 class="text-lg font-semibold text-gray-900 mb-2"><%= @venue.name %></h3>

      <div class="space-y-2 text-sm text-gray-600">
        <%= if @venue.address do %>
          <div class="flex items-start gap-2">
            <.icon name="hero-map-pin" class="w-4 h-4 text-gray-400 mt-0.5" />
            <span><%= @venue.address %></span>
          </div>
        <% end %>

        <%= if @venue.city_ref && is_map(@venue.city_ref) && Map.has_key?(@venue.city_ref, :name) do %>
          <div class="flex items-center gap-2">
            <.icon name="hero-building-office-2" class="w-4 h-4 text-gray-400" />
            <span><%= @venue.city_ref.name %></span>
          </div>
        <% end %>

        <div class="flex items-center gap-2">
          <.icon name="hero-calendar" class="w-4 h-4 text-gray-400" />
          <span><%= @event_count %> events</span>
        </div>

        <%= if @venue.latitude && @venue.longitude do %>
          <div class="flex items-center gap-2">
            <.icon name="hero-globe-alt" class="w-4 h-4 text-gray-400" />
            <span class="font-mono text-xs">
              <%= Float.round(@venue.latitude, 4) %>, <%= Float.round(@venue.longitude, 4) %>
            </span>
          </div>
        <% end %>

        <div class="flex items-center gap-2">
          <.icon name="hero-link" class="w-4 h-4 text-gray-400" />
          <span class="font-mono text-xs"><%= @venue.slug %></span>
        </div>

        <%= if @venue.inserted_at do %>
          <div class="flex items-center gap-2 text-gray-400">
            <.icon name="hero-clock" class="w-4 h-4" />
            <span>Created <%= Calendar.strftime(@venue.inserted_at, "%Y-%m-%d") %></span>
          </div>
        <% end %>
      </div>

      <div class="mt-4 pt-4 border-t">
        <.link
          href={~p"/admin/venues/duplicates?venue_id=#{@venue.id}"}
          class="text-blue-600 hover:text-blue-800 text-sm"
        >
          View all duplicates for this venue →
        </.link>
      </div>
    </div>
    """
  end
end
