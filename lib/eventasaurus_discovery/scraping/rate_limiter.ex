defmodule EventasaurusDiscovery.Scraping.RateLimiter do
  @moduledoc """
  Handles rate limiting for API calls and job scheduling.

  Provides centralized rate limiting functionality for:
  - Scheduling jobs with delays to avoid overwhelming external APIs
  - Configuring job retry parameters
  - Managing hourly job caps for different sources
  """

  require Logger

  # Default configuration
  @defaults %{
    # seconds between jobs
    job_delay_interval: 2,
    # max retry attempts
    max_attempts: 5,
    # job priority (lower = higher priority)
    priority: 3,
    # skip recently updated events
    skip_if_updated_within_days: 7,
    # max jobs per hour per source
    max_jobs_per_hour: 100
  }

  @doc """
  Returns the default max_attempts for jobs.
  """
  def max_attempts, do: @defaults.max_attempts

  @doc """
  Returns the default priority for jobs.
  """
  def priority, do: @defaults.priority

  @doc """
  Returns the default job delay interval in seconds.
  """
  def job_delay_interval, do: @defaults.job_delay_interval

  @doc """
  Returns the default days threshold for skipping recently updated content.
  """
  def skip_if_updated_within_days, do: @defaults.skip_if_updated_within_days

  @doc """
  Returns the maximum number of jobs to schedule per hour.
  """
  def max_jobs_per_hour, do: @defaults.max_jobs_per_hour

  @doc """
  Checks if a job should force update all items regardless of last update time.
  """
  def force_update?(args) when is_map(args) do
    Map.get(args, "force_update", false) || Map.get(args, :force_update, false)
  end

  @doc """
  Schedules a batch of jobs with incremental delays.

  ## Parameters
  - `items` - List of items to process
  - `job_fn` - Function that takes (item, index, delay) and returns an Oban job

  ## Returns
  The number of successfully scheduled jobs.
  """
  def schedule_jobs_with_delay(items, job_fn) when is_list(items) and is_function(job_fn, 3) do
    Logger.info("📋 Scheduling #{length(items)} jobs with rate limiting...")

    Enum.reduce(Enum.with_index(items), 0, fn {item, index}, count ->
      # Calculate delay based on index (in seconds)
      delay_seconds = index * job_delay_interval()

      # Create the job with the calculated delay
      job = job_fn.(item, index, delay_seconds)

      case Oban.insert(job) do
        {:ok, _job} ->
          if rem(index, 10) == 0 or index == length(items) - 1 do
            Logger.info("✅ Scheduled job #{index + 1}/#{length(items)}")
          end

          count + 1

        {:error, error} ->
          Logger.error("❌ Failed to schedule job: #{inspect(error)}")
          count
      end
    end)
  end

  @doc """
  Schedules detail jobs with rate limiting.

  ## Parameters
  - `items` - List of items to process
  - `job_module` - The Oban job module to use
  - `args_fn` - Function that takes an item and returns job args

  ## Returns
  The number of successfully scheduled jobs.
  """
  def schedule_detail_jobs(items, job_module, args_fn)
      when is_list(items) and is_function(args_fn, 1) do
    schedule_jobs_with_delay(items, fn item, _index, delay ->
      args = args_fn.(item)
      job_module.new(args, schedule_in: delay)
    end)
  end

  @doc """
  Schedules jobs distributed across hours to prevent overwhelming systems.

  ## Parameters
  - `items` - List of items to process
  - `job_module` - The Oban job module to use
  - `args_fn` - Function that takes an item and returns job args
  - `opts` - Options including max_per_hour

  ## Returns
  The number of successfully scheduled jobs.
  """
  def schedule_hourly_capped_jobs(items, job_module, args_fn, opts \\ []) do
    total_items = length(items)
    jobs_per_hour = opts[:max_per_hour] || max_jobs_per_hour()

    # Calculate distribution
    hours_needed = ceil(total_items / jobs_per_hour)

    Logger.info("""
    📊 Distributing #{total_items} jobs:
    - Max per hour: #{jobs_per_hour}
    - Hours needed: #{hours_needed}
    """)

    Enum.with_index(items)
    |> Enum.reduce(0, fn {item, index}, count ->
      # Calculate which hour this job belongs in
      hour = div(index, jobs_per_hour)
      position_in_hour = rem(index, jobs_per_hour)

      # Calculate seconds between jobs within an hour
      seconds_per_job = floor(3600 / jobs_per_hour)

      # Calculate total delay
      delay_seconds = hour * 3600 + position_in_hour * seconds_per_job

      # Create and schedule the job
      args = args_fn.(item)
      job = job_module.new(args, schedule_in: delay_seconds)

      case Oban.insert(job) do
        {:ok, _job} ->
          if rem(index, 50) == 0 or index == total_items - 1 do
            scheduled_time = DateTime.utc_now() |> DateTime.add(delay_seconds, :second)

            Logger.info(
              "📅 Scheduled job #{index + 1}/#{total_items} for #{Calendar.strftime(scheduled_time, "%H:%M")}"
            )
          end

          count + 1

        {:error, error} ->
          Logger.error("❌ Failed to schedule job: #{inspect(error)}")
          count
      end
    end)
  end

  @doc """
  Applies rate limiting for a specific API endpoint.
  Returns :ok if the request can proceed, or {:error, :rate_limited} if not.

  Note: This is a simplified rate limiter for now.
  To implement proper rate limiting with Hammer v7, create a dedicated rate limiter module.
  """
  def check_rate_limit(_endpoint, _max_requests_per_minute \\ 60) do
    # TODO: Implement proper rate limiting with Hammer v7
    # For now, always allow requests to proceed
    :ok
  end

  @doc """
  Calculates appropriate delay based on source-specific rate limits.
  """
  def calculate_delay(source_slug, index \\ 0) do
    base_delay =
      case source_slug do
        # More conservative for Bandsintown
        "bandsintown" -> 3
        # Standard delay for Ticketmaster
        "ticketmaster" -> 2
        # Default delay
        _ -> job_delay_interval()
      end

    base_delay * index
  end

  @doc """
  Returns source-specific configuration for rate limiting.
  """
  def source_config(source_slug) do
    configs = %{
      "bandsintown" => %{
        max_per_hour: 500,
        max_per_minute: 20,
        delay_seconds: 3,
        max_attempts: 3
      },
      "ticketmaster" => %{
        max_per_hour: 1000,
        max_per_minute: 50,
        delay_seconds: 2,
        max_attempts: 5
      }
    }

    Map.get(configs, source_slug, %{
      max_per_hour: max_jobs_per_hour(),
      max_per_minute: 30,
      delay_seconds: job_delay_interval(),
      max_attempts: max_attempts()
    })
  end
end
