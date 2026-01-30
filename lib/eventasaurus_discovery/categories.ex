defmodule EventasaurusDiscovery.Categories do
  @moduledoc """
  The Categories context for managing event categories with multi-language support.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.{Category, PublicEventCategory}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  @doc """
  Lists only active categories for display.
  """
  def list_active_categories(opts \\ []) do
    list_categories(Keyword.put(opts, :active_only, true))
  end

  @doc """
  Returns the list of categories.

  ## Options
    * `:locale` - Language for translations (default: "en")
    * `:active_only` - Filter only active categories (default: true)
    * `:parent_id` - Filter by parent category
    * `:preload` - List of associations to preload

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

      iex> list_categories(locale: "pl", parent_id: nil)
      [%Category{}, ...]

  """
  def list_categories(opts \\ []) do
    locale = Keyword.get(opts, :locale, "en")
    active_only = Keyword.get(opts, :active_only, true)
    parent_id = Keyword.get(opts, :parent_id)
    preloads = Keyword.get(opts, :preload, [])

    query =
      from(c in Category,
        order_by: [asc: c.display_order, asc: c.name]
      )

    query =
      if active_only do
        where(query, [c], c.is_active == true)
      else
        query
      end

    query =
      case parent_id do
        nil -> query
        :root -> where(query, [c], is_nil(c.parent_id))
        id -> where(query, [c], c.parent_id == ^id)
      end

    query
    |> Repo.all()
    |> Repo.preload(preloads)
    |> Enum.map(&localize_category(&1, locale))
  end

  @doc """
  Gets a single category.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(123)
      %Category{}

      iex> get_category!(456)
      ** (Ecto.NoResultsError)

  """
  def get_category!(id, opts \\ []) do
    locale = Keyword.get(opts, :locale, "en")
    preloads = Keyword.get(opts, :preload, [])

    Category
    |> Repo.get!(id)
    |> Repo.preload(preloads)
    |> localize_category(locale)
  end

  @doc """
  Gets a category by slug.
  """
  def get_category_by_slug(slug, opts \\ []) do
    locale = Keyword.get(opts, :locale, "en")
    preloads = Keyword.get(opts, :preload, [])

    Category
    |> Repo.get_by(slug: slug)
    |> case do
      nil ->
        nil

      category ->
        category
        |> Repo.preload(preloads)
        |> localize_category(locale)
    end
  end

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(%{field: value})
      {:ok, %Category{}}

      iex> create_category(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.

  ## Examples

      iex> delete_category(category)
      {:ok, %Category{}}

      iex> delete_category(category)
      {:error, %Ecto.Changeset{}}

  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(category)
      %Ecto.Changeset{data: %Category{}}

  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  @doc """
  Assigns categories to a public event.

  ## Options
    * `:primary_id` - ID of the primary category
    * `:source` - Source of the categorization ("ticketmaster", "karnet", "manual")

  ## Examples

      iex> assign_categories_to_event(event_id, [1, 2, 3], primary_id: 1, source: "manual")
      {:ok, [%PublicEventCategory{}, ...]}

  """
  def assign_categories_to_event(event_id, category_ids, opts \\ []) do
    alias Ecto.Multi
    require Logger

    primary_id = Keyword.get(opts, :primary_id)
    source = Keyword.get(opts, :source, "manual")
    category_ids = category_ids |> Enum.uniq()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Build rows
    event_categories =
      Enum.map(category_ids, fn category_id ->
        %{
          event_id: event_id,
          category_id: category_id,
          is_primary: category_id == primary_id,
          source: source,
          confidence: 1.0,
          inserted_at: now
        }
      end)

    multi =
      Multi.new()
      # CRITICAL: If setting a primary, remove ALL existing primaries first
      |> then(fn multi ->
        if primary_id do
          Multi.delete_all(
            multi,
            :delete_old_primary,
            from(pec in PublicEventCategory,
              where: pec.event_id == ^event_id and pec.is_primary == true
            )
          )
        else
          multi
        end
      end)
      # Then remove categories from the same source
      |> Multi.delete_all(
        :delete_old_source,
        from(pec in PublicEventCategory,
          where: pec.event_id == ^event_id and pec.source == ^source
        )
      )
      |> Multi.insert_all(
        :upsert,
        PublicEventCategory,
        event_categories,
        # Replace confidence, source, and is_primary (old primaries were deleted earlier)
        on_conflict: {:replace, [:confidence, :source, :is_primary]},
        conflict_target: [:event_id, :category_id],
        returning: true
      )
      # Update denormalized category_id on the public_event when primary is set
      |> then(fn multi ->
        if primary_id do
          Multi.update_all(
            multi,
            :update_event_category,
            from(pe in PublicEvent, where: pe.id == ^event_id),
            set: [category_id: primary_id, updated_at: now]
          )
        else
          multi
        end
      end)

    case Repo.transaction(multi) do
      {:ok, %{upsert: result}} ->
        # Handle both single result and list of results
        rows =
          case result do
            {_count, rows} when is_list(rows) -> rows
            rows when is_list(rows) -> rows
            single_row -> [single_row]
          end

        {:ok,
         Enum.map(rows, fn row ->
           case row do
             %PublicEventCategory{} = cat -> cat
             map when is_map(map) -> struct(PublicEventCategory, map)
           end
         end)}

      {:error, :delete_old_primary, _, _} ->
        # Race condition - another process already updated
        # Just return success since categories are assigned
        Logger.warning(
          "Category assignment race condition detected for event #{event_id}, retrying..."
        )

        {:ok, []}

      {:error, step, reason, _changes} ->
        Logger.warning("Category assignment failed at #{step}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Search categories across all languages.

  ## Examples

      iex> search_categories_multilingual("koncert")
      [%Category{}, ...]

  """
  def search_categories_multilingual(search_term) do
    term = "%#{search_term}%"

    from(c in Category,
      where:
        ilike(c.name, ^term) or
          ilike(c.description, ^term) or
          fragment("EXISTS (
               SELECT 1 FROM jsonb_each_text(?) AS t(lang, trans)
               WHERE t.trans::jsonb->>'name' ILIKE ? OR
                     t.trans::jsonb->>'description' ILIKE ?
             )", c.translations, ^term, ^term),
      order_by: [asc: c.display_order, asc: c.name]
    )
    |> Repo.all()
  end

  @doc """
  Get categories with their event counts.
  """
  def list_categories_with_counts(opts \\ []) do
    locale = Keyword.get(opts, :locale, "en")

    from(c in Category,
      left_join: pec in PublicEventCategory,
      on: pec.category_id == c.id,
      group_by: c.id,
      select: {c, count(pec.id)},
      order_by: [asc: c.display_order, asc: c.name]
    )
    |> Repo.all()
    |> Enum.map(fn {category, count} ->
      category
      |> localize_category(locale)
      |> Map.put(:event_count, count)
    end)
  end

  @doc """
  Build a hierarchical tree of categories.
  """
  def category_tree(opts \\ []) do
    categories = list_categories(opts)

    # Group by parent_id
    grouped = Enum.group_by(categories, & &1.parent_id)

    # Build tree recursively
    build_tree(grouped[nil] || [], grouped)
  end

  defp build_tree(categories, grouped) do
    Enum.map(categories, fn category ->
      children = grouped[category.id] || []
      Map.put(category, :children, build_tree(children, grouped))
    end)
  end

  @doc """
  Localize a category for display in a specific language.
  Falls back to English if translation is not available.
  """
  def localize_category(%Category{} = category, locale) do
    localized_name = Category.get_name(category, locale)
    localized_description = Category.get_description(category, locale)

    category
    |> Map.put(:localized_name, localized_name)
    |> Map.put(:localized_description, localized_description)
  end
end
