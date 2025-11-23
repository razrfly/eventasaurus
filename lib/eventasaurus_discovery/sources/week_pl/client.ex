defmodule EventasaurusDiscovery.Sources.WeekPl.Client do
  @moduledoc """
  GraphQL client for week.pl restaurant API.

  ## GraphQL Endpoint
  https://api.week.pl/graphql

  ## Queries
  - Restaurant listing with filters by region, date, time slots
  - Restaurant detail with available time slots (reservables)

  ## Example
      iex> Client.fetch_restaurants("1", "Kraków", "2025-11-20", 1140, 2)
      {:ok, %{"data" => %{"restaurants" => %{"nodes" => [...]}}}}

      iex> Client.fetch_restaurant_detail("la-forchetta", "1", "Kraków", "2025-11-20", 1140, 2)
      {:ok, %{"data" => %{"restaurant" => %{"id" => "1373", ...}}}}
  """

  require Logger
  alias EventasaurusDiscovery.Sources.WeekPl.Config

  @doc """
  Fetch restaurants for a specific region across multiple dates using GraphQL query aliases.

  ## Implementation: Option C - Query Aliases (Issue #2351)
  Uses GraphQL aliases to query 8 dates (today through +7 days) in a SINGLE API call.
  This provides comprehensive availability coverage with zero API overhead.

  ## Parameters
  - region_id: Region ID (e.g., "1" for Kraków, "5" for Warszawa)
  - region_name: Region name (e.g., "Kraków") - used for logging only
  - base_date: ISO date string to start from (typically today)
  - slot: Minutes from midnight (e.g., 1140 = 7:00 PM)
  - people_count: Party size (default: 2)

  ## Returns
  {:ok, graphql_response} | {:error, reason}

  Response format mimics Next.js Apollo state for backward compatibility.
  Restaurants are automatically deduplicated (same ID across multiple dates).
  """
  def fetch_restaurants(region_id, region_name, base_date, slot, people_count \\ 2) do
    # Build aliased query for 8 dates: today (day_0) through +7 days (day_7)
    query = """
    query GetRestaurantsMultipleDates(
      $regionId: ID!,
      $filters0: ReservationFilter,
      $filters1: ReservationFilter,
      $filters2: ReservationFilter,
      $filters3: ReservationFilter,
      $filters4: ReservationFilter,
      $filters5: ReservationFilter,
      $filters6: ReservationFilter,
      $filters7: ReservationFilter
    ) {
      day_0: restaurants(region_id: $regionId, reservation_filters: $filters0, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_1: restaurants(region_id: $regionId, reservation_filters: $filters1, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_2: restaurants(region_id: $regionId, reservation_filters: $filters2, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_3: restaurants(region_id: $regionId, reservation_filters: $filters3, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_4: restaurants(region_id: $regionId, reservation_filters: $filters4, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_5: restaurants(region_id: $regionId, reservation_filters: $filters5, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_6: restaurants(region_id: $regionId, reservation_filters: $filters6, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
      day_7: restaurants(region_id: $regionId, reservation_filters: $filters7, first: 50) {
        nodes {
          id
          name
          slug
          address
          latitude
          longitude
          tags {
            name
          }
        }
      }
    }
    """

    # Parse base date and create date strings for all 8 days
    {:ok, start_date} = Date.from_iso8601(base_date)
    dates = for day_offset <- 0..7, do: Date.add(start_date, day_offset) |> Date.to_string()

    # Build variables for each date
    variables =
      %{
        "regionId" => region_id
      }
      |> Map.merge(
        dates
        |> Enum.with_index()
        |> Enum.into(%{}, fn {date, index} ->
          {"filters#{index}",
           %{
             "startsOn" => date,
             "endsOn" => date,
             "hours" => [slot],
             "peopleCount" => people_count
           }}
        end)
      )

    Logger.debug("[WeekPl.Client] GraphQL multi-date query for #{region_name} (ID: #{region_id})")
    Logger.debug("[WeekPl.Client] Querying dates: #{Enum.join(dates, ", ")}")

    case execute_graphql_query(query, variables) do
      {:ok, %{"data" => data}} when is_map(data) ->
        # Extract restaurants from all date aliases and deduplicate by ID
        all_restaurants =
          ["day_0", "day_1", "day_2", "day_3", "day_4", "day_5", "day_6", "day_7"]
          |> Enum.flat_map(fn alias_name ->
            case Map.get(data, alias_name) do
              %{"nodes" => restaurants} when is_list(restaurants) -> restaurants
              _ -> []
            end
          end)
          |> Enum.uniq_by(fn restaurant -> restaurant["id"] end)

        # Transform to Apollo state format for backward compatibility
        apollo_state =
          all_restaurants
          |> Enum.reduce(%{}, fn restaurant, acc ->
            Map.put(acc, "Restaurant:#{restaurant["id"]}", restaurant)
          end)

        response = %{
          "pageProps" => %{
            "apolloState" => apollo_state
          }
        }

        Logger.info(
          "[WeekPl.Client] ✅ Found #{length(all_restaurants)} unique restaurants across 8 dates for #{region_name}"
        )

        {:ok, response}

      {:ok, %{"errors" => errors}} ->
        Logger.error("[WeekPl.Client] ❌ GraphQL errors: #{inspect(errors)}")
        {:error, :graphql_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch detailed restaurant data including all available time slots using GraphQL.

  ## Parameters
  - restaurant_id: Restaurant ID from the listing query (e.g., "1373")
  - slug: Restaurant slug - used for logging (e.g., "la-forchetta")
  - region_name: Region name - used for logging
  - date: ISO date string - used for filtering results client-side
  - slot: Minutes from midnight - used for logging
  - people_count: Party size (default: 2) - not used in query

  ## Returns
  {:ok, graphql_response} | {:error, reason}

  Response format mimics Next.js Apollo state with Restaurant and Daily objects.

  Note: The GraphQL API returns all reservables for a restaurant. We filter client-side
  to only include dates within 2 weeks of the requested date.
  """
  def fetch_restaurant_detail(restaurant_id, slug, region_name, date, _slot, _people_count \\ 2) do
    # Query restaurant by ID with all time slots
    # Note: reservables field is a Union type requiring fragments
    query = """
    query GetRestaurantDetail($id: ID!) {
      restaurant(id: $id) {
        id
        name
        slug
        address
        description
        latitude
        longitude
        rating
        ratingCount
        chef
        restaurator
        establishmentYear
        webUrl
        facebookUrl
        instagramUrl
        menuFileUrl
        imageFiles {
          id
          original
          preview
          profile
          thumbnail
        }
        tags {
          name
        }
        reservables {
          ... on Daily {
            id
            startsAt
            possibleSlots
          }
        }
      }
    }
    """

    variables = %{
      "id" => restaurant_id
    }

    Logger.debug(
      "[WeekPl.Client] GraphQL detail query for #{slug} (ID: #{restaurant_id}) in #{region_name}"
    )

    case execute_graphql_query(query, variables) do
      {:ok, %{"data" => %{"restaurant" => restaurant}}} when not is_nil(restaurant) ->
        # Filter reservables to only include dates within 4 weeks of requested date
        # Expanded from 2 weeks to provide better availability coverage (Issue #2351)
        start_date = Date.from_iso8601!(date)
        end_date = Date.add(start_date, 28)

        filtered_reservables =
          (restaurant["reservables"] || [])
          |> Enum.filter(fn reservable ->
            case Date.from_iso8601(reservable["startsAt"]) do
              {:ok, reservable_date} ->
                Date.compare(reservable_date, start_date) != :lt and
                  Date.compare(reservable_date, end_date) != :gt

              _ ->
                false
            end
          end)

        # Transform to Apollo state format for backward compatibility
        # Create Daily objects for each reservable date
        {apollo_state, reservable_refs} =
          filtered_reservables
          |> Enum.with_index()
          |> Enum.reduce({%{}, []}, fn {reservable, index}, {state_acc, refs_acc} ->
            daily_id = "Daily:#{index}"

            daily_obj = %{
              "__typename" => "Daily",
              "id" => "#{index}",
              "date" => reservable["startsAt"],
              "possibleSlots" => reservable["possibleSlots"] || []
            }

            new_state = Map.put(state_acc, daily_id, daily_obj)
            new_refs = [%{"__ref" => daily_id} | refs_acc]

            {new_state, new_refs}
          end)

        # Add restaurant object with references to Daily objects
        restaurant_obj =
          restaurant
          |> Map.put("__typename", "Restaurant")
          |> Map.put("reservables", Enum.reverse(reservable_refs))

        apollo_state =
          apollo_state
          |> Map.put("Restaurant:#{restaurant["id"]}", restaurant_obj)

        response = %{
          "pageProps" => %{
            "apolloState" => apollo_state
          }
        }

        slot_count =
          apollo_state
          |> Enum.filter(fn {key, _} -> String.starts_with?(key, "Daily:") end)
          |> Enum.flat_map(fn {_, daily} -> daily["possibleSlots"] || [] end)
          |> Enum.uniq()
          |> length()

        Logger.info(
          "[WeekPl.Client] ✅ Loaded #{slug} with #{length(filtered_reservables)} days, #{slot_count} unique time slots"
        )

        {:ok, response}

      {:ok, %{"data" => %{"restaurant" => nil}}} ->
        Logger.warning("[WeekPl.Client] ⚠️  Restaurant not found: #{slug}")
        {:error, :not_found}

      {:ok, %{"errors" => errors}} ->
        Logger.error("[WeekPl.Client] ❌ GraphQL errors: #{inspect(errors)}")
        {:error, :graphql_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch ongoing festival editions from the Week.pl API.

  Returns the real-time festival data including names, prices, and dates
  directly from Week.pl's GraphQL API.

  ## Returns
  {:ok, [festival_editions]} | {:error, reason}

  Each festival edition contains:
  - id: Festival edition ID
  - code: Festival code (e.g., "RW26W")
  - price: Fixed menu price in PLN
  - startsAt: Start date (ISO 8601)
  - endsAt: End date (ISO 8601)
  - festival: %{"id" => ..., "name" => ...}
  """
  def fetch_festival_editions do
    query = """
    query GetOngoingFestivalEditions {
      ongoingFestivalEditions {
        id
        code
        price
        startsAt
        endsAt
        state
        minPeopleCount
        maxPeopleCount
        festival {
          id
          name
        }
      }
    }
    """

    Logger.debug("[WeekPl.Client] Fetching ongoing festival editions from API")

    case execute_graphql_query(query, %{}) do
      {:ok, %{"data" => %{"ongoingFestivalEditions" => editions}}} when is_list(editions) ->
        Logger.info("[WeekPl.Client] ✅ Found #{length(editions)} ongoing festival editions")
        {:ok, editions}

      {:ok, %{"data" => %{"ongoingFestivalEditions" => nil}}} ->
        Logger.info("[WeekPl.Client] No ongoing festivals found")
        {:ok, []}

      {:ok, %{"errors" => errors}} ->
        Logger.error("[WeekPl.Client] ❌ GraphQL errors fetching festivals: #{inspect(errors)}")
        {:error, :graphql_error}

      {:error, reason} ->
        Logger.error("[WeekPl.Client] ❌ Failed to fetch festivals: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private Functions

  defp execute_graphql_query(query, variables) do
    url = Config.graphql_url()
    headers = Config.graphql_headers()

    body =
      Jason.encode!(%{
        "query" => query,
        "variables" => variables
      })

    case HTTPoison.post(url, body, headers,
           timeout: Config.timeout_ms(),
           recv_timeout: Config.timeout_ms()
         ) do
      {:ok, %{status_code: 200, body: response_body}} ->
        Logger.debug("[WeekPl.Client] ✅ GraphQL 200 OK")

        case Jason.decode(response_body) do
          {:ok, json} ->
            {:ok, json}

          {:error, reason} ->
            Logger.error("[WeekPl.Client] ❌ JSON parse error: #{inspect(reason)}")
            {:error, :invalid_json}
        end

      {:ok, %{status_code: 429}} ->
        Logger.warning("[WeekPl.Client] ⚠️  429 Rate Limited")
        {:error, :rate_limited}

      {:ok, %{status_code: status}} ->
        Logger.error("[WeekPl.Client] ❌ HTTP #{status}")
        {:error, :http_error}

      {:error, %{reason: reason}} ->
        Logger.error("[WeekPl.Client] ❌ Request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end
end
