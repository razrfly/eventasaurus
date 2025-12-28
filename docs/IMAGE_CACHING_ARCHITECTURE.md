# Image Caching Architecture

This document describes the image caching system used in Eventasaurus for storing and serving optimized images via Cloudflare R2 and CDN.

## Overview

The image caching system consists of two layers:

1. **R2 Storage Layer** (`ImageCacheService`) - Downloads original images and stores them in Cloudflare R2
2. **CDN Transformation Layer** - Cloudflare applies on-the-fly transformations (resize, format conversion, quality optimization)

Images are cached lazily - they're queued for caching when entities are created or updated, and the cached URL is used once available.

## Entity Types

The system supports the following entity types (defined in `CachedImage` schema):

| Entity Type | Position 0 | Position 1 | Bridge Module |
|-------------|------------|------------|---------------|
| `movie` | Poster | Backdrop | `MovieImages` |
| `venue` | Primary image | - | `VenueImages` |
| `public_event_source` | Event image | - | `EventImageCaching` |
| `performer` | (virtual) | - | `PerformerImages` |
| `event` | Event image | - | `EventImageCaching` |
| `group` | Group image | - | (direct service calls) |

### Position Conventions

- **Position 0**: Primary/default image (poster, main photo, etc.)
- **Position 1**: Secondary image (backdrop for movies)
- Higher positions reserved for future use (galleries, etc.)

## Core Service

### `ImageCacheService`

The core service (`lib/eventasaurus_app/images/image_cache_service.ex`) provides:

```elixir
# Queue an image for caching (async via Oban)
ImageCacheService.cache_image(url, entity_type, entity_id, position \\ 0)

# Get cached URL (returns nil if not cached)
ImageCacheService.get_url(entity_type, entity_id, position \\ 0)

# Get cached URL (returns nil if not cached, no error on missing)
ImageCacheService.get_url!(entity_type, entity_id, position \\ 0)

# Check if image exists in cache
ImageCacheService.exists?(entity_type, entity_id, position \\ 0)

# Get caching statistics
ImageCacheService.stats()
```

### Automatic Caching

Images are automatically queued for caching when:

1. **Movies**: `MovieStore.create_movie/1` queues poster and backdrop URLs
2. **Events**: `EventImageCaching.process/2` queues event images during scraping
3. **Venues**: Queued when venue images are set/updated

## Bridge Module Patterns

Bridge modules provide entity-specific APIs that abstract the underlying cache service. There are three patterns:

### Pattern 1: Direct Lookup

Used when images are directly associated with the entity.

**Example: `MovieImages`**

```elixir
defmodule EventasaurusApp.Images.MovieImages do
  alias EventasaurusApp.Images.ImageCacheService

  @poster_position 0
  @backdrop_position 1

  # Single lookup with fallback
  def get_poster_url(movie_id, fallback \\ nil) when is_integer(movie_id) do
    ImageCacheService.get_url!("movie", movie_id, @poster_position) || fallback
  end

  def get_backdrop_url(movie_id, fallback \\ nil) when is_integer(movie_id) do
    ImageCacheService.get_url!("movie", movie_id, @backdrop_position) || fallback
  end

  # Batch lookup for N+1 prevention
  def get_poster_urls(movie_ids) when is_list(movie_ids) do
    ImageCacheService.get_urls("movie", movie_ids, @poster_position)
  end

  # Batch lookup with fallbacks
  def get_poster_urls_with_fallbacks(movies_with_fallbacks) when is_map(movies_with_fallbacks) do
    # movies_with_fallbacks: %{movie_id => fallback_url}
    movie_ids = Map.keys(movies_with_fallbacks)
    cached = get_poster_urls(movie_ids)

    Map.new(movie_ids, fn id ->
      {id, Map.get(cached, id) || Map.get(movies_with_fallbacks, id)}
    end)
  end
end
```

**When to use**: Entity has its own images stored in `cached_images` table.

### Pattern 2: Derived/Virtual

Used when images are derived from related entities (no separate caching).

**Example: `PerformerImages`**

```elixir
defmodule EventasaurusApp.Images.PerformerImages do
  # Performers don't have their own cached images
  # Images are derived from: performer → events → public_event_sources → cached_images

  def get_url(performer_id) when is_integer(performer_id) do
    case get_primary_image(performer_id) do
      nil -> nil
      cached -> cached.cdn_url
    end
  end

  defp get_primary_image(performer_id) do
    # Query joins through relationships to find associated cached images
    Repo.one(
      from ci in CachedImage,
      join: pes in PublicEventSource, on: pes.id == ci.entity_id,
      join: pe in PublicEvent, on: pe.public_event_source_id == pes.id,
      join: pep in PublicEventPerformer, on: pep.public_event_id == pe.id,
      where: pep.performer_id == ^performer_id,
      where: ci.entity_type == "public_event_source",
      where: ci.status == :completed,
      order_by: [desc: ci.inserted_at],
      limit: 1
    )
  end
end
```

**When to use**: Entity inherits images from related entities.

### Pattern 3: Processor Integration

Used in scraping/processing pipelines to cache images as data flows through.

**Example: `EventImageCaching`**

```elixir
defmodule EventasaurusDiscovery.Scraping.Processors.EventImageCaching do
  @behaviour EventasaurusDiscovery.Scraping.Processor

  def process(event, _context) do
    case event do
      %{image_url: url, public_event_source_id: source_id} when is_binary(url) ->
        ImageCacheService.cache_image(url, "public_event_source", source_id, 0)
        {:ok, event}

      _ ->
        {:ok, event}
    end
  end
end
```

**When to use**: Caching happens as part of a data processing pipeline.

## API Consistency Requirements

All bridge modules MUST follow these conventions:

### Function Naming

| Function | Purpose | Returns |
|----------|---------|---------|
| `get_*_url(id)` | Single lookup, no fallback | `String.t() \| nil` |
| `get_*_url(id, fallback)` | Single lookup with fallback | `String.t()` |
| `get_*_urls([ids])` | Batch lookup | `%{id => url \| nil}` |
| `get_*_urls_with_fallbacks(%{id => fallback})` | Batch with fallbacks | `%{id => url}` |

### Parameter Types

- `id` parameters MUST be integers (use guards: `when is_integer(id)`)
- Fallback parameters MUST accept `nil` or string URLs
- Batch functions MUST accept lists or maps

### Return Values

- Single lookups return `nil` when not cached (never raise)
- Batch lookups return maps with all requested IDs as keys
- Fallbacks are applied when cache misses occur

## CDN URL Helpers

For applying CDN transformations, use `EventasaurusWeb.Helpers.CDNHelper`:

```elixir
# Apply transformations to any image URL
CDNHelper.image_url(url, width: 300, height: 200, fit: "cover")

# Common presets
CDNHelper.thumbnail(url)        # 150x150 cover
CDNHelper.card_image(url)       # 400x300 cover
CDNHelper.hero_image(url)       # 1200x600 cover
```

## Usage in Templates

### LiveView/HEEx

```elixir
# In assigns preparation (controller or mount)
poster_url = MovieImages.get_poster_url(movie.id, movie.poster_url)

# In template
<img src={@poster_url} alt={@movie.title} />
```

### Batch Loading (N+1 Prevention)

```elixir
# In controller/LiveView
def mount(_params, _session, socket) do
  movies = MovieStore.list_movies()

  # Build fallback map
  fallbacks = Map.new(movies, fn m -> {m.id, m.poster_url} end)

  # Batch fetch cached URLs
  poster_urls = MovieImages.get_poster_urls_with_fallbacks(fallbacks)

  {:ok, assign(socket, movies: movies, poster_urls: poster_urls)}
end

# In template
<%= for movie <- @movies do %>
  <img src={@poster_urls[movie.id]} alt={movie.title} />
<% end %>
```

### JSON-LD Schemas

```elixir
defp add_image(schema, movie) do
  # Try cached URL first, fall back to original
  cached_url = MovieImages.get_poster_url(movie.id, movie.poster_url)

  case cached_url do
    nil -> schema
    url -> Map.put(schema, "image", Helpers.cdn_url(url))
  end
end
```

## Database Schema

The `cached_images` table stores cache metadata:

```elixir
schema "cached_images" do
  field :entity_type, :string        # "movie", "venue", etc.
  field :entity_id, :integer         # ID of the associated entity
  field :position, :integer          # 0 = primary, 1 = secondary
  field :original_url, :string       # Source URL
  field :cdn_url, :string            # R2/CDN URL
  field :content_type, :string       # MIME type
  field :file_size, :integer         # Bytes
  field :status, Ecto.Enum           # :pending, :processing, :completed, :failed
  field :error_message, :string      # Error details if failed

  timestamps()
end

# Unique constraint: (entity_type, entity_id, position)
```

## Status Lifecycle

```
:pending → :processing → :completed
                      ↘ :failed
```

- **pending**: Queued for caching, not yet processed
- **processing**: Currently being downloaded/uploaded
- **completed**: Successfully cached, `cdn_url` is valid
- **failed**: Caching failed, `error_message` contains details

## Monitoring & Debugging

### Check Cache Statistics

```elixir
iex> ImageCacheService.stats()
%{
  total: 15234,
  completed: 14892,
  pending: 156,
  processing: 12,
  failed: 174,
  by_entity_type: %{
    "movie" => 8456,
    "venue" => 2341,
    "public_event_source" => 4437
  }
}
```

### Check Specific Entity

```elixir
iex> ImageCacheService.get_url("movie", 123, 0)
"https://cdn.example.com/images/movie/123/0.jpg"

iex> ImageCacheService.exists?("movie", 123, 0)
true
```

### View Failed Images

```sql
SELECT entity_type, entity_id, original_url, error_message, inserted_at
FROM cached_images
WHERE status = 'failed'
ORDER BY inserted_at DESC
LIMIT 20;
```

## Adding a New Entity Type

1. Add entity type to `CachedImage` schema's `@entity_types` list
2. Create a bridge module following Pattern 1 (Direct Lookup)
3. Add automatic caching in the entity's create/update functions
4. Update display components to use the bridge module

Example for a new `artist` entity:

```elixir
# 1. Update CachedImage schema
@entity_types ~w(movie venue public_event_source performer event group artist)

# 2. Create bridge module
defmodule EventasaurusApp.Images.ArtistImages do
  alias EventasaurusApp.Images.ImageCacheService

  @primary_position 0

  def get_image_url(artist_id, fallback \\ nil) when is_integer(artist_id) do
    ImageCacheService.get_url!("artist", artist_id, @primary_position) || fallback
  end

  def get_image_urls(artist_ids) when is_list(artist_ids) do
    ImageCacheService.get_urls("artist", artist_ids, @primary_position)
  end
end

# 3. Add to create function
def create_artist(attrs) do
  case Repo.insert(changeset) do
    {:ok, artist} ->
      if artist.image_url do
        ImageCacheService.cache_image(artist.image_url, "artist", artist.id, 0)
      end
      {:ok, artist}
    error -> error
  end
end
```

## Related Files

- `lib/eventasaurus_app/images/image_cache_service.ex` - Core caching service
- `lib/eventasaurus_app/images/cached_image.ex` - Database schema
- `lib/eventasaurus_app/images/movie_images.ex` - Movie bridge module
- `lib/eventasaurus_app/images/performer_images.ex` - Performer bridge module (derived pattern)
- `lib/eventasaurus_web/helpers/venue_image_helper.ex` - Venue bridge module
- `lib/eventasaurus_app/workers/image_cache_job.ex` - Oban worker for async caching
- `lib/eventasaurus_discovery/scraping/processors/event_image_caching.ex` - Processor integration
