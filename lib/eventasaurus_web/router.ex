defmodule EventasaurusWeb.Router do
  use EventasaurusWeb, :router

  import EventasaurusWeb.Plugs.AuthPlug

  # Development-only routes
  if Mix.env() == :dev do
    # Hot-reloading themes
    get "/themes/:theme_name", EventasaurusWeb.ThemeController, :show

    # Import Oban Web UI router functions
    import Oban.Web.Router

    # Development tools
    scope "/dev", EventasaurusWeb do
      pipe_through :browser

      # Oban Web UI for monitoring background jobs (dev - no auth)
      oban_dashboard("/oban")

      # Discovery Dashboard (dev - no auth)
      live "/imports", Admin.DiscoveryDashboardLive

      # Geocoding Cost Dashboard (dev - no auth)
      live "/geocoding", Admin.GeocodingDashboardLive

      # Category Management (dev - no auth)
      live "/categories", Admin.CategoryIndexLive, :index
      live "/categories/new", Admin.CategoryFormLive, :new
      live "/categories/:id/edit", Admin.CategoryFormLive, :edit

      # Source Management (dev - no auth)
      live "/sources", Admin.SourceIndexLive, :index
      live "/sources/new", Admin.SourceFormLive, :new
      live "/sources/:id/edit", Admin.SourceFormLive, :edit

      # Test page for plug-level 404 rendering (matches ValidateCity behavior)
      get "/test-404", Dev.Test404Controller, :test_plug_404
    end

    # Admin routes (dev - no auth, mirrors production paths)
    scope "/admin", EventasaurusWeb do
      pipe_through :browser

      # Discovery Dashboard (dev - no auth)
      live "/imports", Admin.DiscoveryDashboardLive

      # Geocoding Cost Dashboard (dev - no auth)
      live "/geocoding", Admin.GeocodingDashboardLive
      live "/geocoding/providers", Admin.GeocodingProviderLive, :index

      # City Discovery Configuration (dev - no auth)
      live "/discovery/config", Admin.CityDiscoveryConfigLive, :index
      live "/discovery/config/:slug", Admin.CityDiscoveryConfigLive, :show

      # Category Management (dev - no auth)
      live "/categories", Admin.CategoryIndexLive, :index
      live "/categories/new", Admin.CategoryFormLive, :new
      live "/categories/:id/edit", Admin.CategoryFormLive, :edit

      # Source Management (dev - no auth)
      live "/sources", Admin.SourceIndexLive, :index
      live "/sources/new", Admin.SourceFormLive, :new
      live "/sources/:id/edit", Admin.SourceFormLive, :edit

      # Design tools (dev - no auth)
      live "/design/social-cards", Admin.SocialCardsPreviewLive
    end

    # Category demo routes for testing
    scope "/category-demo", EventasaurusWeb do
      pipe_through :browser

      get "/", CategoryDemoController, :index
      get "/:id", CategoryDemoController, :show
    end
  end

  # Production Oban Web UI with authentication
  if Mix.env() == :prod do
    import Oban.Web.Router

    pipeline :oban_admin do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :put_root_layout, html: {EventasaurusWeb.Layouts, :root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
      # Temporarily disabled CSP while debugging
      # if Mix.env() != :dev do
      #   plug EventasaurusWeb.Plugs.CSPPlug
      # end
      plug EventasaurusWeb.Plugs.SecurityPlug, force_https: true, security_headers: true
      plug :fetch_auth_user
      plug :assign_user_struct
      plug :require_authenticated_user
      plug EventasaurusWeb.Plugs.ObanAuthPlug
    end

    scope "/admin" do
      pipe_through :oban_admin

      # Oban Web UI with admin authentication
      oban_dashboard("/oban", csp_nonce_assign_key: :csp_nonce)

      # Discovery Dashboard with admin authentication
      live "/imports", EventasaurusWeb.Admin.DiscoveryDashboardLive

      # Geocoding Cost Dashboard with admin authentication
      live "/geocoding", EventasaurusWeb.Admin.GeocodingDashboardLive
      live "/geocoding/providers", EventasaurusWeb.Admin.GeocodingProviderLive, :index

      # City Discovery Configuration
      live "/discovery/config", EventasaurusWeb.Admin.CityDiscoveryConfigLive, :index
      live "/discovery/config/:slug", EventasaurusWeb.Admin.CityDiscoveryConfigLive, :show

      # Category Management
      live "/categories", EventasaurusWeb.Admin.CategoryIndexLive, :index
      live "/categories/new", EventasaurusWeb.Admin.CategoryFormLive, :new
      live "/categories/:id/edit", EventasaurusWeb.Admin.CategoryFormLive, :edit

      # Source Management
      live "/sources", EventasaurusWeb.Admin.SourceIndexLive, :index
      live "/sources/new", EventasaurusWeb.Admin.SourceFormLive, :new
      live "/sources/:id/edit", EventasaurusWeb.Admin.SourceFormLive, :edit

      # Design tools (with admin authentication)
      live "/design/social-cards", EventasaurusWeb.Admin.SocialCardsPreviewLive
    end
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :fetch_query_params
    plug :put_root_layout, html: {EventasaurusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Temporarily disabled CSP while debugging
    # if Mix.env() != :dev do
    #   plug EventasaurusWeb.Plugs.CSPPlug
    # end
    if Mix.env() == :dev do
      plug EventasaurusWeb.Dev.DevAuthPlug
    end

    plug :fetch_auth_user
    plug :assign_user_struct
    plug EventasaurusWeb.Plugs.LanguagePlug
  end

  # City browser pipeline with city validation
  pipeline :city_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :fetch_query_params
    plug :put_root_layout, html: {EventasaurusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    if Mix.env() == :dev do
      plug EventasaurusWeb.Dev.DevAuthPlug
    end

    plug :fetch_auth_user
    plug :assign_user_struct
    plug EventasaurusWeb.Plugs.LanguagePlug
    plug EventasaurusWeb.Plugs.ValidateCity
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session

    if Mix.env() == :dev do
      plug EventasaurusWeb.Dev.DevAuthPlug
    end

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
    # 60 requests per minute
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 60, window: 60_000
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
    # 60 requests per minute
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 60, window: 60_000
    plug :fetch_session
    plug :fetch_auth_user
    plug :assign_user_struct
  end

  # Health check pipeline with rate limiting to prevent abuse
  pipeline :health_check do
    plug :accepts, ["json"]
    # 10 requests per minute
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 10, window: 60_000
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
    get "/google", Auth.AuthController, :google_login
  end

  # Auth callback and logout routes (no redirect needed - these need to work for all users)
  scope "/auth", EventasaurusWeb do
    pipe_through :browser

    get "/callback", Auth.AuthController, :callback
    post "/callback", Auth.AuthController, :callback
    get "/logout", Auth.AuthController, :logout
    post "/logout", Auth.AuthController, :logout
  end

  # Development-only quick login route
  if Mix.env() == :dev do
    scope "/dev", EventasaurusWeb do
      pipe_through :browser

      post "/quick-login", Dev.DevAuthController, :quick_login
    end
  end

  # LiveView session for authenticated routes
  live_session :authenticated,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      live "/dashboard", DashboardLive, :index
      live "/groups", GroupLive.Index, :index
      live "/groups/new", GroupLive.New, :new
      live "/groups/:slug", GroupLive.Show, :show
      live "/groups/:slug/events", GroupLive.Show, :events
      live "/groups/:slug/people", GroupLive.Show, :people
      live "/groups/:slug/activities", GroupLive.Show, :activities
      live "/groups/:slug/edit", GroupLive.Edit, :edit
      live "/events", EventsLive
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
  live_session :authenticated_orders,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
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
  live_session :event_management,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}] do
    scope "/events", EventasaurusWeb do
      pipe_through :browser

      live "/:slug", EventManageLive, :overview
      live "/:slug/guests", EventManageLive, :guests
      live "/:slug/registrations", EventManageLive, :registrations
      live "/:slug/polls", EventManageLive, :polls
      live "/:slug/insights", EventManageLive, :insights
      live "/:slug/history", EventManageLive, :history
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
      get "/pitch", PageController, :pitch
      get "/pitch2", PageController, :pitch2
      get "/crypto-pitch", PageController, :crypto_pitch
      get "/invite-only", PageController, :invite_only
      get "/logo-test", LogoTestController, :index

      # Sitemap redirect
      get "/sitemap", PageController, :sitemap_redirect
      get "/sitemap.xml", PageController, :sitemap_redirect
      get "/sitemaps/*path", PageController, :sitemap_redirect

      # Legacy Eventasaurus brand redirect page
      get "/eventasaurus", PageController, :eventasaurus_redirect
      get "/eventasaurus/*path", PageController, :eventasaurus_redirect

      # Direct routes for common auth paths (redirect to proper auth routes)
      get "/login", PageController, :redirect_to_auth_login
      get "/register", PageController, :redirect_to_auth_register

      # Performer profile pages
      live "/performers/:slug", PerformerLive.Show, :show
    end
  end

  # Event signup routes that should redirect authenticated users
  scope "/", EventasaurusWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/signup", PageController, :redirect_to_invite_only
    get "/signup/:event_id", PageController, :redirect_to_auth_register_with_event
  end

  # Public profile routes (with auth user assignment for privacy checking)
  live_session :profiles, on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # Username-based profile routes (new plural form)
      get "/users/:username", ProfileController, :show
      get "/u/:username", ProfileController, :redirect_short

      # Backward compatibility redirects for old /user/ URLs
      get "/user/:username", ProfileController, :redirect_legacy
    end
  end

  # City-based routes with /c/ prefix
  live_session :city,
    on_mount: [
      {EventasaurusWeb.Live.AuthHooks, :assign_auth_user},
      {EventasaurusWeb.Live.CityHooks, :assign_city}
    ] do
    scope "/c", EventasaurusWeb do
      pipe_through :city_browser

      # City homepage (shows events by default)
      live "/:city_slug", CityLive.Index, :index

      # Explicit events routes with filters
      live "/:city_slug/events", CityLive.Events, :index
      live "/:city_slug/events/today", CityLive.Events, :today
      live "/:city_slug/events/weekend", CityLive.Events, :weekend
      live "/:city_slug/events/week", CityLive.Events, :week

      # City venues
      live "/:city_slug/venues", CityLive.Venues, :index
      live "/:city_slug/venues/:venue_slug", VenueLive.Show, :show

      # City search
      live "/:city_slug/search", CityLive.Search, :index

      # Container type index pages (list all festivals, conferences, etc. in a city)
      live "/:city_slug/festivals", CityLive.Events, :festivals
      live "/:city_slug/conferences", CityLive.Events, :conferences
      live "/:city_slug/tours", CityLive.Events, :tours
      live "/:city_slug/series", CityLive.Events, :series
      live "/:city_slug/exhibitions", CityLive.Events, :exhibitions
      live "/:city_slug/tournaments", CityLive.Events, :tournaments

      # Container detail pages (individual festival, conference, etc.)
      live "/:city_slug/festivals/:container_slug", CityLive.ContainerDetailLive, :show
      live "/:city_slug/conferences/:container_slug", CityLive.ContainerDetailLive, :show
      live "/:city_slug/tours/:container_slug", CityLive.ContainerDetailLive, :show
      live "/:city_slug/series/:container_slug", CityLive.ContainerDetailLive, :show
      live "/:city_slug/exhibitions/:container_slug", CityLive.ContainerDetailLive, :show
      live "/:city_slug/tournaments/:container_slug", CityLive.ContainerDetailLive, :show

      # Movie screenings aggregation (must be before catch-all aggregated content)
      live "/:city_slug/movies/:movie_slug", PublicMovieScreeningsLive, :show

      # Aggregated content-type routes (trivia, movies, classes, etc.)
      live "/:city_slug/:content_type/:identifier", AggregatedContentLive, :show
    end
  end

  # Public event routes (with theme support)
  live_session :public,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user_and_theme}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # ===== SCRAPED/DISCOVERY EVENTS (from external APIs) =====
      # PublicEventsIndexLive - Browse all scraped events with filters
      # PublicEventShowLive - Individual scraped event details
      live "/activities", PublicEventsIndexLive, :index
      live "/activities/search", PublicEventsIndexLive, :search
      live "/activities/category/:category", PublicEventsIndexLive, :category
      live "/activities/:slug", PublicEventShowLive, :show
      live "/activities/:slug/:date_slug", PublicEventShowLive, :show

      # Guest-accessible checkout
      live "/events/:slug/checkout", CheckoutLive

      # Public polls page (must be before catch-all)
      live "/:slug/polls", PublicPollsLive

      # Individual poll page (by sequential number)
      live "/:slug/polls/:number", PublicPollLive

      # ===== USER-CREATED EVENTS (private events made public) =====
      # PublicEventLive - Individual user-created event with registration
      # IMPORTANT: This is a catch-all route and must be last in this scope
      live "/:slug", PublicEventLive
    end
  end

  # Public calendar export routes (no auth required)
  scope "/events", EventasaurusWeb do
    pipe_through :browser

    # Calendar export endpoint
    get "/:slug/calendar/:format", CalendarController, :export
  end

  # Public social card generation (no auth required)
  # These routes mirror the public event/poll page structure at root scope
  scope "/", EventasaurusWeb do
    pipe_through :image

    # Event social card generation (matches public event route at /:slug)
    get "/:slug/social-card-:hash/*rest", EventSocialCardController, :generate_card_by_slug,
      as: :social_card_cached

    # Poll social card generation (matches public poll route at /:slug/polls/:number)
    get "/:slug/polls/:number/social-card-:hash/*rest", PollSocialCardController, :generate_card_by_number,
      as: :poll_social_card_cached
  end

  # Other scopes may use custom stacks.
  scope "/api", EventasaurusWeb do
    pipe_through :api

    get "/search/unified", SearchController, :unified
    get "/username/availability/:username", UsernameController, :check_availability
    post "/spotify/token", SpotifyController, :get_token
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
    # Higher limit for webhooks
    plug EventasaurusWeb.Plugs.RateLimitPlug, limit: 1000, window: 60_000
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
