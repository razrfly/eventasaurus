defmodule Tidewave.MCP.Grep do
  @moduledoc false

  alias Tidewave.MCP.GitLS
  alias Tidewave.MCP.Utils

  def grep(pattern, nil, case_sensitive, max_results) do
    with {:ok, files} <- GitLS.list_files() do
      grep_files(files, pattern, case_sensitive, max_results)
    end
  end

  def grep(pattern, glob_pattern, case_sensitive, max_results) do
    files = Path.wildcard("**/#{glob_pattern}")
    grep_files(files, pattern, case_sensitive, max_results)
  end

  defp grep_files(files, pattern, case_sensitive, max_results) do
    # Compile the regex pattern
    regex_opts = if case_sensitive, do: "", else: "i"
    regex = Regex.compile!(pattern, regex_opts)

    # Process files in parallel
    matches =
      Task.async_stream(
        files,
        fn file ->
          search_file(file, regex, max_results)
        end,
        ordered: false,
        timeout: :infinity
      )
      |> Stream.flat_map(fn {:ok, results} -> results end)
      |> Enum.take(max_results)

    {:ok, Jason.encode!(matches)}
  end

  defp search_file(file, regex, max_results) do
    stream =
      if Version.match?(System.version(), ">= 1.16.0") do
        fn file -> File.stream!(file, :line) end
      else
        # Elixir < 1.16 had
        #   File.stream!(file, options, line_or_bytes) instead of
        #   File.stream!(file, line_or_bytes, options)
        fn file -> File.stream!(file, [], :line) end
      end

    try do
      # Stream the file line by line
      stream.(file)
      |> Stream.with_index(1)
      |> Stream.filter(fn {line, _} -> Regex.match?(regex, line) end)
      |> Enum.take(max_results)
      |> Enum.map(fn {line, line_number} ->
        %{
          "path" => file,
          "line" => line_number,
          "content" => Utils.truncate_lines(line)
        }
      end)
    rescue
      _ -> []
    end
  end
end
