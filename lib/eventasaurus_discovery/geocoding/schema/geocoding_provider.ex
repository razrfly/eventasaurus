defmodule EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider do
  @moduledoc """
  Schema for geocoding provider configuration.
  Stores minimal data: name, priority, and active status.
  Module names and display names are inferred from the name field.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "geocoding_providers" do
    field :name, :string
    field :priority, :integer
    field :is_active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :priority, :is_active])
    |> validate_required([:name, :priority])
    |> validate_number(:priority, greater_than: 0, less_than: 100)
    |> unique_constraint(:name)
  end
end
