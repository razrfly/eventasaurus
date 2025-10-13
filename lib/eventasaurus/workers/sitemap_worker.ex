defmodule Eventasaurus.Workers.SitemapWorker do
  @moduledoc """
  Worker that generates and persists a sitemap.
  This is scheduled to run daily through Oban.

  Phase 1 includes activities and static pages.
  Future phases will add cities, venues, movies, and other content.
  """
  use Oban.Worker, queue: :default, max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Log worker details
    Logger.info("Starting scheduled sitemap generation")

    # Check AWS/Tigris credentials availability
    tigris_key = System.get_env("TIGRIS_ACCESS_KEY_ID")
    tigris_secret = System.get_env("TIGRIS_SECRET_ACCESS_KEY")
    aws_key = System.get_env("AWS_ACCESS_KEY_ID")
    aws_secret = System.get_env("AWS_SECRET_ACCESS_KEY")

    Logger.info(
      "Credentials available: Tigris (#{!is_nil(tigris_key) && !is_nil(tigris_secret)}), AWS (#{!is_nil(aws_key) && !is_nil(aws_secret)})"
    )

    Logger.info("Using production configuration for sitemap generation")
    Logger.info("Using host: wombie.com for sitemap URLs")

    # Generate and persist sitemap with explicit production configuration
    # Pass environment and host as options instead of modifying global state
    case Eventasaurus.Sitemap.generate_and_persist(
           environment: :prod,
           host: "wombie.com"
         ) do
      :ok ->
        Logger.info("Scheduled sitemap generation completed successfully")
        :ok

      {:error, error} ->
        Logger.error("Scheduled sitemap generation failed: #{inspect(error, pretty: true)}")
        # We still return :ok to avoid retries, since we've already logged the error
        :ok
    end
  end
end
