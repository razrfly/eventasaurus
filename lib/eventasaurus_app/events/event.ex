defmodule EventasaurusApp.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Events.EventUser

  schema "events" do
    field :title, :string
    field :tagline, :string
    field :description, :string
    field :start_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :timezone, :string
    field :visibility, Ecto.Enum, values: [:public, :private], default: :public
    field :slug, :string
    field :cover_image_url, :string

    belongs_to :venue, Venue
    many_to_many :users, User, join_through: EventUser

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :tagline, :description, :start_at, :ends_at, :timezone, :visibility, :slug, :cover_image_url, :venue_id])
    |> validate_required([:title, :description, :start_at, :ends_at, :timezone, :visibility])
    |> validate_length(:title, min: 3, max: 100)
    |> validate_length(:description, min: 10, max: 2000)
    |> validate_slug()
    |> maybe_generate_slug()
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint(:slug)
  end

  defp validate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil -> changeset
      _slug_value -> validate_format(changeset, :slug, ~r/^[a-z0-9\-]+$/, message: "must contain only lowercase letters, numbers and hyphens")
    end
  end

  defp maybe_generate_slug(changeset) do
    if changeset.valid? && !get_change(changeset, :slug) && get_change(changeset, :title) do
      title = get_change(changeset, :title)
      slug = title
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9\s-]/, "")
        |> String.replace(~r/\s+/, "-")
        |> String.replace(~r/-+/, "-")
        |> String.trim("-")

      put_change(changeset, :slug, slug)
    else
      changeset
    end
  end
end
