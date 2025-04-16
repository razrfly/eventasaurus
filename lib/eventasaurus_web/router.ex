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

  # Public routes
  scope "/", EventasaurusWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Authentication routes
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/login", Auth.AuthController, :login
    post "/login", Auth.AuthController, :create_session
    get "/register", Auth.AuthController, :register
    post "/register", Auth.AuthController, :create_user
    get "/forgot-password", Auth.AuthController, :forgot_password
    post "/request-password-reset", Auth.AuthController, :request_password_reset
    get "/reset-password/:token", Auth.AuthController, :reset_password
    post "/reset-password", Auth.AuthController, :update_password
    get "/auth/callback", Auth.AuthController, :callback
  end

  # Protected routes that require authentication
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/logout", Auth.AuthController, :logout
    # Add other authenticated routes here
    # get "/dashboard", DashboardController, :index
    # resources "/events", EventController
  end

  # Other scopes may use custom stacks.
  # scope "/api", EventasaurusWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:eventasaurus, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
