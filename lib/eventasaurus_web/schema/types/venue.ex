defmodule EventasaurusWeb.Schema.Types.Venue do
  use Absinthe.Schema.Notation

  object :venue do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:address, :string)
    field(:latitude, :float)
    field(:longitude, :float)
  end

  object :recent_venue do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:address, :string)
    field(:latitude, :float)
    field(:longitude, :float)
    field(:usage_count, non_null(:integer))
  end

  object :create_venue_result do
    field(:venue, :venue)
    field(:errors, list_of(non_null(:input_error)))
  end
end
