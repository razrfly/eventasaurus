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

    # Check if name is valid
    if is_nil(normalized_attrs[:name]) or normalized_attrs[:name] == "" do
      Logger.error("Performer name is required but was blank or nil")
      {:error, :name_required}
    else
      # First try fuzzy matching to find existing performer
      # Scope by source_id if provided to avoid cross-source matches
      fuzzy_opts = [threshold: 0.85]
      fuzzy_opts = if normalized_attrs[:source_id],
        do: Keyword.put(fuzzy_opts, :source_id, normalized_attrs[:source_id]),
        else: fuzzy_opts

      case find_by_name(normalized_attrs.name, fuzzy_opts) do
        [existing | _] ->
          Logger.info("🎤 Found existing performer by fuzzy match: #{existing.name}")
          {:ok, existing}

        [] ->
          # No fuzzy match found, proceed with upsert
          upsert_by_slug(normalized_attrs)
      end
    end
  end

  defp upsert_by_slug(attrs) do
    changeset =
      %Performer{}
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

    query =
      from(p in Performer,
        where: p.slug == ^slug,
        limit: 1
      )

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
    # Convert to string keys first to ensure consistency
    string_attrs = for {key, value} <- attrs, into: %{} do
      {to_string(key), value}
    end

    # Now work with string keys consistently
    string_attrs
    |> Map.update("name", nil, fn
      nil -> nil
      name when is_binary(name) ->
        # Clean UTF-8 before any string operations
        clean_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name)
        case String.trim(clean_name) do
          "" -> nil
          trimmed -> trimmed
        end
      other ->
        # Convert to string and clean UTF-8
        clean_other = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(to_string(other))
        case String.trim(clean_other) do
          "" -> nil
          trimmed -> trimmed
        end
    end)
    |> then(fn map ->
      # Convert back to atom keys for the changeset
      %{
        name: map["name"],
        source_id: map["source_id"],
        external_id: map["external_id"],
        metadata: map["metadata"],
        type: map["type"],
        image_url: map["image_url"]
      }
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Map.new()
    end)
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

    # Clean input name to prevent jaro_distance crashes
    clean_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name)

    query = from(p in Performer)

    query =
      if source_id do
        where(query, [p], p.source_id == ^source_id)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.filter(fn performer ->
      # Clean performer name from DB - may contain invalid UTF-8
      clean_performer_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(performer.name)

      # Use String.jaro_distance for fuzzy matching
      similarity =
        String.jaro_distance(
          String.downcase(clean_performer_name),
          String.downcase(clean_name)
        )

      similarity >= threshold
    end)
    |> Enum.sort_by(fn performer ->
      # Clean performer name from DB again for sorting
      clean_performer_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(performer.name)

      # Sort by similarity (highest first)
      similarity =
        String.jaro_distance(
          String.downcase(clean_performer_name),
          String.downcase(clean_name)
        )

      -similarity
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

    query =
      from(p in Performer,
        order_by: [desc: p.inserted_at],
        limit: ^limit
      )

    query =
      if source_id do
        where(query, [p], p.source_id == ^source_id)
      else
        query
      end

    Repo.all(query)
  end
end
