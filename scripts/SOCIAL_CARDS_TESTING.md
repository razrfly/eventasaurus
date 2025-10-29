# Social Card Testing Scripts

Automated scripts for testing, validation, and CI/CD integration of social cards.

---

## Available Scripts

### `validate_social_cards.sh`

**Purpose:** Validates social card endpoints, meta tags, and performance

**Usage:**
```bash
# Test against local development server
APP_URL=http://localhost:4000 ./scripts/validate_social_cards.sh

# Test against staging server
APP_URL=https://staging.wombie.com ./scripts/validate_social_cards.sh

# Test against production
APP_URL=https://wombie.com ./scripts/validate_social_cards.sh

# Verbose mode
VERBOSE=1 APP_URL=http://localhost:4000 ./scripts/validate_social_cards.sh
```

**What It Tests:**
- Server connectivity
- Social card endpoint responses (200, content-type, cache headers, ETag)
- Meta tags (Open Graph, Twitter Cards)
- JSON-LD structured data
- Canonical URLs
- Performance (response times)
- Image dimensions (requires ImageMagick)
- Image file sizes

**Requirements:**
- `curl` (required)
- `jq` (optional, for JSON validation)
- `identify` from ImageMagick (optional, for image dimension checks)

**Exit Codes:**
- `0`: All tests passed (may have warnings)
- `1`: Some tests failed

---

### `ci_social_card_tests.sh`

**Purpose:** Runs comprehensive test suite for CI/CD pipelines

**Usage:**
```bash
# Run all CI/CD checks
./scripts/ci_social_card_tests.sh

# With custom app URL
APP_URL=https://staging.wombie.com ./scripts/ci_social_card_tests.sh
```

**What It Tests:**
1. Code quality checks
   - Code formatting (`mix format --check-formatted`)
   - Compilation warnings (`mix compile --warnings-as-errors`)

2. Unit tests
   - All ExUnit tests (`mix test`)

3. Performance tests
   - Social card generation benchmarks
   - Response time validation
   - Memory usage checks

4. Integration tests (if server running)
   - Live endpoint validation
   - Real HTTP requests

5. Test coverage
   - Coverage report generation
   - Coverage percentage (if configured)

**Requirements:**
- Elixir and Mix
- Phoenix server (for integration tests)
- All project dependencies installed

**Exit Codes:**
- `0`: All checks passed
- `1`: One or more checks failed

---

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/social-cards.yml`:

```yaml
name: Social Cards Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y librsvg2-bin imagemagick jq
          mix deps.get

      - name: Run CI test suite
        run: ./scripts/ci_social_card_tests.sh
        env:
          MIX_ENV: test
          DATABASE_URL: postgresql://postgres:postgres@localhost/eventasaurus_test

      - name: Start server for integration tests
        run: |
          mix phx.server &
          sleep 10

      - name: Run validation script
        run: ./scripts/validate_social_cards.sh
        env:
          APP_URL: http://localhost:4000
```

### GitLab CI Example

Create `.gitlab-ci.yml`:

```yaml
test:social-cards:
  stage: test
  image: elixir:1.15
  services:
    - postgres:15
  variables:
    MIX_ENV: test
    POSTGRES_DB: eventasaurus_test
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    DATABASE_URL: postgresql://postgres:postgres@postgres/eventasaurus_test
  before_script:
    - apt-get update
    - apt-get install -y librsvg2-bin imagemagick jq curl
    - mix local.hex --force
    - mix local.rebar --force
    - mix deps.get
  script:
    - ./scripts/ci_social_card_tests.sh
    - mix phx.server &
    - sleep 10
    - ./scripts/validate_social_cards.sh
```

---

## Local Development Workflow

### Pre-Commit Checks

Run before committing changes:

```bash
# Quick validation
./scripts/ci_social_card_tests.sh

# Full validation with live server
mix phx.server &
sleep 5
./scripts/validate_social_cards.sh
```

### Pre-Deployment Checks

Run before deploying to staging or production:

```bash
# 1. Run CI suite
./scripts/ci_social_card_tests.sh

# 2. Deploy to staging
# (your deployment command)

# 3. Validate staging
APP_URL=https://staging.wombie.com ./scripts/validate_social_cards.sh

# 4. If all pass, deploy to production
# (your deployment command)

# 5. Validate production
APP_URL=https://wombie.com ./scripts/validate_social_cards.sh
```

---

## Troubleshooting

### Script Permission Denied

```bash
chmod +x scripts/*.sh
```

### Server Not Running Error

Integration tests require Phoenix server to be running:

```bash
# Terminal 1: Start server
mix phx.server

# Terminal 2: Run tests
./scripts/validate_social_cards.sh
```

### Missing Dependencies

Install required tools:

```bash
# macOS
brew install imagemagick jq

# Ubuntu/Debian
sudo apt-get install imagemagick jq librsvg2-bin

# Fedora/RHEL
sudo dnf install ImageMagick jq librsvg2-tools
```

### False Positives

Some tests may show warnings for sample data that doesn't exist:

```bash
# Use verbose mode to see details
VERBOSE=1 ./scripts/validate_social_cards.sh
```

---

## Adding New Validation Tests

To add new tests to `validate_social_cards.sh`:

1. Add new test section:

```bash
# Test X: Description
echo "🔍 Testing Feature X..."

# Your test logic here
if [ condition ]; then
    pass "Feature X works"
else
    fail "Feature X failed"
fi

echo ""
```

2. Update counters automatically (using `pass`, `fail`, `warn` helpers)

3. Tests appear in summary automatically

---

## Related Documentation

- [Testing Checklist](../docs/testing_checklist.md)
- [Platform Validation Guide](../docs/platform_validation_guide.md)
- [SEO Best Practices](../docs/seo_best_practices.md)

---

**Last Updated:** 2025-01-29
