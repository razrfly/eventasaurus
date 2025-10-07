defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Enrichment do
  @moduledoc """
  Helper utilities for Resident Advisor artist enrichment.

  Provides convenience functions for:
  - Scheduling enrichment jobs
  - Checking enrichment status
  - Managing enrichment workflows
  """

  require Logger

  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.ArtistEnrichmentJob
  alias EventasaurusDiscovery.Performers.{Performer, PerformerStore}
  alias EventasaurusApp.Repo

  import Ecto.Query

  @doc """
  Enrich a single performer by ID.

  ## Examples

      iex> Enrichment.enrich_performer(123)
      {:ok, :scheduled}

      iex> Enrichment.enrich_performer(999)
      {:error, :performer_not_found}
  """
  def enrich_performer(performer_id) when is_integer(performer_id) do
    case PerformerStore.get_performer(performer_id) do
      nil ->
        {:error, :performer_not_found}

      performer ->
        if has_ra_artist_id?(performer) do
          with {:ok, _job} <-
                 %{performer_id: performer.id}
                 |> ArtistEnrichmentJob.new()
                 |> Oban.insert() do
            {:ok, :scheduled}
          else
            {:error, changeset} ->
              Logger.error(
                "Failed to enqueue enrichment for performer #{performer.id}: #{inspect(changeset.errors)}"
              )

              {:error, :enqueue_failed}
          end
        else
          {:error, :no_ra_artist_id}
        end
    end
  end

  @doc """
  Enrich all performers associated with a specific event.

  Useful after importing RA events to immediately enrich their performers.
  """
  def enrich_event_performers(event_id) do
    query =
      from ep in "event_performers",
        join: p in Performer,
        on: ep.performer_id == p.id,
        where:
          ep.event_id == ^event_id and
            fragment("?->'ra_artist_id' IS NOT NULL", p.metadata),
        select: p

    performers = Repo.all(query)

    result =
      Enum.reduce_while(performers, {:ok, 0}, fn performer, {:ok, acc} ->
        case %{performer_id: performer.id} |> ArtistEnrichmentJob.new() |> Oban.insert() do
          {:ok, _job} -> {:cont, {:ok, acc + 1}}
          {:error, changeset} -> {:halt, {:error, {performer.id, changeset}}}
        end
      end)

    case result do
      {:ok, scheduled} ->
        Logger.info("Scheduled enrichment for #{scheduled} performers from event #{event_id}")
        {:ok, scheduled}

      {:error, {performer_id, changeset}} ->
        Logger.error(
          "Failed to enqueue enrichment for performer #{performer_id}: #{inspect(changeset.errors)}"
        )

        {:error, :enqueue_failed}
    end
  end

  @doc """
  Check if a performer has been enriched.
  """
  def enriched?(performer) when is_struct(performer, Performer) do
    not is_nil(get_in(performer.metadata, ["enriched_at"]))
  end

  def enriched?(performer_id) when is_integer(performer_id) do
    case PerformerStore.get_performer(performer_id) do
      nil -> false
      performer -> enriched?(performer)
    end
  end

  @doc """
  Check if a performer has an RA artist ID.
  """
  def has_ra_artist_id?(performer) when is_struct(performer, Performer) do
    not is_nil(get_in(performer.metadata, ["ra_artist_id"]))
  end

  def has_ra_artist_id?(performer_id) when is_integer(performer_id) do
    case PerformerStore.get_performer(performer_id) do
      nil -> false
      performer -> has_ra_artist_id?(performer)
    end
  end

  @doc """
  Get performers that need enrichment, grouped by priority.

  Returns:
    %{
      high_priority: [performers_without_images],
      medium_priority: [performers_without_urls],
      low_priority: [other_unenriched]
    }
  """
  def get_enrichment_queue do
    all_pending = ArtistEnrichmentJob.find_performers_needing_enrichment(1000)

    %{
      high_priority: Enum.filter(all_pending, &is_nil(&1.image_url)),
      medium_priority:
        Enum.filter(
          all_pending,
          &(not is_nil(&1.image_url) and is_nil(get_in(&1.metadata, ["ra_artist_url"])))
        ),
      low_priority:
        Enum.filter(
          all_pending,
          &(not is_nil(&1.image_url) and not is_nil(get_in(&1.metadata, ["ra_artist_url"])))
        )
    }
  end

  @doc """
  Schedule enrichment for high-priority performers (missing images).
  """
  def enrich_high_priority(limit \\ 50) do
    performers =
      Repo.all(
        from p in Performer,
          where:
            fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
              is_nil(p.image_url),
          limit: ^limit
      )

    result =
      Enum.reduce_while(performers, {:ok, 0}, fn performer, {:ok, acc} ->
        case %{performer_id: performer.id}
             |> ArtistEnrichmentJob.new(priority: 1)
             |> Oban.insert() do
          {:ok, _job} -> {:cont, {:ok, acc + 1}}
          {:error, changeset} -> {:halt, {:error, {performer.id, changeset}}}
        end
      end)

    case result do
      {:ok, scheduled} ->
        Logger.info("Scheduled high-priority enrichment for #{scheduled} performers")
        {:ok, scheduled}

      {:error, {performer_id, changeset}} ->
        Logger.error(
          "Failed to enqueue high-priority enrichment for performer #{performer_id}: #{inspect(changeset.errors)}"
        )

        {:error, :enqueue_failed}
    end
  end

  @doc """
  Get enrichment report for a performer.
  """
  def enrichment_report(performer_id) when is_integer(performer_id) do
    case PerformerStore.get_performer(performer_id) do
      nil ->
        {:error, :performer_not_found}

      performer ->
        {:ok, enrichment_report(performer)}
    end
  end

  def enrichment_report(performer) when is_struct(performer, Performer) do
    metadata = performer.metadata || %{}

    %{
      performer_id: performer.id,
      performer_name: performer.name,
      has_ra_artist_id: not is_nil(metadata["ra_artist_id"]),
      ra_artist_id: metadata["ra_artist_id"],
      has_image: not is_nil(performer.image_url),
      image_url: performer.image_url,
      has_ra_url: not is_nil(metadata["ra_artist_url"]),
      ra_artist_url: metadata["ra_artist_url"],
      country: metadata["country"],
      country_code: metadata["country_code"],
      enriched: not is_nil(metadata["enriched_at"]),
      enriched_at: metadata["enriched_at"],
      completeness_score: calculate_completeness(performer)
    }
  end

  # Calculate completeness percentage for a performer
  defp calculate_completeness(performer) do
    metadata = performer.metadata || %{}

    checks = [
      not is_nil(metadata["ra_artist_id"]),
      not is_nil(performer.image_url),
      not is_nil(metadata["ra_artist_url"]),
      not is_nil(metadata["country"]),
      not is_nil(metadata["country_code"])
    ]

    completed = Enum.count(checks, & &1)
    total = length(checks)

    Float.round(completed / total * 100, 1)
  end

  @doc """
  Clear enrichment timestamp to force re-enrichment.

  Useful for testing or when enrichment logic changes.
  """
  def reset_enrichment(performer_id) when is_integer(performer_id) do
    case PerformerStore.get_performer(performer_id) do
      nil ->
        {:error, :performer_not_found}

      performer ->
        metadata = Map.delete(performer.metadata || %{}, "enriched_at")

        performer
        |> Ecto.Changeset.change(%{metadata: metadata})
        |> Repo.update()
    end
  end
end
