#!/usr/bin/env elixir

# Test script for event consolidation improvements

defmodule TestConsolidation do
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor

  def test_normalization do
    test_cases = [
      # Series events
      {"Comedy Night Episode 1", "Comedy Night Episode 2", true, "Series episodes"},
      {"Jazz Session #1", "Jazz Session #2", true, "Hash numbered series"},
      {"Open Mic Week 1", "Open Mic Week 2", true, "Week series"},
      {"Concert Part I", "Concert Part II", true, "Part series"},

      # Date variations
      {"Concert Sept 23", "Concert Oct 15", true, "Date variations"},
      {"Show 10/15/2024", "Show 11/20/2024", true, "Numeric date variations"},
      {"Thursday Night Jazz", "Friday Night Jazz", true, "Day of week variations"},
      {"Event 7pm doors", "Event 8pm doors", true, "Time variations"},

      # Marketing suffixes
      {"Concert | VIP Experience", "Concert", true, "Marketing suffix"},
      {"Show - Enhanced", "Show", true, "Enhanced suffix"},

      # Should NOT match
      {"Different Artist A", "Different Artist B", false, "Different artists"},
      {"Rock Concert", "Jazz Concert", false, "Different genres"}
    ]

    IO.puts("\n🧪 Testing Event Title Normalization and Matching\n")
    IO.puts("=" |> String.duplicate(80))

    Enum.each(test_cases, fn {title1, title2, should_match, description} ->
      # Use private functions from EventProcessor (normally we'd test through public API)
      norm1 = normalize_title(title1)
      norm2 = normalize_title(title2)

      # Check if they would match with series extraction
      base1 = extract_base(title1)
      base2 = extract_base(title2)

      # Calculate scores
      norm_score = String.jaro_distance(norm1, norm2)
      base_score = String.jaro_distance(base1, base2)
      best_score = max(norm_score, base_score)

      # Determine threshold (would be lower for series events)
      threshold = if is_series?(title1) || is_series?(title2), do: 0.70, else: 0.80

      matches = best_score >= threshold
      status = if matches == should_match, do: "✅", else: "❌"

      IO.puts("\n#{status} #{description}")
      IO.puts("   Title 1: '#{title1}'")
      IO.puts("   Title 2: '#{title2}'")
      IO.puts("   Normalized 1: '#{norm1}'")
      IO.puts("   Normalized 2: '#{norm2}'")
      IO.puts("   Series Base 1: '#{base1}'")
      IO.puts("   Series Base 2: '#{base2}'")
      IO.puts("   Scores: Normalized=#{Float.round(norm_score, 2)}, Base=#{Float.round(base_score, 2)}, Best=#{Float.round(best_score, 2)}")
      IO.puts("   Threshold: #{threshold}, Matches: #{matches}, Expected: #{should_match}")
    end)

    IO.puts("\n" <> String.duplicate("=", 80))
  end

  # Simplified versions of the private functions for testing
  defp normalize_title(title) do
    title
    |> String.downcase()
    |> remove_dates()
    |> remove_episodes()
    |> remove_times()
    |> remove_marketing()
    |> String.replace(~r/[:\-–\/|]/, " ")
    |> String.replace(~r/\s*@\s*.+$/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp remove_dates(title) do
    title
    |> String.replace(~r/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}/i, "")
    |> String.replace(~r/\b\d{1,2}[\/-]\d{1,2}([\/-]\d{2,4})?\b/, "")
    |> String.replace(~r/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*(night|evening)?\b/i, "")
    |> String.replace(~r/\b\d{1,2}(st|nd|rd|th)\b/i, "")
    |> String.replace(~r/\b20\d{2}\b/, "")
  end

  defp remove_episodes(title) do
    title
    |> String.replace(~r/\s*(episode|ep\.?)\s*\d+/i, "")
    |> String.replace(~r/\s*(part|pt\.?)\s*[ivx\d]+/i, "")
    |> String.replace(~r/\s*(week|day|session)\s*\d+/i, "")
    |> String.replace(~r/\s*#\d+\b/, "")
  end

  defp remove_times(title) do
    title
    |> String.replace(~r/\b\d{1,2}(:\d{2})?\s*(am|pm)\b/i, "")
    |> String.replace(~r/\bdoors?\s*(at)?\s*\d{1,2}(:\d{2})?\s*(am|pm)?\b/i, "")
  end

  defp remove_marketing(title) do
    title
    |> String.replace(~r/\s*\|\s*(enhanced|vip|premium|experience|exclusive).*/i, "")
    |> String.replace(~r/\s*[-–]\s*(enhanced|vip|premium|experience|exclusive).*/i, "")
  end

  defp extract_base(title) do
    title
    |> String.downcase()
    |> String.replace(~r/\s*(#\d+|episode\s+\d+|part\s+[ivx\d]+|week\s+\d+|session\s+\d+).*$/i, "")
    |> remove_dates()
    |> remove_times()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp is_series?(title) do
    String.match?(title, ~r/(episode|ep\.|part|week|session|#\d+)/i)
  end

  def test_thresholds do
    IO.puts("\n🎯 Testing Dynamic Similarity Thresholds\n")
    IO.puts("=" |> String.duplicate(80))

    test_titles = [
      {"Comedy Show Episode 5", :series, 0.70},
      {"Weekly Jazz Night", :recurring, 0.75},
      {"Regular Concert", :venue, 0.80},
      {"Random Event Title", :default, 0.85}
    ]

    Enum.each(test_titles, fn {title, type, expected} ->
      threshold = calculate_threshold(title)
      status = if threshold == expected, do: "✅", else: "❌"
      IO.puts("#{status} '#{title}' (#{type}) -> threshold: #{threshold} (expected: #{expected})")
    end)

    IO.puts("\n" <> String.duplicate("=", 80))
  end

  defp calculate_threshold(title) do
    cond do
      String.match?(title, ~r/(episode|part|week|session|#\d+)/i) -> 0.70
      String.match?(title, ~r/(weekly|monthly|every|daily)/i) -> 0.75
      true -> 0.80  # Assuming venue exists
    end
  end
end

# Run tests
TestConsolidation.test_normalization()
TestConsolidation.test_thresholds()

IO.puts("\n✨ Consolidation improvements test complete!\n")