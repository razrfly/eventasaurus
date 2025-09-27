# Test UTF-8 handling in our application
alias EventasaurusApp.Repo
alias EventasaurusApp.Venues.Venue
import Ecto.Query

# The problematic venue name from production
venue_name = "Teatr Ludowy – Scena Pod Ratuszem"
city_id = 1

# Show the bytes
IO.puts "Original string bytes:"
IO.inspect(:erlang.binary_to_list(venue_name))

# The en-dash character
IO.puts "\nEn-dash info:"
IO.puts "UTF-8 bytes for '–': #{inspect(:erlang.binary_to_list("–"))}"

# Try the exact query that's failing
IO.puts "\nTrying exact match query:"
query = from(v in Venue,
  where: v.name == ^venue_name and v.city_id == ^city_id,
  limit: 1
)
result = Repo.one(query)
IO.puts "Result: #{inspect(result && result.name)}"

# Now let's test what happens with a broken UTF-8 string
IO.puts "\n\nTesting with intentionally broken UTF-8:"
# This simulates what might be happening - the en-dash bytes getting corrupted
broken = "Teatr Ludowy " <> <<0xe2, 0x20, 0x53>> <> "cena Pod Ratuszem"
IO.puts "Broken string: #{inspect(broken)}"
IO.puts "Is valid UTF-8? #{String.valid?(broken)}"

# Try to query with broken string
broken_query = from(v in Venue,
  where: v.name == ^broken,
  limit: 1
)
IO.puts "Attempting query with broken UTF-8..."
try do
  Repo.one(broken_query)
  IO.puts "Query succeeded!"
rescue
  error ->
    IO.puts "Error rescued: #{inspect(error)}"
    IO.puts "Message: #{Exception.message(error)}"
end

# Test with similarity query (the other failing case)
IO.puts "\n\nTesting similarity query with broken string:"
sim_query = from(v in Venue,
  where: fragment("similarity(?, ?) > ?", v.name, ^broken, 0.7),
  limit: 1
)
try do
  Repo.one(sim_query)
  IO.puts "Similarity query succeeded!"
rescue
  error ->
    IO.puts "Similarity error: #{Exception.message(error)}"
end
