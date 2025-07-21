defmodule EventasaurusApp.Groups.Group do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.SoftDelete.Schema
  alias Nanoid, as: NanoID

  schema "groups" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :cover_image_url, :string
    field :avatar_url, :string
    
    # Venue fields (for Google Places integration)
    field :venue_name, :string
    field :venue_address, :string
    field :venue_city, :string
    field :venue_state, :string
    field :venue_country, :string
    field :venue_latitude, :float
    field :venue_longitude, :float
    
    belongs_to :venue, EventasaurusApp.Venues.Venue
    belongs_to :created_by, EventasaurusApp.Accounts.User, foreign_key: :created_by_id
    
    many_to_many :users, EventasaurusApp.Accounts.User,
      join_through: EventasaurusApp.Groups.GroupUser
    
    has_many :events, EventasaurusApp.Events.Event
    
    # Deletion metadata fields
    field :deletion_reason, :string
    belongs_to :deleted_by_user, EventasaurusApp.Accounts.User, foreign_key: :deleted_by_user_id
    
    timestamps()
    soft_delete_schema()
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :slug, :description, :cover_image_url, :avatar_url, :venue_id, :created_by_id,
                   :venue_name, :venue_address, :venue_city, :venue_state, :venue_country,
                   :venue_latitude, :venue_longitude])
    |> validate_required([:name, :created_by_id])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_length(:slug, min: 3, max: 100)
    |> validate_slug()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:created_by_id)
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
        # Generate a random slug using the same pattern as events
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