defmodule Mix.Tasks.Db.SyncProduction do
  @moduledoc """
  Sync production Fly Managed Postgres database to local development.

  This task automates the process of:
  1. Starting a Fly proxy to production database
  2. Exporting the production database using pg_dump
  3. Dropping and recreating the local database
  4. Importing the dump using pg_restore
  5. Cleaning up Oban jobs and resetting sequences
  6. Verifying the import was successful

  ## Usage

      # Full sync (drops local, imports fresh)
      mix db.sync_production

      # Export only (saves dump file)
      mix db.sync_production --export-only

      # Import from existing dump
      mix db.sync_production --import-only --dump-file priv/dumps/production_20250126.dump

      # Parallel restore (faster for large DBs)
      mix db.sync_production --parallel 4

      # Verbose mode with detailed progress
      mix db.sync_production --verbose

      # Skip confirmation prompts
      mix db.sync_production --yes

      # Skip verification step
      mix db.sync_production --skip-verify

  ## Prerequisites

  1. Fly CLI installed and authenticated (`fly auth login`)
  2. Local PostgreSQL running
  3. pg_dump and pg_restore in PATH

  ## Environment Variables

  The task will automatically fetch credentials from the running Fly app.
  Alternatively, set these in `.env.production.local` (gitignored):

      FLY_PG_PROXY_PORT=5433
      DATABASE_URL=postgres://postgres:xxx@localhost:5433/eventasaurus

  ## Notes

  - Uses Fly proxy to tunnel to Managed Postgres
  - Production database requires SSL
  - PostGIS extensions are preserved
  - Oban jobs are cleaned to prevent accidental production job execution
  """

  use Mix.Task
  require Logger

  @shortdoc "Sync Fly Managed Postgres production database to local"

  # Configuration
  @dump_dir "priv/dumps"
  @local_db "eventasaurus_dev"
  @local_user "postgres"
  @local_password "postgres"
  @local_host "localhost"
  @local_port "5432"
  @proxy_port "5433"

  # Fly MPG configuration
  @fly_app "eventasaurus"
  @fly_org "teamups"
  @fly_mpg_host "pgbouncer.k1v53olmn9pr8q6p.flympg.net"

  # Timeouts
  @proxy_startup_timeout_ms 30_000
  @stall_timeout_seconds 900

  # Tables to verify after import
  @verify_tables ~w(public_events venues cities movies users)

  # Critical tables that must have data
  @critical_tables ~w(public_events venues cities)

  @impl Mix.Task
  def run(args) do
    # Parse options
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          export_only: :boolean,
          import_only: :boolean,
          dump_file: :string,
          verbose: :boolean,
          skip_verify: :boolean,
          parallel: :integer,
          yes: :boolean,
          keep_dump: :boolean
        ],
        aliases: [
          e: :export_only,
          i: :import_only,
          f: :dump_file,
          v: :verbose,
          p: :parallel,
          y: :yes
        ]
      )

    # Default to keeping dump files
    opts = Keyword.put_new(opts, :keep_dump, true)

    # Store verbose flag for helper functions
    if opts[:verbose] do
      Application.put_env(:eventasaurus, :verbose_sync, true)
    end

    # Run pre-flight checks first
    case run_preflight_checks(opts) do
      :ok ->
        info("\n✅ All pre-flight checks passed\n")
        execute_sync(opts)

      {:error, reason} ->
        error("\n❌ Pre-flight checks failed: #{reason}")
        Mix.raise("Pre-flight checks failed")
    end
  end

  # ============================================================================
  # Pre-flight Checks (Phase 1)
  # ============================================================================

  defp run_preflight_checks(opts) do
    info("\n🔍 Running pre-flight checks...\n")

    checks = [
      {"Checking fly CLI", &check_fly_cli/0},
      {"Checking fly authentication", &check_fly_auth/0},
      {"Checking proxy port #{@proxy_port}", &check_proxy_port_available/0},
      {"Checking local PostgreSQL", &check_local_postgres/0},
      {"Checking local database", &check_local_database/0}
    ]

    # Skip some checks for import-only mode
    checks =
      if opts[:import_only] do
        Enum.reject(checks, fn {name, _} ->
          String.contains?(name, "fly") or String.contains?(name, "proxy")
        end)
      else
        checks
      end

    run_checks(checks)
  end

  defp run_checks([]), do: :ok

  defp run_checks([{name, check_fn} | rest]) do
    IO.write("  #{name}...")

    case check_fn.() do
      :ok ->
        IO.puts(" ✓")
        run_checks(rest)

      {:ok, detail} ->
        IO.puts(" ✓ #{detail}")
        run_checks(rest)

      {:error, reason} ->
        IO.puts(" ✗")
        error("    → #{reason}")
        {:error, reason}
    end
  end

  defp check_fly_cli do
    case System.cmd("which", ["fly"], stderr_to_stdout: true) do
      {path, 0} ->
        verbose_info("    Found at: #{String.trim(path)}")
        :ok

      {_, _} ->
        {:error, "fly CLI not found. Install from: https://fly.io/docs/hands-on/install-flyctl/"}
    end
  end

  defp check_fly_auth do
    case System.cmd("fly", ["auth", "whoami"], stderr_to_stdout: true) do
      {output, 0} ->
        email = String.trim(output)
        {:ok, email}

      {output, _} ->
        if String.contains?(output, "not logged in") do
          {:error, "Not logged in. Run: fly auth login"}
        else
          {:error, "Authentication check failed: #{String.trim(output)}"}
        end
    end
  end

  defp check_proxy_port_available do
    # Check if something is already listening on the proxy port
    case System.cmd("lsof", ["-i", ":#{@proxy_port}"], stderr_to_stdout: true) do
      {output, 0} ->
        # Something is listening
        if String.contains?(output, "fly") do
          {:ok, "fly proxy already running"}
        else
          # Extract process name for helpful error
          process =
            output
            |> String.split("\n")
            |> Enum.at(1, "")
            |> String.split()
            |> List.first()

          {:error,
           "Port #{@proxy_port} in use by #{process || "unknown process"}. " <>
             "Kill it or use a different port."}
        end

      {_, 1} ->
        # Nothing listening - port is available
        {:ok, "available"}

      {output, _} ->
        {:error, "Could not check port: #{String.trim(output)}"}
    end
  end

  defp check_local_postgres do
    # Try to connect to local postgres
    cmd =
      "PGPASSWORD='#{@local_password}' psql -h #{@local_host} -p #{@local_port} -U #{@local_user} -c 'SELECT 1' postgres 2>&1"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        cond do
          String.contains?(output, "connection refused") ->
            {:error, "PostgreSQL not running. Start with: brew services start postgresql"}

          String.contains?(output, "does not exist") ->
            {:error, "User '#{@local_user}' does not exist. Create with: createuser -s postgres"}

          String.contains?(output, "authentication failed") ->
            {:error, "Authentication failed for user '#{@local_user}'"}

          true ->
            {:error, "Cannot connect to PostgreSQL: #{String.slice(output, 0, 100)}"}
        end
    end
  end

  defp check_local_database do
    cmd =
      "PGPASSWORD='#{@local_password}' psql -h #{@local_host} -p #{@local_port} -U #{@local_user} -c 'SELECT 1' #{@local_db} 2>&1"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {_, 0} ->
        # Get table count for extra info
        count_cmd =
          "PGPASSWORD='#{@local_password}' psql -h #{@local_host} -p #{@local_port} -U #{@local_user} -t -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'\" #{@local_db} 2>&1"

        case System.cmd("sh", ["-c", count_cmd], stderr_to_stdout: true) do
          {count, 0} ->
            tables = String.trim(count)
            {:ok, "#{tables} tables"}

          _ ->
            :ok
        end

      {output, _} ->
        if String.contains?(output, "does not exist") do
          {:error,
           "Database '#{@local_db}' does not exist. Create with: mix ecto.create"}
        else
          {:error, "Cannot connect to #{@local_db}: #{String.slice(output, 0, 100)}"}
        end
    end
  end

  # ============================================================================
  # Sync Execution
  # ============================================================================

  defp execute_sync(opts) do
    cond do
      opts[:export_only] ->
        export_only(opts)

      opts[:import_only] ->
        if opts[:dump_file] do
          import_only(opts)
        else
          error("--import-only requires --dump-file path")
          Mix.raise("Missing dump file")
        end

      true ->
        full_sync(opts)
    end
  end

  defp export_only(opts) do
    start_time = System.monotonic_time(:second)

    info("📤 Starting export-only mode...\n")

    with {:ok, proxy_pid} <- start_proxy(),
         {:ok, creds} <- fetch_credentials(),
         {:ok, dump_path} <- export_database(creds, opts) do
      stop_proxy(proxy_pid)
      elapsed = System.monotonic_time(:second) - start_time
      info("\n✅ Export completed in #{format_duration(elapsed)}")
      info("   Dump file: #{dump_path}")
      {:ok, dump_path}
    else
      {:error, reason} ->
        error("\n❌ Export failed: #{reason}")
        Mix.raise("Export failed")
    end
  end

  defp import_only(opts) do
    start_time = System.monotonic_time(:second)
    dump_path = opts[:dump_file]

    info("📥 Starting import from #{dump_path}...\n")

    with :ok <- ensure_dump_file(dump_path),
         :ok <- confirm_destructive_operation(opts),
         :ok <- prepare_local_database(opts),
         :ok <- import_database(dump_path, opts),
         :ok <- post_import_cleanup(opts),
         :ok <- maybe_verify(opts) do
      elapsed = System.monotonic_time(:second) - start_time
      info("\n✅ Import completed successfully in #{format_duration(elapsed)}")
      {:ok, dump_path}
    else
      {:error, reason} ->
        error("\n❌ Import failed: #{reason}")
        {:error, reason}
    end
  end

  defp full_sync(opts) do
    start_time = System.monotonic_time(:second)

    info("🔄 Starting full sync...\n")

    with :ok <- confirm_destructive_operation(opts),
         {:ok, proxy_pid} <- start_proxy(),
         {:ok, creds} <- fetch_credentials(),
         {:ok, dump_path} <- export_database(creds, opts),
         :ok <- tap_stop_proxy(proxy_pid),
         :ok <- prepare_local_database(opts),
         :ok <- import_database(dump_path, opts),
         :ok <- post_import_cleanup(opts),
         :ok <- maybe_verify(opts),
         :ok <- maybe_cleanup_dump(dump_path, opts) do
      elapsed = System.monotonic_time(:second) - start_time
      info("\n✅ Full sync completed successfully in #{format_duration(elapsed)}")
      {:ok, dump_path}
    else
      {:error, reason} ->
        error("\n❌ Sync failed: #{reason}")
        Mix.raise("Sync failed")
    end
  end

  defp tap_stop_proxy(proxy_pid) do
    stop_proxy(proxy_pid)
    :ok
  end

  # ============================================================================
  # Phase 2: Proxy Management
  # ============================================================================

  defp start_proxy do
    info("🔌 Starting fly proxy...")

    # Check if proxy is already running
    case check_proxy_port_available() do
      {:ok, "fly proxy already running"} ->
        info("  ✓ Fly proxy already running on port #{@proxy_port}")
        {:ok, :already_running}

      {:ok, _} ->
        do_start_proxy()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_start_proxy do
    # Start fly proxy in background
    proxy_cmd = "fly proxy #{@proxy_port}:5432 #{@fly_mpg_host} -o #{@fly_org}"
    verbose_info("  → Running: #{proxy_cmd}")

    port =
      Port.open({:spawn, proxy_cmd}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 1024}
      ])

    # Wait for proxy to be ready
    case wait_for_proxy(port, System.monotonic_time(:millisecond)) do
      :ok ->
        info("  ✓ Proxy listening on localhost:#{@proxy_port}")
        {:ok, port}

      {:error, reason} ->
        Port.close(port)
        {:error, reason}
    end
  end

  defp wait_for_proxy(port, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > @proxy_startup_timeout_ms do
      {:error, "Proxy startup timed out after #{div(elapsed, 1000)}s"}
    else
      # Check if port is listening
      case System.cmd("nc", ["-z", "localhost", @proxy_port], stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        _ ->
          # Check for proxy output/errors
          receive do
            {^port, {:data, {:eol, line}}} ->
              verbose_info("  → #{line}")

              if String.contains?(line, "error") or String.contains?(line, "Error") do
                {:error, "Proxy error: #{line}"}
              else
                Process.sleep(500)
                wait_for_proxy(port, start_time)
              end

            {^port, {:exit_status, code}} when code != 0 ->
              {:error, "Proxy exited with code #{code}"}
          after
            500 ->
              wait_for_proxy(port, start_time)
          end
      end
    end
  end

  defp stop_proxy(:already_running) do
    verbose_info("  → Proxy was already running, leaving it active")
    :ok
  end

  defp stop_proxy(port) when is_port(port) do
    verbose_info("  → Stopping proxy...")
    Port.close(port)
    # Give it a moment to clean up
    Process.sleep(500)
    :ok
  end

  # ============================================================================
  # Phase 2: Credential Management
  # ============================================================================

  defp fetch_credentials do
    info("🔑 Fetching database credentials...")

    # Try to get credentials from running app
    cmd = "fly ssh console -a #{@fly_app} -C 'printenv DATABASE_URL'"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse the DATABASE_URL
        # Format: postgresql://user:pass@host/db or postgres://user:pass@host/db
        found_line =
          output
          |> String.split("\n")
          |> Enum.find(fn line ->
            String.starts_with?(line, "postgresql://") or String.starts_with?(line, "postgres://")
          end)

        case found_line do
          nil ->
            {:error, "DATABASE_URL not found in output. Expected line starting with 'postgresql://' or 'postgres://'"}

          line ->
            url = String.trim(line)

            case parse_database_url(url) do
              {:ok, creds} ->
                info("  ✓ Credentials retrieved from #{@fly_app}")
                verbose_info("  → Database: #{creds.database}")
                verbose_info("  → User: #{creds.username}")
                {:ok, creds}

              {:error, reason} ->
                {:error, reason}
            end
        end

      {output, _} ->
        {:error, "Failed to fetch credentials: #{String.slice(output, 0, 200)}"}
    end
  end

  defp parse_database_url(url) when is_binary(url) do
    # postgresql://user:pass@host:port/db or postgresql://user:pass@host/db
    case URI.parse(url) do
      %URI{userinfo: userinfo, host: host, path: "/" <> database, port: _port}
      when is_binary(userinfo) and is_binary(host) ->
        # Safely split userinfo - password may be absent (e.g., "user" vs "user:pass")
        {username, password} =
          case String.split(userinfo, ":", parts: 2) do
            [user, pass] -> {user, pass}
            [user] -> {user, ""}
          end

        {:ok,
         %{
           username: username,
           password: password,
           # Connect through local proxy, not the original host
           host: @local_host,
           port: @proxy_port,
           database: database,
           original_host: host
         }}

      _ ->
        {:error, "Could not parse DATABASE_URL: #{String.slice(url, 0, 50)}..."}
    end
  end

  defp parse_database_url(_), do: {:error, "DATABASE_URL is nil or invalid"}

  # ============================================================================
  # Phase 2: Export Database
  # ============================================================================

  defp export_database(creds, opts) do
    info("📤 Exporting production database...")

    with :ok <- ensure_dump_dir() do
      run_pg_dump(creds, opts)
    end
  end

  defp ensure_dump_dir do
    File.mkdir_p!(@dump_dir)
    :ok
  end

  defp run_pg_dump(creds, _opts) do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.slice(0, 15)
      |> String.replace("T", "_")

    dump_path = Path.join(@dump_dir, "production_#{timestamp}.dump")

    # Build connection string for local proxy
    # Note: PgBouncer doesn't require SSL for internal connections
    conn_string =
      "postgresql://#{creds.username}:#{URI.encode_www_form(creds.password)}@#{creds.host}:#{creds.port}/#{creds.database}"

    # pg_dump command with verbose output for progress tracking
    cmd = """
    pg_dump '#{conn_string}' \
      -Fc \
      --no-owner \
      --no-acl \
      --verbose \
      -f '#{dump_path}' \
      2>&1
    """

    info("  → Connecting to production via proxy...")
    verbose_info("  → Dumping to: #{dump_path}")

    # Start progress monitor
    parent = self()
    monitor_pid = spawn_link(fn -> monitor_dump_progress(dump_path, parent) end)
    start_time = System.monotonic_time(:second)

    # Run pg_dump and capture output
    port = Port.open({:spawn, "sh -c \"#{cmd}\""}, [:binary, :exit_status, :stderr_to_stdout])

    result = collect_dump_output(port, creds.password, [], monitor_pid)

    # Stop the monitor
    send(monitor_pid, :stop)

    elapsed = System.monotonic_time(:second) - start_time

    case result do
      {:ok, _output} ->
        IO.write("\r\e[K")
        size = File.stat!(dump_path).size |> format_size()
        info("  ✓ Exported #{size} in #{format_duration(elapsed)}")
        {:ok, dump_path}

      {:error, output, code} ->
        IO.write("\r\e[K")
        sanitized = sanitize_output(output, creds.password)
        error("  ✗ pg_dump failed (exit code #{code})")

        # Show last few lines for debugging
        sanitized
        |> String.split("\n")
        |> Enum.take(-10)
        |> Enum.reject(&(&1 == ""))
        |> Enum.each(&error("    #{&1}"))

        {:error, "pg_dump failed"}

      {:error, reason} ->
        IO.write("\r\e[K")
        {:error, reason}
    end
  end

  defp collect_dump_output(port, password, acc, monitor_pid) do
    receive do
      {^port, {:data, data}} ->
        # Notify monitor of activity
        send(monitor_pid, :activity)

        # Sanitize password from output
        sanitized = sanitize_output(data, password)

        # Show table progress from verbose output
        sanitized
        |> String.split("\n")
        |> Enum.each(fn line ->
          line = String.trim(line)

          cond do
            line == "" ->
              :ok

            String.contains?(line, "dumping contents of table") ->
              table = extract_table_name(line)
              IO.write("\r\e[K  → Dumping: #{table}...")

            String.contains?(line, "saving") && String.contains?(line, "statistics") ->
              IO.write("\r\e[K  → Saving statistics...")

            String.contains?(String.downcase(line), "error") or
            String.contains?(String.downcase(line), "fatal") or
                String.contains?(String.downcase(line), "refused") ->
              IO.write("\r\e[K")
              IO.puts("  ⚠ #{line}")

            String.contains?(line, "reading") or
            String.contains?(line, "identifying") or
                String.contains?(line, "started") ->
              verbose_info("\r\e[K  → #{line}")

            true ->
              :ok
          end
        end)

        collect_dump_output(port, password, [sanitized | acc], monitor_pid)

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> Enum.reverse() |> Enum.join()}

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> Enum.join()
        {:error, output, code}

      {:timeout_stalled} ->
        Port.close(port)
        {:error, "No progress for #{div(@stall_timeout_seconds, 60)} minutes - connection may have stalled"}
    end
  end

  defp extract_table_name(line) do
    case Regex.run(~r/table "?([^"]+)"?\.?"?([^"]+)"?/, line) do
      [_, schema, table] -> "#{schema}.#{table}"
      _ ->
        case Regex.run(~r/table (\S+)/, line) do
          [_, table] -> table
          _ -> "..."
        end
    end
  end

  defp monitor_dump_progress(dump_path, parent) do
    monitor_dump_progress(dump_path, parent, System.monotonic_time(:second), 0, System.monotonic_time(:second))
  end

  defp monitor_dump_progress(dump_path, parent, start_time, last_size, last_activity_time) do
    receive do
      :stop ->
        :ok

      :activity ->
        # Reset activity timer when we get output
        monitor_dump_progress(dump_path, parent, start_time, last_size, System.monotonic_time(:second))
    after
      2000 ->
        now = System.monotonic_time(:second)

        case File.stat(dump_path) do
          {:ok, %{size: size}} when size > 0 ->
            elapsed = now - start_time
            rate = if elapsed > 0, do: size / elapsed, else: 0

            # Check if file is growing
            file_growing = size > last_size
            new_activity_time = if file_growing, do: now, else: last_activity_time

            # Only update display if size changed
            if size != last_size do
              size_str = format_size(size)
              rate_str = format_size(round(rate)) <> "/s"
              elapsed_str = format_duration(elapsed)
              IO.write("\r\e[K  → Exporting... #{size_str} (#{rate_str}) [#{elapsed_str}]")
            end

            # Check for stall
            stall_duration = now - new_activity_time

            if stall_duration > @stall_timeout_seconds do
              IO.puts("\n  ⚠ No progress for #{div(stall_duration, 60)} minutes")
              send(parent, {:timeout_stalled})
            else
              monitor_dump_progress(dump_path, parent, start_time, size, new_activity_time)
            end

          _ ->
            # File doesn't exist yet, check for initial connection stall
            stall_duration = now - last_activity_time

            if stall_duration > 300 do
              IO.puts("\n  ⚠ No response for #{div(stall_duration, 60)} minutes")
              send(parent, {:timeout_stalled})
            else
              monitor_dump_progress(dump_path, parent, start_time, last_size, last_activity_time)
            end
        end
    end
  end

  defp sanitize_output(output, password) do
    output
    |> String.replace(password, "********")
    |> String.replace(~r/password=\S+/, "password=********")
  end

  # ============================================================================
  # Phase 3: Database Preparation
  # ============================================================================

  defp confirm_destructive_operation(opts) do
    if opts[:yes] do
      :ok
    else
      info("\n⚠️  This will DROP and RECREATE the local database '#{@local_db}'")
      info("   All existing data will be lost!\n")

      case Mix.shell().prompt("Continue? [y/N]") do
        response when response in ["y", "Y", "yes", "Yes", "YES"] ->
          :ok

        _ ->
          {:error, "Operation cancelled by user"}
      end
    end
  end

  defp prepare_local_database(_opts) do
    info("🗄️  Preparing local database...")

    with :ok <- drop_local_database(),
         :ok <- create_local_database() do
      :ok
    end
  end

  defp drop_local_database do
    # First, block new connections and terminate existing ones
    terminate_cmd = """
    PGPASSWORD='#{@local_password}' psql -h #{@local_host} -p #{@local_port} -U #{@local_user} postgres -c "
      -- Revoke connect to prevent new connections
      REVOKE CONNECT ON DATABASE #{@local_db} FROM PUBLIC;

      -- Terminate all existing connections
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '#{@local_db}'
      AND pid <> pg_backend_pid();
    " 2>&1
    """

    case System.cmd("sh", ["-c", terminate_cmd], stderr_to_stdout: true) do
      {_, 0} ->
        verbose_info("  → Terminated existing connections")

      {output, _} ->
        # Only warn if it's not a "database doesn't exist" error
        unless String.contains?(output, "does not exist") do
          verbose_info("  → Note: #{String.slice(output, 0, 100)}")
        end
    end

    # Small delay to let connections close
    Process.sleep(1000)

    # Now drop the database with force flag (Postgres 13+)
    drop_cmd =
      "PGPASSWORD='#{@local_password}' dropdb --if-exists --force -h #{@local_host} -p #{@local_port} -U #{@local_user} #{@local_db} 2>&1"

    case System.cmd("sh", ["-c", drop_cmd], stderr_to_stdout: true) do
      {_output, 0} ->
        info("  ✓ Dropped existing database")
        :ok

      {output, _code} ->
        cond do
          String.contains?(output, "does not exist") ->
            info("  ✓ No existing database to drop")
            :ok

          # If --force isn't supported (older Postgres), retry without it
          String.contains?(output, "unrecognized option") or String.contains?(output, "invalid option") ->
            drop_cmd_legacy =
              "PGPASSWORD='#{@local_password}' dropdb --if-exists -h #{@local_host} -p #{@local_port} -U #{@local_user} #{@local_db} 2>&1"

            case System.cmd("sh", ["-c", drop_cmd_legacy], stderr_to_stdout: true) do
              {_output, 0} ->
                info("  ✓ Dropped existing database")
                :ok

              {output2, _} ->
                error("  ✗ Failed to drop database: #{output2}")
                {:error, "Failed to drop database"}
            end

          true ->
            error("  ✗ Failed to drop database: #{output}")
            {:error, "Failed to drop database"}
        end
    end
  end

  defp create_local_database do
    cmd =
      "PGPASSWORD='#{@local_password}' createdb -h #{@local_host} -p #{@local_port} -U #{@local_user} #{@local_db} 2>&1"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {_output, 0} ->
        info("  ✓ Created fresh database")
        :ok

      {output, _code} ->
        error("  ✗ Failed to create database: #{output}")
        {:error, "Failed to create database"}
    end
  end

  # ============================================================================
  # Phase 3: Import Database
  # ============================================================================

  defp import_database(dump_path, opts) do
    info("📥 Importing to local database...")

    with :ok <- ensure_dump_file(dump_path) do
      do_import_database(dump_path, opts)
    end
  end

  defp do_import_database(dump_path, opts) do
    dump_size = File.stat!(dump_path).size
    info("  → Restoring #{format_size(dump_size)} dump...")

    parallel_arg = if opts[:parallel], do: "-j #{opts[:parallel]}", else: ""

    # Use --verbose to get table-by-table progress
    cmd = """
    PGPASSWORD='#{@local_password}' pg_restore \
      -h #{@local_host} \
      -p #{@local_port} \
      -U #{@local_user} \
      -d #{@local_db} \
      --no-owner \
      --no-acl \
      --verbose \
      #{parallel_arg} \
      '#{dump_path}' \
      2>&1
    """

    start_time = System.monotonic_time(:second)

    # Run pg_restore and capture output for progress
    port = Port.open({:spawn, "sh -c \"#{cmd}\""}, [:binary, :exit_status, :stderr_to_stdout])

    result = collect_restore_output(port, [])

    elapsed = System.monotonic_time(:second) - start_time

    case result do
      {:ok, _output} ->
        IO.write("\r\e[K")
        info("  ✓ Import completed in #{format_duration(elapsed)}")
        :ok

      {:error, output, _code} ->
        IO.write("\r\e[K")
        # pg_restore often returns non-zero for warnings, check for actual errors
        if has_critical_errors?(output) do
          error("  ✗ pg_restore failed")

          # Show last few lines for debugging
          output
          |> String.split("\n")
          |> Enum.take(-10)
          |> Enum.reject(&(&1 == ""))
          |> Enum.each(&error("    #{&1}"))

          {:error, "pg_restore failed"}
        else
          info("  ✓ Import completed in #{format_duration(elapsed)} (with warnings)")
          :ok
        end
    end
  end

  defp collect_restore_output(port, acc) do
    receive do
      {^port, {:data, data}} ->
        # Show table progress from verbose output
        data
        |> String.split("\n")
        |> Enum.each(fn line ->
          cond do
            String.contains?(line, "processing data for table") ->
              table = extract_restore_table_name(line)
              IO.write("\r\e[K  → Restoring: #{table}...")

            String.contains?(line, "creating INDEX") ->
              IO.write("\r\e[K  → Creating indexes...")

            String.contains?(line, "creating CONSTRAINT") ->
              IO.write("\r\e[K  → Creating constraints...")

            String.contains?(line, "creating TRIGGER") ->
              IO.write("\r\e[K  → Creating triggers...")

            String.contains?(line, "creating FK CONSTRAINT") ->
              IO.write("\r\e[K  → Creating foreign keys...")

            String.contains?(line, "creating EXTENSION") ->
              IO.write("\r\e[K  → Creating extensions...")

            String.contains?(line, "creating TYPE") ->
              IO.write("\r\e[K  → Creating types...")

            true ->
              :ok
          end
        end)

        collect_restore_output(port, [data | acc])

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> Enum.reverse() |> Enum.join()}

      {^port, {:exit_status, code}} ->
        {:error, acc |> Enum.reverse() |> Enum.join(), code}
    after
      # 30 minute timeout for large restores
      1_800_000 ->
        Port.close(port)
        {:error, "Timeout after 30 minutes", 1}
    end
  end

  defp extract_restore_table_name(line) do
    case Regex.run(~r/table "?public"?\."?([^"]+)"?/, line) do
      [_, table] ->
        table

      _ ->
        case Regex.run(~r/table (\S+)/, line) do
          [_, table] -> table
          _ -> "..."
        end
    end
  end

  defp has_critical_errors?(output) do
    critical_patterns = [
      "FATAL:",
      "could not connect",
      "connection refused",
      "authentication failed",
      "invalid input syntax",
      "violates foreign key constraint"
    ]

    Enum.any?(critical_patterns, &String.contains?(output, &1))
  end

  # ============================================================================
  # Phase 4: Post-Import Cleanup
  # ============================================================================

  defp post_import_cleanup(_opts) do
    info("🧹 Running post-import cleanup...")

    # Start the application to use Ecto
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    # Start repo manually for this task
    case start_repo() do
      {:ok, _pid} ->
        run_cleanup_tasks()

      {:error, {:already_started, _}} ->
        run_cleanup_tasks()

      {:error, reason} ->
        error("  ✗ Failed to start repo: #{inspect(reason)}")
        # Continue anyway - cleanup is optional
        info("  ⚠ Skipping cleanup steps")
        :ok
    end
  end

  defp run_cleanup_tasks do
    with :ok <- clean_oban_jobs(),
         :ok <- reset_sequences(),
         :ok <- refresh_materialized_views() do
      :ok
    end
  end

  defp start_repo do
    # Get repo config for local development
    repo_config = [
      username: @local_user,
      password: @local_password,
      hostname: @local_host,
      port: String.to_integer(@local_port),
      database: @local_db,
      pool_size: 2,
      timeout: 120_000
    ]

    EventasaurusApp.Repo.start_link(repo_config)
  end

  defp clean_oban_jobs do
    verbose_info("  → Cleaning Oban jobs...")

    queries = [
      "DELETE FROM oban_jobs WHERE state IN ('scheduled', 'available', 'executing')",
      "DELETE FROM oban_peers"
    ]

    Enum.each(queries, fn query ->
      case EventasaurusApp.Repo.query(query) do
        {:ok, result} ->
          verbose_info("    Cleaned #{result.num_rows} rows")

        {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
          verbose_info("    Table doesn't exist, skipping")

        {:error, reason} ->
          verbose_info("    Warning: #{inspect(reason)}")
      end
    end)

    info("  ✓ Cleaned Oban jobs")
    :ok
  end

  defp reset_sequences do
    verbose_info("  → Resetting sequences...")

    # Query to generate reset commands for all sequences
    query = """
    SELECT 'SELECT setval(' ||
           quote_literal(quote_ident(schemaname) || '.' || quote_ident(sequencename)) ||
           ', COALESCE((SELECT MAX(id) FROM ' ||
           quote_ident(schemaname) || '.' || quote_ident(replace(sequencename, '_id_seq', '')) ||
           '), 1))' AS reset_cmd
    FROM pg_sequences
    WHERE schemaname = 'public'
    AND sequencename LIKE '%_id_seq'
    """

    case EventasaurusApp.Repo.query(query) do
      {:ok, %{rows: rows}} ->
        reset_count =
          Enum.reduce(rows, 0, fn [cmd], acc ->
            case EventasaurusApp.Repo.query(cmd) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          end)

        info("  ✓ Reset #{reset_count} sequences")

      {:error, reason} ->
        verbose_info("  ⚠ Could not reset sequences: #{inspect(reason)}")
    end

    :ok
  end

  defp refresh_materialized_views do
    verbose_info("  → Refreshing materialized views...")

    # Find all materialized views
    query = """
    SELECT schemaname || '.' || matviewname
    FROM pg_matviews
    WHERE schemaname = 'public'
    """

    case EventasaurusApp.Repo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.each(rows, fn [view_name] ->
          verbose_info("    Refreshing #{view_name}...")

          # Properly quote schema-qualified identifiers (e.g., "public"."my_view")
          # to prevent SQL injection and handle special characters
          quoted_view =
            case String.split(view_name, ".", parts: 2) do
              [schema, relation] ->
                quoted_schema = ~s("#{String.replace(schema, "\"", "\"\"")}")
                quoted_relation = ~s("#{String.replace(relation, "\"", "\"\"")}")
                "#{quoted_schema}.#{quoted_relation}"

              [single_name] ->
                ~s("#{String.replace(single_name, "\"", "\"\"")}")
            end

          case EventasaurusApp.Repo.query("REFRESH MATERIALIZED VIEW #{quoted_view}") do
            {:ok, _} -> :ok
            {:error, reason} -> verbose_info("    Warning: #{inspect(reason)}")
          end
        end)

        if length(rows) > 0 do
          info("  ✓ Refreshed #{length(rows)} materialized views")
        else
          verbose_info("  → No materialized views to refresh")
        end

      {:error, reason} ->
        verbose_info("  ⚠ Could not refresh views: #{inspect(reason)}")
    end

    :ok
  end

  # ============================================================================
  # Phase 5: Verification
  # ============================================================================

  defp maybe_verify(opts) do
    if opts[:skip_verify] do
      info("⏭️  Skipping verification")
      :ok
    else
      verify_import()
    end
  end

  defp verify_import do
    info("🔍 Verifying import...")

    results =
      Enum.map(@verify_tables, fn table ->
        count = get_table_count(table)
        info("  #{String.pad_trailing(table <> ":", 20)} #{format_number(count)} records")
        {table, count}
      end)

    # Check for empty critical tables
    empty_critical =
      Enum.filter(results, fn {table, count} ->
        count == 0 && table in @critical_tables
      end)

    if Enum.empty?(empty_critical) do
      info("  ✓ All critical tables have data")
      :ok
    else
      tables = Enum.map(empty_critical, &elem(&1, 0)) |> Enum.join(", ")
      error("  ✗ Critical tables are empty: #{tables}")
      {:error, "Critical tables empty"}
    end
  end

  defp get_table_count(table) do
    case EventasaurusApp.Repo.query("SELECT COUNT(*) FROM #{table}") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  # ============================================================================
  # Phase 6: Cleanup
  # ============================================================================

  defp ensure_dump_file(path) do
    if File.exists?(path) do
      :ok
    else
      error("  ✗ Dump file not found: #{path}")
      {:error, "Dump file not found: #{path}"}
    end
  end

  defp maybe_cleanup_dump(dump_path, opts) do
    if opts[:keep_dump] do
      verbose_info("  → Keeping dump file: #{dump_path}")
      :ok
    else
      case File.rm(dump_path) do
        :ok ->
          info("  🗑️  Removed dump file: #{dump_path}")
          :ok

        {:error, reason} ->
          error("  ⚠ Failed to remove dump file: #{inspect(reason)}")
          # Don't fail the whole sync just because cleanup failed
          :ok
      end
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp info(message), do: Mix.shell().info(message)
  defp error(message), do: Mix.shell().error(message)

  defp verbose_info(message) do
    if Application.get_env(:eventasaurus, :verbose_sync, false) do
      Mix.shell().info(message)
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{mins}m #{secs}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    mins = div(rem(seconds, 3600), 60)
    "#{hours}h #{mins}m"
  end

  defp format_number(num) when num < 1000, do: "#{num}"

  defp format_number(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
