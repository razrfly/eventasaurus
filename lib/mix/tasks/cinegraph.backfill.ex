defmodule Mix.Tasks.Cinegraph.Backfill do
  @moduledoc """
  Backfill Cinegraph sync for movies that were stamped but not synced.

  When movies have `cinegraph_synced_at` set but `cinegraph_data = nil`, the weekly
  sweep won't retry them until 7 days have passed. This task resets those movies
  so the sweep picks them up immediately.

  ## Usage

      # Dry run - show current status (no changes)
      mix cinegraph.backfill

      # Reset stamped-but-empty movies and trigger a sweep
      mix cinegraph.backfill --apply

      # Reset ALL movies (including those with data) for a full re-sync
      mix cinegraph.backfill --all

  ## What it does (--apply)

  1. Finds movies where `cinegraph_synced_at IS NOT NULL AND cinegraph_data IS NULL`
  2. Resets `cinegraph_synced_at` to nil on those movies
  3. Enqueues a sweep job so the worker picks them up

  ## What it does (--all)

  Same, but also clears `cinegraph_data` from movies that already have it,
  forcing a full re-sync of every movie.
  """

  use Mix.Task
  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.Workers.CinegraphSyncWorker

  @shortdoc "Backfill Cinegraph sync for stamped-but-empty movies"

  def run(args) do
    Mix.Task.run("app.start")

    apply_changes = "--apply" in args
    reset_all = "--all" in args

    print_status_table()

    cond do
      reset_all ->
        IO.puts("")
        IO.puts("⚠️  --all flag: resetting ALL movies (including those with cinegraph_data).")
        do_reset_all()

      apply_changes ->
        IO.puts("")
        do_apply()

      true ->
        IO.puts("")
        IO.puts("Run `mix cinegraph.backfill --apply` to reset stamped movies and trigger a sweep.")
        IO.puts("Run `mix cinegraph.backfill --all` to force a full re-sync of every movie.")
    end
  end

  defp print_status_table do
    total = Repo.one(from(m in Movie, select: count()))

    with_data =
      Repo.one(from(m in Movie, where: not is_nil(m.cinegraph_data), select: count()))

    stamped_not_found =
      Repo.one(
        from(m in Movie,
          where: is_nil(m.cinegraph_data) and not is_nil(m.cinegraph_synced_at),
          select: count()
        )
      )

    never_synced =
      Repo.one(
        from(m in Movie,
          where: is_nil(m.cinegraph_synced_at),
          select: count()
        )
      )

    IO.puts("Cinegraph Sync Status")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Total movies:         #{String.pad_leading(to_string(total), 6)}")
    IO.puts("With cinegraph_data:  #{String.pad_leading(to_string(with_data), 6)}")

    not_found_note = if stamped_not_found > 0, do: "  ← these need --apply to retry", else: ""

    IO.puts(
      "Stamped as not_found: #{String.pad_leading(to_string(stamped_not_found), 6)}#{not_found_note}"
    )

    IO.puts("Pending (never synced): #{String.pad_leading(to_string(never_synced), 4)}")
  end

  defp do_apply do
    {count, _} =
      from(m in Movie,
        where: is_nil(m.cinegraph_data) and not is_nil(m.cinegraph_synced_at)
      )
      |> Repo.update_all(set: [cinegraph_synced_at: nil])

    IO.puts("Reset #{count} movies (cleared cinegraph_synced_at).")
    enqueue_sweep()
  end

  defp do_reset_all do
    {count, _} = Repo.update_all(Movie, set: [cinegraph_synced_at: nil, cinegraph_data: nil])

    IO.puts("Reset #{count} movies (cleared cinegraph_synced_at and cinegraph_data).")
    enqueue_sweep()
  end

  defp enqueue_sweep do
    case %{sweep: true} |> CinegraphSyncWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        IO.puts("Enqueued Cinegraph sweep job.")
        IO.puts("Run `mix cinegraph.backfill` after the sweep completes to check results.")
        :ok

      {:error, reason} ->
        IO.puts("Failed to enqueue sweep job: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
