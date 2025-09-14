defmodule EventasaurusDiscovery.Performers.PerformerStore do
  @moduledoc """
  Handles finding or creating performers with deduplication logic.
  Uses Ecto upserts for atomic operations and normalized names for matching.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer
  import Ecto.Query
  require Logger

  @doc """
  Find or create performer using upsert pattern based on slug.
  First tries fuzzy matching to avoid duplicates.
  """
  def find_or_create_performer(attrs) do
    normalized_attrs = normalize_performer_attrs(attrs)

    # First try fuzzy matching to find existing performer
    case find_by_name(normalized_attrs.name, threshold: 0.85) do
      [existing | _] ->
        Logger.info("🎤 Found existing performer by fuzzy match: #{existing.name}")
        {:ok, existing}
      [] ->
        # No fuzzy match found, proceed with upsert
        upsert_by_slug(normalized_attrs)
    end
  end

  defp upsert_by_slug(attrs) do
    changeset = %Performer{}
    |> Performer.changeset(attrs)

    case Repo.insert(changeset,
      on_conflict: {:replace, [:name, :image_url, :metadata, :updated_at]},
      conflict_target: :slug,
      returning: true
    ) do
      {:ok, performer} ->
        Logger.info("🎤 Upserted performer: #{performer.name} (#{performer.id})")
        {:ok, performer}
      {:error, changeset} ->
        # Try to find existing performer
        if has_unique_violation?(changeset) do
          find_existing_performer(attrs)
        else
          Logger.error("Failed to upsert performer: #{inspect(changeset.errors)}")
          {:error, changeset}
        end
    end
  rescue
    e ->
      Logger.error("Exception during upsert: #{inspect(e)}")
      {:error, e}
  end

  defp find_existing_performer(%{name: name}) do
    # Generate slug using the shared Normalizer
    slug =
      name
      |> Normalizer.normalize_text()
      |> Normalizer.create_slug()

    query = from p in Performer,
      where: p.slug == ^slug,
      limit: 1

    case Repo.one(query) do
      nil ->
        Logger.error("Could not find existing performer: #{name}")
        {:error, :performer_not_found}
      performer ->
        Logger.info("Found existing performer: #{performer.name} (#{performer.id})")
        {:ok, performer}
    end
  end

  defp normalize_performer_attrs(attrs) do
    attrs
    |> Map.put_new(:source_id, get_default_source_id())
    |> Map.update(:name, "", &String.trim/1)
  end

  defp get_default_source_id do
    # TODO: Get or create a Bandsintown source
    # For now, use a fixed ID (1) or create the source if needed
    1
  end

  defp has_unique_violation?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
      opts[:constraint] == :unique
    end)
  end


  @doc """
  Find performers by name (fuzzy match).
  """
  def find_by_name(name, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.8)
    source_id = Keyword.get(opts, :source_id)

    query = from p in Performer

    query = if source_id do
      where(query, [p], p.source_id == ^source_id)
    else
      query
    end

    query
    |> Repo.all()
    |> Enum.filter(fn performer ->
      # Use Akin for fuzzy matching on names directly
      similarity = Akin.compare(
        String.downcase(performer.name),
        String.downcase(name)
      )
      similarity >= threshold
    end)
    |> Enum.sort_by(fn performer ->
      # Sort by similarity (highest first)
      -Akin.compare(
        String.downcase(performer.name),
        String.downcase(name)
      )
    end)
  end

  @doc """
  Update performer information (e.g., image, genre).
  """
  def update_performer(%Performer{} = performer, attrs) do
    performer
    |> Performer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  List all performers, optionally filtered by source.
  """
  def list_performers(opts \\ []) do
    source_id = Keyword.get(opts, :source_id)
    limit = Keyword.get(opts, :limit, 100)

    query = from p in Performer,
      order_by: [desc: p.inserted_at],
      limit: ^limit

    query = if source_id do
      where(query, [p], p.source_id == ^source_id)
    else
      query
    end

    Repo.all(query)
  end
end