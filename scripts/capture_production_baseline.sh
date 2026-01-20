#!/bin/bash
# Production Baseline Capture Script
# Captures TTFB (Time to First Byte) for city pages from production
#
# Usage:
#   ./scripts/capture_production_baseline.sh [city_slug] [iterations]
#
# Examples:
#   ./scripts/capture_production_baseline.sh krakow 5
#   ./scripts/capture_production_baseline.sh warsaw 10

CITY=${1:-krakow}
ITERATIONS=${2:-5}
BASE_URL="https://wombie.com"

echo "========================================================================"
echo "Production City Page Baseline Capture"
echo "========================================================================"
echo "City: $CITY"
echo "Iterations: $ITERATIONS"
echo "URL: $BASE_URL/$CITY"
echo ""

# Array to store results
declare -a ttfb_times
declare -a total_times

echo "Running $ITERATIONS iterations..."
echo ""

for i in $(seq 1 $ITERATIONS); do
    # Use curl with timing output
    # time_namelookup: DNS lookup
    # time_connect: TCP connection
    # time_starttransfer: TTFB (time to first byte)
    # time_total: Total time

    result=$(curl -s -o /dev/null -w "%{time_namelookup},%{time_connect},%{time_starttransfer},%{time_total}" "$BASE_URL/$CITY")

    IFS=',' read -r dns connect ttfb total <<< "$result"

    # Convert to milliseconds
    ttfb_ms=$(echo "$ttfb * 1000" | bc)
    total_ms=$(echo "$total * 1000" | bc)

    ttfb_times+=("$ttfb_ms")
    total_times+=("$total_ms")

    printf "  Iteration %d: TTFB=%.0fms, Total=%.0fms\n" "$i" "$ttfb_ms" "$total_ms"

    # Small delay between requests to avoid rate limiting
    sleep 0.5
done

echo ""
echo "------------------------------------------------------------------------"
echo "RESULTS SUMMARY"
echo "------------------------------------------------------------------------"

# Calculate statistics
calc_stats() {
    local arr=("$@")
    local sum=0
    local min=999999
    local max=0

    for val in "${arr[@]}"; do
        sum=$(echo "$sum + $val" | bc)
        if (( $(echo "$val < $min" | bc -l) )); then min=$val; fi
        if (( $(echo "$val > $max" | bc -l) )); then max=$val; fi
    done

    local avg=$(echo "scale=1; $sum / ${#arr[@]}" | bc)

    # Sort for P50
    IFS=$'\n' sorted=($(sort -n <<< "${arr[*]}")); unset IFS
    local mid=$((${#sorted[@]} / 2))
    local p50=${sorted[$mid]}

    echo "$avg $min $max $p50"
}

read avg_ttfb min_ttfb max_ttfb p50_ttfb <<< $(calc_stats "${ttfb_times[@]}")
read avg_total min_total max_total p50_total <<< $(calc_stats "${total_times[@]}")

echo ""
echo "TTFB (Time to First Byte):"
printf "  Average: %.0fms\n" "$avg_ttfb"
printf "  Min:     %.0fms\n" "$min_ttfb"
printf "  Max:     %.0fms\n" "$max_ttfb"
printf "  P50:     %.0fms\n" "$p50_ttfb"

echo ""
echo "Total Response Time:"
printf "  Average: %.0fms\n" "$avg_total"
printf "  Min:     %.0fms\n" "$min_total"
printf "  Max:     %.0fms\n" "$max_total"
printf "  P50:     %.0fms\n" "$p50_total"

echo ""
echo "========================================================================"

# Save to file if requested
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASELINE_DIR=".baselines"
mkdir -p "$BASELINE_DIR"

FILENAME="$BASELINE_DIR/prod_${CITY}_${TIMESTAMP}.json"

cat > "$FILENAME" << EOF
{
  "city": "$CITY",
  "url": "$BASE_URL/$CITY",
  "iterations": $ITERATIONS,
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ttfb": {
    "avg_ms": $avg_ttfb,
    "min_ms": $min_ttfb,
    "max_ms": $max_ttfb,
    "p50_ms": $p50_ttfb
  },
  "total": {
    "avg_ms": $avg_total,
    "min_ms": $min_total,
    "max_ms": $max_total,
    "p50_ms": $p50_total
  }
}
EOF

echo "Baseline saved to: $FILENAME"
echo ""
echo "To view internal telemetry from production, run:"
echo "  fly logs -a wombie | grep 'CityPage'"
