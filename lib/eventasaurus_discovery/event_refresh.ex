defmodule EventasaurusDiscovery.EventRefresh do
  @moduledoc """
  Context for refreshing event availability data from various sources.

  Provides a unified interface for user-initiated refresh requests.
  Delegates to source-specific refresh handlers.

  ## Usage

      # Refresh an event's availability
      EventRefresh.refresh_event(event_id, user_id: current_user_id)

  ## Supported Sources

  - week_pl: Restaurant availability refresh via EventAvailabilityRefreshJob

  ## Adding New Sources

  To add refresh support for a new source:
  1. Create a refresh job in the source's jobs directory
  2. Add a handler in this module's `handle_refresh/3` pattern matches
  3. Ensure the job broadcasts updates via PubSub to the event's topic
  """

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  import Ecto.Query

  # Rate limit: minimum time between refresh requests (in seconds)
  @refresh_cooldown_seconds 60

  @doc """
  Refresh event availability data from its source.

  ## Options

  - `:user_id` - ID of user requesting refresh (optional, for rate limiting)

  ## Returns

  - `{:ok, job}` - Refresh job queued successfully
  - `{:error, :no_refreshable_source}` - Event has no sources that support refresh
  - `{:error, :event_not_found}` - Event ID not found
  - `{:error, :rate_limited}` - Refresh requested too soon after last refresh
  - `{:error, reason}` - Other error
  """
  def refresh_event(event_id, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    # Load event with sources preloaded
    event =
      from(pe in PublicEvent,
        where: pe.id == ^event_id,
        preload: [sources: :source]
      )
      |> Repo.one()

    case event do
      nil ->
        {:error, :event_not_found}

      event ->
        # Find first source that supports refresh
        refreshable_source = find_refreshable_source(event.sources)

        case refreshable_source do
          nil ->
            {:error, :no_refreshable_source}

          source ->
            # Check rate limiting before proceeding
            case check_rate_limit(source) do
              {:ok, _} ->
                handle_refresh(source.source.slug, event, source, user_id)

              {:error, :rate_limited} = error ->
                error
            end
        end
    end
  end

  @doc """
  Check if an event has any sources that support refresh.
  """
  def refreshable?(event) do
    find_refreshable_source(event.sources) != nil
  end

  # Private Functions

  defp check_rate_limit(source) do
    metadata = source.metadata || %{}
    last_refreshed_at = metadata["availability_last_refreshed_at"]

    case last_refreshed_at do
      nil ->
        # Never refreshed before, allow refresh
        {:ok, :allowed}

      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, last_refresh_time, _} ->
            now = DateTime.utc_now()
            seconds_since_refresh = DateTime.diff(now, last_refresh_time, :second)

            if seconds_since_refresh < @refresh_cooldown_seconds do
              Logger.info(
                "[EventRefresh] Rate limit hit for source #{source.id}: refreshed #{seconds_since_refresh}s ago (cooldown: #{@refresh_cooldown_seconds}s)"
              )

              {:error, :rate_limited}
            else
              {:ok, :allowed}
            end

          {:error, _} ->
            # Invalid timestamp format, allow refresh
            Logger.warning(
              "[EventRefresh] Invalid timestamp format for source #{source.id}: #{inspect(timestamp)}"
            )

            {:ok, :allowed}
        end

      _ ->
        # Unexpected format, allow refresh
        {:ok, :allowed}
    end
  end

  defp find_refreshable_source(sources) do
    Enum.find(sources, fn source ->
      source.source && supports_refresh?(source.source.slug)
    end)
  end

  defp supports_refresh?("week_pl"), do: true
  defp supports_refresh?(_), do: false

  # Source-specific refresh handlers

  defp handle_refresh("week_pl", event, source, user_id) do
    metadata = source.metadata || %{}
    restaurant_id = metadata["restaurant_id"]

    # Extract slug from website_url (e.g., "https://week.pl/slay-space" -> "slay-space")
    # Handle trailing slashes to avoid empty strings
    restaurant_slug =
      case metadata["website_url"] do
        url when is_binary(url) ->
          url
          |> String.trim_trailing("/")
          |> String.split("/")
          |> List.last()

        _ ->
          nil
      end

    if restaurant_id && restaurant_slug do
      args = %{
        "event_id" => event.id,
        "source_slug" => "week_pl",
        "restaurant_id" => restaurant_id,
        "restaurant_slug" => restaurant_slug,
        "requested_by_user_id" => user_id
      }

      Oban.insert(
        EventasaurusDiscovery.Sources.WeekPl.Jobs.EventAvailabilityRefreshJob.new(args)
      )
    else
      Logger.warning(
        "[EventRefresh] week_pl source missing restaurant_id or website_url for event #{event.id} (metadata: #{inspect(metadata)})"
      )

      {:error, :invalid_source_metadata}
    end
  end

  defp handle_refresh(source_slug, _event, _source, _user_id) do
    Logger.warning("[EventRefresh] Unsupported source for refresh: #{source_slug}")
    {:error, :unsupported_source}
  end
end
