defmodule EventasaurusWeb.Live.UsernameHelper do
  @moduledoc """
  Helper functions for handling username availability checks in LiveViews.

  This module provides utilities for making async HTTP requests to the username
  availability API and handling the responses.
  """

  import Phoenix.LiveView, only: [send_update: 2]
  require Logger

  @doc """
  Adds username checking capabilities to a LiveView.

  Call this function in your LiveView's mount or update function to enable
  handling of username check messages.

  Returns the socket unchanged - this just sets up message handling.
  """
  def enable_username_checking(socket) do
    # This function doesn't modify the socket, it just documents
    # that the LiveView should handle username check messages
    socket
  end

  @doc """
  Handle the async username check message in your LiveView.

  Add this to your LiveView's handle_info/2:

      def handle_info({:check_username_async, username, component_id}, socket) do
        UsernameHelper.handle_username_check_async(username, component_id, socket)
      end
  """
  def handle_username_check_async(username, component_id, socket) do
    # Start the async task to check username availability
    task = Task.async(fn ->
      check_username_availability(username)
    end)

    # Store the task and component info for later
    socket = socket |> Phoenix.Component.assign(:username_check_task, {task, username, component_id})

    {:noreply, socket}
  end

  @doc """
  Handle the completion of the username check task.

  Add this to your LiveView's handle_info/2:

      def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
        case socket.assigns[:username_check_task] do
          {%Task{ref: ref}, username, component_id} when ref == _ref ->
            UsernameHelper.handle_username_check_complete(socket, username, component_id)
          _ ->
            {:noreply, socket}
        end
      end

      def handle_info({ref, result}, socket) when is_reference(ref) do
        case socket.assigns[:username_check_task] do
          {%Task{ref: ^ref}, username, component_id} ->
            UsernameHelper.handle_username_check_result(socket, result, username, component_id)
          _ ->
            {:noreply, socket}
        end
      end
  """
  def handle_username_check_result(socket, result, username, component_id) do
    # Clean up the task reference
    socket = socket |> Phoenix.Component.assign(:username_check_task, nil)

    # Send result to the component
    send_update(EventasaurusWeb.UsernameInputComponent,
      id: component_id,
      check_result: result
    )

    # Also send as a general message that components can listen for
    send(self(), {:username_check_result, username, result, component_id})

    {:noreply, socket}
  end

  def handle_username_check_complete(socket, _username, _component_id) do
    # Clean up the task reference
    socket = socket |> Phoenix.Component.assign(:username_check_task, nil)
    {:noreply, socket}
  end

  @doc """
  Make HTTP request to check username availability.

  Returns a map with the API response or an error.
  """
  def check_username_availability(username) do
    url = "#{get_base_url()}/api/username/availability/#{URI.encode(username)}"

    case HTTPoison.get(url, [], [timeout: 5000, recv_timeout: 5000]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, result} -> result
          {:error, _} ->
            Logger.error("Failed to decode username check response: #{body}")
            %{"available" => false, "valid" => false, "errors" => ["Server error"], "suggestions" => []}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Username check failed with status #{status_code}: #{body}")
        %{"available" => false, "valid" => false, "errors" => ["Service temporarily unavailable"], "suggestions" => []}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Username check HTTP error: #{inspect(reason)}")
        %{"available" => false, "valid" => false, "errors" => ["Network error"], "suggestions" => []}
    end
  end

  # Get the base URL for API requests
  defp get_base_url do
    endpoint_config = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint)

    case endpoint_config[:url] do
      nil -> "http://localhost:4000"  # Development fallback
      url_config ->
        scheme = if url_config[:host] == "localhost", do: "http", else: "https"
        port_suffix = case url_config[:port] do
          nil -> ""
          80 -> ""
          443 -> ""
          port -> ":#{port}"
        end
        "#{scheme}://#{url_config[:host]}#{port_suffix}"
    end
  end
end
