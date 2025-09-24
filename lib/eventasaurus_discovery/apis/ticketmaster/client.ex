defmodule EventasaurusDiscovery.Apis.Ticketmaster.Client do
  @moduledoc """
  HTTP client for Ticketmaster Discovery API.
  Implements the ApiAdapter behavior for consistent API integration.
  """

  @behaviour EventasaurusDiscovery.Apis.Behaviors.ApiAdapter

  require Logger
  alias EventasaurusDiscovery.Apis.Ticketmaster.{Config, Transformer}

  @impl true
  def api_config, do: Config.api_config()

  @impl true
  def fetch_events_by_city(latitude, longitude, city_name, options \\ %{}) do
    params =
      Config.default_params()
      |> Map.merge(%{
        latlong: "#{latitude},#{longitude}",
        radius: options[:radius] || Config.default_radius(),
        unit: options[:unit] || "km",
        page: options[:page] || 0,
        size: options[:size] || Config.default_page_size()
      })
      |> maybe_add_date_range(options)

    Logger.info("""
    🎫 Fetching Ticketmaster events for #{city_name}
    Coordinates: (#{latitude}, #{longitude})
    Radius: #{params.radius}#{params.unit}
    Page: #{params.page}, Size: #{params.size}
    """)

    case make_request("/events.json", params) do
      {:ok, response} ->
        events = response["_embedded"]["events"] || []
        page_info = response["page"] || %{}

        Logger.info(
          "✅ Found #{page_info["totalElements"] || 0} total events (fetched #{length(events)})"
        )

        transformed_events = Enum.map(events, &Transformer.transform_event/1)
        {:ok, transformed_events}

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch events: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def fetch_event_details(event_id) do
    Logger.info("🎫 Fetching details for event: #{event_id}")

    case make_request("/events/#{event_id}.json", Config.default_params()) do
      {:ok, event} ->
        {:ok, Transformer.transform_event(event)}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def fetch_venue_details(venue_id) do
    Logger.info("🏛️ Fetching details for venue: #{venue_id}")

    case make_request("/venues/#{venue_id}.json", Config.default_params()) do
      {:ok, venue} ->
        {:ok, Transformer.transform_venue(venue)}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def fetch_performer_details(performer_id) do
    Logger.info("🎤 Fetching details for performer: #{performer_id}")

    case make_request("/attractions/#{performer_id}.json", Config.default_params()) do
      {:ok, attraction} ->
        {:ok, Transformer.transform_performer(attraction)}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def transform_event(raw_data), do: Transformer.transform_event(raw_data)

  @impl true
  def transform_venue(raw_data), do: Transformer.transform_venue(raw_data)

  @impl true
  def transform_performer(raw_data), do: Transformer.transform_performer(raw_data)

  @impl true
  def validate_response(response) do
    cond do
      Map.has_key?(response, "fault") ->
        {:error, response["fault"]["faultstring"] || "Unknown API error"}

      Map.has_key?(response, "errors") ->
        {:error, format_errors(response["errors"])}

      true ->
        :ok
    end
  end

  # Additional methods for pagination and bulk fetching

  def fetch_all_events_by_city(latitude, longitude, city_name, options \\ %{}) do
    max_pages = options[:max_pages] || 10
    fetch_all_pages(latitude, longitude, city_name, 0, max_pages, [], options)
  end

  defp fetch_all_pages(latitude, longitude, city_name, current_page, max_pages, acc, options)
       when current_page < max_pages do
    options = Map.put(options, :page, current_page)

    case fetch_events_by_city(latitude, longitude, city_name, options) do
      {:ok, events} when events != [] ->
        new_acc = acc ++ events

        fetch_all_pages(
          latitude,
          longitude,
          city_name,
          current_page + 1,
          max_pages,
          new_acc,
          options
        )

      {:ok, []} ->
        # No more events
        {:ok, acc}

      {:error, _reason} = error ->
        if acc == [] do
          error
        else
          # Return what we have so far
          Logger.warning(
            "Stopped at page #{current_page} due to error, returning #{length(acc)} events"
          )

          {:ok, acc}
        end
    end
  end

  defp fetch_all_pages(
         _latitude,
         _longitude,
         _city_name,
         _current_page,
         _max_pages,
         acc,
         _options
       ) do
    {:ok, acc}
  end

  # Private helper functions

  defp make_request(endpoint, params) do
    url = Config.build_url(endpoint)

    client =
      Tesla.client([
        {Tesla.Middleware.BaseUrl, ""},
        {Tesla.Middleware.Query, params},
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Timeout, timeout: Config.timeout()},
        {Tesla.Middleware.Retry,
         delay: 1000,
         max_retries: Config.max_retries(),
         max_delay: 10_000,
         should_retry: fn
           {:ok, %{status: status}} when status in [429, 500, 502, 503, 504] -> true
           {:error, _} -> true
           _ -> false
         end}
      ])

    case Tesla.get(client, url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        case validate_response(body) do
          :ok -> {:ok, body}
          error -> error
        end

      {:ok, %Tesla.Env{status: 401}} ->
        {:error, "Authentication failed - check your API key"}

      {:ok, %Tesla.Env{status: 429}} ->
        {:error, "Rate limit exceeded"}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, "Resource not found"}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_msg =
          if is_map(body) && body["fault"],
            do: body["fault"]["faultstring"],
            else: "HTTP #{status}"

        {:error, error_msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_add_date_range(params, %{start_date: start_date, end_date: end_date}) do
    params
    |> Map.put(:startDateTime, format_datetime(start_date))
    |> Map.put(:endDateTime, format_datetime(end_date))
  end

  defp maybe_add_date_range(params, _), do: params

  defp format_datetime(%Date{} = date) do
    "#{Date.to_iso8601(date)}T00:00:00Z"
  end

  defp format_datetime(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_datetime(_), do: nil

  defp format_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(fn error -> error["detail"] || error["message"] || "Unknown error" end)
    |> Enum.join(", ")
  end

  defp format_errors(error), do: inspect(error)
end
