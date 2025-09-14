defmodule EventasaurusDiscovery.Scraping.Processors.EventProcessor do
  @moduledoc """
  Processes event data from various sources.

  Handles:
  - Creating or updating public events
  - Managing event sources with priority
  - Associating events with venues and performers
  - Deduplication based on external_id
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource, PublicEventPerformer}
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.Scraping.Processors.VenueProcessor
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer

  import Ecto.Query
  require Logger

  @doc """
  Processes event data from a source.
  Creates or updates the event and manages source associations.
  """
  def process_event(event_data, source_id, source_priority \\ 10) do
    with {:ok, normalized} <- normalize_event_data(event_data),
         {:ok, venue} <- process_venue(normalized),
         {:ok, event} <- find_or_create_event(normalized, venue, source_id),
         {:ok, _source} <- update_event_source(event, source_id, source_priority, normalized),
         {:ok, _performers} <- process_performers(event, normalized) do
      {:ok, Repo.preload(event, [:venue, :performers])}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process event: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Finds an existing event by external_id and source.
  """
  def find_existing_event(external_id, source_id) do
    from(pe in PublicEvent,
      join: pes in PublicEventSource,
      on: pes.event_id == pe.id,
      where: pes.external_id == ^external_id and pes.source_id == ^source_id,
      limit: 1
    )
    |> Repo.one()
  end

  defp normalize_event_data(data) do
    normalized = %{
      external_id: data[:external_id] || data["external_id"],
      title: Normalizer.normalize_text(data[:title] || data["title"]),
      description: data[:description] || data["description"],
      start_at: parse_datetime(data[:start_at] || data["start_at"]),
      ends_at: parse_datetime(data[:ends_at] || data["ends_at"]),
      venue_data: data[:venue_data] || data["venue_data"],
      performer_names: data[:performer_names] || data["performer_names"] || [],
      metadata: data[:metadata] || data["metadata"] || %{},
      source_url: data[:source_url] || data["source_url"]
    }

    cond do
      is_nil(normalized.title) ->
        {:error, "Event title is required"}

      is_nil(normalized.start_at) ->
        {:error, "Event start time is required"}

      true ->
        {:ok, normalized}
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp process_venue(%{venue_data: nil}), do: {:ok, nil}
  defp process_venue(%{venue_data: venue_data}) do
    VenueProcessor.process_venue(venue_data)
  end

  defp find_or_create_event(data, venue, source_id) do
    slug = Normalizer.create_slug("#{data.title} #{format_date(data.start_at)}")

    # First check if we have this event from this source
    case find_existing_event(data.external_id, source_id) do
      nil ->
        # Check if we have this event from another source (by slug/title/time)
        case find_similar_event(data.title, data.start_at, venue) do
          nil -> create_event(data, venue, slug)
          existing -> {:ok, existing}
        end

      existing ->
        maybe_update_event(existing, data, venue)
    end
  end

  defp find_similar_event(_title, start_at, venue) do
    # Focus on venue + time matching (ignore title as it's unreliable)
    # Events at same venue within 2 hour window are likely the same
    start_window = DateTime.add(start_at, -7200, :second)  # 2 hours before
    end_window = DateTime.add(start_at, 7200, :second)     # 2 hours after

    # If we have a venue, that's our strongest signal
    if venue do
      from(pe in PublicEvent,
        where: pe.venue_id == ^venue.id and
               pe.starts_at >= ^start_window and
               pe.starts_at <= ^end_window,
        limit: 1
      )
      |> Repo.one()
    else
      # Without venue, we can't reliably match
      # TODO: Could check performers + date as fallback
      nil
    end
  end

  defp create_event(data, venue, slug) do
    city_id = if venue, do: venue.city_id, else: nil

    attrs = %{
      title: data.title,
      slug: slug,
      description: data.description,
      venue_id: if(venue, do: venue.id, else: nil),
      city_id: city_id,
      starts_at: data.start_at,  # Note: normalized data uses start_at, schema uses starts_at
      ends_at: data.ends_at,
      metadata: data.metadata,
      external_id: data.external_id
    }

    %PublicEvent{}
    |> PublicEvent.changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_update_event(event, data, venue) do
    updates = []

    # Only update if we have better data
    updates = if is_nil(event.description) && data.description do
      [{:description, data.description} | updates]
    else
      updates
    end

    updates = if is_nil(event.venue_id) && venue do
      [{:venue_id, venue.id}, {:city_id, venue.city_id} | updates]
    else
      updates
    end

    updates = if is_nil(event.ends_at) && data.ends_at do
      [{:ends_at, data.ends_at} | updates]
    else
      updates
    end

    if Enum.any?(updates) do
      event
      |> PublicEvent.changeset(Map.new(updates))
      |> Repo.update()
    else
      {:ok, event}
    end
  end

  defp update_event_source(event, source_id, priority, data) do
    # Find or create the event source record
    event_source = Repo.get_by(PublicEventSource,
      event_id: event.id,
      source_id: source_id
    ) || %PublicEventSource{}

    # Store priority in metadata if provided
    base = data.metadata || %{}
    metadata =
      case priority do
        nil -> base
        p -> Map.put(base, "priority", p)
      end

    attrs = %{
      event_id: event.id,
      source_id: source_id,
      external_id: data.external_id,
      source_url: data.source_url,
      last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: metadata
    }

    event_source
    |> PublicEventSource.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp process_performers(_event, %{performer_names: []}), do: {:ok, []}
  defp process_performers(event, %{performer_names: names}) do
    performers = Enum.map(names, fn name ->
      find_or_create_performer(name)
    end)

    # Clear existing associations
    from(pep in PublicEventPerformer, where: pep.event_id == ^event.id)
    |> Repo.delete_all()

    # Create new associations
    associations = Enum.with_index(performers, 1) |> Enum.map(fn {performer, index} ->
      %PublicEventPerformer{}
      |> PublicEventPerformer.changeset(%{
        event_id: event.id,
        performer_id: performer.id,
        metadata: %{
          "billing_order" => index,
          "is_headliner" => index == 1
        }
      })
      |> Repo.insert!()
    end)

    {:ok, associations}
  end

  defp find_or_create_performer(name) do
    normalized_name = Normalizer.normalize_text(name)
    slug = Normalizer.create_slug(normalized_name)

    Repo.get_by(Performer, slug: slug) ||
      create_performer(normalized_name, slug)
  end

  defp create_performer(name, slug) do
    %Performer{}
    |> Performer.changeset(%{
      name: name,
      slug: slug,
      performer_type: "unknown"
    })
    |> Repo.insert!()
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end
end