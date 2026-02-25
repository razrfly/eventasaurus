defmodule EventasaurusDiscovery.PublicEvents.PublicEventContainers do
  @moduledoc """
  Context for managing event containers (festivals, conferences, tours, etc.)

  Handles creation, association, and querying of event containers and their memberships.
  """

  import Ecto.Query
  require Logger

  alias EventasaurusApp.Repo

  alias EventasaurusDiscovery.PublicEvents.{
    PublicEvent,
    PublicEventContainer,
    PublicEventContainerMembership
  }

  @doc """
  Get a container by ID with associations preloaded.
  """
  def get_container!(id) do
    PublicEventContainer
    |> where([c], c.id == ^id)
    |> preload([:source, :source_event, :events])
    |> Repo.one!()
  end

  @doc """
  Get a container by ID.
  """
  def get_container(id) do
    Repo.get(PublicEventContainer, id)
  end

  @doc """
  Get a container by slug with associations preloaded.
  """
  def get_container_by_slug(slug) do
    PublicEventContainer
    |> where([c], c.slug == ^slug)
    |> preload([:source, source_event: :source])
    |> Repo.one()
  end

  @doc """
  List all containers, optionally filtered by type and city.

  Options:
  - `:type` - Filter by container type
  - `:active_only` - Only return active containers
  - `:city_id` - Filter containers by city (via event venues)
  - `:with_counts` - Include event counts per container
  """
  def list_containers(opts \\ []) do
    query = PublicEventContainer

    query =
      if type = opts[:type] do
        where(query, [c], c.container_type == ^type)
      else
        query
      end

    query =
      if opts[:active_only] do
        now = DateTime.utc_now()

        where(
          query,
          [c],
          c.end_date >= ^now or (is_nil(c.end_date) and c.start_date <= ^now)
        )
      else
        query
      end

    # Filter by city if provided
    query =
      if city_id = opts[:city_id] do
        query
        |> join(:inner, [c], m in PublicEventContainerMembership, on: m.container_id == c.id)
        |> join(:inner, [c, m], e in PublicEvent, on: e.id == m.event_id)
        |> join(:inner, [c, m, e], v in assoc(e, :venue))
        |> where([c, m, e, v], v.city_id == ^city_id)
        |> distinct([c], c.id)
      else
        query
      end

    # Add event counts if requested
    query =
      if opts[:with_counts] && opts[:city_id] do
        query
        |> select([c, m, e, v], {c, count(e.id)})
        |> group_by([c], c.id)
      else
        if opts[:with_counts] do
          query
          |> join(:left, [c], m in PublicEventContainerMembership, on: m.container_id == c.id)
          |> select([c, m], {c, count(m.event_id)})
          |> group_by([c], c.id)
        else
          query
        end
      end

    results =
      query
      |> order_by([c], desc: c.start_date)
      |> preload([:source, source_event: :sources])
      |> Repo.all()

    # Transform results if counts were requested
    if opts[:with_counts] do
      Enum.map(results, fn {container, count} ->
        Map.put(container, :event_count, count)
      end)
    else
      results
    end
  end

  @doc """
  Create a container from umbrella event data.
  """
  def create_container(attrs) do
    %PublicEventContainer{}
    |> PublicEventContainer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a container.
  """
  def update_container(%PublicEventContainer{} = container, attrs) do
    container
    |> PublicEventContainer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a container and all its memberships (cascades).
  """
  def delete_container(%PublicEventContainer{} = container) do
    Repo.delete(container)
  end

  @doc """
  Refresh container dates from associated events.
  Uses hierarchical data sourcing: umbrella event dates first, then calculated.
  """
  def refresh_container_dates(%PublicEventContainer{} = container) do
    query =
      from(e in PublicEvent,
        join: m in PublicEventContainerMembership,
        on: m.event_id == e.id,
        where: m.container_id == ^container.id,
        select: %{
          min_date: min(e.starts_at),
          max_date: max(e.starts_at)
        }
      )

    case Repo.one(query) do
      %{min_date: nil, max_date: nil} ->
        # No events, keep existing dates (from umbrella event)
        {:ok, container}

      %{min_date: min_date, max_date: max_date} ->
        # If container has umbrella end_date that's valid, keep it
        # Otherwise use calculated max_date
        end_date =
          if container.end_date && DateTime.compare(container.end_date, max_date) in [:gt, :eq] do
            container.end_date
          else
            max_date
          end

        update_container(container, %{
          start_date: min_date,
          end_date: end_date
        })
    end
  end

  @doc """
  Create a container from RA umbrella event data.

  Extracts pattern matching data and stores for future association.
  """
  def create_from_umbrella_event(event_data, source_id) do
    # Extract metadata from RA event
    raw_event = get_in(event_data, [:raw_data, "event"]) || %{}

    attrs = %{
      title: event_data[:title],
      container_type: infer_container_type(event_data),
      start_date: event_data[:starts_at],
      end_date: event_data[:ends_at],
      source_id: source_id,
      title_pattern: extract_title_pattern(event_data[:title]),
      venue_pattern: get_in(raw_event, ["venue", "name"]),
      metadata: %{
        raw_event: raw_event,
        artist_count: length(raw_event["artists"] || []),
        attending_count: raw_event["attending"]
      }
    }

    case create_container(attrs) do
      {:ok, container} ->
        Logger.info("✅ Created event container: #{container.title} (#{container.container_type})")

        # Trigger retroactive association
        associate_matching_events(container)

        {:ok, container}

      {:error, changeset} ->
        Logger.error("❌ Failed to create container: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Create a container from ContainerGrouper data with multi-signal detection.

  This function handles festival containers detected by multi-signal analysis
  (promoter ID, title pattern, date range). It checks for duplicates and
  performs bidirectional association (both prospective and retrospective).
  """
  def create_from_festival_group(festival_data, source_id) do
    promoter_id = festival_data[:promoter_id]
    start_date = festival_data[:start_date]

    # Convert Date to DateTime for database queries (start_date column is utc_datetime)
    start_datetime =
      if start_date do
        start_date
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      else
        nil
      end

    end_datetime =
      if festival_data[:end_date] do
        festival_data[:end_date]
        |> DateTime.new!(~T[23:59:59], "Etc/UTC")
      else
        nil
      end

    # Check for existing container with same promoter + date (deduplication)
    existing =
      if promoter_id && start_datetime do
        PublicEventContainer
        |> where([c], c.source_id == ^source_id)
        |> where([c], fragment("?->>'promoter_id' = ?", c.metadata, ^promoter_id))
        |> where([c], c.start_date >= ^DateTime.add(start_datetime, -1 * 24 * 60 * 60, :second))
        |> where([c], c.start_date <= ^DateTime.add(start_datetime, 24 * 60 * 60, :second))
        |> Repo.one()
      else
        nil
      end

    case existing do
      nil ->
        # Create new container
        attrs = %{
          title: festival_data[:title],
          container_type: festival_data[:container_type] || :festival,
          start_date: start_datetime,
          end_date: end_datetime,
          source_id: source_id,
          title_pattern: festival_data[:title],
          metadata:
            Map.merge(festival_data[:metadata] || %{}, %{
              "promoter_id" => promoter_id,
              "promoter_name" => festival_data[:promoter_name]
            })
        }

        case create_container(attrs) do
          {:ok, container} ->
            Logger.info(
              "✅ Created festival container: #{container.title} (promoter: #{promoter_id})"
            )

            # Trigger retroactive association with existing events
            associate_matching_events(container)

            {:ok, container}

          {:error, changeset} ->
            Logger.error("❌ Failed to create festival container: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      container ->
        # Return existing container (deduplication)
        Logger.info(
          "ℹ️ Container already exists for promoter #{promoter_id} on #{start_date}: #{container.title}"
        )

        {:ok, container}
    end
  end

  @doc """
  Infer container type from event data.

  Currently simple heuristics. Can be improved with ML or explicit markers.
  """
  def infer_container_type(event_data) do
    title = String.downcase(event_data[:title] || "")

    cond do
      String.contains?(title, "festival") ->
        :festival

      String.contains?(title, "conference") || String.contains?(title, "summit") ->
        :conference

      String.contains?(title, "tour") ->
        :tour

      String.contains?(title, "exhibition") || String.contains?(title, "expo") ->
        :exhibition

      String.contains?(title, "tournament") || String.contains?(title, "championship") ->
        :tournament

      true ->
        :unknown
    end
  end

  # Extract title pattern from full title
  defp extract_title_pattern(title) when is_binary(title) do
    PublicEventContainer.extract_pattern_from_title(title)
  end

  defp extract_title_pattern(_), do: nil

  @doc """
  Find events matching a container's patterns.

  Returns events that likely belong to this container.
  Uses multi-signal detection: promoter ID (primary), title pattern, and date range.
  """
  def find_matching_events(%PublicEventContainer{} = container) do
    promoter_id = get_in(container.metadata, ["promoter_id"])

    query = PublicEvent

    # PRIMARY SIGNAL: Match by promoter ID (strongest signal)
    # Need to join with public_event_sources to access metadata
    # Promoter data is nested in metadata->raw_data->promoter_id
    query =
      if promoter_id do
        query
        |> join(:inner, [e], s in assoc(e, :sources))
        |> where([e, s], fragment("?->'raw_data'->>'promoter_id' = ?", s.metadata, ^promoter_id))
        |> distinct([e], e.id)
      else
        # Fallback to title pattern if no promoter ID
        if container.title_pattern do
          where(query, [e], ilike(e.title, ^"%#{container.title_pattern}%"))
        else
          query
        end
      end

    # BOUNDARY SIGNAL: Match by date range (±7 days tolerance for edge cases)
    query =
      if container.end_date do
        date_start = DateTime.add(container.start_date, -7 * 24 * 60 * 60, :second)
        date_end = DateTime.add(container.end_date, 7 * 24 * 60 * 60, :second)

        where(query, [e], e.starts_at >= ^date_start and e.starts_at <= ^date_end)
      else
        where(query, [e], e.starts_at >= ^container.start_date)
      end

    # Exclude the source event itself
    query =
      if container.source_event_id do
        where(query, [e], e.id != ^container.source_event_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Associate matching events with a container (retroactive).

  Called when a container is created to find and associate existing sub-events.
  """
  def associate_matching_events(%PublicEventContainer{} = container) do
    candidates = find_matching_events(container)

    Logger.info(
      "🔍 Found #{length(candidates)} potential sub-events for container #{container.id}"
    )

    Enum.each(candidates, fn event ->
      confidence = calculate_association_confidence(event, container)

      if Decimal.compare(confidence, Decimal.new("0.70")) in [:gt, :eq] do
        case create_membership(container, event, :title_match, confidence) do
          {:ok, _membership} ->
            Logger.info(
              "✅ Associated event #{event.id} with container #{container.id} (confidence: #{confidence})"
            )

          {:error, _changeset} ->
            Logger.debug("⚠️ Failed to associate event #{event.id} (may already be associated)")
        end
      else
        Logger.debug("⏭️ Skipping event #{event.id} - confidence too low (#{confidence})")
      end
    end)
  end

  @doc """
  Check if an event matches any existing containers (prospective).

  Called when importing a new event to see if it belongs to existing containers.
  Uses multi-signal detection: promoter ID (primary), title pattern (validation).
  """
  def check_for_container_match(%PublicEvent{} = event) do
    # Preload sources to access metadata with promoter information
    event = Repo.preload(event, :sources)

    # Extract promoter_id from the first source's metadata (RA source)
    # Promoter data is nested in metadata->raw_data->promoter_id
    event_promoter_id =
      case event.sources do
        [%{metadata: %{"raw_data" => %{"promoter_id" => promoter_id}}} | _] -> promoter_id
        _ -> nil
      end

    # Find containers that might match by date range with ±7 day tolerance
    # This handles edge cases where umbrella event dates don't perfectly align with sub-event dates
    # 7 days in seconds
    date_tolerance = 7 * 24 * 60 * 60
    date_min = DateTime.add(event.starts_at, -date_tolerance, :second)
    date_max = DateTime.add(event.starts_at, date_tolerance, :second)

    potential_containers =
      PublicEventContainer
      |> where(
        [c],
        c.start_date <= ^date_max and
          (is_nil(c.end_date) or c.end_date >= ^date_min)
      )
      |> Repo.all()

    Enum.each(potential_containers, fn container ->
      container_promoter_id = get_in(container.metadata, ["promoter_id"])

      # PRIMARY SIGNAL: Promoter match (strongest)
      promoter_match? = event_promoter_id && event_promoter_id == container_promoter_id

      # VALIDATION SIGNAL: Title pattern match (confirmation)
      title_match? = title_matches?(event.title, container.title_pattern)

      # DEBUG: Log matching signals
      Logger.debug("🔍 Container match check - Event #{event.id} vs Container #{container.id}")

      Logger.debug(
        "   Event promoter: #{inspect(event_promoter_id)}, Container promoter: #{inspect(container_promoter_id)}"
      )

      Logger.debug("   Promoter match: #{promoter_match?}, Title match: #{title_match?}")

      # Associate if promoter matches OR if title matches (fallback for events without promoter)
      if promoter_match? || title_match? do
        confidence = calculate_association_confidence(event, container)
        Logger.debug("   Confidence: #{confidence}")

        if Decimal.compare(confidence, Decimal.new("0.70")) in [:gt, :eq] do
          # Use :explicit for promoter matches (strongest signal), :title_match for title-based matches
          method = if promoter_match?, do: :explicit, else: :title_match

          case create_membership(container, event, method, confidence) do
            {:ok, _membership} ->
              Logger.info(
                "✅ Auto-associated new event #{event.id} with container #{container.id} (method: #{method})"
              )

            {:error, changeset} ->
              Logger.warning(
                "❌ Failed to create membership for event #{event.id} and container #{container.id}"
              )

              Logger.warning("   Changeset errors: #{inspect(changeset.errors)}")
              :ok
          end
        else
          Logger.debug("   ⚠️ Confidence too low (#{confidence} < 0.70)")
        end
      else
        Logger.debug("   ❌ No match signals")
      end
    end)
  end

  @doc """
  Calculate confidence score for event-container association.

  Uses multiple signals with weighted scoring:
  - Promoter match: 70% (PRIMARY SIGNAL - strongest indicator)
  - Title match: 20% (VALIDATION SIGNAL - confirms grouping)
  - Date range: 10% (BOUNDARY SIGNAL - prevents incorrect grouping)
  """
  def calculate_association_confidence(
        %PublicEvent{} = event,
        %PublicEventContainer{} = container
      ) do
    scores = []

    # Preload sources if not already loaded
    event = Repo.preload(event, :sources)

    # Extract promoter_id from the first source's metadata (RA source)
    # Promoter data is nested in metadata->raw_data->promoter_id
    event_promoter_id =
      case event.sources do
        [%{metadata: %{"raw_data" => %{"promoter_id" => promoter_id}}} | _] -> promoter_id
        _ -> nil
      end

    container_promoter_id = get_in(container.metadata, ["promoter_id"])

    # Signal 1: Promoter Match (70% weight) - PRIMARY SIGNAL
    scores =
      if event_promoter_id && event_promoter_id == container_promoter_id do
        [Decimal.new("0.70") | scores]
      else
        scores
      end

    # Signal 2: Title Match (20% weight) - VALIDATION SIGNAL
    scores =
      if title_matches?(event.title, container.title_pattern) do
        [Decimal.new("0.20") | scores]
      else
        scores
      end

    # Signal 3: Date Range (10% weight) - BOUNDARY SIGNAL
    scores =
      if date_within_range?(event.starts_at, container.start_date, container.end_date) do
        [Decimal.new("0.10") | scores]
      else
        scores
      end

    # Sum all scores
    Enum.reduce(scores, Decimal.new("0.00"), &Decimal.add/2)
  end

  # Check if title matches pattern
  defp title_matches?(_title, nil), do: false

  defp title_matches?(title, pattern) when is_binary(title) and is_binary(pattern) do
    title_normalized = String.downcase(title)
    pattern_normalized = String.downcase(pattern)

    String.contains?(title_normalized, pattern_normalized)
  end

  defp title_matches?(_, _), do: false

  # Check if date is within container range
  defp date_within_range?(event_date, start_date, nil) do
    DateTime.compare(event_date, start_date) in [:gt, :eq]
  end

  defp date_within_range?(event_date, start_date, end_date) do
    DateTime.compare(event_date, start_date) in [:gt, :eq] and
      DateTime.compare(event_date, end_date) in [:lt, :eq]
  end

  @doc """
  Create a membership association.
  """
  def create_membership(
        %PublicEventContainer{} = container,
        %PublicEvent{} = event,
        method,
        confidence \\ Decimal.new("1.00")
      ) do
    %PublicEventContainerMembership{}
    |> PublicEventContainerMembership.changeset(%{
      container_id: container.id,
      event_id: event.id,
      association_method: method,
      confidence_score: confidence
    })
    |> Repo.insert()
  end

  @doc """
  Delete a membership.
  """
  def delete_membership(%PublicEventContainerMembership{} = membership) do
    Repo.delete(membership)
  end

  @doc """
  Get events for a container.
  """
  def get_container_events(%PublicEventContainer{} = container) do
    PublicEvent
    |> join(:inner, [e], m in PublicEventContainerMembership, on: m.event_id == e.id)
    |> where([e, m], m.container_id == ^container.id)
    |> order_by([e, m], asc: e.starts_at, desc: m.confidence_score)
    |> preload([venue: [city_ref: :country], sources: []])
    |> Repo.all()
  end

  @doc """
  Get containers for an event.
  """
  def get_event_containers(%PublicEvent{} = event) do
    PublicEventContainer
    |> join(:inner, [c], m in PublicEventContainerMembership, on: m.container_id == c.id)
    |> where([c, m], m.event_id == ^event.id)
    |> order_by([c, m], desc: m.confidence_score)
    |> Repo.all()
  end
end
