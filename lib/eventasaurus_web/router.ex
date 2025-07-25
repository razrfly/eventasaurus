defmodule EventasaurusWeb.Router do
  use EventasaurusWeb, :router

  import EventasaurusWeb.Plugs.AuthPlug

  # Development-only route for hot-reloading themes
  if Mix.env() == :dev do
    get "/themes/:theme_name", EventasaurusWeb.ThemeController, :show
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EventasaurusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug EventasaurusWeb.Plugs.CSPPlug
    plug :fetch_auth_user
    plug :assign_user_struct
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_auth_user
    plug :assign_user_struct
  end

  # Enhanced API pipeline with CSRF protection for sensitive operations
  pipeline :api_csrf_protected do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :fetch_auth_user
    plug :assign_user_struct
  end

  # Secure user search pipeline (combines security measures for user data access)
  pipeline :secure_user_api do
    plug :accepts, ["json"]
    plug EventasaurusWeb.Plugs.SecurityPlug, force_https: true, security_headers: true
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 60, window: 60_000  # 60 requests per minute
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
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

  # Health check pipeline with rate limiting to prevent abuse
  pipeline :health_check do
    plug :accepts, ["json"]
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 10, window: 60_000  # 10 requests per minute
  end

  # Pipeline for redirect if authenticated (but allows password recovery)
  pipeline :redirect_if_authenticated_except_recovery do
    plug :redirect_if_user_is_authenticated_except_recovery
  end

  # Authentication routes - placing these BEFORE the catch-all public routes
  scope "/auth", EventasaurusWeb do
    pipe_through [:browser, :redirect_if_authenticated_except_recovery]

    get "/login", Auth.AuthController, :login
    post "/login", Auth.AuthController, :authenticate
    get "/register", Auth.AuthController, :register
    post "/register", Auth.AuthController, :create_user
    get "/forgot-password", Auth.AuthController, :forgot_password
    post "/forgot-password", Auth.AuthController, :request_password_reset
    get "/reset-password", Auth.AuthController, :reset_password
    post "/reset-password", Auth.AuthController, :update_password
    get "/facebook", Auth.AuthController, :facebook_login
  end

  # Auth callback and logout routes (no redirect needed - these need to work for all users)
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

      live "/dashboard", DashboardLive, :index
      live "/groups", GroupLive.Index, :index
      live "/groups/new", GroupLive.New, :new
      live "/groups/:slug", GroupLive.Show, :show
      live "/groups/:slug/edit", GroupLive.Edit, :edit
      live "/events/new", EventLive.New
      live "/events/:slug/edit", EventLive.Edit
      live "/checkout/payment", CheckoutPaymentLive
    end
  end

  # Protected routes that require authentication
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

    get "/settings", SettingsController, :index
    get "/settings/account", SettingsController, :account
    get "/settings/payments", SettingsController, :payments
    post "/settings/account", SettingsController, :update_account
    post "/settings/password", SettingsController, :update_password
    get "/settings/facebook/link", SettingsController, :link_facebook
    post "/settings/facebook/unlink", SettingsController, :unlink_facebook
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

  # Protected event management LiveView (require authentication)
  live_session :event_management, on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
    scope "/events", EventasaurusWeb do
      pipe_through :browser

      live "/:slug", EventManageLive, :show
      live "/:slug/tickets", AdminTicketLive, :index
      live "/:slug/orders", AdminOrderLive, :index
    end
  end

  # Protected event routes that require authentication (browser)
  scope "/events", EventasaurusWeb do
    pipe_through [:browser, :authenticated]

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

    # Generic participant status management API endpoints
    put "/:slug/participant-status", EventController, :update_participant_status
    delete "/:slug/participant-status", EventController, :remove_participant_status
    get "/:slug/participant-status", EventController, :get_participant_status
    get "/:slug/participants/:status", EventController, :list_participants_by_status
    get "/:slug/participant-analytics", EventController, :participant_analytics
  end

  # Public ticket verification routes (no auth required)
  scope "/tickets", EventasaurusWeb do
    pipe_through :browser

    get "/verify/:ticket_id", TicketController, :verify
  end

  # Public routes with auth user assignment
  live_session :default, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      get "/", PageController, :home
      get "/about", PageController, :about
      get "/our-story", PageController, :our_story
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

  # Public profile routes (with auth user assignment for privacy checking)
  live_session :profiles, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # Username-based profile routes
      get "/user/:username", ProfileController, :show
      get "/u/:username", ProfileController, :redirect_short
    end
  end

  # Public event routes (with theme support)
  live_session :public,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user_and_theme}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # Guest-accessible checkout
      live "/events/:slug/checkout", CheckoutLive

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
    get "/username/availability/:username", UsernameController, :check_availability
  end

  # Stripe payment API routes (require authentication and HTTPS)
  scope "/api/stripe", EventasaurusWeb do
    pipe_through [:secure_api, :api_authenticated]

    post "/payment-intent", StripePaymentController, :create_payment_intent
    post "/confirm-payment", StripePaymentController, :confirm_payment
  end

  # Stripe checkout API routes (public for guest checkout support, but still secure)
  scope "/api/checkout", EventasaurusWeb do
    pipe_through :secure_api

    post "/sessions", CheckoutController, :create_session
    post "/sync/:order_id", CheckoutController, :sync_after_success
  end

  # Checkout success/cancel routes (public for guest checkout support)
  scope "/orders", EventasaurusWeb do
    pipe_through :browser

    get "/:order_id/success", CheckoutController, :success
    get "/cancel", CheckoutController, :cancel
  end

  # User search API routes (require authentication, CSRF protection, enhanced security, and rate limiting)
  scope "/api/users", EventasaurusWeb do
    pipe_through [:secure_user_api, :api_authenticated]

    get "/search", UserSearchController, :search
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

  # Sentry test routes (development only)
  if Mix.env() == :dev do
    scope "/dev/sentry", EventasaurusWeb do
      pipe_through :api

      get "/test-error", SentryTestController, :test_error
      get "/test-message", SentryTestController, :test_message
    end
  end

  # Production Sentry health check (always available)
  scope "/api/health", EventasaurusWeb do
    pipe_through :api

    get "/sentry", SentryTestController, :health_check
  end

  # Secure production Sentry test endpoint
  scope "/api/admin", EventasaurusWeb do
    pipe_through [:secure_api, :api_authenticated]

    post "/sentry-test", SentryTestController, :test_production_error
  end
end
