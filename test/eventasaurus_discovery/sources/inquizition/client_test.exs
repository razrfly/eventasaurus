defmodule EventasaurusDiscovery.Sources.Inquizition.ClientTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Inquizition.Client

  @moduletag :external_api

  describe "fetch_venues/0" do
    test "fetches venues from CDN successfully" do
      assert {:ok, response} = Client.fetch_venues()
      assert is_map(response)
      assert Map.has_key?(response, "stores")
      assert is_list(response["stores"])
      assert length(response["stores"]) > 0
    end

    test "response contains expected venue structure" do
      assert {:ok, response} = Client.fetch_venues()
      stores = response["stores"]

      # Check first venue has expected fields
      first_venue = List.first(stores)
      assert is_map(first_venue)
      assert Map.has_key?(first_venue, "storeid")
      assert Map.has_key?(first_venue, "name")
      assert Map.has_key?(first_venue, "data")

      # Check data has GPS coordinates
      data = first_venue["data"]
      assert Map.has_key?(data, "map_lat")
      assert Map.has_key?(data, "map_lng")
      assert Map.has_key?(data, "address")
    end

    test "fetches expected number of venues (around 143)" do
      assert {:ok, response} = Client.fetch_venues()
      stores = response["stores"]

      # Allow some variance but should be around 143 venues
      assert length(stores) > 100
      assert length(stores) < 200
    end
  end
end
