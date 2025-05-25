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
    plug :fetch_current_user
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
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/login", Auth.AuthController, :login
    post "/login", Auth.AuthController, :authenticate
    get "/register", Auth.AuthController, :register
    post "/register", Auth.AuthController, :create_user
    get "/forgot-password", Auth.AuthController, :forgot_password
    post "/request-password-reset", Auth.AuthController, :request_password_reset
    get "/reset-password/:token", Auth.AuthController, :reset_password
    post "/reset-password", Auth.AuthController, :update_password
    get "/auth/callback", Auth.AuthController, :callback
    post "/auth/callback", Auth.AuthController, :callback
  end

  # LiveView session for authenticated routes - MUST come BEFORE regular routes
  live_session :authenticated, on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
    scope "/", EventasaurusWeb do
      pipe_through [:browser, :authenticated]

      # Add authenticated LiveView routes here
      live "/events/new", EventLive.New
      live "/events/:slug/edit", EventLive.Edit
    end
  end

  # Protected routes that require authentication
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/logout", Auth.AuthController, :logout
    get "/dashboard", DashboardController, :index

    # Internal event management routes with EventController
    get "/events/:slug", EventController, :show
    delete "/events/:slug", EventController, :delete
    get "/events/:slug/attendees", EventController, :attendees

    # Add other authenticated controller routes here
    # resources "/venues", VenueController
  end

  # LiveView session configuration
  live_session :default, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_current_user}] do
    # Public routes
    scope "/", EventasaurusWeb do
      pipe_through :browser

      get "/", PageController, :index
      get "/home", PageController, :home
      get "/about", PageController, :about
      get "/whats-new", PageController, :whats_new
      # Add public LiveView routes here
      # live "/events/:slug", EventLive.Show
    end
  end

  # Public event routes (uses public layout)
  live_session :public,
    layout: {EventasaurusWeb.Layouts, :public},
    root_layout: {EventasaurusWeb.Layouts, :public_root},
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_current_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # Public event page with embedded registration (catch-all route should be last)
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
