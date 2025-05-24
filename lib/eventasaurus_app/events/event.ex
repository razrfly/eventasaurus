defmodule EventasaurusApp.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias Nanoid, as: NanoID



  schema "events" do
    field :title, :string
    field :tagline, :string
    field :description, :string
    field :start_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :timezone, :string
    field :visibility, Ecto.Enum, values: [:public, :private], default: :public
    field :slug, :string
    field :cover_image_url, :string # for user uploads
    field :external_image_data, :map # for Unsplash/TMDB images

    # Theme fields for the theming system
    field :theme, Ecto.Enum,
      values: [:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional],
      default: :minimal
    field :theme_customizations, :map, default: %{}

    belongs_to :venue, EventasaurusApp.Venues.Venue

    many_to_many :users, EventasaurusApp.Accounts.User,
      join_through: EventasaurusApp.Events.EventUser

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :tagline, :description, :start_at, :ends_at, :timezone,
                   :visibility, :slug, :cover_image_url, :venue_id, :external_image_data,
                   :theme, :theme_customizations])
    |> validate_required([:title, :start_at, :timezone, :visibility])
    |> validate_length(:title, min: 3, max: 100)
    |> validate_length(:tagline, max: 255)
    |> validate_length(:slug, min: 3, max: 100)
    |> validate_slug()
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint(:slug)
    |> maybe_generate_slug()

  end



  defp validate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil -> changeset
      slug ->
        if Regex.match?(~r/^[a-z0-9\-]+$/, slug) do
          changeset
        else
          add_error(changeset, :slug, "must contain only lowercase letters, numbers, and hyphens")
        end
    end
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        # Generate a random slug - first try to use Nanoid (which should be in deps)
        slug = try do
          # Generate random slug with 10 characters using the specified alphabet
          NanoID.generate(10, "0123456789abcdefghijklmnopqrstuvwxyz")
        rescue
          _ ->
            # Fallback to a custom implementation if Nanoid is unavailable
            alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

            1..10
            |> Enum.map(fn _ ->
              :rand.uniform(String.length(alphabet)) - 1
              |> then(fn idx -> String.at(alphabet, idx) end)
            end)
            |> Enum.join("")
        end

        put_change(changeset, :slug, slug)
      _ ->
        changeset
    end
  end
end
