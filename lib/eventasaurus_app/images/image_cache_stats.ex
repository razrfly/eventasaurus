defmodule EventasaurusApp.Images.ImageCacheStats do
  @moduledoc """
  Statistics and query functions for the image cache dashboard.

  Provides aggregated stats for cached images by entity type, status,
  provider, and image type.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage

  @doc """
  Get summary statistics for all cached images.

  Returns:
    %{
      total: integer(),
      cached: integer(),
      pending: integer(),
      failed: integer(),
      downloading: integer(),
      total_size_bytes: integer()
    }
  """
  def get_summary_stats do
    stats =
      from(c in CachedImage,
        select: %{
          total: count(c.id),
          cached: sum(fragment("CASE WHEN status = 'cached' THEN 1 ELSE 0 END")),
          pending: sum(fragment("CASE WHEN status = 'pending' THEN 1 ELSE 0 END")),
          failed: sum(fragment("CASE WHEN status = 'failed' THEN 1 ELSE 0 END")),
          downloading: sum(fragment("CASE WHEN status = 'downloading' THEN 1 ELSE 0 END")),
          total_size_bytes: sum(fragment("COALESCE(file_size, 0)"))
        }
      )
      |> Repo.one()

    # Convert nil values to 0
    %{
      total: stats.total || 0,
      cached: decimal_to_int(stats.cached),
      pending: decimal_to_int(stats.pending),
      failed: decimal_to_int(stats.failed),
      downloading: decimal_to_int(stats.downloading),
      total_size_bytes: decimal_to_int(stats.total_size_bytes)
    }
  end

  @doc """
  Get statistics grouped by entity type.

  Returns list of:
    %{
      entity_type: String.t(),
      total: integer(),
      cached: integer(),
      pending: integer(),
      failed: integer(),
      last_activity: DateTime.t() | nil
    }
  """
  def get_stats_by_entity_type do
    from(c in CachedImage,
      group_by: c.entity_type,
      select: %{
        entity_type: c.entity_type,
        total: count(c.id),
        cached: sum(fragment("CASE WHEN status = 'cached' THEN 1 ELSE 0 END")),
        pending: sum(fragment("CASE WHEN status = 'pending' THEN 1 ELSE 0 END")),
        failed: sum(fragment("CASE WHEN status = 'failed' THEN 1 ELSE 0 END")),
        last_activity: max(c.updated_at)
      },
      order_by: [desc: count(c.id)]
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        entity_type: row.entity_type,
        total: row.total,
        cached: decimal_to_int(row.cached),
        pending: decimal_to_int(row.pending),
        failed: decimal_to_int(row.failed),
        last_activity: row.last_activity
      }
    end)
  end

  @doc """
  Get statistics grouped by original_source (provider).

  Returns list of:
    %{
      provider: String.t(),
      total: integer(),
      cached: integer(),
      failed: integer(),
      success_rate: float(),
      last_activity: DateTime.t() | nil
    }
  """
  def get_stats_by_provider do
    from(c in CachedImage,
      where: not is_nil(c.original_source),
      group_by: c.original_source,
      select: %{
        provider: c.original_source,
        total: count(c.id),
        cached: sum(fragment("CASE WHEN status = 'cached' THEN 1 ELSE 0 END")),
        failed: sum(fragment("CASE WHEN status = 'failed' THEN 1 ELSE 0 END")),
        last_activity: max(c.updated_at)
      },
      order_by: [desc: count(c.id)]
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      cached = decimal_to_int(row.cached)
      total = row.total

      success_rate =
        if total > 0 do
          Float.round(cached / total * 100, 1)
        else
          0.0
        end

      %{
        provider: row.provider,
        total: total,
        cached: cached,
        failed: decimal_to_int(row.failed),
        success_rate: success_rate,
        last_activity: row.last_activity
      }
    end)
  end

  @doc """
  Get statistics grouped by image_type (for event sources).

  Returns list of:
    %{
      image_type: String.t(),
      count: integer()
    }
  """
  def get_stats_by_image_type do
    from(c in CachedImage,
      where: c.entity_type == "public_event_source",
      where: c.status == "cached",
      group_by: c.image_type,
      select: %{
        image_type: c.image_type,
        count: count(c.id)
      },
      order_by: [desc: count(c.id)]
    )
    |> Repo.all()
  end

  @doc """
  Get recent activity (last N cached or failed images).

  Returns list of CachedImage structs.
  """
  def get_recent_activity(limit \\ 20) do
    from(c in CachedImage,
      where: c.status in ["cached", "failed"],
      order_by: [desc: c.updated_at],
      limit: ^limit,
      select: %{
        id: c.id,
        entity_type: c.entity_type,
        entity_id: c.entity_id,
        image_type: c.image_type,
        position: c.position,
        status: c.status,
        cdn_url: c.cdn_url,
        original_url: c.original_url,
        original_source: c.original_source,
        file_size: c.file_size,
        last_error: c.last_error,
        updated_at: c.updated_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Get recent failures with error messages.

  Returns list of maps with error details.
  """
  def get_recent_failures(limit \\ 10) do
    from(c in CachedImage,
      where: c.status == "failed",
      order_by: [desc: c.updated_at],
      limit: ^limit,
      select: %{
        id: c.id,
        entity_type: c.entity_type,
        entity_id: c.entity_id,
        original_url: c.original_url,
        original_source: c.original_source,
        last_error: c.last_error,
        retry_count: c.retry_count,
        updated_at: c.updated_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Get failure statistics grouped by error type.

  Returns list of:
    %{
      error_type: String.t(),
      count: integer()
    }
  """
  def get_failure_breakdown do
    from(c in CachedImage,
      where: c.status == "failed",
      where: not is_nil(c.last_error),
      group_by: c.last_error,
      select: %{
        error_type: c.last_error,
        count: count(c.id)
      },
      order_by: [desc: count(c.id)]
    )
    |> Repo.all()
  end

  @doc """
  Get all stats needed for the dashboard in one call.

  Returns a map with all statistics for efficient loading.
  """
  def get_dashboard_stats do
    %{
      summary: get_summary_stats(),
      by_entity_type: get_stats_by_entity_type(),
      by_provider: get_stats_by_provider(),
      by_image_type: get_stats_by_image_type(),
      recent_activity: get_recent_activity(20),
      recent_failures: get_recent_failures(10),
      failure_breakdown: get_failure_breakdown()
    }
  end

  # Helper to convert Decimal to integer safely
  defp decimal_to_int(nil), do: 0
  defp decimal_to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp decimal_to_int(n) when is_integer(n), do: n
  defp decimal_to_int(n) when is_float(n), do: round(n)
end
