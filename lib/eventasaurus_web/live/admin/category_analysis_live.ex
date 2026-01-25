defmodule EventasaurusWeb.Admin.CategoryAnalysisLive do
  @moduledoc """
  LiveView for analyzing events in the "Other" category.
  Shows detailed breakdown of uncategorized events with metadata for improvement analysis.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Admin.PatternAnalyzer
  import Ecto.Query

  @impl true
  def mount(%{"source_slug" => source_slug}, _session, socket) do
    # Load source info
    source = get_source(source_slug)

    if source do
      socket =
        socket
        |> assign(:source, source)
        |> assign(:source_slug, source_slug)
        |> assign(:loading, true)
        |> assign(:other_events, [])
        |> assign(:total_events, 0)
        |> assign(:other_count, 0)
        |> assign(:percentage, 0.0)
        |> assign(:patterns, nil)
        |> assign(:suggestions, [])
        |> assign(:available_categories, [])

      # Load data asynchronously
      if connected?(socket) do
        send(self(), :load_data)
      end

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Source not found")
       |> redirect(to: ~p"/admin/monitoring")}
    end
  end

  @impl true
  def handle_event("copy_yaml", %{"yaml" => _yaml}, socket) do
    {:noreply, socket |> put_flash(:info, "YAML copied to clipboard!")}
  end

  @impl true
  def handle_info(:load_data, socket) do
    source = socket.assigns.source

    # Get total events for this source
    total_events = count_total_events(source.id)

    # Get "Other" category events with full metadata
    other_events = get_other_events(source.id)
    other_count = length(other_events)

    percentage =
      if total_events > 0 do
        Float.round(other_count / total_events * 100, 1)
      else
        0.0
      end

    # Analyze patterns in the other events
    patterns =
      if other_count > 0 do
        PatternAnalyzer.analyze_patterns(other_events)
      else
        nil
      end

    # Get available categories for suggestions
    available_categories = get_available_categories()

    # Generate suggestions based on patterns
    suggestions =
      if patterns do
        PatternAnalyzer.generate_suggestions(patterns, available_categories)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:other_events, other_events)
     |> assign(:total_events, total_events)
     |> assign(:other_count, other_count)
     |> assign(:percentage, percentage)
     |> assign(:patterns, patterns)
     |> assign(:suggestions, suggestions)
     |> assign(:available_categories, available_categories)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">
            Category Analysis: <%= @source.name %>
          </h1>
          <p class="mt-2 text-sm text-gray-600">
            Analyzing events categorized as "Other" for improvement opportunities
          </p>
        </div>
        <.link
          navigate={~p"/admin/monitoring/sources/#{@source_slug}"}
          class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
        >
          ← Back to Source
        </.link>
      </div>

      <%= if @loading do %>
        <!-- Loading State -->
        <div class="bg-white rounded-lg shadow p-12 text-center">
          <div class="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
          <p class="mt-4 text-gray-600">Loading event data...</p>
        </div>
      <% else %>
        <!-- Summary Stats -->
        <div class="bg-white rounded-lg shadow overflow-hidden">
          <div class="px-6 py-5 border-b border-gray-200">
            <h2 class="text-lg font-medium text-gray-900">Summary Statistics</h2>
          </div>
          <div class="px-6 py-5">
            <dl class="grid grid-cols-1 gap-5 sm:grid-cols-3">
              <div class="px-4 py-5 bg-gray-50 shadow rounded-lg overflow-hidden sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Total Events</dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900"><%= @total_events %></dd>
              </div>

              <div class="px-4 py-5 bg-yellow-50 shadow rounded-lg overflow-hidden sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">"Other" Events</dt>
                <dd class="mt-1 text-3xl font-semibold text-yellow-900"><%= @other_count %></dd>
              </div>

              <div class="px-4 py-5 bg-red-50 shadow rounded-lg overflow-hidden sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Percentage</dt>
                <dd class="mt-1 text-3xl font-semibold text-red-900"><%= @percentage %>%</dd>
                <dd class="mt-1 text-sm text-gray-600">
                  Target: &lt;10% (<%=
                    if @percentage < 10, do: "✓ Good", else: "✗ Needs improvement"
                  %>)
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <%= if @other_count > 0 do %>
          <!-- Pattern Analysis Section -->
          <%= if @patterns do %>
            <!-- Suggested Mappings -->
            <%= if length(@suggestions) > 0 do %>
              <div class="bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg shadow-lg overflow-hidden">
                <div class="px-6 py-5 border-b border-indigo-200 bg-white bg-opacity-50">
                  <h2 class="text-lg font-bold text-indigo-900 flex items-center">
                    <span class="text-2xl mr-2">💡</span>
                    Suggested Category Mappings
                  </h2>
                  <p class="mt-1 text-sm text-indigo-700">
                    Based on pattern analysis, these mappings would categorize <%= Enum.sum(Enum.map(@suggestions, & &1.event_count)) %> of <%= @other_count %> events
                    (<%= Float.round(Enum.sum(Enum.map(@suggestions, & &1.event_count)) / @other_count * 100, 1) %>% improvement)
                  </p>
                </div>
                <div class="px-6 py-6 space-y-6">
                  <%= for suggestion <- @suggestions do %>
                    <div class="bg-white rounded-lg border-2 border-indigo-200 shadow-sm p-6">
                      <div class="flex items-start justify-between mb-4">
                        <div>
                          <h3 class="text-xl font-bold text-gray-900"><%= suggestion.category %></h3>
                          <div class="mt-2 flex items-center space-x-4 text-sm">
                            <span class={["inline-flex items-center px-3 py-1 rounded-full text-xs font-medium", confidence_badge_class(suggestion.confidence)]}>
                              <%= confidence_label(suggestion.confidence) %> Confidence
                            </span>
                            <span class="text-gray-600">
                              Would categorize <span class="font-semibold text-indigo-600"><%= suggestion.event_count %></span> events
                            </span>
                          </div>
                        </div>
                      </div>

                      <div class="space-y-4">
                        <%= if length(suggestion.url_patterns) > 0 do %>
                          <div>
                            <h4 class="text-sm font-semibold text-gray-700 mb-2">🔗 URL Patterns:</h4>
                            <div class="flex flex-wrap gap-2">
                              <%= for pattern <- suggestion.url_patterns do %>
                                <code class="px-3 py-1 bg-gray-100 text-gray-800 rounded text-sm font-mono">/<%= pattern %>/</code>
                              <% end %>
                            </div>
                          </div>
                        <% end %>

                        <%= if length(suggestion.keywords) > 0 do %>
                          <div>
                            <h4 class="text-sm font-semibold text-gray-700 mb-2">🏷️ Keywords:</h4>
                            <div class="flex flex-wrap gap-2">
                              <%= for keyword <- suggestion.keywords do %>
                                <span class="px-3 py-1 bg-blue-100 text-blue-800 rounded text-sm"><%= keyword %></span>
                              <% end %>
                            </div>
                          </div>
                        <% end %>

                        <div>
                          <h4 class="text-sm font-semibold text-gray-700 mb-2">📝 YAML Snippet:</h4>
                          <div class="relative">
                            <pre class="bg-gray-900 text-gray-100 p-4 rounded-lg text-sm font-mono overflow-x-auto"><%= suggestion.yaml %></pre>
                            <button
                              phx-click="copy_yaml"
                              phx-value-yaml={suggestion.yaml}
                              class="absolute top-2 right-2 px-3 py-1 bg-indigo-600 hover:bg-indigo-700 text-white text-xs rounded transition"
                            >
                              Copy
                            </button>
                          </div>
                        </div>

                        <%= if length(suggestion.sample_events) > 0 do %>
                          <div>
                            <h4 class="text-sm font-semibold text-gray-700 mb-2">📋 Sample Events:</h4>
                            <ul class="text-sm text-gray-600 space-y-1">
                              <%= for event <- suggestion.sample_events do %>
                                <li class="truncate">• <%= event.title %></li>
                              <% end %>
                            </ul>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Pattern Frequency Tables -->
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <!-- URL Patterns -->
              <%= if length(@patterns.url_patterns) > 0 do %>
                <div class="bg-white rounded-lg shadow overflow-hidden">
                  <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
                    <h3 class="text-lg font-semibold text-gray-900">🔗 Top URL Patterns</h3>
                    <p class="text-sm text-gray-600 mt-1">Most common URL path segments</p>
                  </div>
                  <div class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-gray-200">
                      <thead class="bg-gray-50">
                        <tr>
                          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Pattern</th>
                          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Count</th>
                          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">%</th>
                        </tr>
                      </thead>
                      <tbody class="bg-white divide-y divide-gray-200">
                        <%= for pattern <- Enum.take(@patterns.url_patterns, 10) do %>
                          <tr class="hover:bg-gray-50">
                            <td class="px-6 py-4 whitespace-nowrap">
                              <code class="text-sm font-mono text-indigo-600">/<%= pattern.pattern %>/</code>
                            </td>
                            <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-900 font-medium">
                              <%= pattern.count %>
                            </td>
                            <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-500">
                              <%= pattern.percentage %>%
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              <% end %>

              <!-- Title Keywords -->
              <%= if length(@patterns.title_keywords) > 0 do %>
                <div class="bg-white rounded-lg shadow overflow-hidden">
                  <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
                    <h3 class="text-lg font-semibold text-gray-900">🏷️ Top Title Keywords</h3>
                    <p class="text-sm text-gray-600 mt-1">Most frequent words in event titles</p>
                  </div>
                  <div class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-gray-200">
                      <thead class="bg-gray-50">
                        <tr>
                          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Keyword</th>
                          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Count</th>
                          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">%</th>
                        </tr>
                      </thead>
                      <tbody class="bg-white divide-y divide-gray-200">
                        <%= for keyword <- Enum.take(@patterns.title_keywords, 10) do %>
                          <tr class="hover:bg-gray-50">
                            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                              <%= keyword.keyword %>
                            </td>
                            <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-900 font-medium">
                              <%= keyword.count %>
                            </td>
                            <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-500">
                              <%= keyword.percentage %>%
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Venue Type Distribution -->
            <%= if length(@patterns.venue_types) > 0 do %>
              <div class="bg-white rounded-lg shadow overflow-hidden">
                <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
                  <h3 class="text-lg font-semibold text-gray-900">🏛️ Venue Type Distribution</h3>
                  <p class="text-sm text-gray-600 mt-1">Common venue types for uncategorized events</p>
                </div>
                <div class="p-6">
                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    <%= for venue_type <- @patterns.venue_types do %>
                      <div class="bg-gray-50 rounded-lg p-4 border border-gray-200">
                        <div class="text-sm font-medium text-gray-700"><%= venue_type.venue_type %></div>
                        <div class="mt-2 flex items-baseline">
                          <span class="text-2xl font-bold text-indigo-600"><%= venue_type.count %></span>
                          <span class="ml-2 text-sm text-gray-500">events (<%= venue_type.percentage %>%)</span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>

          <!-- Events List -->
          <div class="bg-white rounded-lg shadow overflow-hidden">
            <div class="px-6 py-5 border-b border-gray-200">
              <h2 class="text-lg font-medium text-gray-900">
                Events Categorized as "Other" (<%= @other_count %>)
              </h2>
              <p class="mt-1 text-sm text-gray-600">
                Review these events to identify patterns for YAML mapping improvements
              </p>
            </div>

            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                    >
                      Event
                    </th>
                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                    >
                      Venue
                    </th>
                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                    >
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for event <- @other_events do %>
                    <tr class="hover:bg-gray-50">
                      <td class="px-6 py-4">
                        <div class="text-sm font-medium text-gray-900 max-w-md">
                          <%= event.title %>
                        </div>
                      </td>
                      <td class="px-6 py-4">
                        <%= if event.venue_name do %>
                          <div class="text-sm text-gray-900"><%= event.venue_name %></div>
                          <%= if event.venue_type do %>
                            <div class="text-xs text-gray-500"><%= event.venue_type %></div>
                          <% end %>
                        <% else %>
                          <span class="text-sm text-gray-400">No venue</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= if event.source_url do %>
                          <a
                            href={event.source_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-indigo-600 hover:text-indigo-900"
                          >
                            View Source →
                          </a>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Improvement Suggestions -->
          <div class="bg-blue-50 rounded-lg shadow p-6">
            <h3 class="text-lg font-medium text-blue-900 mb-4">💡 Next Steps</h3>
            <div class="space-y-3 text-sm text-blue-800">
              <div class="flex items-start">
                <span class="font-bold mr-2">1.</span>
                <span>
                  Review the URL categories and event titles to identify common patterns
                </span>
              </div>
              <div class="flex items-start">
                <span class="font-bold mr-2">2.</span>
                <span>
                  Check <code class="bg-blue-100 px-1 rounded">priv/category_mappings/<%= @source_slug %>.yml</code>
                  for missing mappings
                </span>
              </div>
              <div class="flex items-start">
                <span class="font-bold mr-2">3.</span>
                <span>
                  Add new mappings or patterns to the YAML file based on identified themes
                </span>
              </div>
              <div class="flex items-start">
                <span class="font-bold mr-2">4.</span>
                <span>
                  Run <code class="bg-blue-100 px-1 rounded">mix eventasaurus.recategorize_events --source <%= @source_slug %></code>
                  to apply changes
                </span>
              </div>
              <div class="flex items-start">
                <span class="font-bold mr-2">5.</span>
                <span>
                  Return to this page to verify improvement and iterate if needed
                </span>
              </div>
            </div>
          </div>
        <% else %>
          <!-- No "Other" Events -->
          <div class="bg-green-50 rounded-lg shadow p-12 text-center">
            <div class="text-6xl mb-4">✅</div>
            <h3 class="text-lg font-medium text-green-900">Excellent Categorization!</h3>
            <p class="mt-2 text-sm text-green-700">
              No events are categorized as "Other". All events have specific categories assigned.
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp get_source(slug) do
    query =
      from(s in EventasaurusDiscovery.Sources.Source,
        where: s.slug == ^slug,
        select: %{id: s.id, name: s.name, slug: s.slug}
      )

    Repo.replica().one(query)
  end

  defp count_total_events(source_id) do
    query =
      from(e in PublicEvent,
        join: pes in assoc(e, :sources),
        where: pes.source_id == ^source_id,
        select: count(fragment("DISTINCT ?", e.id))
      )

    Repo.replica().one(query) || 0
  end

  defp get_other_events(source_id) do
    # Get the "Other" category ID
    other_category_id =
      Repo.replica().one(
        from(c in Category,
          where: c.slug == "other" and c.is_active == true,
          select: c.id,
          limit: 1
        )
      )

    if other_category_id do
      query =
        from(e in PublicEvent,
          join: pes in assoc(e, :sources),
          join: pec in "public_event_categories",
          on: pec.event_id == e.id,
          left_join: v in "venues",
          on: v.id == e.venue_id,
          where: pes.source_id == ^source_id,
          where: pec.category_id == ^other_category_id,
          distinct: [e.id],
          select: %{
            id: e.id,
            title: e.title,
            source_url: pes.source_url,
            venue_name: v.name,
            venue_type: v.venue_type,
            inserted_at: e.inserted_at
          },
          order_by: [asc: e.id, desc: e.inserted_at],
          limit: 500
        )

      Repo.replica().all(query)
    else
      []
    end
  end

  defp get_available_categories do
    query =
      from(c in Category,
        where: c.is_active == true and c.slug != "other",
        select: %{id: c.id, name: c.name, slug: c.slug},
        order_by: c.name
      )

    Repo.replica().all(query)
  end

  defp confidence_badge_class(:high), do: "bg-green-100 text-green-800"
  defp confidence_badge_class(:medium), do: "bg-yellow-100 text-yellow-800"
  defp confidence_badge_class(:low), do: "bg-gray-100 text-gray-800"

  defp confidence_label(:high), do: "High"
  defp confidence_label(:medium), do: "Medium"
  defp confidence_label(:low), do: "Low"
end
