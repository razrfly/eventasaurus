defmodule EventasaurusDiscovery.CategoryAnalytics do
  @moduledoc """
  Analytics and statistics for the category system.
  Provides summary metrics, distribution data, and top categories for the admin dashboard.
  """

  import Ecto.Query
  alias EventasaurusDiscovery.Categories.{Category, PublicEventCategory}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Repo

  @doc """
  Returns summary statistics for the category system.

  Returns a map with:
  - total_categories: Count of all categories
  - active_categories: Count of active categories
  - total_categorized_events: Events with at least one category
  - total_events: All public events
  - avg_categories_per_event: Average number of categories per categorized event
  - other_category_percentage: Percentage of events in "Other" category
  - uncategorized_count: Events with no category assigned
  """
  def summary_stats do
    total_categories = count_categories()
    active_categories = count_active_categories()
    total_events = count_total_events()
    categorized_events = count_categorized_events()
    uncategorized_count = total_events - categorized_events
    other_percentage = calculate_other_percentage()
    avg_per_event = calculate_avg_categories_per_event()

    %{
      total_categories: total_categories,
      active_categories: active_categories,
      total_events: total_events,
      categorized_events: categorized_events,
      uncategorized_count: uncategorized_count,
      uncategorized_percentage: safe_percentage(uncategorized_count, total_events),
      other_category_percentage: other_percentage,
      avg_categories_per_event: avg_per_event
    }
  end

  @doc """
  Returns category distribution data for charts.
  Returns a list of maps with category name, slug, color, and event count.
  """
  def category_distribution(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query =
      from c in Category,
        left_join: pec in PublicEventCategory,
        on: pec.category_id == c.id,
        left_join: pe in PublicEvent,
        on: pe.id == pec.event_id,
        group_by: [c.id, c.name, c.slug, c.color, c.display_order],
        select: %{
          id: c.id,
          name: c.name,
          slug: c.slug,
          color: c.color,
          event_count: count(pe.id)
        },
        order_by: [desc: count(pe.id)],
        limit: ^limit

    query =
      if include_inactive do
        query
      else
        from [c, ...] in query, where: c.is_active == true
      end

    Repo.all(query)
  end

  @doc """
  Returns top categories by event count with detailed metrics.
  """
  def top_categories(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    total_events = count_total_events()

    from(c in Category,
      left_join: pec in PublicEventCategory,
      on: pec.category_id == c.id,
      left_join: pe in PublicEvent,
      on: pe.id == pec.event_id,
      where: c.is_active == true,
      group_by: [c.id, c.name, c.slug, c.color, c.icon, c.display_order],
      select: %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        color: c.color,
        icon: c.icon,
        event_count: count(pe.id),
        primary_count: sum(fragment("CASE WHEN ? = true THEN 1 ELSE 0 END", pec.is_primary))
      },
      order_by: [desc: count(pe.id)],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn cat ->
      Map.put(cat, :percentage, safe_percentage(cat.event_count, total_events))
    end)
  end

  @doc """
  Returns categories with hierarchy information for tree display.
  """
  def categories_with_hierarchy do
    from(c in Category,
      left_join: parent in assoc(c, :parent),
      left_join: pec in PublicEventCategory,
      on: pec.category_id == c.id,
      group_by: [c.id, c.name, c.slug, c.parent_id, c.is_active, c.display_order, parent.name],
      select: %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        parent_id: c.parent_id,
        parent_name: parent.name,
        is_active: c.is_active,
        display_order: c.display_order,
        event_count: count(pec.id)
      },
      order_by: [asc: c.display_order, asc: c.name]
    )
    |> Repo.all()
  end

  @doc """
  Returns recent category assignments for activity feed.
  """
  def recent_assignments(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(pec in PublicEventCategory,
      join: c in Category,
      on: c.id == pec.category_id,
      join: pe in PublicEvent,
      on: pe.id == pec.event_id,
      select: %{
        category_name: c.name,
        category_slug: c.slug,
        category_color: c.color,
        event_title: pe.title,
        event_id: pe.id,
        source: pec.source,
        confidence: pec.confidence,
        is_primary: pec.is_primary,
        assigned_at: pec.inserted_at
      },
      order_by: [desc: pec.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns source breakdown for category assignments.
  Shows how categories are being assigned (manual, scraper, ml, etc.)
  """
  def source_breakdown do
    from(pec in PublicEventCategory,
      group_by: pec.source,
      select: %{
        source: pec.source,
        count: count(pec.id)
      },
      order_by: [desc: count(pec.id)]
    )
    |> Repo.all()
  end

  # Private helpers

  defp count_categories do
    Repo.aggregate(Category, :count, :id)
  end

  defp count_active_categories do
    from(c in Category, where: c.is_active == true)
    |> Repo.aggregate(:count, :id)
  end

  defp count_total_events do
    Repo.aggregate(PublicEvent, :count, :id)
  end

  defp count_categorized_events do
    from(pe in PublicEvent,
      join: pec in PublicEventCategory,
      on: pec.event_id == pe.id,
      distinct: true,
      select: pe.id
    )
    |> Repo.aggregate(:count)
  end

  defp calculate_other_percentage do
    other_category =
      from(c in Category, where: c.slug == "other", select: c.id)
      |> Repo.one()

    case other_category do
      nil ->
        0.0

      other_id ->
        other_count =
          from(pec in PublicEventCategory,
            where: pec.category_id == ^other_id,
            distinct: true,
            select: pec.event_id
          )
          |> Repo.aggregate(:count)

        total = count_categorized_events()
        safe_percentage(other_count, total)
    end
  end

  defp calculate_avg_categories_per_event do
    result =
      from(pec in PublicEventCategory,
        select: %{
          total_assignments: count(pec.id),
          unique_events: count(pec.event_id, :distinct)
        }
      )
      |> Repo.one()

    case result do
      %{total_assignments: 0} -> 0.0
      %{unique_events: 0} -> 0.0
      %{total_assignments: total, unique_events: events} -> Float.round(total / events, 2)
    end
  end

  defp safe_percentage(_count, 0), do: 0.0
  defp safe_percentage(count, total), do: Float.round(count / total * 100, 1)
end
