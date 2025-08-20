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

  def invite_only(conn, _params) do
    render(conn, :invite_only)
  end

  def redirect_to_auth_login(conn, _params) do
    # Preserve query parameters when redirecting
    query_string = conn.query_string
    path = if query_string != "" do
      "/auth/login?" <> query_string
    else
      "/auth/login"
    end
    redirect(conn, to: path)
  end

  def redirect_to_auth_register(conn, _params) do
    # Preserve query parameters when redirecting
    query_string = conn.query_string
    path = if query_string != "" do
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
    
    path = if query_string != "" do
      "/auth/register?#{event_param}&#{query_string}"
    else
      "/auth/register?#{event_param}"
    end
    
    redirect(conn, to: path)
  end
end
