defmodule EventasaurusApp.Events.PollOption do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Events.{Poll, PollVote}
  alias EventasaurusApp.Accounts.User

  schema "poll_options" do
    field :title, :string
    field :description, :string
    field :external_id, :string
    field :external_data, :map
    field :image_url, :string
    field :metadata, :map
    field :status, :string, default: "active"
    field :order_index, :integer, default: 0

    belongs_to :poll, Poll
    belongs_to :suggested_by, User, foreign_key: :suggested_by_id
    has_many :votes, PollVote

    timestamps()
  end

  @doc false
  def changeset(poll_option, attrs) do
    poll_option
    |> cast(attrs, [
      :title, :description, :external_id, :external_data, :image_url,
      :metadata, :status, :order_index, :poll_id, :suggested_by_id
    ])
    |> validate_required([:title, :poll_id, :suggested_by_id])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:status, ~w(active hidden removed))
    |> validate_number(:order_index, greater_than_or_equal_to: 0)
    |> validate_external_data()
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:suggested_by_id)
    |> unique_constraint([:poll_id, :suggested_by_id, :title],
         name: :poll_options_unique_per_user,
         message: "You have already suggested this option")
  end

  @doc """
  Creates a changeset for creating a new poll option.
  """
  def creation_changeset(poll_option, attrs) do
    poll_option
    |> cast(attrs, [
      :title, :description, :external_id, :external_data, :image_url,
      :metadata, :order_index, :poll_id, :suggested_by_id
    ])
    |> validate_required([:title, :poll_id, :suggested_by_id])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_number(:order_index, greater_than_or_equal_to: 0)
    |> validate_external_data()
    |> put_change(:status, "active")
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:suggested_by_id)
    |> unique_constraint([:poll_id, :suggested_by_id, :title],
         name: :poll_options_unique_per_user,
         message: "You have already suggested this option")
  end

  @doc """
  Creates a changeset for updating option status (moderation).
  """
  def status_changeset(poll_option, status) when status in ~w(active hidden removed) do
    poll_option
    |> cast(%{status: status}, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(active hidden removed))
  end

  @doc """
  Creates a changeset for updating option order.
  """
  def order_changeset(poll_option, order_index) when is_integer(order_index) do
    poll_option
    |> cast(%{order_index: order_index}, [:order_index])
    |> validate_required([:order_index])
    |> validate_number(:order_index, greater_than_or_equal_to: 0)
  end

  @doc """
  Creates a changeset for enriching option with external API data.
  """
  def enrichment_changeset(poll_option, external_data) do
    attrs = case external_data do
      %{} = data ->
        %{
          external_data: data,
          description: Map.get(data, "description") || poll_option.description,
          image_url: Map.get(data, "image_url") || poll_option.image_url,
          metadata: Map.get(data, "metadata") || poll_option.metadata
        }
      _ ->
        %{}
    end

    poll_option
    |> cast(attrs, [:external_data, :description, :image_url, :metadata])
    |> validate_external_data()
    |> validate_length(:description, max: 1000)
  end

  @doc """
  Check if the option is active (visible and voteable).
  """
  def active?(%__MODULE__{status: "active"}), do: true
  def active?(%__MODULE__{}), do: false

  @doc """
  Check if the option is hidden (not visible to voters).
  """
  def hidden?(%__MODULE__{status: "hidden"}), do: true
  def hidden?(%__MODULE__{}), do: false

  @doc """
  Check if the option is removed (soft deleted).
  """
  def removed?(%__MODULE__{status: "removed"}), do: true
  def removed?(%__MODULE__{}), do: false

  @doc """
  Check if the option has external API data.
  """
  def has_external_data?(%__MODULE__{external_data: nil}), do: false
  def has_external_data?(%__MODULE__{external_data: data}) when map_size(data) == 0, do: false
  def has_external_data?(%__MODULE__{external_data: _}), do: true

  @doc """
  Check if the option has an image.
  """
  def has_image?(%__MODULE__{image_url: nil}), do: false
  def has_image?(%__MODULE__{image_url: ""}), do: false
  def has_image?(%__MODULE__{image_url: _}), do: true

  @doc """
  Get all valid statuses.
  """
  def statuses, do: ~w(active hidden removed)

  @doc """
  Get display name for status.
  """
  def status_display("active"), do: "Active"
  def status_display("hidden"), do: "Hidden"
  def status_display("removed"), do: "Removed"

  @doc """
  Compare two poll options for sorting by order_index.
  """
  def compare(%__MODULE__{order_index: index1}, %__MODULE__{order_index: index2}) do
    cond do
      index1 < index2 -> :lt
      index1 > index2 -> :gt
      true -> :eq
    end
  end

  @doc """
  Get a short display string for the option.
  """
  def to_display_string(%__MODULE__{title: title, description: nil}), do: title
  def to_display_string(%__MODULE__{title: title, description: ""}), do: title
  def to_display_string(%__MODULE__{title: title, description: desc}) when byte_size(desc) > 50 do
    "#{title} - #{String.slice(desc, 0, 47)}..."
  end
  def to_display_string(%__MODULE__{title: title, description: desc}) do
    "#{title} - #{desc}"
  end

  @doc """
  Get external service name from external_id format.
  """
  def external_service(%__MODULE__{external_id: nil}), do: nil
  def external_service(%__MODULE__{external_id: id}) do
    cond do
      String.starts_with?(id, "tmdb:") -> "tmdb"
      String.starts_with?(id, "books:") -> "google_books"
      String.starts_with?(id, "yelp:") -> "yelp"
      String.starts_with?(id, "spotify:") -> "spotify"
      String.starts_with?(id, "places:") -> "google_places"
      true -> "unknown"
    end
  end

  @doc """
  Extract the actual ID from external_id (removing service prefix).
  """
  def extract_external_id(%__MODULE__{external_id: nil}), do: nil
  def extract_external_id(%__MODULE__{external_id: id}) do
    case String.split(id, ":", parts: 2) do
      [_service, actual_id] -> actual_id
      [actual_id] -> actual_id
    end
  end

  defp validate_external_data(changeset) do
    external_data = get_field(changeset, :external_data)

    case external_data do
      nil -> changeset
      %{} = data when map_size(data) == 0 -> changeset
      %{} = _data -> changeset  # Valid map
      _ -> add_error(changeset, :external_data, "must be a valid JSON object")
    end
  end
end
