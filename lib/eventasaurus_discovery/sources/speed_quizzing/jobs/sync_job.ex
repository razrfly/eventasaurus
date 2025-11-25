defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Speed Quizzing scraper.

  Responsibilities:
  - Fetch index page from Speed Quizzing /find/
  - Extract embedded JSON event list
  - Enqueue IndexJob with events data
  - Supports limit parameter for testing

  ## Workflow
  1. Fetch index page HTML
  2. Extract embedded JSON (pattern: var events = JSON.parse('...'))
  3. Parse and validate JSON array
  4. Enqueue IndexJob with events data
  5. IndexJob handles event processing and detail job scheduling

  ## Data Source
  - Endpoint: https://www.speedquizzing.com/find/
  - Embedded JSON in inline script tag
  - Returns array of event objects
  - Single request fetches all events (no pagination)
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger
  alias EventasaurusDiscovery.Sources.{SourceStore, SpeedQuizzing}
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # BaseJob callbacks - not used for HTML scraper orchestration
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Speed Quizzing uses HTML scraper orchestration instead of city-based fetch
    Logger.warning("⚠️ fetch_events called on HTML scraper source - not used")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Speed Quizzing transformation happens in detail jobs
    Logger.debug("🔄 transform_events called (not used in orchestration pattern)")
    raw_events
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    %{
      name: SpeedQuizzing.Source.name(),
      slug: SpeedQuizzing.Source.key(),
      website_url: "https://www.speedquizzing.com",
      priority: SpeedQuizzing.Source.priority(),
      config: %{
        "rate_limit_seconds" => SpeedQuizzing.Config.rate_limit(),
        "max_requests_per_hour" => 1800,
        "language" => "en",
        "scraper_type" => "embedded_json",
        "data_source" => "HTML with embedded JSON",
        "discovery_method" => "html_scraper_orchestration"
      }
    }
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "speed_quizzing_sync_#{Date.utc_today()}"
    IO.puts("=" <> String.duplicate("=", 79))
    IO.puts("🔄 Starting Speed Quizzing sync job")
    IO.puts("=" <> String.duplicate("=", 79))
    Logger.info("🔄 Starting Speed Quizzing sync job")

    limit = args["limit"]
    force = args["force"] || false
    source = SourceStore.get_by_key!(SpeedQuizzing.Source.key())

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    with {:ok, html} <- SpeedQuizzing.Client.fetch_index(),
         _ = IO.puts("✓ HTML fetched, size: #{byte_size(html)} bytes"),
         {:ok, json_string} <- extract_events_json(html),
         {:ok, events} <- parse_events_json(json_string) do
      Logger.info("✅ Successfully extracted #{length(events)} events from index page")

      # Enqueue IndexJob with events data
      %{
        "source_id" => source.id,
        "events" => events,
        "limit" => limit,
        "force" => force
      }
      |> SpeedQuizzing.Jobs.IndexPageJob.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} ->
          Logger.info("✅ Enqueued index job for Speed Quizzing")
          MetricsTracker.record_success(job, external_id)
          {:ok, %{source_id: source.id, events_count: length(events), limit: limit}}

        {:error, reason} = error ->
          Logger.error("❌ Failed to enqueue index job: #{inspect(reason)}")

          MetricsTracker.record_failure(
            job,
            "Failed to enqueue index job: #{inspect(reason)}",
            external_id
          )

          error
      end
    else
      {:error, reason} = error ->
        Logger.error("❌ Speed Quizzing sync job failed: #{inspect(reason)}")

        MetricsTracker.record_failure(
          job,
          "Speed Quizzing sync failed: #{inspect(reason)}",
          external_id
        )

        error
    end
  end

  # Extract embedded JSON from HTML
  # Pattern: var events = JSON.parse('...')
  defp extract_events_json(html) do
    Logger.info("🔍 [SpeedQuizzing] Starting JSON extraction from HTML")

    case Floki.parse_document(html) do
      {:ok, document} ->
        Logger.info("✓ [SpeedQuizzing] HTML parsed successfully")
        extract_json_from_document(document)

      {:error, reason} ->
        Logger.error("❌ [SpeedQuizzing] Failed to parse HTML: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp extract_json_from_document(document) do
    # Try multiple selectors to find scripts
    scripts_no_src = Floki.find(document, "script:not([src])")
    all_scripts = Floki.find(document, "script")

    IO.puts("📜 Found #{length(scripts_no_src)} scripts with :not([src]) selector")
    IO.puts("📜 Found #{length(all_scripts)} total scripts")

    Logger.info(
      "📜 [SpeedQuizzing] Found #{length(scripts_no_src)} scripts with :not([src]) selector"
    )

    Logger.info("📜 [SpeedQuizzing] Found #{length(all_scripts)} total scripts")

    # Use all scripts if the :not([src]) selector doesn't work
    scripts = if length(scripts_no_src) > 0, do: scripts_no_src, else: all_scripts

    # Check each script
    IO.puts("🔍 Checking #{length(scripts)} scripts for 'var events = JSON.parse('...")

    script_content =
      scripts
      |> Enum.map(&Floki.raw_html/1)
      |> Enum.with_index()
      |> Enum.find(fn {html, idx} ->
        contains = String.contains?(html, "var events = JSON.parse(")
        preview = String.slice(html, 0, 80)
        IO.puts("  Script #{idx + 1}: #{preview}... [contains pattern: #{contains}]")
        if contains, do: IO.puts("✓ Found it in script #{idx + 1}!")
        contains
      end)
      |> case do
        {html, _idx} -> html
        nil -> nil
      end

    case script_content do
      nil ->
        IO.puts("❌ Events JSON not found in page (checked #{length(scripts)} scripts)")

        Logger.error(
          "❌ [SpeedQuizzing] Events JSON not found in page (checked #{length(scripts)} scripts)"
        )

        {:error, :events_json_not_found}

      content ->
        IO.puts("🎯 Found events script, extracting JSON...")
        Logger.info("🎯 [SpeedQuizzing] Found events script, extracting JSON...")
        extract_json_string(content)
    end
  end

  defp extract_json_string(script_content) do
    # Extract JSON string from: var events = JSON.parse('[...]')
    # Use non-greedy matching like trivia_advisor
    regex = ~r/var events = JSON\.parse\('(.+?)'\)/s

    case Regex.run(regex, script_content) do
      [_, json_str] ->
        Logger.debug(
          "[SpeedQuizzing] Successfully extracted JSON string (#{String.length(json_str)} chars)"
        )

        # Unescape the JSON string
        unescaped =
          json_str
          |> String.replace("\\'", "'")
          |> String.replace("\\\\", "\\")

        {:ok, unescaped}

      _ ->
        Logger.error("[SpeedQuizzing] Failed to extract JSON string from script")
        Logger.debug("[SpeedQuizzing] Script preview: #{String.slice(script_content, 0, 200)}")
        {:error, :json_extraction_failed}
    end
  end

  # Parse JSON array of events
  defp parse_events_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, events} when is_list(events) ->
        Logger.info("[SpeedQuizzing] Parsed #{length(events)} events from JSON")
        {:ok, events}

      {:ok, _other} ->
        Logger.error("[SpeedQuizzing] Parsed JSON is not an array")
        {:error, :invalid_json_format}

      {:error, reason} ->
        Logger.error("[SpeedQuizzing] Failed to parse JSON: #{inspect(reason)}")
        {:error, {:json_parse_error, reason}}
    end
  end
end
