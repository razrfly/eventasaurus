# MovieDataAdapter Usage Examples

This document shows how the `MovieDataAdapter` solves the movie data integration issues between polling and activity systems.

## Problem Solved

**Before**: Each system had its own movie data handling with different formats, field mappings, and image URL generation.

**After**: Unified adapter handles all movie data transformations with consistent output.

## Usage Examples

### 1. In Poll Seeding (poll_seed.exs)

**Before**:
```elixir
# Complex manual data transformation
case Events.create_poll_option(%{
  poll_id: poll.id,
  title: movie.title,
  description: "#{movie.description || movie.overview || "No description available"} (#{movie.year || (movie.release_date && String.split(movie.release_date, "-") |> hd()) || "Unknown"}, #{movie.genre || "General"})",
  suggested_by_id: organizer_id,
  image_url: MovieConfig.build_image_url(movie.poster_path, "w500"),
  metadata: %{
    "tmdb_id" => movie.tmdb_id,
    "year" => movie.year || (movie.release_date && String.split(movie.release_date, "-") |> hd()),
    "genre" => movie.genre || "General",
    "rating" => movie.rating || movie.vote_average,
    "poster_path" => movie.poster_path,
    "backdrop_path" => movie.backdrop_path,
    "is_movie" => true
  }
}) do
```

**After**:
```elixir
# Simple, consistent transformation
alias EventasaurusWeb.Services.MovieDataAdapter

case MovieDataAdapter.build_poll_option_attrs(movie, poll.id, organizer_id) 
     |> Events.create_poll_option() do
```

### 2. In Activity Seeding (activity_seed.exs)

**Before**:
```elixir
# Manual metadata construction with potential field mismatches
{:ok, _activity} = Events.create_event_activity(%{
  event_id: event.id,
  activity_type: "movie_watched",
  created_by_id: organizer.id,
  occurred_at: event.start_at || DateTime.utc_now(),
  source: "seed_data",
  metadata: %{
    "title" => movie.title,
    "overview" => movie[:overview] || movie[:description],
    "tmdb_id" => movie[:id] || movie[:tmdb_id],
    "year" => movie[:year] || extract_year(movie),
    "genre" => movie[:genre],
    "rating" => movie[:rating],
    "poster_path" => movie[:poster_path],
    "image_url" => build_movie_image_url(movie), # Custom function needed
    "api_source" => if(movie[:id], do: "tmdb", else: "curated"),
    "seeded_at" => DateTime.utc_now()
  }
})
```

**After**:
```elixir
# Consistent metadata with guaranteed field compatibility
{:ok, _activity} = Events.create_event_activity(%{
  event_id: event.id,
  activity_type: "movie_watched", 
  created_by_id: organizer.id,
  occurred_at: event.start_at || DateTime.utc_now(),
  source: "seed_data",
  metadata: MovieDataAdapter.build_activity_metadata(movie)
})
```

### 3. Data Source Handling

The adapter automatically handles different data sources:

**TMDB API Response**:
```elixir
tmdb_movie = %{
  id: 278,
  title: "The Shawshank Redemption", 
  overview: "Two imprisoned men bond...",
  poster_path: "/q6y0Go1365Reb30YRo0DxJHATZR.jpg",
  vote_average: 9.3,
  release_date: "1994-09-23",
  genre_ids: [18, 80]
}

# Adapter handles the transformation automatically
normalized = MovieDataAdapter.normalize_movie_data(tmdb_movie)
# => %{title: "The Shawshank Redemption", overview: "Two imprisoned men bond...", year: "1994", genre: "Drama", ...}
```

**Curated Data**:
```elixir
curated_movie = %{
  title: "The Shawshank Redemption",
  year: 1994,
  genre: "Drama", 
  description: "Two imprisoned men bond...",
  tmdb_id: 278,
  rating: 9.3
}

# Same adapter, different source detection
normalized = MovieDataAdapter.normalize_movie_data(curated_movie)
# => %{title: "The Shawshank Redemption", overview: "Two imprisoned men bond...", year: 1994, genre: "Drama", ...}
```

### 4. Cross-System Compatibility

**Convert Poll Movie to Activity**:
```elixir
# Take a movie from a poll and use it in an activity
poll_option = Events.get_poll_option!(movie_poll_option_id)
activity_metadata = MovieDataAdapter.poll_to_activity_format(poll_option)

Events.create_event_activity(%{
  event_id: event.id,
  activity_type: "movie_watched",
  created_by_id: user.id,
  metadata: activity_metadata
})
```

**Validate Compatibility**:
```elixir
# Ensure poll and activity movie data are compatible
poll_metadata = poll_option.metadata
activity_metadata = MovieDataAdapter.build_activity_metadata(movie_data)

case MovieDataAdapter.validate_compatibility(poll_metadata, activity_metadata) do
  :ok -> Logger.info("Movie data is compatible between systems")
  {:error, {:incompatible_fields, fields}} -> 
    Logger.warning("Incompatible fields detected: #{inspect(fields)}")
end
```

## Benefits Achieved

### 1. Eliminates Duplication
- **Before**: 50+ lines of movie data handling in each seed file
- **After**: 2-3 lines using adapter methods

### 2. Consistent Image URLs  
- **Before**: Different image URL generation patterns
- **After**: Centralized `ensure_image_url/1` handling

### 3. Data Format Compatibility
- **Before**: No guarantee that poll/activity movie data matches
- **After**: `validate_compatibility/2` ensures consistency

### 4. Source Flexibility
- **Before**: Hardcoded handling for TMDB vs curated data
- **After**: Automatic source detection and appropriate transformations

### 5. Future-Proof
- **Before**: New movie sources require changes in multiple places
- **After**: Add source handling once in adapter, works everywhere

## Migration Strategy

1. **Phase 1**: Create adapter service ✅ 
2. **Phase 2**: Update seed files to use adapter
3. **Phase 3**: Add validation and tests
4. **Phase 4**: Extend to other media types (TV, books, etc.)

## Testing

```elixir
# Example tests for the adapter
defmodule MovieDataAdapterTest do
  use ExUnit.Case
  alias EventasaurusWeb.Services.MovieDataAdapter

  test "normalizes TMDB movie data" do
    tmdb_data = %{
      id: 278,
      title: "The Shawshank Redemption",
      overview: "Two imprisoned men...",
      poster_path: "/poster.jpg"
    }
    
    result = MovieDataAdapter.normalize_movie_data(tmdb_data)
    
    assert result.title == "The Shawshank Redemption"
    assert result.source == "tmdb"
    assert String.contains?(result.image_url, "image.tmdb.org")
  end

  test "builds compatible poll and activity data" do
    movie_data = %{title: "Test Movie", overview: "Test description"}
    
    poll_attrs = MovieDataAdapter.build_poll_option_attrs(movie_data, 1, 1)
    activity_metadata = MovieDataAdapter.build_activity_metadata(movie_data)
    
    # Both should have same core movie information
    assert poll_attrs.title == get_in(activity_metadata, ["title"])
    assert :ok == MovieDataAdapter.validate_compatibility(
      poll_attrs.metadata, 
      activity_metadata
    )
  end
end
```

This adapter solves the root cause of the integration issues and provides a clear path forward for consistent movie data handling across the entire application.