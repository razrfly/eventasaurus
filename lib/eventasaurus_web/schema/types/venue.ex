defmodule EventasaurusWeb.Schema.Types.Venue do
  use Absinthe.Schema.Notation

  object :venue do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:address, :string)
    field(:latitude, :float)
    field(:longitude, :float)
  end
end
