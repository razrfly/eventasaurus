defmodule EventasaurusWeb.Schema.Mutations.VenueMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.VenueResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :venue_mutations do
    @desc "Create a new venue (with deduplication via VenueStore)."
    field :create_venue, non_null(:create_venue_result) do
      arg(:name, non_null(:string))
      arg(:address, :string)
      arg(:latitude, :float)
      arg(:longitude, :float)
      arg(:city_name, :string)
      arg(:country_code, :string)
      middleware(Authenticate)
      resolve(&VenueResolver.create_venue/3)
    end
  end
end
