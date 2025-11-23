defmodule EventasaurusDiscovery.Sources.WeekPl.FestivalManager do
  @moduledoc """
  Manages festival containers for week.pl integration.

  ## Responsibilities
  - Create or retrieve festival containers for RestaurantWeek editions
  - Link restaurant events to festival containers
  - Handle festival-scoped aggregation similar to Resident Advisor

  ## Festival Architecture
  - Festival container: "RestaurantWeek Kraków Winter 2025"
  - Restaurant events: Individual restaurants as child events
  - Relationship: parent-child via public_event_container_memberships

  ## Example
  ```
  Festival Container: "RestaurantWeek Kraków Winter 2025"
  ├── Restaurant Event: "La Forchetta RestaurantWeek"
  ├── Restaurant Event: "Wola Verde RestaurantWeek"
  └── Restaurant Event: "Molto RestaurantWeek"
  ```
  """

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventContainers}

  @doc """
  Get or create a festival container for a specific festival and city.

  ## Parameters
  - source_id: week.pl source ID
  - festival: Map with %{code: "RWT25W", name: "RestaurantWeek Test Winter", price: 63.0}
  - city_name: City name (e.g., "Kraków")
  - country: Country name (default: "Poland")

  ## Returns
  {:ok, container} or {:error, changeset}
  """
  def get_or_create_festival_container(source_id, festival, city_name, country \\ "Poland") do
    # Create unique festival identifier: festival_code + city
    festival_identifier = "#{festival.code}_#{normalize_city(city_name)}"

    # Check if container already exists
    case find_existing_container(source_id, festival_identifier) do
      nil ->
        create_festival_container(source_id, festival, city_name, country, festival_identifier)

      container ->
        Logger.info(
          "♻️  [WeekPl.FestivalManager] Using existing festival container: #{container.title} (ID: #{container.id})"
        )

        {:ok, container}
    end
  end

  @doc """
  Link a restaurant event to its festival container.

  ## Parameters
  - event: PublicEvent struct (restaurant event)
  - container_id: Festival container ID

  ## Returns
  {:ok, membership} or {:error, reason}
  """
  def link_event_to_festival(%PublicEvent{} = event, container_id) do
    container = Repo.get(EventasaurusDiscovery.PublicEvents.PublicEventContainer, container_id)

    if container do
      PublicEventContainers.create_membership(
        container,
        event,
        # Explicit association from source data
        :explicit,
        # Full confidence
        Decimal.new("1.00")
      )
    else
      {:error, :container_not_found}
    end
  end

  # Find existing container by festival identifier
  defp find_existing_container(source_id, festival_identifier) do
    import Ecto.Query

    EventasaurusDiscovery.PublicEvents.PublicEventContainer
    |> where([c], c.source_id == ^source_id)
    |> where([c], fragment("?->>'festival_identifier' = ?", c.metadata, ^festival_identifier))
    |> Repo.one()
  end

  # Create a new festival container
  defp create_festival_container(source_id, festival, city_name, country, festival_identifier) do
    # Build festival title: "RestaurantWeek Kraków Winter 2025"
    title = build_festival_title(festival.name, city_name)

    # Calculate festival dates from festival code or use defaults
    {start_date, end_date} = extract_festival_dates(festival)

    attrs = %{
      title: title,
      container_type: :festival,
      start_date: start_date,
      end_date: end_date,
      source_id: source_id,
      title_pattern: title,
      description: build_festival_description(festival, city_name, country),
      metadata: %{
        "festival_code" => festival.code,
        "festival_name" => festival.name,
        "festival_price" => festival.price,
        "city" => city_name,
        "country" => country,
        "festival_identifier" => festival_identifier
      }
    }

    case PublicEventContainers.create_container(attrs) do
      {:ok, container} ->
        Logger.info(
          "✅ [WeekPl.FestivalManager] Created festival container: #{container.title} (ID: #{container.id})"
        )

        {:ok, container}

      {:error, changeset} ->
        Logger.error(
          "❌ [WeekPl.FestivalManager] Failed to create festival container: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  # Build festival title from festival name and city
  defp build_festival_title(festival_name, city_name) do
    "#{festival_name} #{city_name}"
  end

  # Build festival description
  defp build_festival_description(festival, city_name, country) do
    """
    #{festival.name} in #{city_name}, #{country}

    Experience specially curated menus at participating restaurants during #{festival.name}.
    Fixed price menu for #{festival.price} PLN per person.

    Explore the best of #{city_name}'s culinary scene through this limited-time restaurant festival.
    Book your table at one of the participating restaurants and enjoy a unique dining experience.
    """
    |> String.trim()
  end

  # Extract festival dates from festival struct
  # Festivals have starts_at and ends_at fields
  defp extract_festival_dates(festival) do
    start_date =
      cond do
        Map.has_key?(festival, :starts_at) && festival.starts_at ->
          # Convert Date to DateTime if needed
          case festival.starts_at do
            %Date{} = date -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
            %DateTime{} = datetime -> datetime
            _ -> DateTime.utc_now()
          end

        true ->
          DateTime.utc_now()
      end

    end_date =
      cond do
        Map.has_key?(festival, :ends_at) && festival.ends_at ->
          case festival.ends_at do
            %Date{} = date -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
            %DateTime{} = datetime -> datetime
            # Default 14 days
            _ -> DateTime.add(start_date, 14 * 24 * 60 * 60, :second)
          end

        true ->
          # Default 14 days
          DateTime.add(start_date, 14 * 24 * 60 * 60, :second)
      end

    {start_date, end_date}
  end

  # Normalize city name for identifier (lowercase, no spaces)
  defp normalize_city(city_name) do
    city_name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
  end
end
