defmodule Mix.Tasks.Discovery.GenerateSource do
  @moduledoc """
  Generates a new discovery source with standardized structure.

  Creates a new source following the standardized naming conventions and
  module structure defined in docs/source-implementation-guide.md.

  ## Usage

      mix discovery.generate_source SOURCE_SLUG [options]

  ## Arguments

    * `SOURCE_SLUG` - The source identifier (e.g., "my_source", "example_api")

  ## Options

    * `--base-job` - Use BaseJob behavior for SyncJob (default: true)
    * `--no-base-job` - Don't use BaseJob behavior (custom implementation)
    * `--with-index` - Generate IndexPageJob for pagination
    * `--with-detail` - Generate EventDetailJob for detail fetching
    * `--force` - Overwrite existing files

  ## Examples

      # Generate basic source with BaseJob
      mix discovery.generate_source my_source

      # Generate source with index and detail jobs
      mix discovery.generate_source my_source --with-index --with-detail

      # Generate source without BaseJob (custom orchestration)
      mix discovery.generate_source my_source --no-base-job

  ## Generated Structure

      lib/eventasaurus_discovery/sources/my_source/
      ├── client.ex          # HTTP client wrapper
      ├── config.ex          # Configuration constants
      ├── transformer.ex     # Raw data → unified format
      └── jobs/
          ├── sync_job.ex    # Main orchestration job
          ├── index_page_job.ex  # Optional: pagination
          └── event_detail_job.ex  # Optional: detail fetching

  All generated jobs include MetricsTracker integration by default.
  """

  use Mix.Task
  require Logger

  @shortdoc "Generate a new discovery source with standardized structure"

  @default_opts [
    base_job: true,
    with_index: false,
    with_detail: false,
    force: false
  ]

  def run(args) do
    {opts, remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          base_job: :boolean,
          with_index: :boolean,
          with_detail: :boolean,
          force: :boolean
        ]
      )

    opts = Keyword.merge(@default_opts, opts)

    case remaining do
      [source_slug] ->
        generate_source(source_slug, opts)

      [] ->
        Logger.error("❌ Error: SOURCE_SLUG argument is required")
        show_usage()
        System.halt(1)

      _ ->
        Logger.error("❌ Error: Too many arguments")
        show_usage()
        System.halt(1)
    end
  end

  defp generate_source(source_slug, opts) do
    # Validate and normalize slug
    source_slug = validate_slug(source_slug)

    # Generate module name and paths
    module_name = Macro.camelize(source_slug)
    base_path = "lib/eventasaurus_discovery/sources/#{source_slug}"
    jobs_path = Path.join(base_path, "jobs")

    Logger.info("""

    📦 Generating new discovery source: #{source_slug}
    Module: EventasaurusDiscovery.Sources.#{module_name}
    Path: #{base_path}
    """)

    # Create directories
    create_directories(base_path, jobs_path, opts)

    # Generate core modules
    generate_client(base_path, module_name, source_slug, opts)
    generate_config(base_path, module_name, source_slug, opts)
    generate_transformer(base_path, module_name, source_slug, opts)

    # Generate jobs
    generate_sync_job(jobs_path, module_name, source_slug, opts)

    if opts[:with_index] do
      generate_index_page_job(jobs_path, module_name, source_slug, opts)
    end

    if opts[:with_detail] do
      generate_event_detail_job(jobs_path, module_name, source_slug, opts)
    end

    # Generate test files
    generate_tests(source_slug, module_name, opts)

    # Show next steps
    show_next_steps(source_slug, module_name, opts)
  end

  defp validate_slug(slug) do
    # Convert to snake_case and validate
    slug =
      slug
      |> String.downcase()
      |> String.replace("-", "_")
      |> String.replace(~r/[^a-z0-9_]/, "")

    if String.match?(slug, ~r/^[a-z][a-z0-9_]*$/) do
      slug
    else
      Logger.error("❌ Error: Invalid source slug '#{slug}'")

      Logger.error(
        "   Slug must start with a letter and contain only lowercase letters, numbers, and underscores"
      )

      System.halt(1)
    end
  end

  defp create_directories(base_path, jobs_path, opts) do
    force = opts[:force]

    if File.exists?(base_path) && !force do
      Logger.error("❌ Error: Directory #{base_path} already exists")
      Logger.error("   Use --force to overwrite existing files")
      System.halt(1)
    end

    File.mkdir_p!(base_path)
    File.mkdir_p!(jobs_path)

    Logger.info("✅ Created directory structure")
  end

  defp generate_client(base_path, module_name, _source_slug, _opts) do
    file_path = Path.join(base_path, "client.ex")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Client do
      @moduledoc \"\"\"
      HTTP client for #{module_name} API.

      Handles all HTTP requests to the #{module_name} external API,
      including authentication, rate limiting, and error handling.
      \"\"\"

      require Logger

      alias EventasaurusDiscovery.Sources.#{module_name}.Config

      @doc \"\"\"
      Fetches events from the #{module_name} API.

      ## Parameters

        * `from_date` - Start date for event search (Date.t())
        * `to_date` - End date for event search (Date.t())
        * `context` - Additional context/options (map)

      ## Returns

        * `{:ok, events}` - List of raw event data
        * `{:error, reason}` - Error tuple with reason
      \"\"\"
      def fetch_events(from_date, to_date, context \\\\ %{}) do
        Logger.info("Fetching #{module_name} events from \#{from_date} to \#{to_date}")

        # TODO: Implement API request
        # Example:
        # url = build_url(from_date, to_date, context)
        # headers = build_headers()
        #
        # case HTTPoison.get(url, headers) do
        #   {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        #     {:ok, Jason.decode!(body)}
        #
        #   {:ok, %HTTPoison.Response{status_code: status_code}} ->
        #     {:error, "HTTP \#{status_code}"}
        #
        #   {:error, %HTTPoison.Error{reason: reason}} ->
        #     {:error, reason}
        # end

        # Placeholder implementation
        Logger.warning("⚠️  Client.fetch_events not yet implemented")
        {:ok, []}
      end

      # Private helper functions

      defp build_url(from_date, to_date, _context) do
        base_url = Config.api_base_url()
        # TODO: Build URL with query parameters
        "\#{base_url}/events?from=\#{from_date}&to=\#{to_date}"
      end

      defp build_headers do
        api_key = Config.api_key()

        [
          {"Accept", "application/json"},
          {"Content-Type", "application/json"}
          # TODO: Add authentication headers if needed
          # {"Authorization", "Bearer \#{api_key}"}
        ]
      end
    end
    """

    File.write!(file_path, content)
    Logger.info("✅ Generated #{file_path}")
  end

  defp generate_config(base_path, module_name, source_slug, _opts) do
    file_path = Path.join(base_path, "config.ex")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Config do
      @moduledoc \"\"\"
      Configuration for #{module_name} source.

      Centralizes all configuration constants, API endpoints,
      and environment-specific settings.
      \"\"\"

      @doc \"\"\"
      Returns the base URL for the #{module_name} API.
      \"\"\"
      def api_base_url do
        # TODO: Update with actual API base URL
        System.get_env("#{String.upcase(source_slug)}_API_BASE_URL") || "https://api.example.com"
      end

      @doc \"\"\"
      Returns the API key for authentication.
      \"\"\"
      def api_key do
        # TODO: Update with actual environment variable name
        System.get_env("#{String.upcase(source_slug)}_API_KEY")
      end

      @doc \"\"\"
      Returns the source identifier for external IDs.
      \"\"\"
      def source_slug, do: "#{source_slug}"

      @doc \"\"\"
      Returns rate limit configuration.
      \"\"\"
      def rate_limit do
        %{
          # TODO: Configure rate limits based on API documentation
          max_requests: 100,
          time_window: :timer.minutes(1)
        }
      end

      @doc \"\"\"
      Returns retry configuration for failed requests.
      \"\"\"
      def retry_config do
        %{
          max_attempts: 3,
          base_backoff: :timer.seconds(1),
          max_backoff: :timer.seconds(30)
        }
      end
    end
    """

    File.write!(file_path, content)
    Logger.info("✅ Generated #{file_path}")
  end

  defp generate_transformer(base_path, module_name, _source_slug, _opts) do
    file_path = Path.join(base_path, "transformer.ex")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Transformer do
      @moduledoc \"\"\"
      Transforms raw #{module_name} data into standardized event format.

      Handles data normalization, validation, and mapping to the unified
      event structure expected by EventasaurusDiscovery.
      \"\"\"

      require Logger

      alias EventasaurusDiscovery.Sources.#{module_name}.Config

      @doc \"\"\"
      Transforms a list of raw events into standardized format.

      ## Parameters

        * `raw_events` - List of raw event data from the API

      ## Returns

        * `{:ok, events}` - List of transformed events
        * `{:error, reason}` - Error tuple if transformation fails
      \"\"\"
      def transform_events(raw_events) when is_list(raw_events) do
        events =
          raw_events
          |> Enum.map(&transform_event/1)
          |> Enum.reject(&is_nil/1)

        {:ok, events}
      rescue
        error ->
          Logger.error("Failed to transform events: \#{inspect(error)}")
          {:error, error}
      end

      @doc \"\"\"
      Transforms a single raw event into standardized format.

      Returns `nil` if the event cannot be transformed or is invalid.
      \"\"\"
      def transform_event(raw_event) do
        # TODO: Implement event transformation
        # Example structure:
        %{
          external_id: build_external_id(raw_event),
          title: extract_title(raw_event),
          description: extract_description(raw_event),
          start_time: extract_start_time(raw_event),
          end_time: extract_end_time(raw_event),
          venue: extract_venue(raw_event),
          performers: extract_performers(raw_event),
          categories: extract_categories(raw_event),
          source_url: extract_source_url(raw_event),
          source_data: raw_event
        }
      rescue
        error ->
          Logger.warning("Failed to transform event: \#{inspect(error)}")
          Logger.debug("Raw event: \#{inspect(raw_event)}")
          nil
      end

      # Private helper functions

      defp build_external_id(raw_event) do
        # Format: {source}_{type}_{id}
        # IMPORTANT: external_id must be STABLE across sync runs for proper deduplication
        # DO NOT use Date.utc_today() - it breaks deduplication by creating new IDs daily
        # If you need date-based IDs, use the event's actual date (e.g., normalized start date)
        source_id = raw_event["id"] || raw_event[:id]

        "\#{Config.source_slug()}_event_\#{source_id}"
      end

      defp extract_title(raw_event) do
        # TODO: Extract event title from raw data
        raw_event["name"] || raw_event["title"] || "Untitled Event"
      end

      defp extract_description(raw_event) do
        # TODO: Extract event description
        raw_event["description"]
      end

      defp extract_start_time(raw_event) do
        # TODO: Parse start time from raw data
        # Convert to DateTime if needed
        raw_event["start_time"]
      end

      defp extract_end_time(raw_event) do
        # TODO: Parse end time from raw data
        raw_event["end_time"]
      end

      defp extract_venue(raw_event) do
        # TODO: Extract venue information
        # Return map with venue details: %{name: "", address: "", ...}
        raw_event["venue"]
      end

      defp extract_performers(raw_event) do
        # TODO: Extract performers/artists
        # Return list of performer names
        raw_event["performers"] || []
      end

      defp extract_categories(raw_event) do
        # TODO: Extract event categories/tags
        raw_event["categories"] || []
      end

      defp extract_source_url(raw_event) do
        # TODO: Extract URL to original event page
        raw_event["url"]
      end
    end
    """

    File.write!(file_path, content)
    Logger.info("✅ Generated #{file_path}")
  end

  defp generate_sync_job(jobs_path, module_name, source_slug, opts) do
    file_path = Path.join(jobs_path, "sync_job.ex")

    content =
      if opts[:base_job] do
        generate_sync_job_with_base_job(module_name, source_slug)
      else
        generate_sync_job_custom(module_name, source_slug)
      end

    File.write!(file_path, content)
    Logger.info("✅ Generated #{file_path}")
  end

  defp generate_sync_job_with_base_job(module_name, _source_slug) do
    """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Jobs.SyncJob do
      @moduledoc \"\"\"
      Main orchestration job for #{module_name} event synchronization.

      Uses BaseJob behavior for standardized fetch-transform-process workflow.
      Includes MetricsTracker integration for monitoring and error tracking.
      \"\"\"

      use EventasaurusDiscovery.Sources.BaseJob

      require Logger

      alias EventasaurusDiscovery.Sources.#{module_name}.{Client, Config, Transformer}
      alias EventasaurusDiscovery.Metrics.MetricsTracker

      @impl true
      def fetch_events(from_date, to_date, context) do
        Logger.info("🔄 #{module_name} SyncJob: Fetching events from \#{from_date} to \#{to_date}")

        Client.fetch_events(from_date, to_date, context)
      end

      @impl true
      def transform_events(raw_events) do
        Logger.info("🔄 #{module_name} SyncJob: Transforming \#{length(raw_events)} events")

        Transformer.transform_events(raw_events)
      end

      @impl true
      def source_config do
        %{
          source_slug: Config.source_slug(),
          rate_limit: Config.rate_limit(),
          retry_config: Config.retry_config()
        }
      end

      # Optional: Override default date range
      # @impl true
      # def default_date_range do
      #   from_date = Date.utc_today()
      #   to_date = Date.add(from_date, 30)
      #   {from_date, to_date}
      # end

      # Optional: Custom error handling
      # @impl true
      # def handle_error(error, context) do
      #   Logger.error("#{module_name} SyncJob error: \#{inspect(error)}")
      #   super(error, context)
      # end
    end
    """
  end

  defp generate_sync_job_custom(module_name, _source_slug) do
    """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Jobs.SyncJob do
      @moduledoc \"\"\"
      Main orchestration job for #{module_name} event synchronization.

      Custom implementation with MetricsTracker integration for monitoring.
      \"\"\"

      use Oban.Worker,
        queue: :discovery,
        max_attempts: 3

      require Logger

      alias EventasaurusDiscovery.Sources.#{module_name}.{Client, Config, Transformer}
      alias EventasaurusDiscovery.Metrics.MetricsTracker

      @impl Oban.Worker
      def perform(%Oban.Job{args: args} = job) do
        # Parse arguments
        from_date = parse_date(args["from_date"]) || Date.utc_today()
        to_date = parse_date(args["to_date"]) || Date.add(from_date, 30)

        # Build external ID for tracking
        external_id = "\#{Config.source_slug()}_sync_\#{Date.utc_today()}"

        Logger.info(\"\"\"
        🔄 #{module_name} SyncJob started
        Date range: \#{from_date} to \#{to_date}
        External ID: \#{external_id}
        \"\"\")

        # Execute sync workflow
        case execute_sync(from_date, to_date, args) do
          {:ok, result} ->
            Logger.info("✅ #{module_name} SyncJob completed: \#{inspect(result)}")
            MetricsTracker.record_success(job, external_id, %{result: result})
            {:ok, result}

          {:error, reason} = error ->
            Logger.error("❌ #{module_name} SyncJob failed: \#{inspect(reason)}")
            MetricsTracker.record_failure(job, reason, external_id)
            error
        end
      end

      defp execute_sync(from_date, to_date, _args) do
        # TODO: Implement custom sync logic
        # Example workflow:
        # 1. Fetch raw data from API
        # 2. Transform to standardized format
        # 3. Process events (save to database, enqueue child jobs, etc.)

        with {:ok, raw_events} <- Client.fetch_events(from_date, to_date),
             {:ok, events} <- Transformer.transform_events(raw_events),
             {:ok, result} <- process_events(events) do
          {:ok, result}
        end
      end

      defp process_events(events) do
        # TODO: Implement event processing
        # Examples:
        # - Save events to database
        # - Enqueue detail fetching jobs
        # - Update existing events
        # - Send notifications

        Logger.info("Processing \#{length(events)} events")
        {:ok, %{processed: length(events)}}
      end

      defp parse_date(nil), do: nil

      defp parse_date(date_string) when is_binary(date_string) do
        case Date.from_iso8601(date_string) do
          {:ok, date} -> date
          {:error, _} -> nil
        end
      end

      defp parse_date(%Date{} = date), do: date
    end
    """
  end

  defp generate_index_page_job(jobs_path, module_name, _source_slug, _opts) do
    file_path = Path.join(jobs_path, "index_page_job.ex")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Jobs.IndexPageJob do
      @moduledoc \"\"\"
      Fetches index/listing pages for #{module_name}.

      Handles pagination and list fetching, enqueuing detail jobs for
      individual events as needed.
      \"\"\"

      use Oban.Worker,
        queue: :discovery,
        max_attempts: 3

      require Logger

      alias EventasaurusDiscovery.Sources.#{module_name}.{Client, Config}
      alias EventasaurusDiscovery.Metrics.MetricsTracker

      @impl Oban.Worker
      def perform(%Oban.Job{args: args} = job) do
        page = args["page"] || 1
        parent_job_id = args["parent_job_id"]

        # Build external ID
        date = Date.utc_today() |> Date.to_string()
        external_id = "\#{Config.source_slug()}_index_page_\#{page}_\#{date}"

        Logger.info("🔄 #{module_name} IndexPageJob: Fetching page \#{page}")

        case fetch_page(page, args) do
          {:ok, result} ->
            MetricsTracker.record_success(job, external_id, %{
              page: page,
              parent_job_id: parent_job_id
            })

            {:ok, result}

          {:error, reason} = error ->
            MetricsTracker.record_failure(job, reason, external_id)
            error
        end
      end

      defp fetch_page(page, _args) do
        # TODO: Implement page fetching logic
        Logger.warning("⚠️  IndexPageJob.fetch_page not yet implemented")
        {:ok, %{page: page, items: []}}
      end
    end
    """

    File.write!(file_path, content)
    Logger.info("✅ Generated #{file_path}")
  end

  defp generate_event_detail_job(jobs_path, module_name, _source_slug, _opts) do
    file_path = Path.join(jobs_path, "event_detail_job.ex")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Jobs.EventDetailJob do
      @moduledoc \"\"\"
      Fetches detailed event information for #{module_name}.

      Retrieves full event details for individual events, typically
      enqueued by SyncJob or IndexPageJob.
      \"\"\"

      use Oban.Worker,
        queue: :discovery,
        max_attempts: 3

      require Logger

      alias EventasaurusDiscovery.Sources.#{module_name}.{Client, Config, Transformer}
      alias EventasaurusDiscovery.Metrics.MetricsTracker

      @impl Oban.Worker
      def perform(%Oban.Job{args: args} = job) do
        event_id = args["event_id"]
        parent_job_id = args["parent_job_id"]

        if is_nil(event_id) do
          {:error, "event_id is required"}
        else
          # Build external ID
          # NOTE: Using stable format without date to ensure proper deduplication
          # If you need date-based IDs, use the event's actual date from the event data
          external_id = "\#{Config.source_slug()}_event_\#{event_id}"

          Logger.info("🔄 #{module_name} EventDetailJob: Fetching event \#{event_id}")

          case fetch_and_process_event(event_id, args) do
            {:ok, result} ->
              MetricsTracker.record_success(job, external_id, %{
                event_id: event_id,
                parent_job_id: parent_job_id
              })

              {:ok, result}

            {:error, reason} = error ->
              MetricsTracker.record_failure(job, reason, external_id)
              error
          end
        end
      end

      defp fetch_and_process_event(event_id, _args) do
        # TODO: Implement event detail fetching
        # Example:
        # with {:ok, raw_event} <- Client.fetch_event_detail(event_id),
        #      {:ok, event} <- Transformer.transform_event(raw_event),
        #      {:ok, result} <- process_event(event) do
        #   {:ok, result}
        # end

        Logger.warning("⚠️  EventDetailJob.fetch_and_process_event not yet implemented")
        {:ok, %{event_id: event_id}}
      end
    end
    """

    File.write!(file_path, content)
    Logger.info("✅ Generated #{file_path}")
  end

  defp generate_tests(source_slug, module_name, opts) do
    test_base_path = "test/eventasaurus_discovery/sources/#{source_slug}"
    test_jobs_path = Path.join(test_base_path, "jobs")

    File.mkdir_p!(test_base_path)
    File.mkdir_p!(test_jobs_path)

    # Generate test files
    generate_client_test(test_base_path, module_name, opts)
    generate_transformer_test(test_base_path, module_name, opts)
    generate_sync_job_test(test_jobs_path, module_name, opts)

    Logger.info("✅ Generated test files")
  end

  defp generate_client_test(test_base_path, module_name, _opts) do
    file_path = Path.join(test_base_path, "client_test.exs")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.ClientTest do
      use ExUnit.Case, async: true

      alias EventasaurusDiscovery.Sources.#{module_name}.Client

      describe "fetch_events/3" do
        test "returns events for valid date range" do
          from_date = ~D[2024-01-01]
          to_date = ~D[2024-01-31]

          # TODO: Implement test with mocked HTTP responses
          assert {:ok, _events} = Client.fetch_events(from_date, to_date)
        end

        test "handles API errors gracefully" do
          from_date = ~D[2024-01-01]
          to_date = ~D[2024-01-31]

          # TODO: Test error handling
          # Mock HTTP error response and verify error handling
        end
      end
    end
    """

    File.write!(file_path, content)
  end

  defp generate_transformer_test(test_base_path, module_name, _opts) do
    file_path = Path.join(test_base_path, "transformer_test.exs")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.TransformerTest do
      use ExUnit.Case, async: true

      alias EventasaurusDiscovery.Sources.#{module_name}.Transformer

      describe "transform_events/1" do
        test "transforms valid events successfully" do
          raw_events = [
            %{
              "id" => "123",
              "name" => "Test Event",
              "start_time" => "2024-01-15T20:00:00Z"
            }
          ]

          assert {:ok, [event]} = Transformer.transform_events(raw_events)
          assert event.external_id =~ "event_123"
          assert event.title == "Test Event"
        end

        test "filters out invalid events" do
          raw_events = [
            %{"id" => "valid", "name" => "Valid Event"},
            %{"invalid" => "data"}
          ]

          assert {:ok, events} = Transformer.transform_events(raw_events)
          assert length(events) == 1
        end
      end

      describe "transform_event/1" do
        test "builds correct external ID format" do
          raw_event = %{"id" => "abc123", "name" => "Event"}

          event = Transformer.transform_event(raw_event)
          assert event.external_id =~ ~r/^[a-z_]+_event_abc123_\\d{4}-\\d{2}-\\d{2}$/
        end
      end
    end
    """

    File.write!(file_path, content)
  end

  defp generate_sync_job_test(test_jobs_path, module_name, _opts) do
    file_path = Path.join(test_jobs_path, "sync_job_test.exs")

    content = """
    defmodule EventasaurusDiscovery.Sources.#{module_name}.Jobs.SyncJobTest do
      use Eventasaurus.DataCase, async: true
      use Oban.Testing, repo: EventasaurusApp.Repo

      alias EventasaurusDiscovery.Sources.#{module_name}.Jobs.SyncJob

      describe "perform/1" do
        test "successfully syncs events" do
          args = %{
            "from_date" => "2024-01-01",
            "to_date" => "2024-01-31"
          }

          # TODO: Mock external API calls
          # Execute job
          assert {:ok, _result} = perform_job(SyncJob, args)
        end

        test "records success with MetricsTracker" do
          args = %{"from_date" => "2024-01-01"}

          perform_job(SyncJob, args)

          # TODO: Verify MetricsTracker.record_success was called
          # Check job_execution_summaries table
        end

        test "records failure with MetricsTracker on error" do
          # TODO: Mock API to return error
          # Verify MetricsTracker.record_failure was called
        end
      end
    end
    """

    File.write!(file_path, content)
  end

  defp show_next_steps(source_slug, module_name, opts) do
    Logger.info("""

    ✅ Successfully generated #{module_name} source!

    📝 Next Steps:

    1. Update configuration in lib/eventasaurus_discovery/sources/#{source_slug}/config.ex
       - Set API base URL and authentication details
       - Configure rate limits and retry settings

    2. Implement HTTP client in lib/eventasaurus_discovery/sources/#{source_slug}/client.ex
       - Add API request methods
       - Handle authentication and headers

    3. Implement data transformation in lib/eventasaurus_discovery/sources/#{source_slug}/transformer.ex
       - Map raw API data to standardized event format
       - Add validation and error handling

    4. Complete job implementation in lib/eventasaurus_discovery/sources/#{source_slug}/jobs/sync_job.ex
       #{if opts[:base_job], do: "- Verify fetch_events/3 and transform_events/1 callbacks", else: "- Implement custom sync workflow"}
       - Test MetricsTracker integration

    5. Write tests in test/eventasaurus_discovery/sources/#{source_slug}/
       - Add HTTP mocks for client tests
       - Test transformation edge cases
       - Verify job execution and error handling

    6. Register source in lib/mix/tasks/discovery.sync.ex
       - Add to @sources map: "#{source_slug}" => EventasaurusDiscovery.Sources.#{module_name}.Jobs.SyncJob

    7. Update documentation
       - Add source to README if needed
       - Document any source-specific quirks

    📚 Reference Documentation:
       - docs/source-implementation-guide.md - Implementation standards
       - docs/scraper-monitoring-guide.md - Monitoring integration

    🧪 Test your source:
       mix test test/eventasaurus_discovery/sources/#{source_slug}/
       mix discovery.sync #{source_slug} --limit 10 --inline

    """)
  end

  defp show_usage do
    Logger.info("""

    Usage: mix discovery.generate_source SOURCE_SLUG [options]

    Options:
      --base-job           Use BaseJob behavior (default: true)
      --no-base-job        Don't use BaseJob (custom implementation)
      --with-index         Generate IndexPageJob for pagination
      --with-detail        Generate EventDetailJob for detail fetching
      --force              Overwrite existing files

    Examples:
      mix discovery.generate_source my_source
      mix discovery.generate_source my_source --with-index --with-detail
      mix discovery.generate_source my_source --no-base-job --force

    See docs/source-implementation-guide.md for implementation details.
    """)
  end
end
