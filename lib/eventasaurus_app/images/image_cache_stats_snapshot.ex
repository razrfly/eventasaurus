defmodule EventasaurusApp.Images.ImageCacheStatsSnapshot do
  @moduledoc """
  Schema for storing pre-computed image cache stats snapshots.

  Stats are computed by an Oban job running daily and stored in this table.
  The admin image cache dashboard reads from the latest snapshot instead of
  computing stats on-demand, avoiding connection pool pressure.

  ## Why Background Computation?

  The stats computation involves 7 sequential database queries that can take
  7+ seconds total under load. By computing in the background and storing
  results, the admin dashboard loads instantly.
  """

  use Ecto.Schema
  import Ecto.Query
  alias EventasaurusApp.Repo

  schema "image_cache_stats_snapshots" do
    field(:stats_data, :map)
    field(:computed_at, :utc_datetime_usec)
    field(:computation_time_ms, :integer)
    field(:status, :string, default: "completed")

    timestamps()
  end

  @doc """
  Get the latest completed stats snapshot.
  Returns nil if no snapshot exists.
  """
  def get_latest do
    from(s in __MODULE__,
      where: s.status == "completed",
      order_by: [desc: s.computed_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Get the stats data from the latest snapshot.
  Returns nil if no snapshot exists.
  """
  def get_latest_stats do
    case get_latest() do
      nil -> nil
      snapshot -> atomize_keys(snapshot.stats_data)
    end
  end

  @doc """
  Insert a new stats snapshot.
  """
  def insert(attrs) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(attrs, [:stats_data, :computed_at, :computation_time_ms, :status])
    |> Ecto.Changeset.validate_required([:stats_data, :computed_at])
    |> Repo.insert()
  end

  @doc """
  Delete old snapshots, keeping only the most recent N.
  Default keeps last 5 snapshots (5 days of daily runs).
  """
  def cleanup(keep_count \\ 5) do
    # Get IDs of snapshots to keep
    keep_ids =
      from(s in __MODULE__,
        order_by: [desc: s.computed_at],
        limit: ^keep_count,
        select: s.id
      )
      |> Repo.all()

    # Delete all others
    from(s in __MODULE__, where: s.id not in ^keep_ids)
    |> Repo.delete_all()
  end

  # Convert string keys to atoms for compatibility with existing code
  # Handles JSON deserialization where keys become strings
  defp atomize_keys(nil), do: nil

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        # Try to convert to existing atom, keep as string if not possible
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> key
          end

        {atom_key, atomize_keys(value)}

      {key, value} when is_atom(key) ->
        {key, atomize_keys(value)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end
