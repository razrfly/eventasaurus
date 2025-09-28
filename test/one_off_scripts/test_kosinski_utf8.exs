#!/usr/bin/env elixir
# Test script specifically for the Kosiński UTF-8 issue
# Run with: mix run test_kosinski_utf8.exs

require Logger
alias EventasaurusDiscovery.Utils.UTF8
alias EventasaurusDiscovery.Scraping.Helpers.Normalizer
import Ecto.Query
alias EventasaurusApp.Repo

IO.puts("\n=== Testing Kosiński UTF-8 Issue ===\n")

# The exact name from production that's failing
problem_name = "Rock-Serwis Piotr Kosiński"

IO.puts("Test 1: Original Name Processing")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("  Original: #{inspect(problem_name)}")
IO.puts("  Bytes: #{inspect(:binary.bin_to_list(problem_name))}")
IO.puts("  Valid UTF-8? #{String.valid?(problem_name)}")

# Step 1: Clean UTF-8
clean_name = UTF8.ensure_valid_utf8(problem_name)
IO.puts("\n  After UTF8.ensure_valid_utf8:")
IO.puts("    Result: #{inspect(clean_name)}")
IO.puts("    Valid? #{String.valid?(clean_name)}")

# Step 2: Normalize
normalized = Normalizer.normalize_text(clean_name)
IO.puts("\n  After Normalizer.normalize_text:")
IO.puts("    Result: #{inspect(normalized)}")
IO.puts("    Valid? #{String.valid?(normalized)}")

# Step 3: Clean again (our fix)
final_clean = UTF8.ensure_valid_utf8(normalized)
IO.puts("\n  After second UTF8.ensure_valid_utf8:")
IO.puts("    Result: #{inspect(final_clean)}")
IO.puts("    Valid? #{String.valid?(final_clean)}")

# Test 2: Database Query
IO.puts("\nTest 2: Database Query with Cleaned Name")
IO.puts("=" <> String.duplicate("=", 60))

# Test the exact query that's failing
test_query = fn name ->
  try do
    result = Repo.one(
      from p in "performers",
      where: fragment("lower(?) = lower(?)", p.name, ^name),
      limit: 1,
      select: p.name
    )
    {:ok, result}
  rescue
    e in Postgrex.Error ->
      {:error, e.message}
  end
end

# Try with original (should fail)
IO.puts("  Query with original name:")
case test_query.(problem_name) do
  {:ok, result} -> IO.puts("    ✅ Success: #{inspect(result)}")
  {:error, msg} -> IO.puts("    ❌ Error: #{msg}")
end

# Try with cleaned name
IO.puts("\n  Query with cleaned name:")
case test_query.(final_clean) do
  {:ok, result} -> IO.puts("    ✅ Success: #{inspect(result)}")
  {:error, msg} -> IO.puts("    ❌ Error: #{msg}")
end

# Test 3: Other Polish names that might have issues
IO.puts("\nTest 3: Other Polish Names with Special Characters")
IO.puts("=" <> String.duplicate("=", 60))

polish_names = [
  "Stanisław Wyspiański",
  "Czesław Miłosz",
  "Lech Wałęsa",
  "Krzysztof Kieślowski",
  "Zbigniew Boniek"
]

for name <- polish_names do
  clean = UTF8.ensure_valid_utf8(name)
  normalized = Normalizer.normalize_text(clean)
  final = UTF8.ensure_valid_utf8(normalized)

  valid = String.valid?(final)
  status = if valid, do: "✅", else: "❌"
  IO.puts("  #{status} #{name} → #{final}")
end

IO.puts("\n=== Test Complete ===")