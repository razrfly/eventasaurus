defmodule EventasaurusDiscovery.Locations.VenueStore do
  @moduledoc """
  Handles finding or creating venues with deduplication logic.
  Uses PostGIS for geo-proximity matching and Ecto upserts for atomic operations.

  ## Deduplication Strategy

  The matching strategy uses a progressive fallback approach:
  1. **Proximity + Name**: Find venues within threshold distance and compare names
  2. **Fuzzy Name**: Find venues in same city with similar names (handles geocoding drift)
  3. **Normalized Address**: Find venues in same city with same normalized address
  4. **Exact Name**: Find venues with exact normalized name match
  5. **Create**: Create new venue if no matches found

  ## Telemetry Events

  Emits telemetry events for monitoring deduplication decisions:
  - `[:eventasaurus, :venue, :dedup, :match]` - Venue matched by a method
  - `[:eventasaurus, :venue, :dedup, :create]` - New venue created

  Metadata includes:
  - `:method` - Matching method used (proximity, fuzzy_name, address, exact_name, create)
  - `:venue_id` - ID of matched/created venue
  - `:incoming_name` - Name of incoming venue attempt
  - `:matched_name` - Name of matched venue (if applicable)
  - `:similarity_score` - Similarity score (for fuzzy matching)
  - `:distance_meters` - Distance in meters (for proximity matching)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country, VenueNameMatcher}
  import Ecto.Query
  require Logger

  # Get venue matching configuration
  @proximity_threshold_meters Application.compile_env(
                                :eventasaurus,
                                [:venue_matching, :proximity_threshold_meters],
                                1000
                              )

  @fuzzy_name_threshold Application.compile_env(
                          :eventasaurus,
                          [:venue_matching, :fuzzy_name_threshold],
                          0.6
                        )

  # Telemetry event names
  @telemetry_match [:eventasaurus, :venue, :dedup, :match]
  @telemetry_create [:eventasaurus, :venue, :dedup, :create]

  # Emit telemetry for a deduplication match
  defp emit_dedup_telemetry(:match, metadata) do
    :telemetry.execute(@telemetry_match, %{count: 1}, metadata)
  end

  defp emit_dedup_telemetry(:create, metadata) do
    :telemetry.execute(@telemetry_create, %{count: 1}, metadata)
  end

  @doc """
  Find or create venue using progressive matching strategy.
  Uses Ecto upserts for atomic operations.

  Matching order:
  1. Proximity match (within configurable threshold) + name similarity
  2. Fuzzy name match (same city, name similarity above threshold)
  3. Normalized address match (same city, same normalized address)
  4. Exact normalized name match
  5. Create new venue
  """
  def find_or_create_venue(attrs) do
    with {:ok, normalized_attrs} <- normalize_venue_attrs(attrs) do
      # Try each method in sequence, falling back to the next
      case find_by_proximity(normalized_attrs) do
        {:ok, venue} ->
          {:ok, venue}

        _ ->
          # Try fuzzy name matching within the same city
          case find_by_fuzzy_name(normalized_attrs) do
            {:ok, venue} ->
              {:ok, venue}

            _ ->
              # Try normalized address matching
              case find_by_normalized_address(normalized_attrs) do
                {:ok, venue} ->
                  {:ok, venue}

                _ ->
                  # Fall back to exact name match or create
                  case find_by_name_and_city(normalized_attrs) do
                    {:ok, venue} -> {:ok, venue}
                    _ -> create_venue(normalized_attrs)
                  end
              end
          end
      end
    else
      {:error, reason} = error ->
        Logger.error("Failed to find or create venue: #{inspect(reason)}")
        error
    end
  end

  # Step 1: Try geo-proximity match
  # Uses configurable threshold from config :eventasaurus, :venue_matching
  defp find_by_proximity(%{latitude: lat, longitude: lng, name: name, city_id: city_id})
       when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) do
    # Convert to float for PostGIS
    lat_float = to_float(lat)
    lng_float = to_float(lng)

    # Skip if coordinates couldn't be parsed
    if is_nil(lat_float) or is_nil(lng_float) do
      Logger.debug("Skipping proximity match due to invalid coordinates: #{inspect({lat, lng})}")
      nil
    else
      query =
        from(v in Venue,
          where: v.city_id == ^city_id,
          where: not is_nil(v.latitude) and not is_nil(v.longitude),
          where:
            fragment(
              "ST_DWithin(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
              v.longitude,
              v.latitude,
              ^lng_float,
              ^lat_float,
              ^@proximity_threshold_meters
            ),
          select: %{
            venue: v,
            distance:
              fragment(
                "ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)",
                v.longitude,
                v.latitude,
                ^lng_float,
                ^lat_float
              )
          },
          order_by:
            fragment(
              "ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)",
              v.longitude,
              v.latitude,
              ^lng_float,
              ^lat_float
            )
        )

      # Get all venues within proximity threshold
      candidates = Repo.all(query)

      # Filter candidates using name similarity matching
      matching_venue =
        Enum.find(candidates, fn %{venue: venue, distance: distance} ->
          case to_float(distance) do
            nil ->
              false

            distance_meters ->
              VenueNameMatcher.should_match?(name, venue.name, distance_meters)
          end
        end)

      case matching_venue do
        nil ->
          if Enum.empty?(candidates) do
            Logger.debug(
              "No venue found within #{@proximity_threshold_meters}m of (#{lat}, #{lng})"
            )
          else
            Logger.debug(
              "Found #{length(candidates)} venue(s) within #{@proximity_threshold_meters}m but none passed name similarity check for '#{name}'"
            )
          end

          nil

        %{venue: venue, distance: distance} ->
          distance_meters = to_float(distance)
          similarity_score = VenueNameMatcher.similarity_score(name, venue.name)

          Logger.info(
            "📍 Found venue by proximity + name match: '#{venue.name}' (ID:#{venue.id}) matches incoming '#{name}' at #{distance_meters}m"
          )

          emit_dedup_telemetry(:match, %{
            method: :proximity,
            venue_id: venue.id,
            incoming_name: name,
            matched_name: venue.name,
            distance_meters: distance_meters,
            similarity_score: similarity_score,
            city_id: city_id
          })

          # Decide if we should update the name based on quality
          updated_attrs = %{latitude: lat_float, longitude: lng_float}

          # Update name if the new one is significantly better
          updated_attrs =
            if should_update_venue_name?(venue.name, name) do
              Logger.info(
                "🔄 Updating venue name from '#{venue.name}' to '#{name}' (better quality)"
              )

              Map.put(updated_attrs, :name, name)
            else
              updated_attrs
            end

          case update_venue_if_needed(venue, updated_attrs) do
            {:ok, v} ->
              {:ok, v}

            {:error, changeset} ->
              Logger.error(
                "Failed to update proximity-matched venue #{venue.id}: #{inspect(changeset.errors)}"
              )

              # Still return the found venue
              {:ok, venue}
          end
      end
    end
  end

  defp find_by_proximity(_), do: nil

  # Step 2: Try fuzzy name matching within the same city
  # This catches duplicates caused by geocoding drift beyond the proximity threshold
  defp find_by_fuzzy_name(%{name: name, city_id: city_id} = attrs)
       when not is_nil(name) and not is_nil(city_id) do
    # Extract significant tokens from the incoming name to pre-filter candidates
    # This avoids loading all venues in a city into memory (performance optimization)
    tokens = VenueNameMatcher.extract_significant_tokens(name)

    if Enum.empty?(tokens) do
      Logger.debug("No significant tokens in name '#{name}' for fuzzy matching")
      nil
    else
      # Build a query that pre-filters by significant tokens using ILIKE
      # This reduces the candidate set before computing full similarity scores
      base_query =
        from(v in Venue,
          where: v.city_id == ^city_id,
          select: v
        )

      # Add ILIKE conditions for each token (OR logic - match any token)
      query =
        Enum.reduce(tokens, base_query, fn token, query ->
          pattern = "%#{token}%"
          from(v in query, or_where: ilike(v.name, ^pattern))
        end)

      venues = Repo.all(query)

      if Enum.empty?(venues) do
        Logger.debug("No venue candidates found for tokens #{inspect(tokens)} in city #{city_id}")
        nil
      else
        # Calculate similarity for each candidate and find the best match
        best_match =
          venues
          |> Enum.map(fn venue ->
            score = VenueNameMatcher.similarity_score(name, venue.name)
            {venue, score}
          end)
          |> Enum.filter(fn {_venue, score} -> score >= @fuzzy_name_threshold end)
          |> Enum.sort_by(fn {_venue, score} -> score end, :desc)
          |> List.first()

        case best_match do
          nil ->
            Logger.debug(
              "No fuzzy name match found for '#{name}' in city #{city_id} (threshold: #{@fuzzy_name_threshold * 100}%)"
            )

            nil

          {venue, score} ->
            Logger.info("""
            🔍 Found venue by fuzzy name match:
               Incoming: '#{name}'
               Matched: '#{venue.name}' (ID:#{venue.id})
               Similarity: #{Float.round(score * 100, 1)}%
               Threshold: #{Float.round(@fuzzy_name_threshold * 100, 1)}%
            """)

            emit_dedup_telemetry(:match, %{
              method: :fuzzy_name,
              venue_id: venue.id,
              incoming_name: name,
              matched_name: venue.name,
              similarity_score: score,
              city_id: city_id
            })

            # Update coordinates if the new venue has them and existing doesn't
            updated_attrs = maybe_update_coordinates(attrs, venue)

            case update_venue_if_needed(venue, updated_attrs) do
              {:ok, v} ->
                {:ok, v}

              {:error, changeset} ->
                Logger.error(
                  "Failed to update fuzzy-matched venue #{venue.id}: #{inspect(changeset.errors)}"
                )

                # Still return the found venue
                {:ok, venue}
            end
        end
      end
    end
  end

  defp find_by_fuzzy_name(_), do: nil

  # Helper to extract coordinate updates from attrs
  defp maybe_update_coordinates(
         %{latitude: lat, longitude: lng} = _attrs,
         %Venue{latitude: existing_lat, longitude: existing_lng}
       )
       when not is_nil(lat) and not is_nil(lng) do
    lat_float = to_float(lat)
    lng_float = to_float(lng)

    # Only include coordinates if they're valid and venue doesn't have them
    if lat_float && lng_float && (is_nil(existing_lat) || is_nil(existing_lng)) do
      %{latitude: lat_float, longitude: lng_float}
    else
      %{}
    end
  end

  defp maybe_update_coordinates(_, _), do: %{}

  # Step 3: Try normalized address matching within the same city
  # This catches duplicates with different names but same physical address
  defp find_by_normalized_address(%{address: address, city_id: city_id} = attrs)
       when is_binary(address) and byte_size(address) > 0 and not is_nil(city_id) do
    normalized_addr = normalize_address(address)

    if normalized_addr == "" do
      nil
    else
      # Find venues with matching normalized address in the same city
      query =
        from(v in Venue,
          where: v.city_id == ^city_id,
          where: not is_nil(v.address),
          select: v
        )

      matching_venue =
        Repo.all(query)
        |> Enum.find(fn venue ->
          normalize_address(venue.address) == normalized_addr
        end)

      case matching_venue do
        nil ->
          Logger.debug(
            "No address match found for '#{address}' (normalized: '#{normalized_addr}') in city #{city_id}"
          )

          nil

        venue ->
          Logger.info("""
          📍 Found venue by address match:
             Incoming: '#{attrs[:name]}' at '#{address}'
             Matched: '#{venue.name}' (ID:#{venue.id}) at '#{venue.address}'
             Normalized address: '#{normalized_addr}'
          """)

          emit_dedup_telemetry(:match, %{
            method: :address,
            venue_id: venue.id,
            incoming_name: attrs[:name],
            matched_name: venue.name,
            incoming_address: address,
            matched_address: venue.address,
            normalized_address: normalized_addr,
            city_id: city_id
          })

          # Update name if the incoming name is better
          updated_attrs =
            maybe_update_coordinates(attrs, venue)
            |> maybe_add_name_update(venue, attrs[:name])

          case update_venue_if_needed(venue, updated_attrs) do
            {:ok, v} ->
              {:ok, v}

            {:error, changeset} ->
              Logger.error(
                "Failed to update address-matched venue #{venue.id}: #{inspect(changeset.errors)}"
              )

              {:ok, venue}
          end
      end
    end
  end

  defp find_by_normalized_address(_), do: nil

  # Normalize address for comparison
  # Removes common Polish street prefixes and standardizes format
  defp normalize_address(address) when is_binary(address) do
    address
    |> String.downcase()
    |> String.normalize(:nfc)
    # Remove Polish street prefixes
    |> String.replace(~r/^(ul\.|ulica|ul|al\.|aleja|pl\.|plac)\s*/i, "")
    # Remove building numbers with letters (e.g., "27A" -> "27")
    |> String.replace(~r/(\d+)[a-z]/i, "\\1")
    # Remove apartment/unit numbers (e.g., "27/5" -> "27")
    |> String.replace(~r/\/\d+/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_address(_), do: ""

  # Helper to add name update if the new name is better
  defp maybe_add_name_update(attrs, venue, new_name) when is_binary(new_name) do
    if should_update_venue_name?(venue.name, new_name) do
      Map.put(attrs, :name, new_name)
    else
      attrs
    end
  end

  defp maybe_add_name_update(attrs, _venue, _name), do: attrs

  # Step 4: Try exact name + city match using upsert
  defp find_by_name_and_city(%{name: name, city_id: city_id} = attrs) when not is_nil(city_id) do
    # The normalized_name will be set by the database trigger
    venue_attrs =
      Map.merge(attrs, %{
        normalized_name: normalize_for_comparison(name)
      })

    changeset =
      %Venue{}
      |> Venue.changeset(venue_attrs)

    # Try to find existing venue first by name and city
    existing =
      from(v in Venue,
        where: v.normalized_name == ^normalize_for_comparison(name) and v.city_id == ^city_id
      )
      |> Repo.one()

    case existing do
      nil ->
        # Create new venue
        case Repo.insert(changeset) do
          {:ok, venue} ->
            Logger.info("🏢 Created new venue: #{venue.name} (#{venue.id})")

            emit_dedup_telemetry(:create, %{
              method: :exact_name_new,
              venue_id: venue.id,
              venue_name: venue.name,
              city_id: city_id
            })

            {:ok, venue}

          {:error, changeset} ->
            Logger.error("Failed to create venue: #{inspect(changeset.errors)}")
            nil
        end

      venue ->
        # Update existing venue (found by exact name match)
        Logger.info("🏢 Found venue by exact name match: #{venue.name} (#{venue.id})")

        emit_dedup_telemetry(:match, %{
          method: :exact_name,
          venue_id: venue.id,
          incoming_name: name,
          matched_name: venue.name,
          city_id: city_id
        })

        case Repo.update(Venue.changeset(venue, attrs)) do
          {:ok, venue} ->
            Logger.info("🏢 Updated existing venue: #{venue.name} (#{venue.id})")
            {:ok, venue}

          {:error, changeset} ->
            Logger.error("Failed to update venue: #{inspect(changeset.errors)}")
            # Return the existing venue even if update failed
            {:ok, venue}
        end
    end
  rescue
    e ->
      Logger.error("Exception during upsert: #{inspect(e)}")
      nil
  end

  defp find_by_name_and_city(_), do: nil

  # Step 5: Create new venue (no matches found)
  defp create_venue(attrs) do
    changeset =
      %Venue{}
      |> Venue.changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, venue} ->
        Logger.info("✨ Created new venue: #{venue.name} (#{venue.id})")

        emit_dedup_telemetry(:create, %{
          method: :no_match,
          venue_id: venue.id,
          venue_name: venue.name,
          city_id: attrs[:city_id]
        })

        {:ok, venue}

      {:error, changeset} ->
        # Try to handle unique constraint violations
        if has_unique_violation?(changeset) do
          Logger.info("Venue already exists, attempting to find it")
          find_existing_venue(attrs)
        else
          Logger.error("Failed to create venue: #{inspect(changeset.errors)}")
          {:error, changeset}
        end
    end
  end

  # Fallback: Find existing venue when creation fails
  defp find_existing_venue(%{name: name, city_id: city_id}) when not is_nil(city_id) do
    normalized_name = normalize_for_comparison(name)

    query =
      from(v in Venue,
        where: v.normalized_name == ^normalized_name and v.city_id == ^city_id,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :venue_not_found}
      venue -> {:ok, venue}
    end
  end

  defp find_existing_venue(_), do: {:error, :invalid_venue_data}

  defp normalize_for_comparison(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfc)
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_for_comparison(_), do: ""

  # Intelligently decide if we should update venue name
  defp should_update_venue_name?(existing_name, new_name) do
    cond do
      # Don't update if new name is nil or empty
      is_nil(new_name) or new_name == "" ->
        false

      # Don't update if existing is clearly better (has venue type suffix)
      has_venue_type_suffix?(existing_name) && !has_venue_type_suffix?(new_name) ->
        false

      # Update if new name is significantly longer and more descriptive
      String.length(new_name) > String.length(existing_name) * 1.3 ->
        true

      # Update if new name has venue type suffix and existing doesn't
      !has_venue_type_suffix?(existing_name) && has_venue_type_suffix?(new_name) ->
        true

      # Default: keep existing name
      true ->
        false
    end
  end

  defp has_venue_type_suffix?(name) when is_binary(name) do
    Regex.match?(
      ~r/(Arena|Stadium|Club|Hall|Theater|Theatre|Center|Centre|Venue|Stage|Room|Space|Bar|Lounge|Pub|House)$/i,
      name
    )
  end

  defp has_venue_type_suffix?(_), do: false

  defp normalize_venue_attrs(attrs) do
    normalized =
      attrs
      |> Map.put_new(:venue_type, "venue")
      |> Map.put_new(:source, "scraper")
      |> Map.put_new(:is_public, true)
      |> ensure_numeric_coordinates()
      |> ensure_city_id()

    {:ok, normalized}
  end

  defp ensure_numeric_coordinates(%{latitude: lat, longitude: lng} = attrs)
       when is_binary(lat) or is_binary(lng) do
    # Convert to floats for the database
    attrs
    |> Map.put(:latitude, to_float(lat))
    |> Map.put(:longitude, to_float(lng))
  end

  defp ensure_numeric_coordinates(attrs), do: attrs

  defp ensure_city_id(%{city_id: city_id} = attrs) when not is_nil(city_id), do: attrs

  defp ensure_city_id(%{city_name: city_name, country_code: country_code} = attrs)
       when not is_nil(city_name) and not is_nil(country_code) do
    # Try to find or create the city
    case find_or_create_city(city_name, country_code) do
      {:ok, city} -> Map.put(attrs, :city_id, city.id)
      _ -> attrs
    end
  end

  defp ensure_city_id(attrs), do: attrs

  defp find_or_create_city(city_name, country_code) do
    # First find or create country
    with {:ok, country} <- find_or_create_country(country_code),
         {:ok, city} <- find_or_create_city_in_country(city_name, country) do
      {:ok, city}
    end
  end

  defp find_or_create_country(country_code) when is_binary(country_code) do
    code = String.upcase(country_code)

    case Repo.get_by(Country, code: code) do
      nil ->
        # Create with a default name based on code
        %Country{}
        |> Country.changeset(%{
          name: country_name_from_code(code),
          code: code
        })
        |> Repo.insert()
        |> case do
          {:ok, country} ->
            {:ok, country}

          {:error, %Ecto.Changeset{} = changeset} ->
            # Handle race condition - another process may have created the country
            case Repo.get_by(Country, code: code) do
              nil -> {:error, changeset}
              country -> {:ok, country}
            end
        end

      country ->
        {:ok, country}
    end
  end

  defp find_or_create_city_in_country(city_name, %Country{id: country_id}) do
    # Try to find by name and country_id first
    # Slugs are auto-generated and globally unique, so we can't reliably predict them
    city = Repo.get_by(City, name: city_name, country_id: country_id)

    # If not found by name, check alternate names (e.g., "Warszawa" should match "Warsaw")
    city =
      city ||
        from(c in City,
          where: c.country_id == ^country_id,
          where: fragment("? = ANY(?)", ^city_name, c.alternate_names),
          limit: 1
        )
        |> Repo.one()

    case city do
      nil ->
        %City{}
        |> City.changeset(%{
          name: city_name,
          country_id: country_id
        })
        |> Repo.insert()
        |> case do
          {:ok, city} ->
            {:ok, city}

          {:error, %Ecto.Changeset{} = changeset} ->
            # Handle race condition - another process may have created the city
            # Try to fetch by name (primary lookup) or alternate names
            case Repo.get_by(City, name: city_name, country_id: country_id) do
              nil ->
                # Last attempt: check alternate_names again
                case from(c in City,
                       where: c.country_id == ^country_id,
                       where: fragment("? = ANY(?)", ^city_name, c.alternate_names),
                       limit: 1
                     )
                     |> Repo.one() do
                  nil -> {:error, changeset}
                  city -> {:ok, city}
                end

              city ->
                {:ok, city}
            end
        end

      city ->
        {:ok, city}
    end
  end

  # Helper to get country name from code using the countries library
  defp country_name_from_code(code) when is_binary(code) do
    upcase_code = String.upcase(code)

    case Countries.get(upcase_code) do
      nil ->
        Logger.warning("Unknown country code: #{code}, using code as name")
        upcase_code

      country ->
        country.name
    end
  end

  defp country_name_from_code(_), do: "Unknown"

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp to_float(nil), do: nil
  defp to_float(_), do: nil

  defp update_venue_if_needed(venue, updates) do
    if should_update_venue?(venue, updates) do
      venue
      |> Venue.changeset(updates)
      |> Repo.update()
    else
      {:ok, venue}
    end
  end

  defp should_update_venue?(venue, updates) do
    # Check if name needs updating
    name_change? =
      case Map.fetch(updates, :name) do
        {:ok, new_name} ->
          normalize_for_comparison(new_name) != normalize_for_comparison(venue.name || "")

        :error ->
          false
      end

    # Check if coordinates need updating
    coord_change? =
      case {Map.get(updates, :latitude), Map.get(updates, :longitude)} do
        {lat, lng} when not is_nil(lat) and not is_nil(lng) ->
          is_nil(venue.latitude) || is_nil(venue.longitude) ||
            !coords_equal?(venue.latitude, lat) || !coords_equal?(venue.longitude, lng)

        _ ->
          false
      end

    name_change? || coord_change?
  end

  defp coords_equal?(nil, _), do: false
  defp coords_equal?(_, nil), do: false

  defp coords_equal?(coord1, coord2) do
    # Compare coordinates with small tolerance
    f1 = to_float(coord1)
    f2 = to_float(coord2)

    if is_nil(f1) or is_nil(f2) do
      false
    else
      abs(f1 - f2) < 0.00001
    end
  end

  defp has_unique_violation?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
      opts[:constraint] == :unique
    end)
  end
end
