defmodule Eventasaurus.SocialCards.UrlBuilder do
  @moduledoc """
  Centralized URL building for social cards across all entity types.

  This module provides a unified interface for generating social card URLs,
  ensuring consistent patterns across events, polls, and future entity types.

  ## Design Principles

  1. **Consistency**: All social card URLs follow predictable patterns
  2. **Extensibility**: Easy to add new entity types
  3. **Cache Busting**: URL changes when content changes via hash
  4. **SEO Friendly**: URLs include human-readable slugs

  ## URL Patterns

  - Events: `/:event_slug/social-card-:hash.png`
  - Polls: `/:event_slug/polls/:poll_number/social-card-:hash.png`
  - Future: `/:entity_slug/:type/:id/social-card-:hash.png`

  ## Usage

      # For events
      UrlBuilder.build_path(:event, event)
      # => "/tech-meetup/social-card-abc123.png"

      # For polls
      UrlBuilder.build_path(:poll, poll, event: event)
      # => "/tech-meetup/polls/1/social-card-abc123.png"

      # Extract hash from any social card URL
      UrlBuilder.extract_hash("/tech-meetup/social-card-abc123.png")
      # => "abc123"
  """

  alias Eventasaurus.SocialCards.HashGenerator

  @doc """
  Builds a social card URL path for a given entity type.

  ## Parameters

    * `entity_type` - The type of entity (`:event`, `:poll`)
    * `entity` - The entity struct/map
    * `opts` - Additional options (e.g., `event:` for polls)

  ## Examples

      iex> event = %{slug: "tech-meetup", title: "Tech Meetup", updated_at: ~N[2023-01-01 12:00:00]}
      iex> UrlBuilder.build_path(:event, event)
      "/tech-meetup/social-card-abc123.png"

      iex> poll = %{number: 1, title: "Pizza Poll"}
      iex> event = %{slug: "tech-meetup"}
      iex> UrlBuilder.build_path(:poll, poll, event: event)
      "/tech-meetup/polls/1/social-card-abc123.png"
  """
  @spec build_path(atom(), map(), keyword()) :: String.t()
  def build_path(entity_type, entity, opts \\ [])

  def build_path(:event, event, _opts) do
    HashGenerator.generate_url_path(event)
  end

  def build_path(:poll, poll, _opts) do
    HashGenerator.generate_url_path(poll, :poll)
  end

  @doc """
  Builds a complete social card URL with external domain.

  ## Parameters

    * `entity_type` - The type of entity (`:event`, `:poll`)
    * `entity` - The entity struct/map
    * `opts` - Additional options (e.g., `event:` for polls)

  ## Examples

      iex> event = %{slug: "tech-meetup", title: "Tech Meetup", updated_at: ~N[2023-01-01 12:00:00]}
      iex> UrlBuilder.build_url(:event, event)
      "https://wombie.com/tech-meetup/social-card-abc123.png"
  """
  @spec build_url(atom(), map(), keyword()) :: String.t()
  def build_url(entity_type, entity, opts \\ []) do
    path = build_path(entity_type, entity, opts)
    EventasaurusWeb.UrlHelper.build_url(path)
  end

  @doc """
  Extracts the hash from any social card URL path.

  Supports multiple URL patterns:
  - Event: `/:slug/social-card-:hash.png`
  - Poll: `/:slug/polls/:number/social-card-:hash.png`

  ## Examples

      iex> UrlBuilder.extract_hash("/tech-meetup/social-card-abc123.png")
      "abc123"

      iex> UrlBuilder.extract_hash("/tech-meetup/polls/1/social-card-abc123.png")
      "abc123"

      iex> UrlBuilder.extract_hash("/invalid/path")
      nil
  """
  @spec extract_hash(String.t()) :: String.t() | nil
  def extract_hash(path) when is_binary(path) do
    HashGenerator.extract_hash_from_path(path)
  end

  @doc """
  Validates that a hash matches the current entity data.

  ## Examples

      iex> event = %{slug: "tech-meetup", title: "Tech Meetup", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = HashGenerator.generate_hash(event)
      iex> UrlBuilder.validate_hash(:event, event, hash)
      true

      iex> UrlBuilder.validate_hash(:event, event, "invalid")
      false
  """
  @spec validate_hash(atom(), map(), String.t(), keyword()) :: boolean()
  def validate_hash(entity_type, entity, hash, opts \\ [])

  def validate_hash(:event, event, hash, _opts) do
    HashGenerator.validate_hash(event, hash)
  end

  def validate_hash(:poll, poll, hash, _opts) do
    HashGenerator.validate_hash(poll, hash, :poll)
  end

  @doc """
  Detects the entity type from a social card URL path.

  ## Examples

      iex> UrlBuilder.detect_entity_type("/tech-meetup/social-card-abc123.png")
      :event

      iex> UrlBuilder.detect_entity_type("/tech-meetup/polls/1/social-card-abc123.png")
      :poll

      iex> UrlBuilder.detect_entity_type("/invalid/path")
      nil
  """
  @spec detect_entity_type(String.t()) :: atom() | nil
  def detect_entity_type(path) when is_binary(path) do
    cond do
      # Poll pattern: contains /polls/ segment
      String.contains?(path, "/polls/") && HashGenerator.extract_hash_from_path(path) ->
        :poll

      # City pattern: contains /social-cards/city/
      String.contains?(path, "/social-cards/city/") && HashGenerator.extract_hash_from_path(path) ->
        :city

      # Event pattern: simpler structure
      HashGenerator.extract_hash_from_path(path) ->
        :event

      true ->
        nil
    end
  end

  @doc """
  Extracts slug components from a social card URL path.

  Returns a map with relevant identifiers:
  - Events: `%{event_slug: "tech-meetup"}`
  - Polls: `%{event_slug: "tech-meetup", poll_number: 1}`

  ## Examples

      iex> UrlBuilder.parse_path("/tech-meetup/social-card-abc123.png")
      %{entity_type: :event, event_slug: "tech-meetup", hash: "abc123"}

      iex> UrlBuilder.parse_path("/tech-meetup/polls/1/social-card-abc123.png")
      %{entity_type: :poll, event_slug: "tech-meetup", poll_number: 1, hash: "abc123"}
  """
  @spec parse_path(String.t()) :: map() | nil
  def parse_path(path) when is_binary(path) do
    entity_type = detect_entity_type(path)
    hash = extract_hash(path)

    case entity_type do
      :poll ->
        # Extract: /:event_slug/polls/:poll_number/social-card-:hash.png
        case Regex.run(~r/\/([^\/]+)\/polls\/(\d+)\/social-card-[a-f0-9]{8}(?:\.png)?$/, path) do
          [_full, event_slug, poll_number] ->
            %{
              entity_type: :poll,
              event_slug: event_slug,
              poll_number: String.to_integer(poll_number),
              hash: hash
            }

          _ ->
            nil
        end

      :event ->
        # Extract: /:event_slug/social-card-:hash.png
        case Regex.run(~r/\/([^\/]+)\/social-card-[a-f0-9]{8}(?:\.png)?$/, path) do
          [_full, event_slug] ->
            %{
              entity_type: :event,
              event_slug: event_slug,
              hash: hash
            }

          _ ->
            nil
        end

      nil ->
        nil
    end
  end
end
