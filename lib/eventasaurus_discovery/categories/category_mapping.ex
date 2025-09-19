defmodule EventasaurusDiscovery.Categories.CategoryMapping do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "category_mappings" do
    field :external_source, :string
    field :external_type, :string
    field :external_value, :string
    field :external_locale, :string, default: "en"
    field :priority, :integer, default: 0

    belongs_to :category, EventasaurusDiscovery.Categories.Category

    timestamps()
  end

  @doc false
  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:external_source, :external_type, :external_value, :external_locale,
                    :category_id, :priority])
    |> validate_required([:external_source, :external_value, :category_id])
    |> validate_inclusion(:external_source, ["ticketmaster", "karnet", "bandsintown", "other"])
    |> validate_inclusion(:external_type, ["segment", "genre", "subgenre", "category", nil])
    |> validate_length(:external_locale, min: 2, max: 5)
    |> unique_constraint([:external_source, :external_type, :external_value])
    |> foreign_key_constraint(:category_id)
  end

  @doc """
  Find the best matching category for an external classification
  """
  def find_category(repo, source, type, value) do
    query = from m in __MODULE__,
      where: m.external_source == ^source,
      where: m.external_type == ^type or is_nil(m.external_type),
      where: fragment("LOWER(?) = LOWER(?)", m.external_value, ^value),
      order_by: [desc: m.priority, asc: m.id],
      limit: 1,
      preload: :category

    repo.one(query)
  end

  @doc """
  Find all matching categories for multiple classifications
  Returns categories sorted by priority
  """
  def find_categories(repo, classifications) when is_list(classifications) do
    # Build a query that finds all matching mappings
    base_query = from m in __MODULE__,
      order_by: [desc: m.priority],
      preload: :category,
      distinct: true

    # Add WHERE conditions for each classification
    query = Enum.reduce(classifications, base_query, fn {source, type, value}, query ->
      from m in query,
        or_where: m.external_source == ^source and
                  (m.external_type == ^type or is_nil(m.external_type)) and
                  fragment("LOWER(?) = LOWER(?)", m.external_value, ^value)
    end)

    repo.all(query)
    |> Enum.map(& &1.category)
    |> Enum.uniq_by(& &1.id)
  end
end