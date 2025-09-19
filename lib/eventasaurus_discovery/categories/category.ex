defmodule EventasaurusDiscovery.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :translations, :map, default: %{}
    field :icon, :string
    field :color, :string
    field :display_order, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :parent, __MODULE__, foreign_key: :parent_id
    has_many :children, __MODULE__, foreign_key: :parent_id

    # Update relationship to use many-to-many through join table
    many_to_many :public_events, EventasaurusDiscovery.PublicEvents.PublicEvent,
      join_through: "public_event_categories",
      join_keys: [category_id: :id, event_id: :id]

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :translations,
                    :icon, :color, :display_order, :is_active, :parent_id])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/, message: "must be a valid hex color")
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Get category name in specified language, fallback to English
  """
  def get_name(%__MODULE__{} = category, locale \\ "en") do
    case locale do
      "en" -> category.name
      _ -> get_in(category.translations, [locale, "name"]) || category.name
    end
  end

  @doc """
  Get category description in specified language, fallback to English
  """
  def get_description(%__MODULE__{} = category, locale \\ "en") do
    case locale do
      "en" -> category.description
      _ -> get_in(category.translations, [locale, "description"]) || category.description
    end
  end
end