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
  Includes icon, color, and builds a proper tree structure with aggregate counts.
  """
  def categories_with_hierarchy do
    # Fetch all categories with their direct event counts
    categories =
      from(c in Category,
        left_join: pec in PublicEventCategory,
        on: pec.category_id == c.id,
        group_by: [c.id, c.name, c.slug, c.parent_id, c.is_active, c.display_order, c.icon, c.color],
        select: %{
          id: c.id,
          name: c.name,
          slug: c.slug,
          icon: c.icon,
          color: c.color,
          parent_id: c.parent_id,
          is_active: c.is_active,
          display_order: c.display_order,
          direct_event_count: count(pec.id)
        },
        order_by: [asc: c.display_order, asc: c.name]
      )
      |> Repo.all()

    # Build tree structure with aggregate counts
    build_category_tree(categories)
  end

  @doc """
  Builds a hierarchical tree from flat category list.
  Calculates total_event_count (direct + all children) for each category.
  """
  def build_category_tree(categories) do
    # Create a map for quick lookup
    category_map = Map.new(categories, fn c -> {c.id, c} end)

    # Find root categories (no parent)
    roots = Enum.filter(categories, fn c -> is_nil(c.parent_id) end)

    # Find children for each category
    children_map =
      categories
      |> Enum.filter(fn c -> not is_nil(c.parent_id) end)
      |> Enum.group_by(fn c -> c.parent_id end)

    # Build tree recursively with aggregate counts
    Enum.map(roots, fn root ->
      build_tree_node(root, children_map, category_map)
    end)
    |> sort_categories()
  end

  defp build_tree_node(category, children_map, _category_map) do
    children = Map.get(children_map, category.id, [])

    built_children =
      Enum.map(children, fn child ->
        build_tree_node(child, children_map, %{})
      end)
      |> sort_categories()

    children_event_count =
      Enum.reduce(built_children, 0, fn child, acc ->
        acc + child.total_event_count
      end)

    category
    |> Map.put(:children, built_children)
    |> Map.put(:children_event_count, children_event_count)
    |> Map.put(:total_event_count, category.direct_event_count + children_event_count)
  end

  defp sort_categories(categories) do
    # Sort by display_order first, then by name, with "other" always at the end
    Enum.sort_by(categories, fn c ->
      is_other = String.downcase(c.slug || "") == "other"
      {is_other, c.display_order || 0, c.name || ""}
    end)
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
