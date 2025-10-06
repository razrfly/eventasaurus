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
  List all containers, optionally filtered by type.
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
        where(query, [c], c.end_date >= ^now or (is_nil(c.end_date) and c.start_date >= ^now))
      else
        query
      end

    query
    |> order_by([c], desc: c.start_date)
    |> Repo.all()
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
  Infer container type from event data.

  Currently simple heuristics. Can be improved with ML or explicit markers.
  """
  def infer_container_type(event_data) do
    title = String.downcase(event_data[:title] || "")

    cond do
      String.contains?(title, "festival") -> :festival
      String.contains?(title, "conference") || String.contains?(title, "summit") -> :conference
      String.contains?(title, "tour") -> :tour
      String.contains?(title, "exhibition") || String.contains?(title, "expo") -> :exhibition
      String.contains?(title, "tournament") || String.contains?(title, "championship") -> :tournament
      true -> :unknown
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
  """
  def find_matching_events(%PublicEventContainer{} = container) do
    query = PublicEvent

    # Match by title pattern
    query =
      if container.title_pattern do
        where(query, [e], ilike(e.title, ^"%#{container.title_pattern}%"))
      else
        query
      end

    # Match by date range
    query =
      where(query, [e],
        e.starts_at >= ^container.start_date and
          (is_nil(^container.end_date) or e.starts_at <= ^container.end_date)
      )

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

    Logger.info("🔍 Found #{length(candidates)} potential sub-events for container #{container.id}")

    Enum.each(candidates, fn event ->
      confidence = calculate_association_confidence(event, container)

      if Decimal.compare(confidence, Decimal.new("0.70")) in [:gt, :eq] do
        case create_membership(container, event, :title_match, confidence) do
          {:ok, _membership} ->
            Logger.info("✅ Associated event #{event.id} with container #{container.id} (confidence: #{confidence})")

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
  """
  def check_for_container_match(%PublicEvent{} = event) do
    # Find containers that might match
    potential_containers =
      PublicEventContainer
      |> where([c],
        c.start_date <= ^event.starts_at and
          (is_nil(c.end_date) or c.end_date >= ^event.starts_at)
      )
      |> Repo.all()

    Enum.each(potential_containers, fn container ->
      if title_matches?(event.title, container.title_pattern) do
        confidence = calculate_association_confidence(event, container)

        if Decimal.compare(confidence, Decimal.new("0.70")) in [:gt, :eq] do
          case create_membership(container, event, :title_match, confidence) do
            {:ok, _membership} ->
              Logger.info("✅ Auto-associated new event #{event.id} with container #{container.id}")

            {:error, _changeset} ->
              :ok
          end
        end
      end
    end)
  end

  @doc """
  Calculate confidence score for event-container association.

  Uses multiple signals with weighted scoring:
  - Title match: 40%
  - Date range: 30%
  - Artist overlap: 20%
  - Venue pattern: 10%
  """
  def calculate_association_confidence(%PublicEvent{} = event, %PublicEventContainer{} = container) do
    scores = []

    # Signal 1: Title Match (40% weight)
    scores =
      if title_matches?(event.title, container.title_pattern) do
        [Decimal.new("0.40") | scores]
      else
        scores
      end

    # Signal 2: Date Range (30% weight)
    scores =
      if date_within_range?(event.starts_at, container.start_date, container.end_date) do
        [Decimal.new("0.30") | scores]
      else
        scores
      end

    # Signal 3: Artist Overlap (20% weight) - TODO: Implement when artist data available
    # Signal 4: Venue Pattern (10% weight) - TODO: Implement when venue patterns available

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
    |> order_by([e, m], [asc: e.starts_at, desc: m.confidence_score])
    |> preload(:venue)
    |> Repo.all()
  end

  @doc """
  Get containers for an event.
  """
  def get_event_containers(%PublicEvent{} = event) do
    PublicEventContainer
    |> join(:inner, [c], m in PublicEventContainerMembership, on: m.container_id == c.id)
    |> where([c, m], m.event_id == ^event.id)
    |> order_by([c, m], [desc: m.confidence_score])
    |> Repo.all()
  end
end
