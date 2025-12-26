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
  - `venue` - Venue images (primary, gallery)
  - `public_event_source` - Event source images
  - `performer` - Performer/artist images
  - `event` - Event cover images
  - `movie` - Movie posters and backdrops
  - `group` - Group avatars and covers

  ## Image Roles

  Common roles:
  - `primary` - Main/hero image
  - `poster` - Movie poster
  - `backdrop` - Movie backdrop
  - `avatar` - Profile image
  - `cover` - Cover/banner image
  - `gallery_0`, `gallery_1`, etc. - Gallery images
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @valid_statuses ~w(pending downloading cached failed)
  @valid_entity_types ~w(venue public_event_source performer event movie group)
  @valid_image_roles ~w(primary poster backdrop avatar cover hero gallery)

  schema "cached_images" do
    # Polymorphic association
    field(:entity_type, :string)
    field(:entity_id, :integer)
    field(:image_role, :string)

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

    # Metadata
    field(:content_type, :string)
    field(:file_size, :integer)
    field(:width, :integer)
    field(:height, :integer)
    field(:metadata, :map, default: %{})

    # Cache timing
    field(:cached_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)

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
      :image_role,
      :original_url,
      :original_source,
      :r2_key,
      :cdn_url,
      :status,
      :retry_count,
      :last_error,
      :content_type,
      :file_size,
      :width,
      :height,
      :metadata,
      :cached_at,
      :expires_at
    ])
    |> validate_required([:entity_type, :entity_id, :image_role, :original_url])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_entity_type()
    |> validate_image_role()
    |> unique_constraint([:entity_type, :entity_id, :image_role])
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
      :file_size,
      :width,
      :height,
      :cached_at
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

  defp validate_image_role(changeset) do
    validate_change(changeset, :image_role, fn :image_role, role ->
      # Allow known roles or gallery_N pattern
      base_role = role |> String.split("_") |> List.first()

      if base_role in @valid_image_roles do
        []
      else
        [image_role: "must be a valid image role"]
      end
    end)
  end

  # Query helpers

  @doc """
  Query for finding a cached image by entity and role.
  """
  def for_entity(entity_type, entity_id, image_role) do
    from(c in __MODULE__,
      where:
        c.entity_type == ^entity_type and
          c.entity_id == ^entity_id and
          c.image_role == ^image_role
    )
  end

  @doc """
  Query for finding all cached images for an entity.
  """
  def for_entity(entity_type, entity_id) do
    from(c in __MODULE__,
      where: c.entity_type == ^entity_type and c.entity_id == ^entity_id,
      order_by: [asc: c.image_role]
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

  @doc """
  Query for expired cached images.
  """
  def expired do
    now = DateTime.utc_now()

    from(c in __MODULE__,
      where: c.status == "cached" and not is_nil(c.expires_at) and c.expires_at < ^now
    )
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
