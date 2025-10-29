#!/bin/bash

# CI/CD Social Card Testing Script
# Runs comprehensive tests in CI/CD pipeline

set -e

echo ""
echo "======================================================================"
echo "🚀 CI/CD Social Card Test Suite"
echo "======================================================================"
echo ""

# Exit codes
EXIT_CODE=0

# Step 1: Code quality checks
echo "📝 Step 1: Code Quality Checks"
echo "----------------------------------------------------------------------"

echo "Running mix format check..."
if mix format --check-formatted; then
    echo "✅ Code formatting passed"
else
    echo "❌ Code formatting failed"
    EXIT_CODE=1
fi

echo ""
echo "Running mix compile with warnings as errors..."
if mix compile --warnings-as-errors; then
    echo "✅ Compilation passed"
else
    echo "❌ Compilation failed"
    EXIT_CODE=1
fi

echo ""

# Step 2: Unit tests
echo "🧪 Step 2: Unit Tests"
echo "----------------------------------------------------------------------"

echo "Running all tests..."
if mix test; then
    echo "✅ All tests passed"
else
    echo "❌ Some tests failed"
    EXIT_CODE=1
fi

echo ""

# Step 3: Performance tests
echo "⚡ Step 3: Performance Tests"
echo "----------------------------------------------------------------------"

echo "Running performance benchmarks..."
if mix test test/eventasaurus_web/controllers/social_card_performance_test.exs; then
    echo "✅ Performance tests passed"
else
    echo "❌ Performance tests failed"
    EXIT_CODE=1
fi

echo ""

# Step 4: Integration tests (if server is running)
echo "🔌 Step 4: Integration Tests"
echo "----------------------------------------------------------------------"

# Check if server is running
if curl -s -o /dev/null -w "%{http_code}" "${APP_URL:-http://localhost:4000}" | grep -q "200\|302\|301"; then
    echo "Server is running, executing integration tests..."

    if elixir test/validation/social_card_validator.exs; then
        echo "✅ Integration tests passed"
    else
        echo "❌ Integration tests failed"
        EXIT_CODE=1
    fi
else
    echo "⚠️  Server not running, skipping integration tests"
    echo "   Start server with: mix phx.server"
fi

echo ""

# Step 5: Coverage report
echo "📊 Step 5: Test Coverage"
echo "----------------------------------------------------------------------"

echo "Generating coverage report..."
if mix test --cover; then
    echo "✅ Coverage report generated"

    # Check coverage percentage (requires parsing coverage output)
    # This is a simple check, adjust based on your coverage tool
    if mix test --cover 2>&1 | grep -q "COV"; then
        echo "Coverage data available"
    fi
else
    echo "⚠️  Coverage report failed (tests may have failed)"
fi

echo ""

# Summary
echo "======================================================================"
echo "📊 CI/CD Test Summary"
echo "======================================================================"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ All CI/CD checks passed!"
    echo ""
    echo "Ready to deploy ✨"
else
    echo "❌ Some CI/CD checks failed"
    echo ""
    echo "Please review the errors above before deploying."
fi

echo ""
exit $EXIT_CODE
