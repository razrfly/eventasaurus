# Eventasaurus

Event management platform built with Phoenix LiveView.

## Development Setup

### Prerequisites
- Elixir 1.15 or later
- Phoenix 1.7 or later  
- PostgreSQL 14 or later
- Node.js 16 or later

### Initial Setup

1. **Install dependencies:**
   ```bash
   mix deps.get
   ```

2. **Install assets dependencies:**
   ```bash
   cd assets && npm install && cd ..
   ```

3. **Set up environment variables:**
   Copy the environment variables template and configure:
   ```bash
   # Add these to your shell profile (e.g., ~/.zshrc)
   # Required for development with Supabase
   export SUPABASE_URL=http://127.0.0.1:54321
   export SUPABASE_API_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
   export SUPABASE_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
   
   # Optional: Stripe configuration for currency management
   export STRIPE_SECRET_KEY=sk_test_your_stripe_test_key_here
   export STRIPE_CONNECT_CLIENT_ID=ca_your_connect_client_id_here
   
   # Optional: Analytics
   export POSTHOG_PUBLIC_API_KEY=your_posthog_key_here
   ```

4. **Set up the database:**
   ```bash
   mix ecto.setup
   ```

5. **Start the development server:**
   ```bash
   mix phx.server
   ```

Visit [`localhost:4000`](http://localhost:4000) to see the application.

## Stripe Configuration

Eventasaurus uses Stripe for payment processing and currency management. The app will work without Stripe configuration but with limited functionality.

### Without Stripe (Fallback Mode)
- Uses hardcoded currency list (73+ currencies)
- No live currency data from Stripe API
- No payment processing capabilities
- Regional currency grouping still works

### With Stripe (Full Functionality)
1. **Get your Stripe keys** from [Stripe Dashboard](https://dashboard.stripe.com/test/apikeys)
2. **Set environment variables:**
   ```bash
   export STRIPE_SECRET_KEY=sk_test_...  # Your test secret key
   export STRIPE_CONNECT_CLIENT_ID=ca_...  # For marketplace functionality
   ```
3. **Benefits:**
   - Live currency data from Stripe API
   - Up-to-date currency support based on country specs
   - Payment processing capabilities
   - Automatic currency list updates

### Development vs Production

**Development (dev.secret.exs):**
```elixir
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY") || "sk_test_YOUR_TEST_KEY_HERE",
  connect_client_id: System.get_env("STRIPE_CONNECT_CLIENT_ID") || "ca_YOUR_CONNECT_CLIENT_ID_HERE"
```

**Production (runtime.exs):**
```elixir
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  connect_client_id: System.get_env("STRIPE_CONNECT_CLIENT_ID")
```

## Environment Variables Reference

### Required for Production
- `SECRET_KEY_BASE` - Phoenix secret key base
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_API_KEY` - Supabase API key
- `SUPABASE_DATABASE_URL` - Supabase database connection string
- `RESEND_API_KEY` - Resend email service API key

### Optional for Enhanced Functionality
- `STRIPE_SECRET_KEY` - Stripe secret key for payment processing and live currency data
- `STRIPE_CONNECT_CLIENT_ID` - Stripe Connect client ID for marketplace functionality
- `POSTHOG_PUBLIC_API_KEY` - PostHog analytics API key
- `POSTHOG_PRIVATE_API_KEY` - PostHog private API key for analytics queries  
- `POSTHOG_PROJECT_ID` - PostHog project ID

## Currency Management System

Eventasaurus has a sophisticated currency management system:

### Components
1. **CurrencyHelpers** - Core currency utilities and validation
2. **StripeCurrencyService** - GenServer for fetching live Stripe currency data
3. **Grouped Currency Select** - UI component with regional grouping
4. **Currency Integration** - Unified across all forms (events, tickets, settings)

### Features
- ✅ **73+ supported currencies** with regional grouping
- ✅ **Live Stripe integration** with fallback to hardcoded list
- ✅ **User preferences** - respects user's default currency
- ✅ **Consistent validation** across all models (User, Event, Ticket, Order)
- ✅ **Smart caching** with 24-hour TTL
- ✅ **Graceful degradation** when Stripe API is unavailable

### CLI Commands
```bash
# Refresh currency data from Stripe API
mix currencies.refresh

# This command will:
# - Fetch latest currencies from Stripe API
# - Update the cache
# - Fall back to hardcoded currencies if API unavailable
```

## Testing

Run the full test suite:
```bash
mix test
```

Run specific tests:
```bash
# Currency system tests
mix test test/eventasaurus_web/services/stripe_currency_service_test.exs
mix test test/eventasaurus_web/helpers/currency_helpers_test.exs

# Feature tests
mix test test/eventasaurus_web/features/
```

## Project Structure

```
lib/
├── eventasaurus/          # Core business logic
├── eventasaurus_app/      # Application context
└── eventasaurus_web/      # Web interface
    ├── components/        # Reusable UI components
    ├── controllers/       # HTTP controllers
    ├── live/             # LiveView modules
    ├── services/         # Business services
    └── helpers/          # View helpers

test/
├── eventasaurus/         # Core logic tests
├── eventasaurus_app/     # Context tests
└── eventasaurus_web/     # Web layer tests
    ├── features/         # Integration tests
    ├── live/            # LiveView tests
    └── services/        # Service tests
```

## Common Development Tasks

### Adding a new currency
The system automatically fetches currencies from Stripe. For manual additions:
1. Add to fallback list in `StripeCurrencyService`
2. Add display name to `CurrencyHelpers.@currency_names`
3. Add regional mapping in `get_currency_region/1`

### Debugging currency issues
```bash
# Check current currency cache
iex -S mix
iex> EventasaurusWeb.Services.StripeCurrencyService.get_currencies()

# Force refresh
iex> EventasaurusWeb.Services.StripeCurrencyService.refresh_currencies()
```

### Working with forms
All currency selection forms use the standardized `currency_select` component:
```heex
<.currency_select 
  id="event_currency" 
  name="event[currency]" 
  value={@event.currency}
  use_stripe_data={true} 
/>
```

## Contributing

1. Follow Phoenix/Elixir conventions
2. Write tests for new features
3. Update documentation for API changes
4. Test both with and without Stripe configuration

## Deployment

See deployment documentation for production setup requirements including:
- Environment variables configuration
- Database setup
- Stripe webhook configuration
- SSL certificate setup 