defmodule EventasaurusApp.Events.PollPagination do
  @moduledoc """
  Provides pagination support for polls with many options,
  especially date selection polls that can have hundreds of date options.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Poll, PollOption}

  @default_page_size 20
  @max_page_size 100

  @doc """
  Paginates poll options, particularly useful for date selection polls.

  Options:
  - page: Page number (default: 1)
  - page_size: Number of items per page (default: 20, max: 100)
  - order_by: How to order results (:date, :votes, :title)
  - filter: Optional filter parameters
  """
  def paginate_poll_options(%Poll{} = poll, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = min(Keyword.get(opts, :page_size, @default_page_size), @max_page_size)
    order_by = Keyword.get(opts, :order_by, :default)
    filter = Keyword.get(opts, :filter, %{})

    offset = (page - 1) * page_size

    # Base query
    query =
      from(po in PollOption,
        where: po.poll_id == ^poll.id,
        preload: [:votes]
      )

    # Apply filters
    query = apply_filters(query, filter, poll.poll_type)

    # Apply ordering
    query = apply_ordering(query, order_by, poll.poll_type)

    # Get total count
    total_count = Repo.aggregate(query, :count)

    # Get paginated results
    options =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      options: options,
      page: page,
      page_size: page_size,
      total_pages: ceil(total_count / page_size),
      total_count: total_count,
      has_next: page < ceil(total_count / page_size),
      has_prev: page > 1
    }
  end

  @doc """
  Gets poll options grouped by month for date selection polls.
  Useful for displaying date options in a calendar-like view.
  """
  def group_date_options_by_month(%Poll{poll_type: "date_selection"} = poll) do
    options =
      from(po in PollOption,
        where: po.poll_id == ^poll.id,
        preload: [:votes]
      )
      |> Repo.all()

    # Group by month
    options
    |> Enum.filter(&has_valid_date_metadata?/1)
    |> Enum.group_by(&extract_month_key/1)
    |> Enum.sort_by(fn {month_key, _} -> month_key end)
    |> Enum.map(fn {month_key, month_options} ->
      %{
        month_key: month_key,
        month_label: format_month_label(month_key),
        options: Enum.sort_by(month_options, &extract_date_from_metadata/1)
      }
    end)
  end

  @doc """
  Gets poll options within a date range for date selection polls.
  """
  def get_options_in_date_range(%Poll{poll_type: "date_selection"} = poll, start_date, end_date) do
    from(po in PollOption,
      where: po.poll_id == ^poll.id,
      where: fragment("(?->>'date')::date >= ?", po.metadata, ^start_date),
      where: fragment("(?->>'date')::date <= ?", po.metadata, ^end_date),
      preload: [:votes]
    )
    |> Repo.all()
    |> Enum.sort_by(&extract_date_from_metadata/1)
  end

  # Private helpers

  defp apply_filters(query, %{}, _poll_type), do: query

  defp apply_filters(query, %{date_range: {start_date, end_date}}, "date_selection") do
    from(po in query,
      where: fragment("(?->>'date')::date >= ?", po.metadata, ^start_date),
      where: fragment("(?->>'date')::date <= ?", po.metadata, ^end_date)
    )
  end

  defp apply_filters(query, %{has_votes: true}, _poll_type) do
    from(po in query,
      join: pv in assoc(po, :votes),
      group_by: po.id,
      having: count(pv.id) > 0
    )
  end

  defp apply_filters(query, %{status: status}, _poll_type)
       when status in ["active", "approved"] do
    from(po in query,
      where: po.status == ^status
    )
  end

  defp apply_filters(query, _, _), do: query

  defp apply_ordering(query, :date, "date_selection") do
    from(po in query,
      order_by: fragment("(?->>'date')::date ASC", po.metadata)
    )
  end

  defp apply_ordering(query, :votes, _poll_type) do
    from(po in query,
      left_join: pv in assoc(po, :votes),
      group_by: po.id,
      order_by: [desc: count(pv.id)]
    )
  end

  defp apply_ordering(query, :title, _poll_type) do
    from(po in query,
      order_by: [asc: po.title]
    )
  end

  defp apply_ordering(query, _, _poll_type) do
    from(po in query,
      order_by: [asc: po.order_index, asc: po.id]
    )
  end

  defp has_valid_date_metadata?(%PollOption{metadata: %{"date" => date_string}}) do
    case Date.from_iso8601(date_string) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp has_valid_date_metadata?(_), do: false

  defp extract_date_from_metadata(%PollOption{metadata: %{"date" => date_string}}) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp extract_date_from_metadata(_), do: nil

  defp extract_month_key(%PollOption{} = option) do
    case extract_date_from_metadata(option) do
      %Date{year: year, month: month} -> {year, month}
      # Sort unknown dates last
      _ -> {9999, 99}
    end
  end

  defp format_month_label({year, month}) do
    month_name =
      case month do
        1 -> "January"
        2 -> "February"
        3 -> "March"
        4 -> "April"
        5 -> "May"
        6 -> "June"
        7 -> "July"
        8 -> "August"
        9 -> "September"
        10 -> "October"
        11 -> "November"
        12 -> "December"
        _ -> "Unknown"
      end

    "#{month_name} #{year}"
  end
end

