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

  def redirect_to_auth_login(conn, _params) do
    redirect(conn, to: ~p"/auth/login")
  end

  def redirect_to_auth_register(conn, _params) do
    redirect(conn, to: ~p"/auth/register")
  end
end
