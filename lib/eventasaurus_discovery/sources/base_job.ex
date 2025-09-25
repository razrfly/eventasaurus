defmodule EventasaurusDiscovery.Sources.BaseJob do
  @moduledoc """
  Base behaviour for all source synchronization jobs.

  Provides a consistent interface and common functionality for all event sources
  (Ticketmaster, BandsInTown, Eventbrite, etc.)
  """

  # Note: We don't define perform/1 as a callback since Oban.Worker already defines it

  @doc """
  Transform raw source data into our standard format
  """
  @callback transform_events(list()) :: list()

  @doc """
  Fetch events from the source for a given city
  """
  @callback fetch_events(integer(), integer(), map()) :: {:ok, list()} | {:error, term()}

  defmacro __using__(opts \\ []) do
    queue = Keyword.get(opts, :queue, :discovery)
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    priority = Keyword.get(opts, :priority, 1)

    quote do
      use Oban.Worker,
        queue: unquote(queue),
        max_attempts: unquote(max_attempts),
        priority: unquote(priority)

      @behaviour EventasaurusDiscovery.Sources.BaseJob

      require Logger

      alias EventasaurusApp.Repo
      alias EventasaurusDiscovery.Locations.City
      alias EventasaurusDiscovery.Sources.{Processor, SourceStore}

      @impl Oban.Worker
      def perform(%Oban.Job{args: args} = job) do
        city_id = args["city_id"]
        limit = args["limit"] || 100
        options = args["options"] || %{}

        with {:ok, city} <- get_city(city_id),
             {:ok, source} <- get_or_create_source(),
             {:ok, raw_events} <- fetch_events(city, limit, options),
             transformed_events <- transform_events(raw_events),
             result <- process_events(transformed_events, source) do
          case result do
            {:ok, processed} ->
              Logger.info("""
              ✅ Successfully synced #{length(processed)} events for #{city.name}
              Source: #{source.name}
              """)

              # Schedule coordinate recalculation after successful sync
              schedule_coordinate_update(city_id)

              {:ok, %{events_processed: length(processed), city: city.name}}

            {:discard, reason} ->
              # Propagate discard to Oban
              Logger.error("Job discarded: #{reason}")
              {:discard, reason}

            other ->
              other
          end
        else
          {:discard, reason} ->
            # Propagate discard to Oban
            Logger.error("Job discarded: #{reason}")
            {:discard, reason}

          {:error, reason} = error ->
            Logger.error("Failed to sync events: #{inspect(reason)}")
            error
        end
      end

      defp get_city(city_id) do
        case Repo.get(City, city_id) do
          nil -> {:error, :city_not_found}
          city -> {:ok, Repo.preload(city, :country)}
        end
      end

      defp get_or_create_source do
        SourceStore.get_or_create_source(source_config())
      end

      defp process_events(events, source) do
        Processor.process_source_data(events, source)
      end

      defp schedule_coordinate_update(city_id) do
        # Schedule the coordinate calculation job
        # It will check internally if update is needed (24hr check)
        EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob.schedule_update(city_id)
        :ok
      rescue
        error ->
          Logger.warning("Failed to schedule coordinate update for city #{city_id}: #{inspect(error)}")
          :ok  # Don't fail the main job if coordinate update scheduling fails
      end

      # Sources must implement source_config/0
      # We don't define it here to avoid conflicts

      defoverridable perform: 1
    end
  end
end
