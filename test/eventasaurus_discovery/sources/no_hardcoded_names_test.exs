defmodule EventasaurusDiscovery.Sources.NoHardcodedNamesTest do
  use EventasaurusApp.DataCase, async: false

  @moduledoc """
  Safeguard test to prevent hardcoding of source display names.

  This test scans the codebase for patterns that indicate hardcoded source names
  and fails if any are found, ensuring all source display names come from the
  database via Source.get_display_name/1.

  ## Why This Test Exists

  Before centralization, source names were hardcoded in multiple places:
  - AggregatedContentLive.get_source_name/1 (2 sources)
  - JobRegistry.humanize_source_name/1 (13 sources)

  This led to:
  - Inconsistent naming across the app
  - Need for code changes when adding new sources
  - Risk of outdated names when sources rebrand

  ## Solution

  All source display names must come from:
  - Database: `sources` table `name` field
  - Helper: `Source.get_display_name/1`
  - Fallback: Automatic slug-to-title conversion

  ## What This Test Checks

  1. No pattern matching on known source slugs for display names
  2. No hardcoded source names in specific high-risk files
  3. Usage of Source.get_display_name/1 in appropriate contexts

  ## If This Test Fails

  You likely added hardcoded source names. Instead:

  ```elixir
  # ❌ BAD - Hardcoded
  defp get_name("week_pl"), do: "Restaurant Week"
  defp get_name("bandsintown"), do: "Bandsintown"

  # ✅ GOOD - Database-driven
  defp get_name(slug), do: Source.get_display_name(slug)
  ```

  To add a new source:
  1. Add to `priv/repo/seeds/reference_data/sources.exs`
  2. Run seeds: `mix run priv/repo/seeds.exs`
  3. Source name automatically available via Source.get_display_name/1
  """

  # Known source slugs that should NEVER be hardcoded
  @known_source_slugs [
    "week_pl",
    "bandsintown",
    "resident-advisor",
    "ticketmaster",
    "pubquiz-pl",
    "question-one",
    "geeks-who-drink",
    "speed-quizzing",
    "quizmeisters",
    "inquizition",
    "cinema-city",
    "kino-krakow",
    "sortiraparis",
    "karnet",
    "waw4free"
  ]

  # Known source display names that should NEVER be hardcoded
  @known_source_names [
    "Restaurant Week",
    "Bandsintown",
    "Resident Advisor",
    "Ticketmaster",
    "PubQuiz Poland",
    "Question One",
    "Geeks Who Drink",
    "Speed Quizzing",
    "Quizmeisters",
    "Inquizition",
    "Cinema City",
    "Kino Krakow",
    "SortirAParis",
    "Karnet",
    "Waw4Free"
  ]

  # Files that previously had hardcoded names and are high-risk for regression
  @high_risk_files [
    "lib/eventasaurus_web/live/aggregated_content_live.ex",
    "lib/eventasaurus_app/monitoring/job_registry.ex"
  ]

  describe "source name hardcoding prevention" do
    test "no pattern matching on source slugs for display names" do
      violations = find_hardcoded_slug_patterns()

      assert Enum.empty?(violations),
             """
             Found hardcoded source slug pattern matching!

             Files with violations:
             #{format_violations(violations)}

             These patterns suggest hardcoded source names. Use Source.get_display_name/1 instead:

             ❌ BAD:
               defp get_source_name("week_pl"), do: "Restaurant Week"
               defp humanize("bandsintown"), do: "Bandsintown Sync"

             ✅ GOOD:
               defp get_source_name(slug), do: Source.get_display_name(slug)
               defp humanize(slug), do: Source.get_display_name(slug) <> " Sync"

             See: lib/eventasaurus_discovery/sources/source.ex:178
             """
    end

    test "no hardcoded source names in high-risk files" do
      violations = find_hardcoded_names_in_files(@high_risk_files)

      assert Enum.empty?(violations),
             """
             Found hardcoded source display names in high-risk files!

             Violations:
             #{format_violations(violations)}

             These files previously had hardcoded names and were refactored.
             Do not add hardcoded names back - use Source.get_display_name/1 instead.

             See Phase 2 implementation in issue #2344
             """
    end

    test "Source.get_display_name/1 is used correctly" do
      # Verify the helper function exists and works
      assert function_exported?(EventasaurusDiscovery.Sources.Source, :get_display_name, 1),
             """
             Source.get_display_name/1 function not found!

             This is the required helper for source display names.
             See: lib/eventasaurus_discovery/sources/source.ex
             """

      # Test it works for known sources
      alias EventasaurusDiscovery.Sources.Source

      # These should return proper names (fallback if not in DB)
      assert is_binary(Source.get_display_name("week_pl"))
      assert is_binary(Source.get_display_name("bandsintown"))
      assert is_binary(Source.get_display_name("unknown-source"))
    end
  end

  # Find files with pattern matching on source slugs that return display names
  defp find_hardcoded_slug_patterns do
    # Look for pattern matching that returns capitalized strings (likely display names)
    # Pattern: defp func("source_slug"), do: "Display Name"
    # We want to catch functions that return display-name-like strings
    patterns = [
      # Function pattern matching on slug returning a capitalized multi-word string
      # This catches: defp get_name("week_pl"), do: "Restaurant Week"
      ~r/defp?\s+\w*name\w*\("(#{Enum.join(@known_source_slugs, "|")})"\)\s*,?\s*do:\s*"[A-Z][a-z]+(\s+[A-Z][a-z]+)+"/,

      # Function pattern matching returning capitalized single word (brand names)
      # This catches: defp get_name("bandsintown"), do: "Bandsintown"
      ~r/defp?\s+\w*name\w*\("(#{Enum.join(@known_source_slugs, "|")})"\)\s*,?\s*do:\s*"[A-Z][a-z]+"/
    ]

    find_violations(patterns, "lib/**/*.ex")
  end

  # Find hardcoded source display names in specific files
  defp find_hardcoded_names_in_files(files) do
    # Look for pattern matching that returns hardcoded source names
    # This is more specific than just finding the strings - we want to catch
    # functions that pattern match on slugs and return hardcoded names
    Enum.flat_map(files, fn file ->
      if File.exists?(file) do
        content = File.read!(file)
        lines = String.split(content, "\n")

        # Look for pattern matching that returns known source names
        # Pattern: defp some_name_func("slug"), do: "Source Name"
        pattern = ~r/defp?\s+\w*\("[\w_-]+"\)\s*,?\s*do:\s*"(#{Enum.join(@known_source_names, "|")})"/

        matching_lines =
          Enum.with_index(lines, 1)
          |> Enum.filter(fn {line, _idx} ->
            Regex.match?(pattern, line) and
            not (String.trim(line) |> String.starts_with?("#"))
          end)

        case matching_lines do
          [] -> []
          lines -> [{file, Enum.map(lines, fn {line, idx} -> {idx, String.trim(line)} end)}]
        end
      else
        []
      end
    end)
  end

  # Generic violation finder
  defp find_violations(patterns, glob_pattern) do
    Path.wildcard(glob_pattern)
    |> Enum.flat_map(fn file ->
      content = File.read!(file)

      Enum.flat_map(patterns, fn pattern ->
        case Regex.scan(pattern, content) do
          [] ->
            []

          matches ->
            lines = String.split(content, "\n")
            matching_lines =
              Enum.with_index(lines, 1)
              |> Enum.filter(fn {line, _idx} ->
                Enum.any?(matches, fn [match | _] -> String.contains?(line, match) end)
              end)
              |> Enum.reject(fn {line, _idx} ->
                # Ignore comments and test files
                String.trim(line) |> String.starts_with?("#") or
                String.contains?(file, "test/") or
                String.contains?(line, "@moduledoc") or
                String.contains?(line, "@doc")
              end)

            case matching_lines do
              [] -> []
              lines -> [{file, Enum.map(lines, fn {line, idx} -> {idx, String.trim(line)} end)}]
            end
        end
      end)
    end)
  end

  defp format_violations(violations) do
    violations
    |> Enum.map(fn {file, lines} ->
      lines_formatted =
        lines
        |> Enum.map(fn {line_num, line_content} ->
          "    Line #{line_num}: #{line_content}"
        end)
        |> Enum.join("\n")

      "  #{file}:\n#{lines_formatted}"
    end)
    |> Enum.join("\n\n")
  end
end
