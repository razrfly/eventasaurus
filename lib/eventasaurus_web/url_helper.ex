defmodule EventasaurusWeb.UrlHelper do
  @moduledoc """
  Centralized URL generation for external-facing URLs (social cards, emails, etc.).

  This module ensures that all external URLs use the configured base URL instead of
  Endpoint.url(), which returns localhost in development environments.

  ## Configuration

  The base URL is configured per environment in config files:

  - Development: config :eventasaurus, :base_url, "http://localhost:4000"
  - Test: config :eventasaurus, :base_url, "http://localhost:4002"
  - Production: config :eventasaurus, :base_url, "https://wombie.com"

  For development with ngrok or other tunneling tools, override with environment variable:

      export BASE_URL="https://your-subdomain.ngrok.io"

  ## Usage

      # Get the base URL for external services (social media, email, etc.)
      base_url = UrlHelper.get_base_url()

      # Build a complete external URL
      full_url = UrlHelper.build_url("/events/my-event")
      # => "https://wombie.com/events/my-event"
  """

  @doc """
  Returns the configured base URL for external-facing links.

  Priority order:
  1. BASE_URL environment variable (for development overrides like ngrok)
  2. Application config :base_url
  3. Fallback to EventasaurusWeb.Endpoint.url() (localhost in dev)

  ## Examples

      iex> UrlHelper.get_base_url()
      "https://wombie.com"

      # With BASE_URL env var set
      iex> System.put_env("BASE_URL", "https://test.ngrok.io")
      iex> UrlHelper.get_base_url()
      "https://test.ngrok.io"
  """
  @spec get_base_url() :: String.t()
  def get_base_url do
    # Use the same logic as Layouts.get_base_url for consistency
    # This correctly handles ngrok and other proxy headers
    endpoint = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint, [])
    url_config = Keyword.get(endpoint, :url, [])
    scheme = Keyword.get(url_config, :scheme, "https")
    host = Keyword.get(url_config, :host, "wombie.com")
    port = Keyword.get(url_config, :port)

    # Only include port if not standard (80 for http, 443 for https)
    if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) || is_nil(port) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  @doc """
  Builds a complete external URL by combining base URL with a path.

  Accepts an optional URI struct from the request context. If provided,
  uses the request's actual host (supporting ngrok, proxies, etc.).

  ## Examples

      iex> UrlHelper.build_url("/events/tech-meetup")
      "https://wombie.com/events/tech-meetup"

      # With request URI (ngrok example)
      iex> request_uri = URI.parse("https://example.ngrok.io/some-path")
      iex> UrlHelper.build_url("/events/tech-meetup", request_uri)
      "https://example.ngrok.io/events/tech-meetup"
  """
  @spec build_url(String.t(), URI.t() | nil) :: String.t()
  def build_url(path, request_uri \\ nil)

  def build_url(path, %URI{scheme: scheme, host: host, port: port}) when is_binary(path) do
    # Build base URL from request URI (respects actual request host like ngrok)
    base_url = build_base_url_from_uri(scheme, host, port)

    # Remove trailing slash from base_url and ensure path starts with /
    base_url = String.trim_trailing(base_url, "/")
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path

    base_url <> path
  end

  def build_url(path, nil) when is_binary(path) do
    # Fallback to config-based base URL
    base_url = get_base_url()

    # Remove trailing slash from base_url and ensure path starts with /
    base_url = String.trim_trailing(base_url, "/")
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path

    base_url <> path
  end

  # Private helper to build base URL from URI components
  # IMPORTANT: Forces HTTPS for external domains (production, ngrok, etc.)
  # Only allows HTTP for localhost development
  defp build_base_url_from_uri(scheme, host, port) do
    # Force HTTPS for external domains, allow HTTP for localhost only
    # This handles Cloudflare SSL termination where internal requests use HTTP
    scheme =
      cond do
        host in ["localhost", "127.0.0.1"] -> scheme || "https"
        true -> "https"
      end

    # Only include port if not standard (80 for http, 443 for https)
    if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) || is_nil(port) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
