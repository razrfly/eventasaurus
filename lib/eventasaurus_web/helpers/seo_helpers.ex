defmodule EventasaurusWeb.Helpers.SEOHelpers do
  @moduledoc """
  Helpers for assigning SEO meta tags and structured data in LiveViews.

  This module provides a standardized way to set meta tags for:
  - Open Graph (Facebook, LinkedIn, other social platforms)
  - Twitter Cards
  - Standard SEO meta tags (`<meta name="description">`)
  - JSON-LD structured data
  - Canonical URLs for SEO

  ## Usage

  In your LiveView's `mount/3` or `handle_params/3`:

      socket
      |> SEOHelpers.assign_meta_tags(
        title: "Events in Warsaw",
        description: "Discover events happening in Warsaw, Poland",
        image: social_card_url,
        type: "website",
        canonical_path: "/c/warsaw"
      )

  ## Standardized Assigns

  This module sets the following socket assigns that are consumed by the root layout:

  - `:page_title` - Page title for `<title>` tag
  - `:meta_title` - Open Graph / Twitter Card title (defaults to `:page_title`)
  - `:meta_description` - Meta description for SEO and social sharing
  - `:meta_image` - Social card image URL (absolute URL)
  - `:meta_type` - Open Graph type (default: "website", can be "event", "article", etc.)
  - `:canonical_url` - Canonical URL for SEO (absolute URL)
  - `:json_ld` - JSON-LD structured data (optional)

  ## Related ADR

  See `docs/adr/001-meta-tag-pattern-standardization.md` for the architectural decision
  rationale behind this pattern.
  """

  import Phoenix.Component, only: [assign: 3]
  alias EventasaurusWeb.UrlHelper
  alias Eventasaurus.SocialCards.UrlBuilder

  @type meta_tag_opts :: [
          title: String.t(),
          description: String.t(),
          image: String.t() | nil,
          type: String.t(),
          canonical_path: String.t() | nil,
          canonical_url: String.t() | nil,
          json_ld: String.t() | nil
        ]

  @doc """
  Assigns standard SEO meta tags to a LiveView socket.

  This is the primary function for setting SEO metadata in LiveViews. It assigns
  all standard meta tag values that are consumed by the root layout template.

  ## Options

    * `:title` - Page title (required). Used for both `<title>` and Open Graph title.
    * `:description` - Meta description (required). Used for SEO and social sharing.
    * `:image` - Social card image URL (optional). Can be relative or absolute.
    * `:type` - Open Graph type (optional, default: "website"). Common values:
      - "website" - Generic website
      - "event" - Event page
      - "article" - Blog post or article
      - "profile" - User profile
    * `:canonical_path` - Canonical URL path (optional). Will be converted to absolute URL.
    * `:canonical_url` - Canonical URL absolute (optional). Takes precedence over `:canonical_path`.
    * `:json_ld` - JSON-LD structured data (optional). Should be JSON-encoded string.
    * `:request_uri` - Request URI struct (optional). Used for building URLs with correct host (ngrok support).

  ## Examples

      # Minimal usage with required fields only
      socket
      |> SEOHelpers.assign_meta_tags(
        title: "Events in Warsaw",
        description: "Discover upcoming events in Warsaw, Poland"
      )

      # Full usage with all options and request context
      request_uri = get_connect_info(socket, :uri)
      socket
      |> SEOHelpers.assign_meta_tags(
        title: "Summer Music Festival 2025",
        description: "Join us for the biggest music festival of the summer",
        image: "/images/festival-card.png",
        type: "event",
        canonical_path: "/events/summer-music-festival-2025",
        json_ld: PublicEventSchema.generate(event),
        request_uri: request_uri
      )

  ## Returns

  Updated socket with SEO meta tag assigns.
  """
  @spec assign_meta_tags(Phoenix.LiveView.Socket.t(), meta_tag_opts()) ::
          Phoenix.LiveView.Socket.t()
  def assign_meta_tags(socket, opts) do
    # Required fields
    title = Keyword.fetch!(opts, :title)
    description = Keyword.fetch!(opts, :description)

    # Optional fields with defaults
    image = Keyword.get(opts, :image)
    meta_type = Keyword.get(opts, :type, "website")
    json_ld = Keyword.get(opts, :json_ld)
    request_uri = Keyword.get(opts, :request_uri)

    # Handle canonical URL - prefer explicit canonical_url, fallback to building from canonical_path
    canonical_url =
      cond do
        url = Keyword.get(opts, :canonical_url) ->
          url

        path = Keyword.get(opts, :canonical_path) ->
          build_canonical_url(path, request_uri)

        true ->
          nil
      end

    # Normalize image URL to absolute if provided
    absolute_image = normalize_image_url(image, request_uri)

    # Assign all meta tag values to socket
    socket
    |> assign(:page_title, title)
    |> assign(:meta_title, title)
    |> assign(:meta_description, description)
    |> assign(:meta_image, absolute_image)
    |> assign(:meta_type, meta_type)
    |> assign(:canonical_url, canonical_url)
    |> assign(:json_ld, json_ld)
  end

  @doc """
  Builds a social card URL for an entity with cache-busting hash.

  Generates a complete social card URL using the unified social card system.
  The URL includes a hash for cache busting - when entity data changes,
  the hash changes, ensuring social media platforms re-fetch the card.

  ## Entity Types

    * `:event` - Event social cards (default)
    * `:poll` - Poll social cards (requires `event` in opts)
    * `:city` - City social cards (requires `stats` in opts)

  ## Arguments

    * `entity` - The entity struct (Event, Poll, or City)
    * `type` - Entity type atom (`:event`, `:poll`, or `:city`)
    * `opts` - Additional options (`:event` for polls, `:stats` for cities)

  ## Examples

      # Event social card
      event_card_url = SEOHelpers.build_social_card_url(event, :event)
      # => "https://wombie.com/summer-festival/social-card-a1b2c3d4.png"

      # Poll social card (requires parent event)
      poll_card_url = SEOHelpers.build_social_card_url(poll, :poll, event: event)
      # => "https://wombie.com/summer-festival/polls/1/social-card-e5f6g7h8.png"

      # City social card (requires stats)
      stats = %{events_count: 127, venues_count: 45, categories_count: 12}
      city_card_url = SEOHelpers.build_social_card_url(city, :city, stats: stats)
      # => "https://wombie.com/social-cards/city/warsaw/b2c3d4e5.png"

  ## Returns

  Absolute URL to social card PNG (includes base URL, path, hash, and .png extension).
  """
  @spec build_social_card_url(map(), atom(), keyword()) :: String.t()
  def build_social_card_url(entity, type \\ :event, opts \\ [])

  def build_social_card_url(entity, :event, _opts) do
    UrlBuilder.build_url(:event, entity)
  end

  def build_social_card_url(poll, :poll, opts) do
    # For polls, ensure event association is present
    poll_with_event =
      case Map.get(poll, :event) do
        nil ->
          event = Keyword.fetch!(opts, :event)
          Map.put(poll, :event, event)

        _event ->
          poll
      end

    UrlBuilder.build_url(:poll, poll_with_event)
  end

  def build_social_card_url(city, :city, opts) do
    # For cities, ensure stats are present
    city_with_stats =
      case Map.get(city, :stats) do
        nil ->
          stats = Keyword.get(opts, :stats, %{})
          Map.put(city, :stats, stats)

        _stats ->
          city
      end

    UrlBuilder.build_url(:city, city_with_stats)
  end

  @doc """
  Builds a canonical URL from a path.

  Converts a relative path to an absolute canonical URL by prepending the base URL.
  The base URL is determined from the application's endpoint configuration or
  from the request URI if provided (supports ngrok, proxies, etc.).

  ## Arguments

    * `path` - Relative path (must start with `/`)
    * `request_uri` - Optional URI struct from the request context

  ## Examples

      SEOHelpers.build_canonical_url("/events/summer-festival")
      # => "https://wombie.com/events/summer-festival"

      # With request context (ngrok)
      request_uri = URI.parse("https://example.ngrok.io/some-path")
      SEOHelpers.build_canonical_url("/c/warsaw", request_uri)
      # => "https://example.ngrok.io/c/warsaw"

  ## Returns

  Absolute canonical URL as a string.
  """
  @spec build_canonical_url(String.t(), URI.t() | nil) :: String.t()
  def build_canonical_url(path, request_uri \\ nil) when is_binary(path) do
    UrlHelper.build_url(path, request_uri)
  end

  # Private helper to normalize image URLs to absolute URLs
  defp normalize_image_url(nil, _request_uri), do: nil

  defp normalize_image_url(url, request_uri) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Already absolute
        url

      %URI{path: "/" <> _rest} ->
        # Relative path starting with /
        UrlHelper.build_url(url, request_uri)

      _ ->
        # Relative path without leading /
        UrlHelper.build_url("/#{url}", request_uri)
    end
  end
end
