defmodule EventasaurusApp.Monitoring.JobRegistry do
  @moduledoc """
  Registry of all known Oban workers and their configurations.

  This module maintains a curated list of Oban workers that should be monitored.
  For Phase 1 (MVP), this is a manual registry. Future versions could auto-discover
  workers by scanning the codebase.
  """

  @doc """
  Returns a list of all registered job configurations.

  Each configuration includes:
  - worker: Full module name as string (e.g., "Eventasaurus.Workers.SitemapWorker")
  - display_name: Human-readable name
  - category: :discovery | :scheduled | :maintenance | :background
  - queue: Queue name
  - schedule: Cron expression (for scheduled jobs) or nil
  - description: What this job does

  Includes regularly scheduled automated jobs (discovery, scheduled cron, maintenance).
  Excludes on-demand background jobs triggered by user actions.
  """
  def list_all_jobs do
    scheduled_jobs() ++ discovery_jobs() ++ maintenance_jobs()
  end

  @doc """
  Get configuration for a specific worker by name.
  """
  def get_job_config(worker_name) when is_binary(worker_name) do
    list_all_jobs()
    |> Enum.find(&(&1.worker == worker_name))
  end

  # Scheduled Cron Jobs (from config/config.exs Oban.Plugins.Cron)
  defp scheduled_jobs do
    [
      %{
        worker: "Eventasaurus.Workers.SitemapWorker",
        display_name: "Sitemap Generator",
        category: :scheduled,
        queue: "default",
        schedule: "0 2 * * *",
        description: "Generates XML sitemaps daily at 2 AM UTC"
      },
      %{
        worker: "EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator",
        display_name: "City Discovery Orchestrator",
        category: :scheduled,
        queue: "discovery",
        schedule: "0 0 * * *",
        description: "Orchestrates city-wide event discovery at midnight UTC"
      },
      %{
        worker: "EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker",
        display_name: "City Coordinate Recalculation",
        category: :scheduled,
        queue: "maintenance",
        schedule: "0 1 * * *",
        description: "Recalculates city coordinates daily at 1 AM UTC"
      },
      %{
        worker: "EventasaurusApp.Workers.UnsplashRefreshWorker",
        display_name: "Unsplash Images Refresh",
        category: :scheduled,
        queue: "default",
        schedule: "0 3 * * *",
        description: "Refreshes Unsplash city images daily at 3 AM UTC"
      },
      %{
        worker: "EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob",
        display_name: "Now Playing Movies Sync",
        category: :scheduled,
        queue: "scraper",
        schedule: nil,
        description: "Syncs now playing movies from TMDB"
      }
    ]
  end

  # Discovery Jobs (Event scrapers and data sync)
  defp discovery_jobs do
    [
      # Bandsintown
      %{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.IndexPageJob",
        display_name: "Bandsintown Sync",
        category: :discovery,
        queue: "scraper_index",
        schedule: nil,
        description: "Syncs events from Bandsintown"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob",
        display_name: "Bandsintown Event Details",
        category: :discovery,
        queue: "scraper_detail",
        schedule: nil,
        description: "Fetches detailed event information from Bandsintown",
        show_in_dashboard: false  # Spawned by Index job
      },

      # Resident Advisor
      %{
        worker: "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob",
        display_name: "Resident Advisor Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs events from Resident Advisor"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.EventDetailJob",
        display_name: "Resident Advisor Event Details",
        category: :discovery,
        queue: "scraper_detail",
        schedule: nil,
        description: "Fetches detailed event information from Resident Advisor",
        show_in_dashboard: false  # Spawned by Sync job
      },
      %{
        worker: "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.ArtistEnrichmentJob",
        display_name: "Resident Advisor Artist Enrichment",
        category: :discovery,
        queue: "scraper_detail",
        schedule: nil,
        description: "Enriches events with artist information from Resident Advisor",
        show_in_dashboard: false  # Spawned by Sync job
      },

      # Ticketmaster
      %{
        worker: "EventasaurusDiscovery.Apis.Ticketmaster.Jobs.CitySyncJob",
        display_name: "Ticketmaster Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs events from Ticketmaster API"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob",
        display_name: "Ticketmaster Event Processor",
        category: :discovery,
        queue: "scraper",
        schedule: nil,
        description: "Processes Ticketmaster events",
        show_in_dashboard: false  # Spawned by CitySyncJob
      },

      # Quiz Sources
      %{
        worker: "EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob",
        display_name: "Pubquiz Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs trivia events from Pubquiz"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob",
        display_name: "Question One Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs trivia events from Question One"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob",
        display_name: "Geeks Who Drink Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs trivia events from Geeks Who Drink"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.SyncJob",
        display_name: "Speed Quizzing Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs trivia events from Speed Quizzing"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.Quizmeisters.Jobs.SyncJob",
        display_name: "Quizmeisters Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs trivia events from Quizmeisters"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.Inquizition.Jobs.SyncJob",
        display_name: "Inquizition Sync",
        category: :discovery,
        queue: "discovery",
        schedule: nil,
        description: "Syncs trivia events from Inquizition"
      },

      # Movie Sources
      %{
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        display_name: "Cinema City Sync",
        category: :discovery,
        queue: "scraper",
        schedule: nil,
        description: "Syncs showtimes from Cinema City"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.DayPageJob",
        display_name: "Kino Krakow Sync",
        category: :discovery,
        queue: "scraper",
        schedule: nil,
        description: "Syncs showtimes from Kino Krakow"
      },

      # Paris Events
      %{
        worker: "EventasaurusDiscovery.Sources.Sortiraparis.Jobs.SyncJob",
        display_name: "SortirAParis Sync",
        category: :discovery,
        queue: "scraper_index",
        schedule: nil,
        description: "Syncs events from SortirAParis"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob",
        display_name: "SortirAParis Event Details",
        category: :discovery,
        queue: "scraper_detail",
        schedule: nil,
        description: "Fetches event details from SortirAParis",
        show_in_dashboard: false  # Spawned by SyncJob
      },

      # Krakow Events
      %{
        worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.IndexPageJob",
        display_name: "Karnet Sync",
        category: :discovery,
        queue: "scraper_index",
        schedule: nil,
        description: "Syncs events from Karnet"
      },
      %{
        worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob",
        display_name: "Karnet Event Details",
        category: :discovery,
        queue: "scraper_detail",
        schedule: nil,
        description: "Fetches event details from Karnet",
        show_in_dashboard: false  # Spawned by IndexPageJob
      }
    ]
  end

  # Maintenance and Background Jobs
  defp maintenance_jobs do
    [
      %{
        worker: "EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob",
        display_name: "City Coordinate Calculation",
        category: :maintenance,
        queue: "maintenance",
        schedule: nil,
        description: "Calculates coordinates for cities"
      },
      %{
        worker: "EventasaurusDiscovery.Geocoding.ProviderIdBackfillJob",
        display_name: "Geocoding Provider ID Backfill",
        category: :maintenance,
        queue: "maintenance",
        schedule: nil,
        description: "Backfills provider IDs for existing geocoded venues"
      },
      %{
        worker: "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob",
        display_name: "Venue Images Backfill Orchestrator",
        category: :maintenance,
        queue: "venue_backfill",
        schedule: nil,
        description: "Orchestrates venue image backfill operations"
      }
    ]
  end
end
