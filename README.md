# Eventasaurus 🦕

A modern event planning and management platform built with Phoenix LiveView, designed to help groups organize activities, coordinate schedules, and track shared experiences.

## Features

- **Event Creation & Management**: Create and manage events with rich details, themes, and customization options
- **Group Organization**: Form groups, manage memberships, and coordinate group activities
- **Polling System**: Democratic decision-making with various poll types (dates, activities, movies, restaurants)
- **Activity Tracking**: Track and log group activities with ratings and reviews
- **Real-time Updates**: LiveView-powered real-time interactions without page refreshes
- **Ticketing System**: Optional ticketing and payment processing via Stripe
- **Responsive Design**: Mobile-first design with Tailwind CSS
- **Soft Delete**: Data preservation with recovery options

## Tech Stack

- **Backend**: Elixir/Phoenix 1.7
- **Frontend**: Phoenix LiveView, Tailwind CSS, Alpine.js
- **Database**: PostgreSQL 14+ (via Supabase)
- **Authentication**: Supabase Auth
- **Payments**: Stripe (optional)
- **Analytics**: PostHog (optional)
- **Testing**: ExUnit, Wallaby (E2E)

## Prerequisites

- Elixir 1.15 or later
- Phoenix 1.7 or later
- PostgreSQL 14 or later
- Node.js 16 or later
- Supabase CLI (for local development)

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/razrfly/eventasaurus.git
cd eventasaurus
```

### 2. Install dependencies

```bash
# Elixir dependencies
mix deps.get

# JavaScript dependencies
cd assets && npm install && cd ..
```

### 3. Set up environment variables

Create a `.env` file in the project root or add these to your shell profile:

```bash
# Required: Supabase (local development)
export SUPABASE_URL=http://127.0.0.1:54321
export SUPABASE_API_KEY=your_supabase_anon_key
export SUPABASE_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres

# Optional: External services
export STRIPE_SECRET_KEY=sk_test_your_stripe_test_key
export STRIPE_CONNECT_CLIENT_ID=ca_your_connect_client_id
export POSTHOG_PUBLIC_API_KEY=your_posthog_key
export GOOGLE_MAPS_API_KEY=your_google_maps_key
export TMDB_API_KEY=your_tmdb_api_key
export RESEND_API_KEY=your_resend_api_key
```

### 4. Start Supabase locally

```bash
# Install Supabase CLI if you haven't already
brew install supabase/tap/supabase

# Start Supabase
supabase start
```

### 5. Set up the database

```bash
# Create and migrate the database
mix ecto.setup

# Or if the database already exists
mix ecto.migrate
```

### 6. Seed development data with authenticated users

For the seeding to create users that can actually log in, you need the Supabase service role key:

```bash
# Get the service role key from Supabase
supabase status | grep "service_role key"

# Export it for the current session
export SUPABASE_SERVICE_ROLE_KEY_LOCAL="<your-service-role-key>"

# Run the main seeds (creates holden@gmail.com account)
mix run priv/repo/seeds.exs

mix seed.dev --users 5 --events 10 --groups 2
```

### 7. Start the Phoenix server

```bash
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Development Commands

### Database Management

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Reset and seed with dev data
mix ecto.reset.dev

# Drop and recreate Supabase database completely
supabase db reset
```

#### Complete Database Reset with Authenticated Users

When you need to completely reset everything and create users that can log in:

```bash
# 1. Reset Supabase database (clears everything including auth users)
supabase db reset

# 2. Get and export the service role key
supabase status | grep "service_role key"
export SUPABASE_SERVICE_ROLE_KEY_LOCAL="<your-service-role-key>"

# 3. Run migrations
mix ecto.migrate

# 4. Create personal login account
mix run priv/repo/seeds.exs

# 5. Create test accounts and development data
mix seed.dev --users 5 --events 10 --groups 2
```

### Development Seeding

The project includes comprehensive development seeding using Faker and ExMachina:

```bash
# Seed with default configuration (50 users, 100 events, 15 groups)
mix seed.dev

# Seed with custom quantities
mix seed.dev --users 100 --events 200 --groups 30

# Seed specific entities only
mix seed.dev --only users,events

# Add data without cleaning existing
mix seed.dev --append

# Clean all seeded data
mix seed.clean

# Clean specific entity types
mix seed.clean --only events,polls,activities

# Reset and seed in one command
mix ecto.reset.dev
```

#### Seeded Data Includes:
- **Users**: Realistic profiles with names, emails, bios, social handles
- **Groups**: Various group sizes with members and roles
- **Events**: Past, current, and future events in different states (draft, polling, confirmed, canceled)
- **Participants**: Event attendees with various RSVP statuses
- **Activities**: Historical activity records for completed events
- **Venues**: Physical and virtual venue information

#### Test Accounts:
The seeding process creates test accounts you can use for development:

**Personal Login (created via seeds.exs):**
- Email: `holden@gmail.com`
- Password: `sawyer1234`

**Test Accounts (created via dev seeds with SUPABASE_SERVICE_ROLE_KEY_LOCAL):**
- Admin: `admin@example.com` / `testpass123`
- Demo: `demo@example.com` / `testpass123`

Note: All seeded accounts have auto-confirmed emails for immediate login in the dev environment.

### Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/eventasaurus_web/live/event_live_test.exs

# Run tests with coverage
mix test --cover

# Run tests in watch mode
mix test.watch
```

### Code Quality

```bash
# Format code
mix format

# Run linter
mix credo

# Run dialyzer for type checking
mix dialyzer

# Check for security vulnerabilities
mix sobelow
```

### Asset Management

```bash
# Build assets for development
mix assets.build

# Build assets for production
mix assets.deploy

# Watch assets for changes
mix assets.watch
```

## Project Structure

```
eventasaurus/
├── assets/              # JavaScript, CSS, and static assets
├── config/              # Configuration files
├── lib/
│   ├── eventasaurus/    # Business logic
│   │   ├── accounts/    # User management
│   │   ├── events/      # Event, polls, activities
│   │   ├── groups/      # Group management
│   │   └── venues/      # Venue management
│   ├── eventasaurus_web/ # Web layer
│   │   ├── components/  # Reusable LiveView components
│   │   ├── live/        # LiveView modules
│   │   └── controllers/ # Traditional controllers
│   └── mix/
│       └── tasks/       # Custom mix tasks (seed.dev, etc.)
├── priv/
│   ├── repo/
│   │   ├── migrations/  # Database migrations
│   │   ├── seeds.exs    # Production seeds
│   │   └── dev_seeds/   # Development seed modules
│   └── static/          # Static files
├── test/                # Test files
│   └── support/
│       └── factory.ex   # Test factories (ExMachina)
└── .formatter.exs       # Code formatter config
```

## Key Concepts

### Event Lifecycle
Events progress through various states:
1. **Draft**: Initial creation, editing details
2. **Polling**: Collecting availability and preferences
3. **Threshold**: Waiting for minimum participants
4. **Confirmed**: Event is happening
5. **Canceled**: Event was canceled

### Polling System
- **Date Polls**: Find the best date for an event
- **Activity Polls**: Vote on movies, restaurants, activities
- **Generic Polls**: Custom decision-making
- Supports multiple voting systems (single choice, multiple choice, ranked)

### Soft Delete
Most entities support soft delete, allowing data recovery:
- Events, polls, users, and groups can be soft-deleted
- Deleted items are excluded from queries by default
- Can be restored through the admin interface

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Format your code (`mix format`)
6. Commit your changes (`git commit -m 'Add some amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## Troubleshooting

### Common Issues

**Database connection errors:**
- Ensure PostgreSQL/Supabase is running
- Check DATABASE_URL in your environment

**Asset compilation errors:**
- Run `cd assets && npm install`
- Clear build cache: `rm -rf _build deps`

**Seeding errors:**
- Ensure database is migrated: `mix ecto.migrate`
- Check for unique constraint violations
- Try cleaning first: `mix seed.clean`

## License

This project is proprietary software. All rights reserved.

## Support

For issues and questions, please open an issue on GitHub or contact the maintainers.

---

Built with ❤️ using Elixir and Phoenix LiveView