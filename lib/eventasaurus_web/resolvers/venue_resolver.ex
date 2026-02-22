defmodule EventasaurusWeb.Resolvers.VenueResolver do
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Events
  alias EventasaurusDiscovery.Locations.VenueStore

  def search_venues(_parent, %{query: query} = args, _resolution) do
    limit = Map.get(args, :limit, 20)

    venues =
      Venues.search_venues(query)
      |> Enum.take(limit)

    {:ok, venues}
  end

  def my_recent_venues(_parent, args, %{context: %{current_user: user}}) do
    limit = Map.get(args, :limit, 10)
    recent = Events.get_recent_locations_for_user(user.id, limit: limit)

    venues =
      Enum.map(recent, fn loc ->
        %{
          id: loc.id,
          name: loc.name,
          address: loc.address,
          latitude: nil,
          longitude: nil,
          usage_count: loc.usage_count
        }
      end)

    {:ok, venues}
  end

  def create_venue(_parent, args, _resolution) do
    attrs =
      %{
        name: args.name,
        address: Map.get(args, :address),
        latitude: Map.get(args, :latitude),
        longitude: Map.get(args, :longitude),
        source: "user"
      }
      |> maybe_put(:city_name, Map.get(args, :city_name))
      |> maybe_put(:country_code, Map.get(args, :country_code))

    case VenueStore.find_or_create_venue(attrs) do
      {:ok, venue} ->
        {:ok, %{venue: venue, errors: []}}

      {:error, %Ecto.Changeset{} = changeset} ->
        # When duplicate detection finds a nearby venue, return it instead of erroring
        case extract_duplicate_venue_id(changeset) do
          {:ok, venue_id} ->
            case Venues.get_venue(venue_id) do
              nil ->
                {:ok, %{venue: nil, errors: format_changeset_errors(changeset)}}

              venue ->
                {:ok, %{venue: venue, errors: []}}
            end

          :not_duplicate ->
            {:ok, %{venue: nil, errors: format_changeset_errors(changeset)}}
        end

      {:error, reason} ->
        {:ok, %{venue: nil, errors: [%{field: "base", message: to_string(reason)}]}}
    end
  end

  defp extract_duplicate_venue_id(changeset) do
    base_errors = Keyword.get_values(changeset.errors, :base)

    duplicate_error =
      Enum.find(base_errors, fn {msg, _opts} ->
        String.contains?(msg, "Duplicate venue found:")
      end)

    case duplicate_error do
      {msg, _opts} ->
        case Regex.run(~r/ID:\s*(\d+)/, msg) do
          [_, id_str] -> {:ok, String.to_integer(id_str)}
          _ -> :not_duplicate
        end

      nil ->
        :not_duplicate
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, &%{field: to_string(field), message: &1})
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
