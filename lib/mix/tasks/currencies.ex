defmodule Mix.Tasks.Currencies do
  @moduledoc """
  Mix tasks for managing currency data from Stripe API.

  ## Usage

      # Refresh currencies from Stripe API
      mix currencies.refresh

  """
  use Mix.Task
  require Logger

  @shortdoc "Manage currency data from Stripe API"

  def run(["refresh"]) do
    [:postgrex, :ecto, :eventasaurus]
    |> Enum.each(&Application.ensure_all_started/1)

    # Start the application supervisor tree if not already started
    case Eventasaurus.Application.start(:normal, []) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Wait a moment for the service to initialize
    Process.sleep(1000)

    IO.puts("Refreshing currencies from Stripe API...")
    Logger.info("Admin task: Starting currency refresh")

    case refresh_currencies() do
      :ok ->
        IO.puts("✅ Currencies refreshed successfully.")
        Logger.info("Admin task: Currency refresh completed successfully")

      {:error, reason} ->
        IO.puts("❌ Failed to refresh currencies: #{inspect(reason)}")
        Logger.error("Admin task: Currency refresh failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  def run(_) do
    IO.puts("""
    Usage:
      mix currencies.refresh    # Refresh currencies from Stripe API
    """)
  end

  defp refresh_currencies do
    try do
      # Get the service and refresh
      EventasaurusWeb.Services.StripeCurrencyService.refresh_currencies()

      # Wait a moment for the refresh to complete
      Process.sleep(2000)

      # Verify the refresh worked by checking if we got currencies
      currencies = EventasaurusWeb.Services.StripeCurrencyService.get_currencies()

      if length(currencies) > 0 do
        IO.puts("Retrieved #{length(currencies)} currencies")
        :ok
      else
        {:error, "No currencies retrieved after refresh"}
      end
    rescue
      exception ->
        Logger.error("Exception during currency refresh: #{inspect(exception)}")
        {:error, exception}
    end
  end
end
