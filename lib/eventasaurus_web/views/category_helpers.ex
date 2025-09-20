defmodule EventasaurusWeb.CategoryHelpers do
  @moduledoc """
  Helper functions for displaying categories in views.
  """

  alias EventasaurusDiscovery.Categories.Category

  @doc """
  Gets the primary category for an event.
  If the event has categories loaded, finds the primary one.
  Otherwise returns nil.
  """
  def primary_category(event) do
    cond do
      # If categories are preloaded and we have the join table info
      is_list(event.categories) && length(event.categories) > 0 ->
        # This would require the join table data which we might not have
        # So just return the first category as primary
        List.first(event.categories)

      # If we have old category_id field
      Map.get(event, :category_id) ->
        %{id: event.category_id, name: "Category #{event.category_id}"}

      true ->
        nil
    end
  end

  @doc """
  Returns a display name for the primary category.
  """
  def primary_category_name(event, locale \\ "en") do
    case primary_category(event) do
      %Category{} = category ->
        Category.get_name(category, locale)
      nil ->
        ""
      _ ->
        ""
    end
  end

  @doc """
  Returns all category names for an event as a comma-separated string.
  """
  def category_names(event, locale \\ "en") do
    case Map.get(event, :categories) do
      categories when is_list(categories) ->
        categories
        |> Enum.map(fn cat -> Category.get_name(cat, locale) end)
        |> Enum.join(", ")
      _ ->
        ""
    end
  end

  @doc """
  Returns category badges for display.
  Returns HTML-safe content for use in templates.
  """
  def category_badges(event, locale \\ "en") do
    case Map.get(event, :categories) do
      categories when is_list(categories) ->
        categories
        |> Enum.map(fn category ->
          name = Category.get_name(category, locale)
          color = Map.get(category, :color, "#6B7280")
          icon = Map.get(category, :icon, "tag")
          is_primary = is_primary_category?(event, category)

          badge_class = if is_primary do
            "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ring-2 ring-offset-1"
          else
            "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
          end

          {name, color, icon, badge_class}
        end)
      _ ->
        []
    end
  end

  @doc """
  Returns the primary category badge only.
  """
  def primary_category_badge(event, locale \\ "en") do
    category = primary_category(event)

    if category do
      name = Category.get_name(category, locale)
      color = Map.get(category, :color, "#6B7280")
      icon = Map.get(category, :icon, "tag")

      {name, color, icon}
    else
      nil
    end
  end

  @doc """
  Returns category slugs for URL filtering.
  """
  def category_slugs(event) do
    case Map.get(event, :categories) do
      categories when is_list(categories) ->
        Enum.map(categories, & &1.slug)
      _ ->
        []
    end
  end

  @doc """
  Returns true if the given category is the primary category for the event.
  """
  def is_primary_category?(event, category) do
    # Since we don't have the join table data readily available,
    # we'll consider the first category as primary
    case Map.get(event, :categories) do
      [first | _rest] ->
        first.id == category.id
      _ ->
        false
    end
  end
end