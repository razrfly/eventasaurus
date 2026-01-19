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

  @doc """
  Keyset-based pagination for ordered queries.

  Uses composite cursor (sort_field, id) to efficiently paginate without OFFSET scans.
  This is O(1) vs O(n) for OFFSET pagination.

  ## Parameters
    - query: Base Ecto query (should NOT include order_by, limit, or offset)
    - repo: The Ecto repo module
    - opts: Keyword list with:
      - :cursor - Encoded cursor string (nil for first page)
      - :page_size - Number of entries per page (default 20)
      - :sort_field - The field to sort by (default :name)
      - :sort_dir - Sort direction :asc or :desc (default :asc)

  ## Returns
    Map with:
    - :entries - List of entries for this page
    - :cursor - Cursor for the next page (nil if no more pages)
    - :has_more? - Boolean indicating if there are more pages
    - :total_entries - Total count of all matching entries
    - :page_size - The page size used

  ## Example

      Pagination.paginate_keyset(
        from(v in Venue, where: v.is_public == true),
        Repo,
        cursor: params["cursor"],
        page_size: 30,
        sort_field: :name,
        sort_dir: :asc
      )
  """
  def paginate_keyset(query, repo, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    page_size = min(Keyword.get(opts, :page_size, @default_page_size), @max_page_size)
    sort_field = Keyword.get(opts, :sort_field, :name)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)

    # Get total count (cheap operation - no row scanning)
    total_entries = repo.aggregate(query, :count, :id)

    # Decode cursor if present
    decoded_cursor = decode_keyset_cursor(cursor)

    # Build the keyset query
    keyset_query =
      query
      |> apply_keyset_filter(decoded_cursor, sort_field, sort_dir)
      |> apply_keyset_order(sort_field, sort_dir)
      |> limit(^(page_size + 1))

    # Fetch entries
    entries = repo.all(keyset_query)

    # Check if there are more pages
    has_more? = length(entries) > page_size
    entries = Enum.take(entries, page_size)

    # Build next cursor from last entry
    next_cursor =
      if has_more? and entries != [] do
        last_entry = List.last(entries)
        encode_keyset_cursor(Map.get(last_entry, sort_field), last_entry.id)
      else
        nil
      end

    %{
      entries: entries,
      cursor: next_cursor,
      has_more?: has_more?,
      total_entries: total_entries,
      page_size: page_size
    }
  end

  @doc """
  Encode a keyset cursor from sort value and id.
  """
  def encode_keyset_cursor(sort_value, id) do
    data = %{v: sort_value, id: id}

    data
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decode a keyset cursor back to sort value and id.
  """
  def decode_keyset_cursor(nil), do: nil
  def decode_keyset_cursor(""), do: nil

  def decode_keyset_cursor(cursor) when is_binary(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, binary} ->
        try do
          term = :erlang.binary_to_term(binary, [:safe])
          # Validate the decoded term has the expected structure
          case term do
            %{v: _sort_value, id: _id} -> term
            _ -> nil
          end
        rescue
          _ -> nil
        end

      :error ->
        nil
    end
  end

  # Apply keyset filter based on cursor position
  defp apply_keyset_filter(query, nil, _sort_field, _sort_dir), do: query

  defp apply_keyset_filter(query, %{v: sort_value, id: id}, sort_field, :asc) do
    # For ASC: get entries where (sort_field, id) > (cursor_value, cursor_id)
    # Using row value comparison for correct composite ordering
    from(q in query,
      where:
        field(q, ^sort_field) > ^sort_value or
          (field(q, ^sort_field) == ^sort_value and q.id > ^id)
    )
  end

  defp apply_keyset_filter(query, %{v: sort_value, id: id}, sort_field, :desc) do
    # For DESC: get entries where (sort_field, id) < (cursor_value, cursor_id)
    from(q in query,
      where:
        field(q, ^sort_field) < ^sort_value or
          (field(q, ^sort_field) == ^sort_value and q.id < ^id)
    )
  end

  # Apply ordering based on sort direction
  defp apply_keyset_order(query, sort_field, :asc) do
    from(q in query, order_by: [asc: field(q, ^sort_field), asc: q.id])
  end

  defp apply_keyset_order(query, sort_field, :desc) do
    from(q in query, order_by: [desc: field(q, ^sort_field), desc: q.id])
  end
end
