defmodule EventasaurusWeb.PageController do
  use EventasaurusWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip using the default app layout.
    render(conn, :home, layout: false)
  end

  def index(conn, _params) do
    render(conn, :index)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def our_story(conn, _params) do
    render(conn, :our_story)
  end

  def whats_new(conn, _params) do
    render(conn, :whats_new)
  end

  def components(conn, _params) do
    render(conn, :components)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def your_data(conn, _params) do
    render(conn, :your_data)
  end

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def pitch(conn, _params) do
    render(conn, :pitch)
  end

  def pitch2(conn, _params) do
    render(conn, :pitch2)
  end

  def crypto_pitch(conn, _params) do
    render(conn, :crypto_pitch)
  end

  def invite_only(conn, _params) do
    render(conn, :invite_only)
  end

  def redirect_to_auth_login(conn, _params) do
    # Preserve query parameters when redirecting
    query_string = conn.query_string

    path =
      if query_string != "" do
        "/auth/login?" <> query_string
      else
        "/auth/login"
      end

    redirect(conn, to: path)
  end

  def redirect_to_auth_register(conn, _params) do
    # Preserve query parameters when redirecting
    query_string = conn.query_string

    path =
      if query_string != "" do
        "/auth/register?" <> query_string
      else
        "/auth/register"
      end

    redirect(conn, to: path)
  end

  def redirect_to_auth_register_with_event(conn, %{"event_id" => event_id}) do
    # Redirect to auth register with event_id parameter
    query_string = conn.query_string
    event_param = "event_id=#{URI.encode_www_form(event_id)}"

    path =
      if query_string != "" do
        "/auth/register?#{event_param}&#{query_string}"
      else
        "/auth/register?#{event_param}"
      end

    redirect(conn, to: path)
  end

  def redirect_to_invite_only(conn, _params) do
    # Direct signup attempts (without event_id) should go to invite-only page
    redirect(conn, to: "/invite-only")
  end


  def changelog(conn, _params) do
    entries = [
      %{
        id: "1",
        date: "December 8, 2024",
        iso_date: "2024-12-08",
        title: "December Updates",
        summary: "Performance improvements and bug fixes for event discovery",
        changes: [
          %{type: "added", description: "Improved city search with better autocomplete"},
          %{type: "changed", description: "50% faster event loading through speed optimizations"},
          %{type: "fixed", description: "Duplicate events from Bandsintown scraper"},
          %{type: "fixed", description: "Ireland location accuracy"},
          %{type: "security", description: "Updated authentication tokens with improved encryption"}
        ],
        image: nil
      },
      %{
        id: "2",
        date: "November 25, 2024",
        iso_date: "2024-11-25",
        title: "Infrastructure Improvements",
        summary: "Major backend refactoring for better reliability",
        changes: [
          %{type: "changed", description: "Refactored Oban job processing for better reliability"},
          %{type: "fixed", description: "Migration stability improvements"},
          %{type: "fixed", description: "GitHub integration fixes"},
          %{type: "removed", description: "Deprecated legacy scraper endpoints"}
        ],
        image: nil
      },
      %{
        id: "3",
        date: "November 15, 2024",
        iso_date: "2024-11-15",
        title: "Bulk Event Creation",
        summary: "New feature for faster event imports",
        changes: [
          %{type: "added", description: "Bulk event creation for faster imports"},
          %{type: "added", description: "New scraper sources added"},
          %{type: "fixed", description: "Duplicate event handling improvements"}
        ],
        image: "https://placehold.co/600x300/f3f4f6/1f2937?text=Bulk+Event+Creation"
      },
      %{
        id: "4",
        date: "November 1, 2024",
        iso_date: "2024-11-01",
        title: "Bug Fixes & Polish",
        summary: "Various fixes and quality improvements",
        changes: [
          %{type: "fixed", description: "Scraper stability for Resident Advisor"},
          %{type: "fixed", description: "Event location accuracy improvements"},
          %{type: "changed", description: "Improved error handling in job processing"}
        ],
        image: nil
      },
      %{
        id: "5",
        date: "October 20, 2024",
        iso_date: "2024-10-20",
        title: "Image Migration",
        summary: "Moved all event images to new CDN",
        changes: [
          %{type: "changed", description: "Migrated all images to new CDN for faster loading"},
          %{type: "changed", description: "Improved image compression"},
          %{type: "added", description: "WebP format support"}
        ],
        image: nil
      }
    ]

    render(conn, :changelog, entries: entries)
  end

  def eventasaurus_redirect(conn, _params) do
    render(conn, :eventasaurus, layout: false)
  end

  def sitemap_redirect(conn, params) do
    # Redirect all sitemap requests to R2 CDN
    # Uses configuration from :eventasaurus, :r2
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}
    cdn_url = r2_config[:cdn_url] || System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"

    # Determine the sitemap file to serve
    requested_path =
      case params do
        %{"path" => path_parts} when is_list(path_parts) ->
          # /sitemaps/* - serve the exact file requested (e.g., sitemap-00001.xml.gz)
          "sitemaps/" <> Enum.join(path_parts, "/")

        _ ->
          # /sitemap or /sitemap.xml - serve the main sitemap index file
          "sitemaps/sitemap.xml.gz"
      end

    storage_url = "#{cdn_url}/#{requested_path}"
    redirect(conn, external: storage_url)
  end
end
