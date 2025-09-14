defmodule Mix.Tasks.TestVenueMatching do
  @moduledoc """
  Test venue coordinate matching.
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  import Ecto.Query

  @shortdoc "Test venue coordinate matching"

  def run(_args) do
    Application.ensure_all_started(:eventasaurus)

    # Get a sample venue
    venue = Repo.one(from v in Venue, where: not is_nil(v.latitude), limit: 1)

    if venue do
      Logger.info("""

      Testing venue matching for: #{venue.name}
      Coordinates: (#{venue.latitude}, #{venue.longitude})
      City ID: #{venue.city_id}
      """)

      # Try to find it by coordinates
      lat = if is_struct(venue.latitude, Decimal), do: Decimal.to_float(venue.latitude), else: venue.latitude
      lng = if is_struct(venue.longitude, Decimal), do: Decimal.to_float(venue.longitude), else: venue.longitude

      Logger.info("Converted coords: (#{lat}, #{lng})")

      # Simple query
      found = from(v in Venue,
        where: v.city_id == ^venue.city_id,
        limit: 5
      )
      |> Repo.all()

      Logger.info("Found #{length(found)} venues in city #{venue.city_id}")

      # Try coordinate matching
      lat_delta = 0.001  # About 100m
      lng_delta = 0.001

      found_by_coords = from(v in Venue,
        where: v.city_id == ^venue.city_id and
               fragment("CAST(? AS float8) >= ?", v.latitude, ^(lat - lat_delta)) and
               fragment("CAST(? AS float8) <= ?", v.latitude, ^(lat + lat_delta)) and
               fragment("CAST(? AS float8) >= ?", v.longitude, ^(lng - lng_delta)) and
               fragment("CAST(? AS float8) <= ?", v.longitude, ^(lng + lng_delta))
      )
      |> Repo.all()

      Logger.info("Found #{length(found_by_coords)} venues by coordinates")
      Enum.each(found_by_coords, fn v ->
        Logger.info("  - #{v.name} at (#{v.latitude}, #{v.longitude})")
      end)
    else
      Logger.error("No venues with coordinates found!")
    end
  end
end