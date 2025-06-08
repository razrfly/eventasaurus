defmodule EventasaurusWeb.Router do
  use EventasaurusWeb, :router

  import EventasaurusWeb.Plugs.AuthPlug

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EventasaurusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_auth_user
    plug :assign_user_struct
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Routes that require authentication
  pipeline :authenticated do
    plug :require_authenticated_user
  end

  # Routes that should redirect if already authenticated
  pipeline :redirect_if_authenticated do
    plug :redirect_if_user_is_authenticated
  end

  # Authentication routes - placing these BEFORE the catch-all public routes
  scope "/auth", EventasaurusWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/login", Auth.AuthController, :login
    post "/login", Auth.AuthController, :authenticate
    get "/register", Auth.AuthController, :register
    post "/register", Auth.AuthController, :create_user
    get "/forgot-password", Auth.AuthController, :forgot_password
    post "/forgot-password", Auth.AuthController, :request_password_reset
    get "/reset-password", Auth.AuthController, :reset_password
    post "/reset-password", Auth.AuthController, :update_password
  end

  # Auth callback and logout (no redirect needed)
  scope "/auth", EventasaurusWeb do
    pipe_through :browser

    get "/callback", Auth.AuthController, :callback
    post "/callback", Auth.AuthController, :callback
    get "/logout", Auth.AuthController, :logout
    post "/logout", Auth.AuthController, :logout

    # Social auth error handling endpoints
    post "/error", Auth.AuthController, :auth_error
    post "/retry", Auth.AuthController, :retry_auth
  end

  # LiveView session for authenticated routes
  live_session :authenticated, on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      live "/events/new", EventLive.New
      live "/events/:slug/edit", EventLive.Edit
    end
  end

  # Protected routes that require authentication
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/dashboard", DashboardController, :index
  end

  # Session management test route (authenticated)
  live_session :session_test, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user_with_session_sync}] do
    scope "/", EventasaurusWeb do
      pipe_through [:browser, :authenticated]

      live "/session-test", SessionTestLive
    end
  end

  # Protected event routes that require authentication
  scope "/events", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/:slug", EventController, :show
    get "/:slug/attendees", EventController, :attendees
    delete "/:slug", EventController, :delete
  end

  # Public routes with auth user assignment
  live_session :default, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      get "/", PageController, :home
      get "/about", PageController, :about
      get "/whats-new", PageController, :whats_new
      get "/components", PageController, :components

      # Direct routes for common auth paths (redirect to proper auth routes)
      get "/login", PageController, :redirect_to_auth_login
      get "/register", PageController, :redirect_to_auth_register
    end
  end

  # Public event routes (with theme support) - MUST BE LAST due to catch-all route
  live_session :public,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user_and_theme}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # Public event page with embedded registration (catch-all route MUST be last)
      live "/:slug", PublicEventLive
    end
  end

  # Other scopes may use custom stacks.
  scope "/api", EventasaurusWeb do
    pipe_through :api

    get "/search/unified", SearchController, :unified
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:eventasaurus, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
