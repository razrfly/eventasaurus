defmodule EventasaurusDiscovery.Pagination do
  @moduledoc """
  Pagination helpers for query results.
  Supports both offset-based and cursor-based pagination.
  """

  import Ecto.Query

  @default_page_size 20
  @max_page_size 100

  defstruct [:entries, :page_number, :page_size, :total_entries, :total_pages]

  @doc """
  Paginate a query with offset-based pagination.

  Returns a Pagination struct with entries and metadata.
  """
  def paginate(query, repo, page, page_size \\ @default_page_size) do
    page = max(page || 1, 1)
    page_size = min(page_size || @default_page_size, @max_page_size)
    offset = (page - 1) * page_size

    # Get total count
    total_entries = repo.aggregate(query, :count, :id)
    total_pages = ceil(total_entries / page_size)

    # Get paginated entries
    entries =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> repo.all()

    %__MODULE__{
      entries: entries,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @doc """
  Create pagination metadata for LiveView.
  """
  def metadata(%__MODULE__{} = pagination) do
    %{
      page_number: pagination.page_number,
      page_size: pagination.page_size,
      total_entries: pagination.total_entries,
      total_pages: pagination.total_pages,
      has_previous?: pagination.page_number > 1,
      has_next?: pagination.page_number < pagination.total_pages,
      first_page?: pagination.page_number == 1,
      last_page?: pagination.page_number >= pagination.total_pages
    }
  end

  @doc """
  Generate page links for pagination controls.
  """
  def page_links(%__MODULE__{} = pagination, window \\ 2) do
    current = pagination.page_number
    total = pagination.total_pages

    if total <= 1 do
      []
    else
      start_page = max(1, current - window)
      end_page = min(total, current + window)

      # Always include first page
      pages = if start_page > 1, do: [1], else: []

      # Add ellipsis if needed
      pages = if start_page > 2, do: pages ++ [:ellipsis], else: pages

      # Add window pages
      pages = pages ++ Enum.to_list(start_page..end_page)

      # Add ellipsis if needed
      pages = if end_page < total - 1, do: pages ++ [:ellipsis], else: pages

      # Always include last page
      if end_page < total, do: pages ++ [total], else: pages
    end
  end

  @doc """
  Cursor-based pagination for infinite scroll.
  """
  def paginate_cursor(query, repo, cursor, page_size \\ @default_page_size) do
    page_size = min(page_size || @default_page_size, @max_page_size)

    # Add explicit ordering to match cursor predicate
    query =
      query
      |> order_by(asc: :id)
      |> then(fn q ->
        if cursor do
          from(q in q, where: q.id > ^cursor)
        else
          q
        end
      end)

    # Fetch one extra to determine if there are more
    entries =
      query
      |> limit(^(page_size + 1))
      |> repo.all()

    has_more? = length(entries) > page_size
    entries = Enum.take(entries, page_size)

    next_cursor =
      if has_more? and entries != [] do
        List.last(entries).id
      else
        nil
      end

    %{
      entries: entries,
      cursor: next_cursor,
      has_more?: has_more?
    }
  end

  @doc """
  Build URL with updated page parameter.
  """
  def page_url(current_url, page) do
    uri = URI.parse(current_url)
    query_params = URI.decode_query(uri.query || "")
    updated_params = Map.put(query_params, "page", to_string(page))

    %{uri | query: URI.encode_query(updated_params)}
    |> URI.to_string()
  end
end
