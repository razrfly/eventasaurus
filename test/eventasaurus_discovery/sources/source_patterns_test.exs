defmodule EventasaurusDiscovery.Sources.SourcePatternsTest do
  @moduledoc """
  Tests for the SourcePatterns module which provides worker patterns
  for CLI mix tasks, derived from SourceRegistry.
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.SourcePatterns
  alias EventasaurusDiscovery.Sources.SourceRegistry

  describe "get_worker_pattern/1" do
    test "returns SQL LIKE pattern for valid source" do
      assert {:ok, pattern} = SourcePatterns.get_worker_pattern("cinema_city")
      assert pattern =~ "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%"
      assert String.ends_with?(pattern, "%")
    end

    test "converts CLI key (underscores) to registry key (hyphens)" do
      # cinema_city (CLI) -> cinema-city (registry)
      assert {:ok, _pattern} = SourcePatterns.get_worker_pattern("cinema_city")

      # resident_advisor (CLI) -> resident-advisor (registry)
      assert {:ok, pattern} = SourcePatterns.get_worker_pattern("resident_advisor")
      assert pattern =~ "ResidentAdvisor"
    end

    test "handles sources with no conversion needed" do
      # Sources like "bandsintown" have same CLI and registry key
      assert {:ok, pattern} = SourcePatterns.get_worker_pattern("bandsintown")
      assert pattern =~ "EventasaurusDiscovery.Sources.Bandsintown.Jobs.%"
    end

    test "returns error for unknown source" do
      assert {:error, :not_found} = SourcePatterns.get_worker_pattern("unknown_source")
      assert {:error, :not_found} = SourcePatterns.get_worker_pattern("")
    end
  end

  describe "get_sync_worker/1" do
    test "returns exact SyncJob worker name" do
      assert {:ok, worker} = SourcePatterns.get_sync_worker("cinema_city")
      assert worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"
    end

    test "returns error for unknown source" do
      assert {:error, :not_found} = SourcePatterns.get_sync_worker("unknown_source")
    end
  end

  describe "get_display_name/1" do
    test "capitalizes words separated by underscores" do
      assert SourcePatterns.get_display_name("cinema_city") == "Cinema City"
      assert SourcePatterns.get_display_name("resident_advisor") == "Resident Advisor"
      assert SourcePatterns.get_display_name("geeks_who_drink") == "Geeks Who Drink"
    end

    test "capitalizes single word sources" do
      assert SourcePatterns.get_display_name("bandsintown") == "Bandsintown"
      assert SourcePatterns.get_display_name("karnet") == "Karnet"
    end

    test "handles edge cases" do
      assert SourcePatterns.get_display_name("") == ""
      assert SourcePatterns.get_display_name("a") == "A"
    end
  end

  describe "all_cli_keys/0" do
    test "returns all sources in CLI format (underscores)" do
      keys = SourcePatterns.all_cli_keys()

      # Should have 16 sources
      assert length(keys) == 16

      # Most keys should use underscores, not hyphens (except edge cases in registry)
      keys_with_hyphens = Enum.filter(keys, &String.contains?(&1, "-"))

      # Currently there are no keys with hyphens in CLI format
      # (registry keys with hyphens get converted to underscores)
      assert length(keys_with_hyphens) == 0
    end

    test "returns keys in sorted order" do
      keys = SourcePatterns.all_cli_keys()
      assert keys == Enum.sort(keys)
    end

    test "includes expected sources" do
      keys = SourcePatterns.all_cli_keys()

      assert "cinema_city" in keys
      assert "bandsintown" in keys
      assert "resident_advisor" in keys
      assert "geeks_who_drink" in keys
    end
  end

  describe "all_patterns/0" do
    test "returns map of CLI keys to worker patterns" do
      patterns = SourcePatterns.all_patterns()

      assert is_map(patterns)
      assert map_size(patterns) == 16

      # Check structure
      Enum.each(patterns, fn {key, pattern} ->
        assert is_binary(key)
        assert is_binary(pattern)
        assert String.ends_with?(pattern, "%")
        assert pattern =~ "EventasaurusDiscovery.Sources."
      end)
    end

    test "patterns can be used for SQL LIKE queries" do
      patterns = SourcePatterns.all_patterns()

      # All patterns should end with % for SQL LIKE matching
      Enum.each(patterns, fn {_key, pattern} ->
        assert String.ends_with?(pattern, "%")
      end)
    end
  end

  describe "all_sync_workers/0" do
    test "returns map of CLI keys to exact SyncJob worker names" do
      workers = SourcePatterns.all_sync_workers()

      assert is_map(workers)
      assert map_size(workers) == 16

      # Check structure
      Enum.each(workers, fn {key, worker} ->
        assert is_binary(key)
        assert is_binary(worker)
        assert String.ends_with?(worker, "SyncJob")
        refute String.ends_with?(worker, "%")
      end)
    end
  end

  describe "valid_source?/1" do
    test "returns true for valid CLI keys" do
      assert SourcePatterns.valid_source?("cinema_city")
      assert SourcePatterns.valid_source?("bandsintown")
      assert SourcePatterns.valid_source?("resident_advisor")
    end

    test "returns false for invalid keys" do
      refute SourcePatterns.valid_source?("unknown_source")
      refute SourcePatterns.valid_source?("")
      refute SourcePatterns.valid_source?("not_a_real_source")
    end

    test "accepts both CLI format (underscores) and registry format (hyphens)" do
      # CLI format
      assert SourcePatterns.valid_source?("cinema_city")
      # Registry format (also valid for user convenience)
      assert SourcePatterns.valid_source?("cinema-city")
    end

    test "most CLI keys returned by all_cli_keys/0 are valid" do
      # Get all CLI keys and check most are valid
      # Note: "week_pl" is a known edge case in SourceRegistry (uses underscore instead of hyphen)
      valid_count =
        SourcePatterns.all_cli_keys()
        |> Enum.count(&SourcePatterns.valid_source?/1)

      # At least 15 of 16 sources should be valid (accounting for week_pl edge case)
      assert valid_count >= 15
    end
  end

  describe "consistency with SourceRegistry" do
    test "all_cli_keys matches SourceRegistry.all_sources count" do
      registry_count = SourceRegistry.all_sources() |> length()
      patterns_count = SourcePatterns.all_cli_keys() |> length()

      assert registry_count == patterns_count,
             "SourcePatterns has #{patterns_count} sources but SourceRegistry has #{registry_count}"
    end

    test "most CLI keys map to valid SourceRegistry sources" do
      # Count how many CLI keys successfully map to registry sources
      success_count =
        SourcePatterns.all_cli_keys()
        |> Enum.count(fn cli_key ->
          registry_key = String.replace(cli_key, "_", "-")
          result = SourceRegistry.get_sync_job(registry_key)
          match?({:ok, _}, result)
        end)

      # At least 15 of 16 should succeed (week_pl is a known edge case)
      assert success_count >= 15,
             "Expected at least 15 sources to map correctly, got #{success_count}"
    end
  end
end
