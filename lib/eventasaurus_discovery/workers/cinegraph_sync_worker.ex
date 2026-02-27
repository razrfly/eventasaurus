defmodule EventasaurusDiscovery.Workers.CinegraphSyncWorker do
  @moduledoc """
  Oban worker that syncs Cinegraph data to the movies table.

  Supports two modes dispatched on args:

  1. **Single movie**: `%{"movie_id" => id}` — fetches one movie's data and persists it.
  2. **Sweep**: `%{"sweep" => true}` — finds all movies needing sync and enqueues individual jobs.

  ## Scheduling

  The sweep runs weekly via Oban cron. Individual jobs are enqueued on movie creation
  and can also be triggered manually:

      # Single movie
      %{movie_id: movie.id}
      |> EventasaurusDiscovery.Workers.CinegraphSyncWorker.new()
      |> Oban.insert()

      # Full sweep
      %{sweep: true}
      |> EventasaurusDiscovery.Workers.CinegraphSyncWorker.new()
      |> Oban.insert()

  ## Retry Behavior

  Uses Oban's standard retry (max 3 attempts with exponential backoff).
  On failure, existing cinegraph_data is left intact.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusWeb.Services.CinegraphClient

  @sync_interval_days 7

  @spec perform(Oban.Job.t()) :: {:ok, term()} | {:error, term()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sweep" => true}}) do
    Logger.info("CinegraphSyncWorker: starting weekly sweep")

    cutoff = DateTime.add(DateTime.utc_now(), -@sync_interval_days * 24 * 3600, :second)

    movies_needing_sync =
      from(m in Movie,
        where: is_nil(m.cinegraph_synced_at) or m.cinegraph_synced_at < ^cutoff,
        where: not is_nil(m.tmdb_id),
        select: m.id
      )
      |> Repo.all()

    Logger.info("CinegraphSyncWorker: #{length(movies_needing_sync)} movies need sync")

    movies_needing_sync
    |> Enum.chunk_every(50)
    |> Enum.each(fn chunk ->
      jobs =
        Enum.map(chunk, fn movie_id ->
          EventasaurusDiscovery.Workers.CinegraphSyncWorker.new(%{movie_id: movie_id})
        end)

      Oban.insert_all(jobs)
    end)

    {:ok, %{enqueued: length(movies_needing_sync)}}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"movie_id" => movie_id}}) do
    case Repo.get(Movie, movie_id) do
      nil ->
        Logger.info("CinegraphSyncWorker: movie #{movie_id} not found in DB (deleted?)")
        {:ok, :missing}

      movie ->
        if is_nil(movie.tmdb_id) do
          Logger.info("CinegraphSyncWorker: skipping movie #{movie_id} — no tmdb_id")
          {:ok, :skipped}
        else
          sync_movie(movie)
        end
    end
  end

  defp sync_movie(movie) do
    case CinegraphClient.get_movie(movie.tmdb_id) do
      {:ok, data} ->
        result =
          movie
          |> Movie.cinegraph_changeset(%{
            cinegraph_data: data,
            cinegraph_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()

        case result do
          {:ok, _} ->
            Logger.info("CinegraphSyncWorker: synced movie #{movie.id} (tmdb_id=#{movie.tmdb_id})")
            {:ok, :synced}

          {:error, changeset} ->
            Logger.warning(
              "CinegraphSyncWorker: DB update failed for movie #{movie.id}: #{inspect(changeset.errors)}"
            )

            {:error, {:db_update_failed, changeset.errors}}
        end

      {:error, :not_found} ->
        # Movie not in Cinegraph yet — mark as attempted to avoid constant retries
        result =
          movie
          |> Movie.cinegraph_changeset(%{
            cinegraph_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()

        case result do
          {:ok, _} -> {:ok, :not_found}

          {:error, changeset} ->
            Logger.warning(
              "CinegraphSyncWorker: DB update failed for movie #{movie.id}: #{inspect(changeset.errors)}"
            )

            {:error, {:db_update_failed, changeset.errors}}
        end

      {:error, reason} ->
        Logger.warning(
          "CinegraphSyncWorker: failed for movie #{movie.id}: #{inspect(reason)}"
        )

        # Leave existing cinegraph_data intact — Oban retries up to max_attempts
        {:error, :cinegraph_unavailable}
    end
  end
end
