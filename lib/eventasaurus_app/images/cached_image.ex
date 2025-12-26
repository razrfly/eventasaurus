defmodule EventasaurusApp.Images.CachedImage do
  @moduledoc """
  Represents a cached copy of an external image stored in R2.

  This schema supports polymorphic associations, allowing any entity type
  (venues, performers, events, etc.) to have cached images.

  ## Status Lifecycle

  - `pending` - Record created, waiting for download job
  - `downloading` - Job is actively downloading the image
  - `cached` - Successfully downloaded and stored in R2
  - `failed` - Download failed after all retries

  ## Entity Types

  Supported entity types:
  - `venue` - Venue images
  - `public_event_source` - Event source images
  - `performer` - Performer/artist images
  - `event` - Event cover images
  - `movie` - Movie posters and backdrops
  - `group` - Group avatars and covers

  ## Ordering

  Images are ordered by `position` (0-based index). Position 0 is typically
  used as the primary/hero image, but this is a display concern, not a
  schema concern.

  ## Metadata Field

  **IMPORTANT**: The `metadata` field is a raw dump of whatever the original
  source provided. This is NOT for application logic or parsing. It exists
  solely to preserve original source data (Google Places attribution, quality
  scores, provider URLs, etc.) so we don't lose information during migration.

  If something from metadata becomes important for queries or display, promote
  it to a proper column. Don't parse metadata in application code.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @valid_statuses ~w(pending downloading cached failed)
  @valid_entity_types ~w(venue public_event_source performer event movie group)

  schema "cached_images" do
    # Polymorphic association
    field(:entity_type, :string)
    field(:entity_id, :integer)
    field(:position, :integer, default: 0)

    # Source tracking
    field(:original_url, :string)
    field(:original_source, :string)

    # R2 storage
    field(:r2_key, :string)
    field(:cdn_url, :string)

    # Status tracking
    field(:status, :string, default: "pending")
    field(:retry_count, :integer, default: 0)
    field(:last_error, :string)

    # File metadata
    field(:content_type, :string)
    field(:file_size, :integer)

    # Raw source data - DO NOT PARSE, just preserve
    # See moduledoc for details
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new cached image record.
  """
  def changeset(cached_image, attrs) do
    cached_image
    |> cast(attrs, [
      :entity_type,
      :entity_id,
      :position,
      :original_url,
      :original_source,
      :r2_key,
      :cdn_url,
      :status,
      :retry_count,
      :last_error,
      :content_type,
      :file_size,
      :metadata
    ])
    |> validate_required([:entity_type, :entity_id, :position, :original_url])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_entity_type()
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:entity_type, :entity_id, :position])
  end

  @doc """
  Changeset for updating cache status after download attempt.
  """
  def cache_result_changeset(cached_image, attrs) do
    cached_image
    |> cast(attrs, [
      :r2_key,
      :cdn_url,
      :status,
      :retry_count,
      :last_error,
      :content_type,
      :file_size
    ])
    |> validate_inclusion(:status, @valid_statuses)
  end

  defp validate_entity_type(changeset) do
    validate_change(changeset, :entity_type, fn :entity_type, entity_type ->
      # Allow known types or any type with underscore (for future types)
      if entity_type in @valid_entity_types or String.contains?(entity_type, "_") do
        []
      else
        [entity_type: "must be a valid entity type"]
      end
    end)
  end

  # Query helpers

  @doc """
  Query for finding a cached image by entity and position.
  """
  def for_entity(entity_type, entity_id, position) do
    from(c in __MODULE__,
      where:
        c.entity_type == ^entity_type and
          c.entity_id == ^entity_id and
          c.position == ^position
    )
  end

  @doc """
  Query for finding all cached images for an entity, ordered by position.
  """
  def for_entity(entity_type, entity_id) do
    from(c in __MODULE__,
      where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
      order_by: [asc: c.position]
    )
  end

  @doc """
  Query for finding cached image by original URL.
  """
  def by_original_url(url) do
    from(c in __MODULE__, where: c.original_url == ^url)
  end

  @doc """
  Query for pending images that need to be cached.
  """
  def pending do
    from(c in __MODULE__,
      where: c.status == "pending",
      order_by: [asc: c.inserted_at]
    )
  end

  @doc """
  Query for failed images that can be retried.
  """
  def retriable(max_retries \\ 3) do
    from(c in __MODULE__,
      where: c.status == "failed" and c.retry_count < ^max_retries,
      order_by: [asc: c.updated_at]
    )
  end

  @doc """
  Query for successfully cached images.
  """
  def cached do
    from(c in __MODULE__, where: c.status == "cached")
  end

  # Status helpers

  @doc """
  Check if the image is successfully cached.
  """
  def cached?(%__MODULE__{status: "cached"}), do: true
  def cached?(_), do: false

  @doc """
  Check if the image can be retried.
  """
  def retriable?(cached_image, max_retries \\ 3)

  def retriable?(%__MODULE__{status: "failed", retry_count: count}, max_retries) do
    count < max_retries
  end

  def retriable?(_, _), do: false

  @doc """
  Get the effective URL for this cached image.
  Returns cdn_url if cached, original_url as fallback.
  """
  def effective_url(%__MODULE__{status: "cached", cdn_url: cdn_url}) when is_binary(cdn_url) do
    cdn_url
  end

  def effective_url(%__MODULE__{original_url: url}), do: url
end
