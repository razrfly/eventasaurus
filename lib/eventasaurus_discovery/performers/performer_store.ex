defmodule EventasaurusDiscovery.Performers.PerformerStore do
  @moduledoc """
  Handles finding or creating performers with deduplication logic.
  Uses Ecto upserts for atomic operations and normalized names for matching.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Performers.Performer
  import Ecto.Query
  require Logger

  @doc """
  Find or create performer using upsert pattern.
  Prioritizes external_id, then normalized name.
  """
  def find_or_create_performer(attrs) do
    normalized_attrs = normalize_performer_attrs(attrs)

    # Try upsert by external_id first
    if normalized_attrs[:external_id] do
      upsert_by_external_id(normalized_attrs)
    else
      upsert_by_name(normalized_attrs)
    end
  end

  defp upsert_by_external_id(attrs) do
    changeset = %Performer{}
    |> Performer.changeset(attrs)

    case Repo.insert(changeset,
      on_conflict: {:replace, [:name, :image_url, :genre, :updated_at]},
      conflict_target: [:external_id, :source_id],
      returning: true
    ) do
      {:ok, performer} ->
        Logger.info("🎤 Upserted performer by external_id: #{performer.name} (#{performer.id})")
        {:ok, performer}
      {:error, changeset} ->
        Logger.error("Failed to upsert performer by external_id: #{inspect(changeset.errors)}")
        # Fallback to name-based upsert
        upsert_by_name(attrs)
    end
  rescue
    e ->
      Logger.error("Exception during external_id upsert: #{inspect(e)}")
      upsert_by_name(attrs)
  end

  defp upsert_by_name(attrs) do
    # Ensure we have normalized_name for the constraint
    attrs = Map.put(attrs, :normalized_name, normalize_performer_name(attrs[:name]))

    changeset = %Performer{}
    |> Performer.changeset(attrs)

    case Repo.insert(changeset,
      on_conflict: {:replace, [:image_url, :genre, :external_id, :updated_at]},
      conflict_target: [:normalized_name, :source_id],
      returning: true
    ) do
      {:ok, performer} ->
        Logger.info("🎤 Upserted performer by name: #{performer.name} (#{performer.id})")
        {:ok, performer}
      {:error, changeset} ->
        # Last resort: try to find existing performer
        if has_unique_violation?(changeset) do
          find_existing_performer(attrs)
        else
          Logger.error("Failed to upsert performer: #{inspect(changeset.errors)}")
          {:error, changeset}
        end
    end
  rescue
    e ->
      Logger.error("Exception during name upsert: #{inspect(e)}")
      {:error, e}
  end

  defp find_existing_performer(%{name: name, source_id: source_id}) do
    normalized_name = normalize_performer_name(name)

    query = from p in Performer,
      where: p.normalized_name == ^normalized_name and p.source_id == ^source_id,
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
    |> Map.put(:normalized_name, normalize_performer_name(attrs[:name]))
  end

  defp normalize_performer_name(nil), do: ""
  defp normalize_performer_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfc)
    |> String.replace(~r/[^a-z0-9]/, "")
  end
  defp normalize_performer_name(_), do: ""

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
  Find performer by external ID.
  """
  def find_by_external_id(external_id, source_id \\ nil) do
    query = from p in Performer,
      where: p.external_id == ^external_id

    query = if source_id do
      where(query, [p], p.source_id == ^source_id)
    else
      query
    end

    Repo.one(query)
  end

  @doc """
  Find performers by name (fuzzy match).
  """
  def find_by_name(name, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.8)
    source_id = Keyword.get(opts, :source_id)
    normalized_name = normalize_performer_name(name)

    query = from p in Performer

    query = if source_id do
      where(query, [p], p.source_id == ^source_id)
    else
      query
    end

    query
    |> Repo.all()
    |> Enum.filter(fn performer ->
      # Use Akin for fuzzy matching
      similarity = Akin.compare(
        normalize_performer_name(performer.name),
        normalized_name
      )
      similarity >= threshold
    end)
    |> Enum.sort_by(fn performer ->
      # Sort by similarity (highest first)
      -Akin.compare(
        normalize_performer_name(performer.name),
        normalized_name
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