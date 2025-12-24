defmodule EventasaurusWeb.Router do
  use EventasaurusWeb, :router

  import EventasaurusWeb.Plugs.AuthPlug

  # Development and test routes
  if Mix.env() in [:dev, :test] do
    # Hot-reloading themes
    get "/themes/:theme_name", EventasaurusWeb.ThemeController, :show

    # Import Oban Web UI router functions
    import Oban.Web.Router

    # Development tools (debugging and testing utilities only)
    scope "/dev", EventasaurusWeb do
      pipe_through :browser

      # Test page for plug-level 404 rendering (matches ValidateCity behavior)
      get "/test-404", Dev.Test404Controller, :test_plug_404

      # CDN testing page (dev - no auth)
      get "/cdn-test", Dev.CdnTestController, :index

      # ImageKit CDN testing page (dev - no auth)
      get "/imagekit-test", Dev.ImagekitTestController, :index

      # Venue Images testing page (dev - no auth)
      get "/venue-images", Dev.VenueImagesTestController, :index
      post "/venue-images/test-enrichment", Dev.VenueImagesTestController, :test_enrichment
      put "/venue-images/update-provider-ids", Dev.VenueImagesTestController, :update_provider_ids

      post "/venue-images/save-discovered-ids",
           Dev.VenueImagesTestController,
           :save_discovered_ids

      post "/venue-images/clear-cache", Dev.VenueImagesTestController, :clear_cache
    end

    # Admin routes (dev - no auth, mirrors production paths)
    scope "/admin", EventasaurusWeb do
      pipe_through :browser

      # Main Admin Dashboard (dev - no auth)
      live "/", Admin.AdminDashboardLive

      # Oban Web UI for monitoring background jobs (dev - no auth)
      oban_dashboard("/oban")

      # Sitemap Statistics (dev - no auth)
      live "/sitemap", Admin.SitemapLive

      # Discovery Dashboard (dev - no auth)
      live "/imports", Admin.DiscoveryDashboardLive

      # Discovery Stats Dashboard (dev - no auth)
      live "/discovery/stats", Admin.DiscoveryStatsLive, :index
      live "/discovery/stats/source/:source_slug", Admin.DiscoveryStatsLive.SourceDetail, :show
      live "/discovery/stats/city/:city_slug", Admin.DiscoveryStatsLive.CityDetail, :show

      # Scraper Processing Logs (dev - no auth)
      live "/scraper-logs", Admin.ScraperLogsLive

      # Job Execution Monitor (dev - no auth)
      live "/job-executions", Admin.JobExecutionMonitorLive
      live "/job-executions/sources/:source_slug", Admin.SourcePipelineMonitorLive
      live "/job-executions/:worker", Admin.JobTypeMonitorLive

      # Error Trends & Analysis (dev - no auth)
      live "/error-trends", Admin.ErrorTrendsLive

      # Category Analysis (dev - no auth)
      live "/discovery/category-analysis/:source_slug", Admin.CategoryAnalysisLive, :show

      # Geocoding Cost Dashboard (dev - no auth)
      live "/geocoding", Admin.GeocodingDashboardLive
      live "/geocoding/providers", Admin.GeocodingProviderLive, :index
      live "/geocoding/operations/:city_slug", Admin.GeocodingOperationsLive

      # Venue Images Stats Dashboard (dev - no auth)
      live "/venue-images/stats", Admin.VenueImagesStatsLive

      # Venue Image Operations (dev - no auth)
      live "/venue-images/operations", Admin.VenueImageOperationsLive

      # Unified Venue Image Enrichment History (dev - no auth)
      live "/venue-images/enrichment-history", Admin.VenueImageEnrichmentHistoryLive

      # Venue Duplicate Management (dev - no auth)
      live "/venues/duplicates", Admin.VenueDuplicatesLive

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

      # City Management (dev - no auth)
      live "/cities", Admin.CityIndexLive, :index
      live "/cities/new", Admin.CityFormLive, :new
      live "/cities/:id/edit", Admin.CityFormLive, :edit
      live "/cities/duplicates", Admin.CityDuplicatesLive, :index
      live "/cities/cleanup", Admin.CityCleanupLive

      # Venue Country Mismatches (dev - no auth)
      live "/venues/country-mismatches", Admin.VenueCountryMismatchesLive, :index

      # Design tools (dev - no auth)
      live "/design/social-cards", Admin.SocialCardsPreviewLive

      # Unsplash Integration (dev - no auth)
      get "/unsplash", Admin.UnsplashTestController, :index
      post "/unsplash/fetch/:city_id", Admin.UnsplashTestController, :fetch_images

      post "/unsplash/refresh-category/:city_id/:category",
           Admin.UnsplashTestController,
           :refresh_category

      post "/unsplash/refresh-all-cities", Admin.UnsplashTestController, :refresh_all_cities
      post "/unsplash/refresh-all-countries", Admin.UnsplashTestController, :refresh_all_countries
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

      # Main Admin Dashboard with admin authentication
      live "/", EventasaurusWeb.Admin.AdminDashboardLive

      # Oban Web UI with admin authentication
      oban_dashboard("/oban", csp_nonce_assign_key: :csp_nonce)

      # Scraper Processing Logs with admin authentication
      live "/scraper-logs", EventasaurusWeb.Admin.ScraperLogsLive

      # Job Execution Monitor with admin authentication
      live "/job-executions", EventasaurusWeb.Admin.JobExecutionMonitorLive
      live "/job-executions/sources/:source_slug", EventasaurusWeb.Admin.SourcePipelineMonitorLive
      live "/job-executions/:worker", EventasaurusWeb.Admin.JobTypeMonitorLive

      # Error Trends & Analysis with admin authentication
      live "/error-trends", EventasaurusWeb.Admin.ErrorTrendsLive

      # Sitemap Statistics with admin authentication
      live "/sitemap", EventasaurusWeb.Admin.SitemapLive

      # Discovery Dashboard with admin authentication
      live "/imports", EventasaurusWeb.Admin.DiscoveryDashboardLive

      # Discovery Stats Dashboard with admin authentication
      live "/discovery/stats", EventasaurusWeb.Admin.DiscoveryStatsLive, :index

      live "/discovery/stats/source/:source_slug",
           EventasaurusWeb.Admin.DiscoveryStatsLive.SourceDetail,
           :show

      live "/discovery/stats/city/:city_slug",
           EventasaurusWeb.Admin.DiscoveryStatsLive.CityDetail,
           :show

      # Category Analysis with admin authentication
      live "/discovery/category-analysis/:source_slug",
           EventasaurusWeb.Admin.CategoryAnalysisLive,
           :show

      # Geocoding Cost Dashboard with admin authentication
      live "/geocoding", EventasaurusWeb.Admin.GeocodingDashboardLive
      live "/geocoding/providers", EventasaurusWeb.Admin.GeocodingProviderLive, :index
      live "/geocoding/operations/:city_slug", EventasaurusWeb.Admin.GeocodingOperationsLive

      # Venue Images Stats Dashboard with admin authentication
      live "/venue-images/stats", EventasaurusWeb.Admin.VenueImagesStatsLive

      # Venue Image Operations with admin authentication
      live "/venue-images/operations", EventasaurusWeb.Admin.VenueImageOperationsLive

      # Unified Venue Image Enrichment History with admin authentication
      live "/venue-images/enrichment-history",
           EventasaurusWeb.Admin.VenueImageEnrichmentHistoryLive

      # Venue Duplicate Management with admin authentication
      live "/venues/duplicates", EventasaurusWeb.Admin.VenueDuplicatesLive

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

      # City Management (with admin authentication)
      live "/cities", EventasaurusWeb.Admin.CityIndexLive, :index
      live "/cities/new", EventasaurusWeb.Admin.CityFormLive, :new
      live "/cities/:id/edit", EventasaurusWeb.Admin.CityFormLive, :edit
      live "/cities/duplicates", EventasaurusWeb.Admin.CityDuplicatesLive, :index
      live "/cities/cleanup", EventasaurusWeb.Admin.CityCleanupLive

      # Venue Country Mismatches (with admin authentication)
      live "/venues/country-mismatches", EventasaurusWeb.Admin.VenueCountryMismatchesLive, :index

      # Design tools (with admin authentication)
      live "/design/social-cards", EventasaurusWeb.Admin.SocialCardsPreviewLive

      # Unsplash Integration (with admin authentication)
      get "/unsplash", EventasaurusWeb.Admin.UnsplashTestController, :index
      post "/unsplash/fetch/:city_id", EventasaurusWeb.Admin.UnsplashTestController, :fetch_images

      post "/unsplash/refresh-category/:city_id/:category",
           EventasaurusWeb.Admin.UnsplashTestController,
           :refresh_category

      post "/unsplash/refresh-all-cities",
           EventasaurusWeb.Admin.UnsplashTestController,
           :refresh_all_cities

      post "/unsplash/refresh-all-countries",
           EventasaurusWeb.Admin.UnsplashTestController,
           :refresh_all_countries
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
    # Prevent CDN/browser caching of auth-aware pages (fixes #2625)
    plug EventasaurusWeb.Plugs.CacheControlPlug
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
    plug EventasaurusWeb.Plugs.AggregationTypeRedirect
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
    # Prevent CDN/browser caching of auth-aware pages (fixes #2625)
    plug EventasaurusWeb.Plugs.CacheControlPlug

    if Mix.env() == :dev do
      plug EventasaurusWeb.Dev.DevAuthPlug
    end

    plug :fetch_auth_user
    plug :assign_user_struct
    plug EventasaurusWeb.Plugs.LanguagePlug
    plug EventasaurusWeb.Plugs.ValidateCity
    plug EventasaurusWeb.Plugs.AggregationTypeRedirect
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

  # Authentication routes (Clerk-only)
  # Clerk handles all auth UI via its components, these routes just render pages
  scope "/auth", EventasaurusWeb do
    pipe_through [:browser, :redirect_if_authenticated_except_recovery]

    get "/login", Auth.ClerkAuthController, :login
    get "/register", Auth.ClerkAuthController, :register
  end

  # Auth callback and logout routes
  scope "/auth", EventasaurusWeb do
    pipe_through :browser

    get "/callback", Auth.ClerkAuthController, :callback
    get "/logout", Auth.ClerkAuthController, :logout
    post "/logout", Auth.ClerkAuthController, :logout
    get "/profile", Auth.ClerkAuthController, :profile
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
      live "/people", PeopleLive.Index, :index
      live "/people/discover", PeopleLive.Index, :index
      live "/people/introductions", ConnectionRequestsLive, :index
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
    get "/settings/privacy", SettingsController, :privacy
    post "/settings/account", SettingsController, :update_account
    post "/settings/password", SettingsController, :update_password
    post "/settings/privacy", SettingsController, :update_privacy
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
      get "/about-v2", PageController, :about_v2
      get "/about-v3", PageController, :about_v3
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
      get "/changelog", PageController, :changelog
      get "/changelog-beta", PageController, :changelog_beta
      get "/roadmap", PageController, :roadmap
      get "/how-it-works", PageController, :how_it_works
      get "/manifesto", PageController, :manifesto

      # Sitemap redirect
      get "/sitemap", PageController, :sitemap_redirect
      get "/sitemap.xml", PageController, :sitemap_redirect
      get "/sitemaps/*path", PageController, :sitemap_redirect

      # Legacy Eventasaurus brand redirect page
      get "/eventasaurus", PageController, :eventasaurus_redirect
      get "/eventasaurus/*path", PageController, :eventasaurus_redirect

      # Direct routes for common auth paths (redirect to proper auth routes)
      get "/login", PageController, :redirect_to_auth_login
      # /register without event_id goes to invite-only page (registration is invite-only)
      get "/register", PageController, :redirect_to_invite_only

      # Performer profile pages
      live "/performers/:slug", PerformerLive.Show, :show

      # Direct venue pages (for trivia_advisor compatibility)
      live "/venues/:slug", VenueLive.Show, :show
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
      live "/users/:username", ProfileLive, :show
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

      # Container detail pages - type-specific routes for semantic URLs and schema.org mapping
      # Each container type has its own route for SEO and clarity
      live "/:city_slug/festivals/:container_slug", CityLive.ContainerDetailLive, :festival
      live "/:city_slug/conferences/:container_slug", CityLive.ContainerDetailLive, :conference
      live "/:city_slug/tours/:container_slug", CityLive.ContainerDetailLive, :tour
      live "/:city_slug/series/:container_slug", CityLive.ContainerDetailLive, :series
      live "/:city_slug/exhibitions/:container_slug", CityLive.ContainerDetailLive, :exhibition
      live "/:city_slug/tournaments/:container_slug", CityLive.ContainerDetailLive, :tournament

      # Movie screenings aggregation (must be before catch-all aggregated content)
      live "/:city_slug/movies/:movie_slug", PublicMovieScreeningsLive, :show

      # Aggregated content-type routes (trivia, movies, classes, etc.)
      live "/:city_slug/:content_type/:identifier", AggregatedContentLive, :show
    end
  end

  # Public social card generation (no auth required)
  # IMPORTANT: These routes MUST come before the :public live_session to avoid conflicts
  # with the catch-all aggregated content route (/:content_type/:identifier)
  # Otherwise URLs like /event-slug/social-card-hash.png will be incorrectly matched
  # as aggregated content instead of social cards.
  scope "/", EventasaurusWeb do
    pipe_through :image

    # City social card generation (matches city route at /c/:slug)
    get "/social-cards/city/:slug/:hash/*rest", CitySocialCardController, :generate_card_by_slug,
      as: :city_social_card_cached

    # Activity social card generation (matches public activity route at /activities/:slug)
    get "/social-cards/activity/:slug/:hash/*rest",
        ActivitySocialCardController,
        :generate_card_by_slug,
        as: :activity_social_card_cached

    # Source aggregation social card generation (matches /c/:city_slug/:content_type/:identifier)
    get "/social-cards/source/:city_slug/:content_type/:identifier/:hash/*rest",
        SourceAggregationSocialCardController,
        :generate_card,
        as: :source_aggregation_social_card_cached

    # Venue social card generation (matches /c/:city_slug/venues/:venue_slug)
    get "/social-cards/venue/:city_slug/:venue_slug/:hash/*rest",
        VenueSocialCardController,
        :generate_card,
        as: :venue_social_card_cached

    # Performer social card generation (matches /performers/:slug)
    get "/social-cards/performer/:slug/:hash/*rest",
        PerformerSocialCardController,
        :generate_card,
        as: :performer_social_card_cached

    # Movie social card generation (matches /c/:city_slug/movies/:movie_slug)
    get "/social-cards/movie/:city_slug/:movie_slug/:hash/*rest",
        MovieSocialCardController,
        :generate_card,
        as: :movie_social_card_cached

    # Event social card generation (matches public event route at /:slug)
    get "/:slug/social-card-:hash/*rest", EventSocialCardController, :generate_card_by_slug,
      as: :social_card_cached

    # Poll social card generation (matches public poll route at /:slug/polls/:number)
    get "/:slug/polls/:number/social-card-:hash/*rest",
        PollSocialCardController,
        :generate_card_by_number,
        as: :poll_social_card_cached
  end

  # Public event routes (with theme support)
  live_session :public,
    on_mount: [{EventasaurusWeb.Live.AuthHooks, :assign_auth_user_and_theme}] do
    scope "/", EventasaurusWeb do
      pipe_through :browser

      # ===== SCRAPED/DISCOVERY EVENTS (from external APIs) =====
      # PublicEventsHomeLive - Discovery homepage with curated content
      live "/activities", PublicEventsHomeLive, :index
      live "/activities/:slug", PublicEventShowLive, :show
      live "/activities/:slug/:date_slug", PublicEventShowLive, :show

      # Multi-city aggregated content (trivia, movies, classes, etc. across all cities)
      # Uses explicit routes for each content type to prevent greedy matching
      # Pattern: /trivia/pubquiz-pl?scope=all&city=krakow
      # See AggregationTypeSlug for the complete list of valid content types
      live "/social/:identifier", AggregatedContentLive, :multi_city
      live "/food/:identifier", AggregatedContentLive, :multi_city

      # Movies index page - shows all movies currently in cinemas
      live "/movies", MoviesIndexLive, :index

      # Generic movie page - cross-site linking from Cinegraph
      # Identifier can be TMDB ID (e.g., /movies/157336) or slug-tmdb_id (e.g., /movies/interstellar-157336)
      live "/movies/:identifier", GenericMovieLive, :show
      live "/music/:identifier", AggregatedContentLive, :multi_city
      live "/happenings/:identifier", AggregatedContentLive, :multi_city
      live "/comedy/:identifier", AggregatedContentLive, :multi_city
      live "/dance/:identifier", AggregatedContentLive, :multi_city
      live "/classes/:identifier", AggregatedContentLive, :multi_city
      live "/festivals/:identifier", AggregatedContentLive, :multi_city
      live "/sports/:identifier", AggregatedContentLive, :multi_city
      live "/theater/:identifier", AggregatedContentLive, :multi_city

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

  # File upload API routes (require authentication)
  scope "/api/upload", EventasaurusWeb do
    pipe_through [:secure_api, :api_authenticated]

    post "/presign", UploadController, :presign
    delete "/", UploadController, :delete
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

  # Admin API routes for discovery/stats
  scope "/api/admin", EventasaurusWeb.Admin, as: :admin_api do
    pipe_through [:secure_api, :api_authenticated]

    get "/stats/source/:source_slug", SourceStatsController, :show
  end
end
