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
    System.get_env("BASE_URL") ||
      Application.get_env(:eventasaurus, :base_url) ||
      EventasaurusWeb.Endpoint.url()
  end

  @doc """
  Builds a complete external URL by combining base URL with a path.

  ## Examples

      iex> UrlHelper.build_url("/events/tech-meetup")
      "https://wombie.com/events/tech-meetup"

      iex> UrlHelper.build_url("/events/tech-meetup/social-card-abc123.png")
      "https://wombie.com/events/tech-meetup/social-card-abc123.png"
  """
  @spec build_url(String.t()) :: String.t()
  def build_url(path) when is_binary(path) do
    base_url = get_base_url()

    # Remove trailing slash from base_url and leading slash from path if both present
    base_url = String.trim_trailing(base_url, "/")
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path

    base_url <> path
  end
end
