defmodule Mix.Tasks.Db.QueryProduction do
  @moduledoc """
  Run read-only SQL queries against the production database.

  This task provides a safe, simple way to query production data without
  the complexity of setting up proxies or MCP servers. All queries are
  validated to be read-only before execution.

  ## Usage

      # Simple query
      mix db.query_production "SELECT COUNT(*) FROM public_events"

      # Formatted output
      mix db.query_production "SELECT id, title FROM movies LIMIT 5" --format table
      mix db.query_production "SELECT * FROM cities WHERE slug = 'krakow'" --format json

      # CSV for piping to file
      mix db.query_production "SELECT id, name FROM venues" --format csv > venues.csv

      # Dry run (show query without executing)
      mix db.query_production "SELECT 1" --dry-run

      # Custom timeout (default 30s)
      mix db.query_production "SELECT * FROM large_table" --timeout 60

  ## Output Formats

  - `table` (default) - ASCII table, human-readable
  - `json` - JSON array of objects
  - `csv` - CSV with headers
  - `raw` - Elixir term (for debugging)

  ## Safety

  This task enforces read-only access by:
  1. Validating queries start with SELECT, WITH, EXPLAIN, or SHOW
  2. Rejecting queries containing semicolons (no multi-statement)
  3. Rejecting INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, CREATE

  ## Prerequisites

  1. Fly CLI installed and authenticated (`fly auth login`)
  2. Production app running on Fly.io
  """

  use Mix.Task

  @shortdoc "Run read-only SQL queries against production database"

  @fly_app "eventasaurus"

  # Dangerous SQL keywords that indicate write operations
  @write_keywords ~w(INSERT UPDATE DELETE DROP ALTER TRUNCATE CREATE GRANT REVOKE VACUUM REINDEX)

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          dry_run: :boolean,
          timeout: :integer,
          no_headers: :boolean,
          help: :boolean
        ],
        aliases: [
          f: :format,
          d: :dry_run,
          t: :timeout,
          h: :help
        ]
      )

    if opts[:help] do
      print_help()
      System.halt(0)
    end

    query = Enum.join(positional, " ") |> String.trim()

    if query == "" do
      error("No query provided. Usage: mix db.query_production \"SELECT ...\"")
      System.halt(1)
    end

    format = opts[:format] || "table"
    timeout = opts[:timeout] || 30
    dry_run = opts[:dry_run] || false
    no_headers = opts[:no_headers] || false

    unless format in ~w(table json csv raw) do
      error("Invalid format '#{format}'. Must be one of: table, json, csv, raw")
      System.halt(1)
    end

    # Validate read-only
    case validate_read_only(query) do
      :ok ->
        :ok

      {:error, reason} ->
        error("Query rejected: #{reason}")
        System.halt(1)
    end

    if dry_run do
      info("🔍 Dry run - would execute:")
      IO.puts("")
      IO.puts("  #{query}")
      IO.puts("")
      info("Format: #{format}, Timeout: #{timeout}s")
      System.halt(0)
    end

    # Execute the query
    info("🔍 Querying production database...")

    case execute_query(query, timeout) do
      {:ok, columns, rows} ->
        format_output(columns, rows, format, no_headers)

      {:error, reason} ->
        error("Query failed: #{reason}")
        System.halt(1)
    end
  end

  # ============================================================================
  # Read-Only Validation
  # ============================================================================

  defp validate_read_only(query) do
    # Normalize for checking
    normalized = query |> String.trim() |> String.upcase()

    cond do
      # Check for semicolons (multi-statement injection)
      String.contains?(query, ";") ->
        {:error, "Multi-statement queries not allowed (found ';')"}

      # Check for write keywords anywhere in the query
      contains_write_keyword?(normalized) ->
        {:error, "Write operations not allowed (found dangerous keyword)"}

      # Must start with allowed read-only keywords
      String.starts_with?(normalized, "SELECT") or
      String.starts_with?(normalized, "WITH") or
      String.starts_with?(normalized, "EXPLAIN") or
          String.starts_with?(normalized, "SHOW") ->
        :ok

      true ->
        {:error, "Only SELECT, WITH, EXPLAIN, and SHOW queries allowed"}
    end
  end

  defp contains_write_keyword?(normalized_query) do
    # Check if any write keyword appears as a word (not substring)
    Enum.any?(@write_keywords, fn keyword ->
      # Match keyword as whole word using regex
      Regex.match?(~r/\b#{keyword}\b/, normalized_query)
    end)
  end

  # ============================================================================
  # Query Execution
  # ============================================================================

  defp execute_query(query, timeout_seconds) do
    # Escape the query for shell - double quotes need escaping for the nested shell command
    escaped_query =
      query
      |> String.replace("\\", "\\\\\\\\")
      |> String.replace("\"", "\\\\\\\"")

    # Build the RPC command as a single line with semicolons
    # We encode the result as JSON for easy parsing
    timeout_ms = timeout_seconds * 1000

    rpc_code =
      "result = Ecto.Adapters.SQL.query(EventasaurusApp.Repo, \\\"#{escaped_query}\\\", [], timeout: #{timeout_ms}); " <>
        "case result do " <>
        "{:ok, %{columns: cols, rows: rows}} -> IO.puts(\\\"__RESULT_START__\\\"); IO.puts(Jason.encode!(%{columns: cols, rows: rows})); IO.puts(\\\"__RESULT_END__\\\"); " <>
        "{:error, %Postgrex.Error{postgres: %{message: msg}}} -> IO.puts(\\\"__ERROR__:\\\" <> msg); " <>
        "{:error, reason} -> IO.puts(\\\"__ERROR__:\\\" <> inspect(reason)) " <>
        "end"

    # Execute via fly ssh console
    cmd = "fly ssh console -a #{@fly_app} -C '/app/bin/eventasaurus rpc \"#{rpc_code}\"'"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} ->
        parse_rpc_output(output)

      {output, _exit_code} ->
        {:error, "SSH command failed: #{String.slice(output, 0, 500)}"}
    end
  end

  defp parse_rpc_output(output) do
    cond do
      String.contains?(output, "__RESULT_START__") ->
        # Extract JSON between markers
        case Regex.run(~r/__RESULT_START__\s*(.+?)\s*__RESULT_END__/s, output) do
          [_, json] ->
            case Jason.decode(json) do
              {:ok, %{"columns" => columns, "rows" => rows}} ->
                {:ok, columns, rows}

              {:error, _} ->
                {:error, "Failed to parse result JSON"}
            end

          nil ->
            {:error, "Could not find result markers in output"}
        end

      String.contains?(output, "__ERROR__:") ->
        case Regex.run(~r/__ERROR__:(.+)/, output) do
          [_, error_msg] -> {:error, String.trim(error_msg)}
          nil -> {:error, "Unknown error"}
        end

      true ->
        {:error, "Unexpected output format: #{String.slice(output, 0, 200)}"}
    end
  end

  # ============================================================================
  # Output Formatting
  # ============================================================================

  defp format_output(columns, rows, format, no_headers) do
    case format do
      "table" -> format_table(columns, rows, no_headers)
      "json" -> format_json(columns, rows)
      "csv" -> format_csv(columns, rows, no_headers)
      "raw" -> format_raw(columns, rows)
    end
  end

  defp format_table(columns, rows, no_headers) do
    if Enum.empty?(rows) do
      info("(0 rows)")
      return_ok()
    end

    # Calculate column widths
    all_data = if no_headers, do: rows, else: [columns | rows]

    widths =
      columns
      |> Enum.with_index()
      |> Enum.map(fn {_col, idx} ->
        all_data
        |> Enum.map(fn row ->
          value = Enum.at(row, idx)
          value |> to_string() |> String.length()
        end)
        |> Enum.max()
      end)

    # Print header
    unless no_headers do
      header_line =
        columns
        |> Enum.with_index()
        |> Enum.map(fn {col, idx} -> String.pad_trailing(col, Enum.at(widths, idx)) end)
        |> Enum.join(" | ")

      IO.puts(header_line)

      separator =
        widths
        |> Enum.map(fn w -> String.duplicate("-", w) end)
        |> Enum.join("-+-")

      IO.puts(separator)
    end

    # Print rows
    Enum.each(rows, fn row ->
      line =
        row
        |> Enum.with_index()
        |> Enum.map(fn {val, idx} ->
          String.pad_trailing(format_value(val), Enum.at(widths, idx))
        end)
        |> Enum.join(" | ")

      IO.puts(line)
    end)

    IO.puts("")
    info("(#{length(rows)} rows)")
  end

  defp format_json(columns, rows) do
    result =
      Enum.map(rows, fn row ->
        columns
        |> Enum.zip(row)
        |> Map.new()
      end)

    IO.puts(Jason.encode!(result, pretty: true))
  end

  defp format_csv(columns, rows, no_headers) do
    unless no_headers do
      IO.puts(Enum.join(columns, ","))
    end

    Enum.each(rows, fn row ->
      line =
        row
        |> Enum.map(&csv_escape/1)
        |> Enum.join(",")

      IO.puts(line)
    end)
  end

  defp format_raw(columns, rows) do
    IO.puts("Columns: #{inspect(columns)}")
    IO.puts("Rows:")

    Enum.each(rows, fn row ->
      IO.puts("  #{inspect(row)}")
    end)
  end

  defp format_value(nil), do: "NULL"
  defp format_value(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp format_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_string(dt)
  defp format_value(%Date{} = d), do: Date.to_string(d)
  defp format_value(val) when is_binary(val), do: val
  defp format_value(val), do: inspect(val)

  defp csv_escape(nil), do: ""

  defp csv_escape(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"#{String.replace(val, "\"", "\"\"")}\""
    else
      val
    end
  end

  defp csv_escape(val), do: csv_escape(format_value(val))

  # ============================================================================
  # Output Helpers
  # ============================================================================

  defp info(msg), do: Mix.shell().info(msg)
  defp error(msg), do: Mix.shell().error("❌ #{msg}")

  defp return_ok, do: :ok

  defp print_help do
    IO.puts("""
    Usage: mix db.query_production [options] "SQL QUERY"

    Run read-only SQL queries against the production database.

    Options:
      --format, -f    Output format: table (default), json, csv, raw
      --dry-run, -d   Show query without executing
      --timeout, -t   Query timeout in seconds (default: 30)
      --no-headers    Omit column headers in table/csv output
      --help, -h      Show this help message

    Examples:
      mix db.query_production "SELECT COUNT(*) FROM public_events"
      mix db.query_production "SELECT id, title FROM movies LIMIT 5" --format json
      mix db.query_production "SELECT * FROM cities" --format csv > cities.csv

    Safety:
      Only SELECT, WITH, EXPLAIN, and SHOW queries are allowed.
      Queries with INSERT, UPDATE, DELETE, DROP, etc. are rejected.
    """)
  end
end
