defmodule EventasaurusDiscovery.Locations.Country.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
end

defmodule EventasaurusDiscovery.Locations.Country do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.Locations.Country.Slug

  schema "countries" do
    field :name, :string
    field :code, :string
    field :slug, Slug.Type

    has_many :cities, EventasaurusDiscovery.Locations.City

    timestamps()
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:name, :code])
    |> validate_required([:name, :code])
    |> validate_length(:code, is: 2)
    |> upcase_code()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:code)
    |> unique_constraint(:slug)
  end

  defp upcase_code(changeset) do
    case get_change(changeset, :code) do
      nil -> changeset
      code -> put_change(changeset, :code, String.upcase(code))
    end
  end
end