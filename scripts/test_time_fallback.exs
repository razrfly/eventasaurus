#!/usr/bin/env elixir

# Direct test of parse_time_with_fallback function

alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser

IO.puts("=" |> String.duplicate(100))
IO.puts("TESTING parse_time_with_fallback FUNCTION")
IO.puts("=" |> String.duplicate(100))
IO.puts("")

# Test cases
test_cases = [
  {"Wednesday at 7pm", "Should extract 7pm"},
  {"Thursday at 00:00", "Should fallback to 8pm (20:00)"},
  {"Saturday at 00pm", "Should fallback to 8pm (20:00)"},
  {"Tuesday at 8.30pm", "Should extract 8:30pm"},
  {"Invalid time text", "Should fallback to 8pm (20:00)"},
  {nil, "Nil should fallback to 8pm (20:00)"}
]

IO.puts("Running #{length(test_cases)} test cases:")
IO.puts("")

Enum.each(test_cases, fn {text, description} ->
  IO.puts("Test: #{description}")
  IO.puts("  Input: #{inspect(text)}")

  result = RecurringEventParser.parse_time_with_fallback(text)

  case result do
    {:ok, time} ->
      IO.puts("  ✅ Result: #{Time.to_string(time)}")
    {:error, reason} ->
      IO.puts("  ❌ Error: #{reason}")
  end

  IO.puts("")
end)

IO.puts("=" |> String.duplicate(100))
IO.puts("TEST COMPLETE")
IO.puts("=" |> String.duplicate(100))
