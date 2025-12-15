defmodule EventasaurusDiscovery.Movies.Provider do
  @moduledoc """
  Behaviour for movie data providers.

  This defines the contract that all movie providers must implement,
  enabling a pluggable architecture for the MovieLookupService.

  ## Implementing a Provider

      defmodule MyProvider do
        @behaviour EventasaurusDiscovery.Movies.Provider

        @impl true
        def search(query, opts) do
          # Search for movies matching the query
          {:ok, [%{id: 123, title: "Movie", ...}]}
        end

        @impl true
        def get_details(id) do
          # Get detailed information for a specific movie
          {:ok, %{id: 123, title: "Movie", runtime: 120, ...}}
        end

        @impl true
        def supports_language?(lang) do
          lang in ["en", "pl"]
        end

        @impl true
        def name, do: :my_provider

        @impl true
        def priority, do: 100
      end

  ## Provider Priority

  Providers with lower priority numbers are tried first. The default priorities are:
  - TmdbProvider: 10 (primary)
  - OmdbProvider: 20 (secondary/fallback)

  ## Confidence Scoring

  Each provider should return results with a `confidence` field (0.0-1.0) indicating
  how confident the provider is in the match. The MovieLookupService uses this
  to aggregate and rank results across providers.
  """

  @typedoc """
  A movie search query with optional filters.
  """
  @type query :: %{
          optional(:title) => String.t(),
          optional(:original_title) => String.t(),
          optional(:polish_title) => String.t(),
          optional(:year) => integer(),
          optional(:runtime) => integer(),
          optional(:director) => String.t(),
          optional(:country) => String.t(),
          optional(:imdb_id) => String.t(),
          optional(:tmdb_id) => integer()
        }

  @typedoc """
  A movie search result from a provider.
  """
  @type result :: %{
          required(:id) => term(),
          required(:title) => String.t(),
          optional(:original_title) => String.t(),
          optional(:year) => integer(),
          optional(:release_date) => String.t(),
          optional(:runtime) => integer(),
          optional(:overview) => String.t(),
          optional(:poster_path) => String.t(),
          optional(:confidence) => float(),
          optional(:provider) => atom(),
          optional(:imdb_id) => String.t(),
          optional(:tmdb_id) => integer()
        }

  @typedoc """
  Search options for providers.
  """
  @type search_opts :: [
          language: String.t(),
          year: integer(),
          page: integer(),
          include_adult: boolean()
        ]

  @doc """
  Search for movies matching the given query.

  ## Parameters

  - `query` - A map with search criteria (title, year, etc.)
  - `opts` - Optional search parameters (language, page, etc.)

  ## Returns

  - `{:ok, results}` - List of matching movies with confidence scores
  - `{:error, reason}` - Search failed
  """
  @callback search(query :: query(), opts :: search_opts()) ::
              {:ok, list(result())} | {:error, term()}

  @doc """
  Get detailed information for a specific movie.

  ## Parameters

  - `id` - The provider-specific movie ID

  ## Returns

  - `{:ok, details}` - Detailed movie information
  - `{:error, reason}` - Lookup failed
  """
  @callback get_details(id :: term()) :: {:ok, map()} | {:error, term()}

  @doc """
  Check if the provider supports searching in the given language.

  ## Parameters

  - `lang` - ISO 639-1 language code (e.g., "en", "pl")

  ## Returns

  - `true` if the provider supports the language
  - `false` otherwise
  """
  @callback supports_language?(lang :: String.t()) :: boolean()

  @doc """
  Get the provider's unique identifier name.

  ## Returns

  An atom identifying the provider (e.g., `:tmdb`, `:omdb`).
  """
  @callback name() :: atom()

  @doc """
  Get the provider's priority for the lookup chain.

  Lower numbers = higher priority (tried first).

  ## Returns

  An integer priority value.
  """
  @callback priority() :: integer()

  @doc """
  Calculate confidence score for a result against the original query.

  This is optional - providers can calculate confidence during search
  or use this callback for post-hoc scoring.

  ## Parameters

  - `result` - A search result from this provider
  - `query` - The original search query

  ## Returns

  A float between 0.0 and 1.0 indicating match confidence.
  """
  @callback confidence_score(result :: result(), query :: query()) :: float()

  @optional_callbacks [confidence_score: 2]
end
