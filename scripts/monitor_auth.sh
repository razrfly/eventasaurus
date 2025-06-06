#!/bin/bash

# Authentication Monitoring Script for Eventasaurus
# Continuously monitors authentication endpoints and system health

set -e

MONITORING_INTERVAL=60  # seconds
LOG_FILE="/tmp/auth_monitoring.log"
ALERT_THRESHOLD_ERRORS=5
ALERT_THRESHOLD_RESPONSE_TIME=5  # seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_metric() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

check_auth_health() {
    local start_time=$(date +%s.%N)
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://eventasaur.us/health/auth" --max-time 10)
    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)
    
    if [ "$status_code" = "200" ]; then
        log_success "Auth health check OK - Response time: ${response_time}s"
        echo "healthy"
    else
        log_error "Auth health check FAILED - Status: $status_code"
        echo "unhealthy"
    fi
}

check_main_site() {
    local start_time=$(date +%s.%N)
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://eventasaur.us/" --max-time 10)
    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)
    
    if [ "$status_code" = "200" ]; then
        log_success "Main site OK - Response time: ${response_time}s"
        
        # Check if response time is concerning
        if (( $(echo "$response_time > $ALERT_THRESHOLD_RESPONSE_TIME" | bc -l) )); then
            log_warning "Slow response time: ${response_time}s (threshold: ${ALERT_THRESHOLD_RESPONSE_TIME}s)"
            send_alert "warning" "Slow response time detected: ${response_time}s"
        fi
    else
        log_error "Main site FAILED - Status: $status_code"
        send_alert "critical" "Main site unreachable - Status: $status_code"
    fi
}

check_auth_endpoints() {
    local endpoints=(
        "https://eventasaur.us/auth/login"
        "https://eventasaur.us/auth/register" 
        "https://eventasaur.us/auth/callback"
    )
    
    for endpoint in "${endpoints[@]}"; do
        local endpoint_name=$(basename "$endpoint")
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" --max-time 10)
        
        if [[ "$status_code" =~ ^(200|302)$ ]]; then
            log_success "Auth endpoint $endpoint_name OK - Status: $status_code"
        else
            log_error "Auth endpoint $endpoint_name FAILED - Status: $status_code"
            send_alert "high" "Authentication endpoint $endpoint_name failing - Status: $status_code"
        fi
    done
}

monitor_application_logs() {
    if command -v fly &> /dev/null && fly auth whoami &> /dev/null; then
        local error_count=$(fly logs --app eventasaurus | tail -100 | grep -cE "(ERROR|CRITICAL|FATAL)" || echo "0")
        log_metric "Recent error count: $error_count"
        
        if [ "$error_count" -gt "$ALERT_THRESHOLD_ERRORS" ]; then
            log_error "High error count detected: $error_count errors in recent logs"
            send_alert "high" "High error count: $error_count errors detected in application logs"
        fi
        
        # Check for specific authentication errors
        local auth_errors=$(fly logs --app eventasaurus | tail -100 | grep -cE "(auth|authentication|callback).*ERROR" || echo "0")
        if [ "$auth_errors" -gt 0 ]; then
            log_warning "Authentication-specific errors detected: $auth_errors"
            send_alert "medium" "Authentication errors detected: $auth_errors in recent logs"
        fi
    else
        log_warning "Cannot check application logs (fly CLI not available or not authenticated)"
    fi
}

check_database_health() {
    if command -v fly &> /dev/null && fly auth whoami &> /dev/null; then
        local db_check=$(fly ssh console --app eventasaurus -C "/app/bin/eventasaurus eval 'EventasaurusApp.Repo.query(\"SELECT 1\")'" 2>/dev/null)
        
        if echo "$db_check" | grep -q "ok"; then
            log_success "Database connectivity OK"
        else
            log_error "Database connectivity FAILED"
            send_alert "critical" "Database connection failed - check Supabase connectivity"
        fi
    else
        log_warning "Cannot check database health (fly CLI not available or not authenticated)"
    fi
}

send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log the alert locally
    echo "ALERT [$severity] $timestamp - $message" >> "$LOG_FILE"
    
    # Slack notification (if webhook URL is configured)
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local emoji="🔔"
        case "$severity" in
            "critical") emoji="🚨" ;;
            "high") emoji="⚠️" ;;
            "medium") emoji="⚡" ;;
            "warning") emoji="💛" ;;
        esac
        
        curl -X POST -H 'Content-type: application/json' \
          --data "{\"text\":\"$emoji [$severity] Eventasaurus Alert: $message - $timestamp\"}" \
          "$SLACK_WEBHOOK_URL" --silent || true
    fi
    
    # Email notification (if configured)
    if [ -n "$ALERT_EMAIL" ] && command -v mail &> /dev/null; then
        echo "$message - $timestamp" | mail -s "[$severity] Eventasaurus Alert" "$ALERT_EMAIL" || true
    fi
    
    # Console notification
    case "$severity" in
        "critical") log_error "ALERT: $message" ;;
        "high"|"medium") log_warning "ALERT: $message" ;;
        *) log_metric "ALERT: $message" ;;
    esac
}

generate_status_report() {
    echo ""
    echo "📊 Authentication Monitoring Status Report"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Monitoring interval: ${MONITORING_INTERVAL}s"
    echo "Log file: $LOG_FILE"
    echo ""
    echo "Recent activity:"
    tail -10 "$LOG_FILE" | grep -E "(SUCCESS|ERROR|WARNING)" || echo "No recent activity"
    echo ""
}

cleanup() {
    echo ""
    log_metric "Authentication monitoring stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main monitoring function
run_monitoring_cycle() {
    log_metric "Starting authentication monitoring cycle"
    
    # Core health checks
    local auth_health=$(check_auth_health)
    check_main_site
    check_auth_endpoints
    
    # Advanced checks (if available)
    monitor_application_logs
    check_database_health
    
    # Overall status assessment
    if [ "$auth_health" = "unhealthy" ]; then
        send_alert "critical" "Authentication health check failing - immediate attention required"
    fi
    
    log_metric "Monitoring cycle completed"
}

# Print startup information
echo "🔍 Eventasaurus Authentication Monitoring"
echo "=========================================="
echo "Starting continuous monitoring..."
echo "Interval: ${MONITORING_INTERVAL} seconds"
echo "Alert thresholds:"
echo "  - Error count: $ALERT_THRESHOLD_ERRORS"
echo "  - Response time: ${ALERT_THRESHOLD_RESPONSE_TIME}s"
echo ""
echo "Configuration:"
echo "  - Slack alerts: $([ -n "$SLACK_WEBHOOK_URL" ] && echo "Enabled" || echo "Disabled")"
echo "  - Email alerts: $([ -n "$ALERT_EMAIL" ] && echo "Enabled" || echo "Disabled")"
echo "  - Log file: $LOG_FILE"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Initial status report
generate_status_report

# Main monitoring loop
while true; do
    run_monitoring_cycle
    
    # Generate periodic status report (every 10 cycles)
    local cycle_count_file="/tmp/monitor_cycle_count"
    local cycle_count=1
    
    if [ -f "$cycle_count_file" ]; then
        cycle_count=$(cat "$cycle_count_file")
        cycle_count=$((cycle_count + 1))
    fi
    
    echo "$cycle_count" > "$cycle_count_file"
    
    if [ $((cycle_count % 10)) -eq 0 ]; then
        generate_status_report
    fi
    
    sleep "$MONITORING_INTERVAL"
done 