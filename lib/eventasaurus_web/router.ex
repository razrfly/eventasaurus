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
    plug :fetch_session
    plug :fetch_auth_user
    plug :assign_user_struct
  end

  pipeline :image do
    plug :accepts, ["png", "jpg", "jpeg", "gif", "webp"]
  end

  # Routes that require authentication
  pipeline :authenticated do
    plug :require_authenticated_user
  end

  # API routes that require authentication (returns JSON instead of redirecting)
  pipeline :api_authenticated do
    plug :require_authenticated_api_user
  end

  # Routes that should redirect if already authenticated
  pipeline :redirect_if_authenticated do
    plug :redirect_if_user_is_authenticated
  end

  # Webhook pipeline (no authentication, but captures raw body)
  pipeline :webhook do
    plug :accepts, ["json"]
    plug EventasaurusWeb.Plugs.RawBodyPlug
  end

  # Secure pipeline for sensitive endpoints (HTTPS enforcement)
  pipeline :secure do
    plug EventasaurusWeb.Plugs.SecurityPlug, force_https: true, security_headers: true
  end

  # Secure API pipeline for sensitive API endpoints
  pipeline :secure_api do
    plug :accepts, ["json"]
    plug EventasaurusWeb.Plugs.SecurityPlug, force_https: true, security_headers: true
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 60, window: 60_000  # 60 requests per minute
    plug :fetch_session
    plug :fetch_auth_user
    plug :assign_user_struct
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

  # Protected LiveView routes that require authentication
  live_session :authenticated_orders, on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      live "/orders", OrderLive, :index
    end
  end

  # Stripe Connect routes (require authentication and HTTPS)
  scope "/stripe", EventasaurusWeb do
    pipe_through [:browser, :secure, :authenticated]

    get "/connect", StripeConnectController, :connect
    post "/disconnect", StripeConnectController, :disconnect
    get "/status", StripeConnectController, :status
  end

  # Stripe Connect OAuth callback (no authentication required for callback, but HTTPS enforced)
  scope "/stripe", EventasaurusWeb do
    pipe_through [:browser, :secure]

    get "/callback", StripeConnectController, :callback
  end

  # Protected event routes that require authentication (browser)
  scope "/events", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/:slug", EventController, :show
    get "/:slug/attendees", EventController, :attendees
    delete "/:slug", EventController, :delete
    post "/:slug/cancel", EventController, :cancel
    post "/:slug/auto-correct-status", EventController, :auto_correct_status
  end

  # Protected event API routes that require authentication (JSON)
  scope "/api/events", EventasaurusWeb do
    pipe_through [:api, :api_authenticated]

    # Action-driven setup API endpoints
    post "/:slug/pick-date", EventController, :pick_date
    post "/:slug/enable-polling", EventController, :enable_polling
    post "/:slug/set-threshold", EventController, :set_threshold
    post "/:slug/enable-ticketing", EventController, :enable_ticketing
    post "/:slug/add-details", EventController, :add_details
    post "/:slug/publish", EventController, :publish
  end

  # Public routes with auth user assignment
  live_session :default, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      get "/", PageController, :home
      get "/about", PageController, :about
      get "/whats-new", PageController, :whats_new
      get "/components", PageController, :components
      get "/privacy", PageController, :privacy
      get "/your-data", PageController, :your_data
      get "/terms", PageController, :terms

      # Direct routes for common auth paths (redirect to proper auth routes)
      get "/login", PageController, :redirect_to_auth_login
      get "/register", PageController, :redirect_to_auth_register
    end
  end

  # Public event routes (with theme support)
  live_session :public,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user_and_theme}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # Public event page with embedded registration (catch-all route should be last)
      live "/:slug", PublicEventLive
    end
  end

  # Public social card generation (no auth required)
  scope "/events", EventasaurusWeb do
    pipe_through :image

    # Cache-busting social card generation (by slug with hash)
    get "/:slug/social-card-:hash/*rest", EventSocialCardController, :generate_card_by_slug, as: :social_card_cached
  end

  # Other scopes may use custom stacks.
  scope "/api", EventasaurusWeb do
    pipe_through :api

    get "/search/unified", SearchController, :unified
  end

  # Stripe payment API routes (require authentication and HTTPS)
  scope "/api/stripe", EventasaurusWeb do
    pipe_through [:secure_api, :api_authenticated]

    post "/payment-intent", StripePaymentController, :create_payment_intent
    post "/confirm-payment", StripePaymentController, :confirm_payment
  end

  # Stripe checkout API routes (require authentication and HTTPS)
  scope "/api/checkout", EventasaurusWeb do
    pipe_through [:secure_api, :api_authenticated]

    post "/sessions", CheckoutController, :create_session
    post "/sync/:order_id", CheckoutController, :sync_after_success
  end

  # Checkout success/cancel routes (browser, require authentication)
  scope "/orders", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/:order_id/success", CheckoutController, :success
    get "/cancel", CheckoutController, :cancel
  end

  # Order management API routes (require authentication)
  scope "/api/orders", EventasaurusWeb do
    pipe_through [:api, :api_authenticated]

    get "/", OrdersController, :index
    get "/:id", OrdersController, :show
    post "/:id/cancel", OrdersController, :cancel
  end

  # Webhook pipeline with security measures for Stripe webhooks
  pipeline :secure_webhook do
    plug :accepts, ["json"]
    plug EventasaurusWeb.Plugs.RawBodyPlug
    plug EventasaurusWeb.Plugs.SecurityPlug, force_https: true, security_headers: false
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 1000, window: 60_000  # Higher limit for webhooks
  end

  # Stripe webhook routes (no authentication required, but with security measures)
  scope "/webhooks/stripe", EventasaurusWeb do
    pipe_through :secure_webhook

    post "/", StripeWebhookController, :handle_webhook
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:eventasaurus, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
