# Rich Data Provider Architecture

The Rich Data Provider Architecture is an extensible system for integrating external APIs to provide comprehensive metadata for events. The system supports multiple content providers (TMDB, Spotify, etc.) through a unified interface.

## Architecture Overview

```
┌─────────────────────────────────────┐
│        Rich Data Manager            │
│  (Orchestrates all providers)       │
└─────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
┌───────▼─────┐ ┌───▼─────┐ ┌───▼─────┐
│TMDB Provider│ │Spotify  │ │Future   │
│  (Movies)   │ │Provider │ │Provider │
│             │ │(Music)  │ │         │
└─────────────┘ └─────────┘ └─────────┘
```

## Core Components

### 1. RichDataProviderBehaviour
Defines the contract that all providers must implement.

### 2. RichDataManager
Central orchestrator that manages providers and provides unified search/data access.

### 3. Provider Implementations
- **TmdbRichDataProvider**: Movie and TV show data from The Movie Database
- **SpotifyRichDataProvider**: Music and artist data (example implementation)

## Using the System

### Basic Usage

```elixir
# Search across all providers
{:ok, results} = RichDataManager.search("The Matrix")

# Results structure:
%{
  tmdb: {:ok, [%{id: 603, type: :movie, title: "The Matrix", ...}]},
  spotify: {:ok, [%{id: "abc123", type: :music, title: "Matrix Soundtrack", ...}]}
}

# Get details from specific provider
{:ok, movie_details} = RichDataManager.get_cached_details(:tmdb, 603, :movie)

# Check provider health
{:ok, health_status} = RichDataManager.health_check()
```

### Search Options

```elixir
# Search specific providers only
{:ok, results} = RichDataManager.search("The Matrix", %{
  providers: [:tmdb],
  page: 1,
  timeout: 10_000
})

# Filter by content types
{:ok, results} = RichDataManager.search("Artist Name", %{
  types: [:music, :artist]
})
```

### Provider Management

```elixir
# List registered providers
providers = RichDataManager.list_providers()
# [{:tmdb, TmdbRichDataProvider, :healthy}, {:spotify, SpotifyRichDataProvider, :unhealthy}]

# Register a new provider
:ok = RichDataManager.register_provider(MyCustomProvider)

# Validate all providers
{:ok, validation_results} = RichDataManager.validate_providers()
```

## Adding a New Provider

### Step 1: Implement the Behaviour

```elixir
defmodule MyCustomProvider do
  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour
  
  @impl true
  def provider_id, do: :my_custom_provider
  
  @impl true
  def provider_name, do: "My Custom API"
  
  @impl true
  def supported_types, do: [:books, :articles]
  
  @impl true
  def search(query, options \\ %{}) do
    # Implementation here
    {:ok, search_results}
  end
  
  @impl true
  def get_details(id, type, options \\ %{}) do
    # Implementation here
    {:ok, detailed_result}
  end
  
  @impl true
  def get_cached_details(id, type, options \\ %{}) do
    # Usually falls back to get_details/3 unless you implement caching
    get_details(id, type, options)
  end
  
  @impl true
  def validate_config do
    case System.get_env("MY_API_KEY") do
      nil -> {:error, "MY_API_KEY not set"}
      _key -> :ok
    end
  end
  
  @impl true
  def config_schema do
    %{
      api_key: %{
        type: :string,
        required: true,
        description: "API key from provider"
      }
    }
  end
end
```

### Step 2: Register the Provider

Add to `RichDataManager` default providers or register at runtime:

```elixir
# At runtime
RichDataManager.register_provider(MyCustomProvider)

# Or add to @default_providers in RichDataManager
@default_providers [
  TmdbRichDataProvider,
  SpotifyRichDataProvider,
  MyCustomProvider  # Add here
]
```

### Step 3: Environment Configuration

Add required environment variables:

```bash
# .env
MY_API_KEY=your_api_key_here
```

## Data Format Standards

All providers must return data in the standardized format:

### Search Results
```elixir
%{
  id: provider_specific_id,
  type: :movie | :tv | :music | :artist | :book | :article,
  title: "Content Title",
  description: "Brief description",
  images: [
    %{url: "image_url", type: :poster | :backdrop | :cover, size: "dimensions"}
  ],
  metadata: %{
    # Provider-specific fields
  }
}
```

### Detailed Results
```elixir
%{
  id: provider_specific_id,
  type: content_type,
  title: "Content Title",
  description: "Full description",
  metadata: %{
    # Comprehensive provider-specific metadata
  },
  images: [list_of_images],
  external_urls: %{
    provider_name: "external_url",
    imdb: "imdb_url"  # If applicable
  },
  cast: [list_of_cast_members],  # If applicable
  crew: [list_of_crew_members],  # If applicable
  media: %{
    # Videos, tracks, previews, etc.
  },
  additional_data: %{
    # Provider-specific additional information
  }
}
```

## Error Handling

Providers should handle errors gracefully:

```elixir
def search(query, _options) do
  case make_api_request(query) do
    {:ok, data} -> {:ok, normalize_data(data)}
    {:error, :rate_limited} -> {:error, "Rate limit exceeded"}
    {:error, :not_found} -> {:ok, []}  # Empty results
    {:error, reason} -> {:error, "API error: #{reason}"}
  end
end
```

## Best Practices

### 1. Caching
Implement caching for better performance:

```elixir
defp get_from_cache(key) do
  case :ets.lookup(@cache_table, key) do
    [{^key, data, timestamp}] ->
      if cache_valid?(timestamp), do: {:ok, data}, else: {:error, :expired}
    [] ->
      {:error, :not_found}
  end
end
```

### 2. Rate Limiting
Respect API rate limits:

```elixir
defp check_rate_limit do
  # Implementation to check and enforce rate limits
  case current_request_count() do
    count when count < @max_requests -> :ok
    _ -> {:error, :rate_limited}
  end
end
```

### 3. Configuration Validation
Provide helpful configuration errors:

```elixir
def validate_config do
  with {:ok, api_key} <- get_api_key(),
       {:ok, _} <- test_api_connection(api_key) do
    :ok
  else
    {:error, :no_api_key} -> {:error, "API_KEY environment variable not set"}
    {:error, :invalid_key} -> {:error, "API key is invalid or expired"}
    {:error, reason} -> {:error, "Configuration error: #{reason}"}
  end
end
```

### 4. Logging
Use structured logging for monitoring:

```elixir
require Logger

def search(query, options) do
  Logger.info("Provider search", %{
    provider: provider_id(),
    query: query,
    options: options
  })
  
  # Implementation...
end
```

## Integration with Events

### Storing Rich Data

Use the `rich_external_data` field in events:

```elixir
# Store TMDB movie data
event_params = %{
  title: "Movie Night: The Matrix",
  rich_external_data: %{
    "tmdb" => %{
      "id" => 603,
      "type" => "movie",
      "title" => "The Matrix",
      # ... other movie data
    }
  }
}

# Store multiple provider data
event_params = %{
  title: "The Matrix Experience",
  rich_external_data: %{
    "tmdb" => movie_data,
    "spotify" => soundtrack_data
  }
}
```

### Using Helper Functions

```elixir
# Get TMDB data from event
tmdb_data = Event.get_tmdb_data(event)

# Check if event has external data
has_data = Event.has_external_data?(event)

# Get all providers used
providers = Event.list_providers(event)
```

## Testing

### Mock Provider for Tests

```elixir
defmodule MockProvider do
  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour
  
  def provider_id, do: :mock
  def provider_name, do: "Mock Provider"
  def supported_types, do: [:test]
  
  def search(_query, _options), do: {:ok, [mock_result()]}
  def get_details(_id, _type, _options), do: {:ok, mock_details()}
  def get_cached_details(id, type, options), do: get_details(id, type, options)
  def validate_config, do: :ok
  def config_schema, do: %{}
  
  defp mock_result do
    %{id: "test123", type: :test, title: "Test Item", description: "Test", images: [], metadata: %{}}
  end
  
  defp mock_details do
    # ... mock detailed response
  end
end
```

## Future Enhancements

- **Background Data Sync**: Automatic updating of cached data
- **Provider Fallbacks**: Fallback to secondary providers if primary fails
- **Data Enrichment**: Combine data from multiple providers
- **Analytics**: Track provider usage and performance
- **Admin Interface**: UI for managing providers and configurations 