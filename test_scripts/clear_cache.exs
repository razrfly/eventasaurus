# Clear the Cachex cache for krakow to force a cache miss
cache_name = :city_page_cache

IO.puts("Clearing cache for krakow...")

# Get all keys
{:ok, keys} = Cachex.keys(cache_name)
krakow_keys = Enum.filter(keys, fn key -> String.contains?(to_string(key), "krakow") end)

IO.puts("Found #{length(krakow_keys)} krakow cache keys")

Enum.each(krakow_keys, fn key ->
  Cachex.del(cache_name, key)
  IO.puts("  Deleted: #{key}")
end)

IO.puts("Cache cleared!")
