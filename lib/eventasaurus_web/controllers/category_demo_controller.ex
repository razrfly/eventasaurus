defmodule EventasaurusWeb.CategoryDemoController do
  use EventasaurusWeb, :controller
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusDiscovery.Categories

  def index(conn, params) do
    # Get selected categories from params
    selected_categories = params["categories"] || []

    selected_categories =
      if is_list(selected_categories), do: selected_categories, else: [selected_categories]

    selected_categories = Enum.reject(selected_categories, &(&1 == ""))

    # Get all categories for filter
    all_categories = Categories.list_active_categories()

    # Get events based on filters
    events =
      if Enum.empty?(selected_categories) do
        # Get all recent events
        PublicEvents.recent_events(limit: 20)
      else
        # Filter by selected categories
        PublicEvents.by_categories(selected_categories, limit: 20)
      end

    # Get locale from params or default to "en"
    locale = params["locale"] || "en"

    render(conn, "index.html",
      events: events,
      categories: all_categories,
      selected_categories: selected_categories,
      locale: locale
    )
  end

  def show(conn, %{"id" => id}) do
    event = PublicEvents.get_public_event!(id)
    locale = conn.params["locale"] || "en"

    render(conn, "show.html",
      event: event,
      locale: locale
    )
  end
end
