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
