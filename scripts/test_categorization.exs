#!/usr/bin/env elixir

error_message = "EventasaurusDiscovery.Sources.QuestionOne.Jobs.VenueDetailJob failed with {:error, \"Missing icon text for 'pin'\"}"

IO.puts("Testing error categorization...")
IO.puts("Error message: #{error_message}")
IO.puts("")

# Test if pattern matches
match1 = String.contains?(error_message, "Missing icon text for")
IO.puts("Does 'Missing icon text for' match? #{match1}")

match2 = String.contains?(error_message, "icon text")
IO.puts("Does 'icon text' match? #{match2}")

# Test actual categorization
result = EventasaurusDiscovery.ScraperProcessingLogs.categorize_error(error_message)
IO.puts("")
IO.puts("Categorization result: #{result}")

# Test with Oban.PerformError exception
IO.puts("\nTesting with exception struct...")
try do
  raise Oban.PerformError, reason: {:error, "Missing icon text for 'pin'"}
catch
  :error, exception ->
    message = Exception.message(exception)
    IO.puts("Exception message: #{message}")
    result2 = EventasaurusDiscovery.ScraperProcessingLogs.categorize_error(exception)
    IO.puts("Exception categorization: #{result2}")
end
