defmodule EventasaurusDiscovery.CategoryAnalytics do
  @moduledoc """
  Analytics and statistics for the category system.
  Provides summary metrics, distribution data, and top categories for the admin dashboard.
  """

  import Ecto.Query
  alias EventasaurusDiscovery.Categories.{Category, PublicEventCategory}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Repo

  # Type definitions for return values
  @type summary_stats_result :: %{
          total_categories: non_neg_integer(),
          active_categories: non_neg_integer(),
          total_events: non_neg_integer(),
          categorized_events: non_neg_integer(),
          uncategorized_count: non_neg_integer(),
          uncategorized_percentage: float(),
          other_category_percentage: float(),
          avg_categories_per_event: float()
        }

  @type category_distribution_result :: %{
          id: pos_integer(),
          name: String.t(),
          slug: String.t(),
          color: String.t() | nil,
          event_count: non_neg_integer()
        }

  @type top_category_result :: %{
          id: pos_integer(),
          name: String.t(),
          slug: String.t(),
          color: String.t() | nil,
          icon: String.t() | nil,
          event_count: non_neg_integer(),
          primary_count: non_neg_integer(),
          percentage: float()
        }

  @type assignment_result :: %{
          category_name: String.t(),
          category_slug: String.t(),
          category_color: String.t() | nil,
          event_title: String.t(),
          event_id: pos_integer(),
          source: String.t() | nil,
          confidence: float() | nil,
          is_primary: boolean(),
          assigned_at: DateTime.t()
        }

  @type source_breakdown_result :: %{source: String.t() | nil, count: non_neg_integer()}

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
  @spec summary_stats() :: summary_stats_result()
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
  @spec category_distribution(keyword()) :: [category_distribution_result()]
  def category_distribution(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query =
      from(c in Category,
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
      )

    query =
      if include_inactive do
        query
      else
        from([c, ...] in query, where: c.is_active == true)
      end

    Repo.all(query)
  end

  @doc """
  Returns top categories by event count with detailed metrics.
  """
  @spec top_categories(keyword()) :: [top_category_result()]
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
      cat
      |> Map.put(:primary_count, cat.primary_count || 0)
      |> Map.put(:percentage, safe_percentage(cat.event_count, total_events))
    end)
  end

  @doc """
  Returns categories with hierarchy information for tree display.
  Includes icon, color, and builds a proper tree structure with aggregate counts.
  """
  @spec categories_with_hierarchy() :: [map()]
  def categories_with_hierarchy do
    # Fetch all categories with their direct event counts
    categories =
      from(c in Category,
        left_join: pec in PublicEventCategory,
        on: pec.category_id == c.id,
        group_by: [
          c.id,
          c.name,
          c.slug,
          c.parent_id,
          c.is_active,
          c.display_order,
          c.icon,
          c.color
        ],
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
  @spec build_category_tree([map()]) :: [map()]
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
  @spec recent_assignments(keyword()) :: [assignment_result()]
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
  @spec source_breakdown() :: [source_breakdown_result()]
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

  # ============================================================================
  # Category Insights Functions
  # ============================================================================

  @doc """
  Returns category trends over time - events per category by month.
  Default: Last 6 months of data.

  Returns a list of maps:
  %{month: "2024-12", category_id: 1, category_name: "Concerts", event_count: 150}
  """
  @spec category_trends(keyword()) :: [map()]
  def category_trends(opts \\ []) do
    months = Keyword.get(opts, :months, 6)
    limit_categories = Keyword.get(opts, :limit_categories, 10)

    # Get top categories first
    top_category_ids =
      top_categories(limit: limit_categories)
      |> Enum.map(& &1.id)

    # Calculate the start date
    start_date =
      Date.utc_today()
      |> Date.beginning_of_month()
      |> Date.add(-30 * (months - 1))

    from(pec in PublicEventCategory,
      join: c in Category,
      on: c.id == pec.category_id,
      join: pe in PublicEvent,
      on: pe.id == pec.event_id,
      where: c.id in ^top_category_ids,
      where: pe.starts_at >= ^DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"),
      group_by: [
        fragment("to_char(?, 'YYYY-MM')", pe.starts_at),
        c.id,
        c.name,
        c.color
      ],
      select: %{
        month: fragment("to_char(?, 'YYYY-MM')", pe.starts_at),
        category_id: c.id,
        category_name: c.name,
        category_color: c.color,
        event_count: count(pe.id)
      },
      order_by: [asc: fragment("to_char(?, 'YYYY-MM')", pe.starts_at), desc: count(pe.id)]
    )
    |> Repo.all()
  end

  @doc """
  Returns all months in the trend range for chart axis.
  """
  @spec trend_months(pos_integer()) :: [String.t()]
  def trend_months(months \\ 6) do
    today = Date.utc_today()

    0..(months - 1)
    |> Enum.map(fn offset ->
      today
      |> Date.beginning_of_month()
      |> Date.add(-30 * offset)
      |> Calendar.strftime("%Y-%m")
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns source breakdown for a specific category.
  Shows which scrapers/sources contribute events to this category.
  """
  @spec source_breakdown_by_category(pos_integer()) :: [source_breakdown_result()]
  def source_breakdown_by_category(category_id) do
    from(pec in PublicEventCategory,
      where: pec.category_id == ^category_id,
      group_by: pec.source,
      select: %{
        source: pec.source,
        count: count(pec.id)
      },
      order_by: [desc: count(pec.id)]
    )
    |> Repo.all()
    |> Enum.map(fn item ->
      Map.put(item, :source, item.source || "unknown")
    end)
  end

  @doc """
  Returns source breakdown for all categories.
  Shows which scrapers contribute to each category.

  Returns: %{category_name => [%{source: "karnet", count: 50}, ...], ...}
  """
  @spec all_categories_source_breakdown(keyword()) :: %{String.t() => [map()]}
  def all_categories_source_breakdown(opts \\ []) do
    limit_categories = Keyword.get(opts, :limit_categories, 10)

    top_category_ids =
      top_categories(limit: limit_categories)
      |> Enum.map(& &1.id)

    from(pec in PublicEventCategory,
      join: c in Category,
      on: c.id == pec.category_id,
      where: c.id in ^top_category_ids,
      group_by: [c.id, c.name, c.color, pec.source],
      select: %{
        category_id: c.id,
        category_name: c.name,
        category_color: c.color,
        source: pec.source,
        count: count(pec.id)
      },
      order_by: [asc: c.name, desc: count(pec.id)]
    )
    |> Repo.all()
    |> Enum.map(fn item ->
      Map.put(item, :source, item.source || "unknown")
    end)
    |> Enum.group_by(& &1.category_name)
  end

  @doc """
  Returns category overlap analysis - events that have multiple categories.
  Shows which category pairs frequently appear together.

  Returns list of: %{category_1: "Concerts", category_2: "Nightlife", overlap_count: 150}
  """
  @spec category_overlap_matrix(keyword()) :: [map()]
  def category_overlap_matrix(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)

    # Self-join to find pairs of categories on the same event
    from(pec1 in PublicEventCategory,
      join: pec2 in PublicEventCategory,
      on: pec1.event_id == pec2.event_id and pec1.category_id < pec2.category_id,
      join: c1 in Category,
      on: c1.id == pec1.category_id,
      join: c2 in Category,
      on: c2.id == pec2.category_id,
      group_by: [c1.id, c1.name, c1.color, c2.id, c2.name, c2.color],
      select: %{
        category_1_id: c1.id,
        category_1_name: c1.name,
        category_1_color: c1.color,
        category_2_id: c2.id,
        category_2_name: c2.name,
        category_2_color: c2.color,
        overlap_count: count(pec1.event_id)
      },
      order_by: [desc: count(pec1.event_id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns count of multi-category events (events with 2+ categories).
  """
  @spec multi_category_events_count() :: non_neg_integer()
  def multi_category_events_count do
    # Use subquery to count grouped results
    subquery =
      from(pec in PublicEventCategory,
        group_by: pec.event_id,
        having: count(pec.category_id) > 1,
        select: pec.event_id
      )

    from(s in subquery(subquery), select: count())
    |> Repo.one()
  end

  @doc """
  Returns distribution of category counts per event.
  E.g., how many events have 1 category, 2 categories, 3+ categories.
  """
  @spec category_count_distribution() :: [%{label: String.t(), count: non_neg_integer()}]
  def category_count_distribution do
    from(pec in PublicEventCategory,
      group_by: pec.event_id,
      select: %{
        event_id: pec.event_id,
        category_count: count(pec.category_id)
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn %{category_count: count} ->
      cond do
        count == 1 -> "1 category"
        count == 2 -> "2 categories"
        count >= 3 -> "3+ categories"
      end
    end)
    |> Enum.map(fn {label, events} ->
      %{label: label, count: length(events)}
    end)
    |> Enum.sort_by(& &1.label)
  end

  @doc """
  Returns confidence score distribution for ML/automated categorizations.
  """
  @spec confidence_distribution() :: %{
          high: non_neg_integer(),
          medium: non_neg_integer(),
          low: non_neg_integer()
        }
  def confidence_distribution do
    from(pec in PublicEventCategory,
      where: not is_nil(pec.confidence),
      select: %{
        confidence: pec.confidence,
        count: count(pec.id)
      },
      group_by: pec.confidence,
      order_by: [desc: pec.confidence]
    )
    |> Repo.all()
    |> Enum.reduce(%{high: 0, medium: 0, low: 0}, fn %{confidence: conf, count: count}, acc ->
      cond do
        conf >= 0.8 -> Map.update!(acc, :high, &(&1 + count))
        conf >= 0.5 -> Map.update!(acc, :medium, &(&1 + count))
        true -> Map.update!(acc, :low, &(&1 + count))
      end
    end)
  end
end
