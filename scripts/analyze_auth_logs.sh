#!/bin/bash

# Authentication Log Analysis Script for Eventasaurus
# Analyzes authentication-related logs for patterns and issues

set -e

TIMEFRAME="${1:-1h}"  # Default to last hour
OUTPUT_FORMAT="${2:-console}"  # console or json
LOG_SOURCE="fly logs --app eventasaurus"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo -e "${BLUE}🔍 Authentication Log Analysis (Last $TIMEFRAME)${NC}"
        echo "================================================"
        echo ""
    fi
}

print_section() {
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo -e "${YELLOW}$1${NC}"
        echo "---"
    fi
}

analyze_registration_attempts() {
    print_section "📝 Registration Attempts"
    
    local reg_logs=$($LOG_SOURCE | grep "registration_attempt" | tail -50)
    local reg_count=$(echo "$reg_logs" | grep -c "registration_attempt" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo "Total registration attempts: $reg_count"
        echo ""
        if [ "$reg_count" -gt 0 ]; then
            echo "Recent attempts:"
            echo "$reg_logs" | tail -10
        else
            echo "No registration attempts found in recent logs"
        fi
        echo ""
    fi
    
    # Return data for JSON output
    echo "reg_count:$reg_count"
}

analyze_email_delivery() {
    print_section "📧 Email Delivery"
    
    local email_logs=$($LOG_SOURCE | grep "email_sent" | tail -30)
    local email_count=$(echo "$email_logs" | grep -c "email_sent" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo "Total emails sent: $email_count"
        echo ""
        if [ "$email_count" -gt 0 ]; then
            echo "Recent email deliveries:"
            echo "$email_logs" | tail -10
        else
            echo "No email deliveries found in recent logs"
        fi
        echo ""
    fi
    
    echo "email_count:$email_count"
}

analyze_callback_attempts() {
    print_section "🔗 Callback Attempts"
    
    local callback_logs=$($LOG_SOURCE | grep "callback_attempt" | tail -30)
    local callback_count=$(echo "$callback_logs" | grep -c "callback_attempt" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo "Total callback attempts: $callback_count"
        echo ""
        if [ "$callback_count" -gt 0 ]; then
            echo "Recent callbacks:"
            echo "$callback_logs" | tail -10
        else
            echo "No callback attempts found in recent logs"
        fi
        echo ""
    fi
    
    echo "callback_count:$callback_count"
}

analyze_errors() {
    print_section "❌ Errors"
    
    local error_logs=$($LOG_SOURCE | grep -E "(ERROR|CRITICAL|FATAL)" | tail -30)
    local error_count=$(echo "$error_logs" | grep -cE "(ERROR|CRITICAL|FATAL)" 2>/dev/null || echo "0")
    
    # Specifically look for authentication errors
    local auth_error_logs=$($LOG_SOURCE | grep -E "(auth|authentication|callback).*ERROR" | tail -20)
    local auth_error_count=$(echo "$auth_error_logs" | grep -cE "ERROR" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo "Total errors: $error_count"
        echo "Authentication-specific errors: $auth_error_count"
        echo ""
        
        if [ "$error_count" -gt 0 ]; then
            echo "Recent errors:"
            echo "$error_logs" | tail -10
            echo ""
        fi
        
        if [ "$auth_error_count" -gt 0 ]; then
            echo "Authentication errors:"
            echo "$auth_error_logs"
            echo ""
        fi
        
        if [ "$error_count" -eq 0 ] && [ "$auth_error_count" -eq 0 ]; then
            echo -e "${GREEN}No errors found in recent logs ✅${NC}"
            echo ""
        fi
    fi
    
    echo "error_count:$error_count"
    echo "auth_error_count:$auth_error_count"
}

analyze_response_times() {
    print_section "⏱️  Response Times"
    
    local response_logs=$($LOG_SOURCE | grep -E "completed in [0-9]+ms" | tail -50)
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        if [ -n "$response_logs" ]; then
            echo "Recent response times:"
            echo "$response_logs" | grep -E "completed in [0-9]+ms" | tail -10
            
            # Calculate average response time if possible
            local times=$(echo "$response_logs" | grep -oE "[0-9]+ms" | sed 's/ms//' | head -20)
            if [ -n "$times" ]; then
                local total=0
                local count=0
                for time in $times; do
                    total=$((total + time))
                    count=$((count + 1))
                done
                
                if [ "$count" -gt 0 ]; then
                    local avg=$((total / count))
                    echo ""
                    echo "Average response time (last 20 requests): ${avg}ms"
                    
                    if [ "$avg" -gt 5000 ]; then
                        echo -e "${RED}⚠️  High average response time detected${NC}"
                    elif [ "$avg" -gt 2000 ]; then
                        echo -e "${YELLOW}⚠️  Elevated response times${NC}"
                    else
                        echo -e "${GREEN}✅ Response times look good${NC}"
                    fi
                fi
            fi
        else
            echo "No response time data found in recent logs"
        fi
        echo ""
    fi
}

analyze_user_patterns() {
    print_section "👥 User Patterns"
    
    local user_logs=$($LOG_SOURCE | grep -E "(user_id|email)" | tail -50)
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        # Extract email domains if possible
        local domains=$(echo "$user_logs" | grep -oE "@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | sort | uniq -c | sort -nr | head -10)
        
        if [ -n "$domains" ]; then
            echo "Top email domains:"
            echo "$domains"
        else
            echo "No user pattern data found in recent logs"
        fi
        echo ""
    fi
}

generate_summary_statistics() {
    print_section "📊 Summary Statistics"
    
    # Parse previously gathered data
    local reg_count=$(grep "reg_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local email_count=$(grep "email_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local callback_count=$(grep "callback_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local error_count=$(grep "error_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local auth_error_count=$(grep "auth_error_count:" /tmp/auth_analysis_data | cut -d: -f2)
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo "Registration attempts: $reg_count"
        echo "Emails sent: $email_count"
        echo "Callbacks processed: $callback_count"
        echo "Total errors: $error_count"
        echo "Authentication errors: $auth_error_count"
        echo ""
        
        # Calculate success rates
        if [ "$reg_count" -gt 0 ]; then
            local email_rate=$(echo "scale=1; $email_count * 100 / $reg_count" | bc 2>/dev/null || echo "0")
            echo "Email delivery rate: ${email_rate}%"
        fi
        
        if [ "$email_count" -gt 0 ]; then
            local callback_rate=$(echo "scale=1; $callback_count * 100 / $email_count" | bc 2>/dev/null || echo "0")
            echo "Email confirmation rate: ${callback_rate}%"
        fi
        
        if [ "$reg_count" -gt 0 ]; then
            local error_rate=$(echo "scale=1; $error_count * 100 / $reg_count" | bc 2>/dev/null || echo "0")
            echo "Error rate: ${error_rate}%"
            
            # Color-code error rate
            if (( $(echo "$error_rate > 10" | bc -l 2>/dev/null || echo "0") )); then
                echo -e "${RED}⚠️  High error rate detected${NC}"
            elif (( $(echo "$error_rate > 5" | bc -l 2>/dev/null || echo "0") )); then
                echo -e "${YELLOW}⚠️  Elevated error rate${NC}"
            else
                echo -e "${GREEN}✅ Error rate looks good${NC}"
            fi
        fi
        echo ""
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        # Output JSON format
        cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "timeframe": "$TIMEFRAME",
  "metrics": {
    "registration_attempts": $reg_count,
    "emails_sent": $email_count,
    "callbacks_processed": $callback_count,
    "total_errors": $error_count,
    "auth_errors": $auth_error_count,
    "email_delivery_rate": $([ "$reg_count" -gt 0 ] && echo "scale=1; $email_count * 100 / $reg_count" | bc || echo "0"),
    "confirmation_rate": $([ "$email_count" -gt 0 ] && echo "scale=1; $callback_count * 100 / $email_count" | bc || echo "0"),
    "error_rate": $([ "$reg_count" -gt 0 ] && echo "scale=1; $error_count * 100 / $reg_count" | bc || echo "0")
  }
}
EOF
    fi
}

generate_recommendations() {
    if [ "$OUTPUT_FORMAT" != "console" ]; then
        return
    fi
    
    print_section "💡 Recommendations"
    
    local reg_count=$(grep "reg_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local email_count=$(grep "email_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local callback_count=$(grep "callback_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local error_count=$(grep "error_count:" /tmp/auth_analysis_data | cut -d: -f2)
    local auth_error_count=$(grep "auth_error_count:" /tmp/auth_analysis_data | cut -d: -f2)
    
    local recommendations=()
    
    # Check email delivery rate
    if [ "$reg_count" -gt 0 ] && [ "$email_count" -gt 0 ]; then
        local email_rate=$(echo "scale=0; $email_count * 100 / $reg_count" | bc)
        if [ "$email_rate" -lt 95 ]; then
            recommendations+=("🔧 Email delivery rate is ${email_rate}% - investigate email service issues")
        fi
    fi
    
    # Check confirmation rate
    if [ "$email_count" -gt 0 ] && [ "$callback_count" -gt 0 ]; then
        local callback_rate=$(echo "scale=0; $callback_count * 100 / $email_count" | bc)
        if [ "$callback_rate" -lt 50 ]; then
            recommendations+=("📧 Email confirmation rate is ${callback_rate}% - consider improving email content or delivery time")
        fi
    fi
    
    # Check error rates
    if [ "$error_count" -gt 10 ]; then
        recommendations+=("❌ High error count ($error_count) - investigate application logs immediately")
    fi
    
    if [ "$auth_error_count" -gt 3 ]; then
        recommendations+=("🔐 Authentication errors detected ($auth_error_count) - review auth flow configuration")
    fi
    
    # Output recommendations
    if [ ${#recommendations[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All metrics look healthy - no immediate action required${NC}"
    else
        for rec in "${recommendations[@]}"; do
            echo "$rec"
        done
    fi
    echo ""
}

check_system_health() {
    if [ "$OUTPUT_FORMAT" != "console" ]; then
        return
    fi
    
    print_section "🏥 System Health Check"
    
    # Quick health check of the main endpoints
    local main_status=$(curl -s -o /dev/null -w "%{http_code}" "https://eventasaur.us/" --max-time 10 || echo "000")
    local auth_status=$(curl -s -o /dev/null -w "%{http_code}" "https://eventasaur.us/health/auth" --max-time 10 || echo "000")
    
    echo "Main site status: $main_status $([ "$main_status" = "200" ] && echo "✅" || echo "❌")"
    echo "Auth health endpoint: $auth_status $([ "$auth_status" = "200" ] && echo "✅" || echo "❌")"
    echo ""
}

# Main execution
main() {
    # Create temporary file for data sharing between functions
    echo "" > /tmp/auth_analysis_data
    
    print_header
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        echo "Analyzing authentication logs for the last $TIMEFRAME..."
        echo ""
    fi
    
    # Run analysis functions and collect data
    analyze_registration_attempts >> /tmp/auth_analysis_data
    analyze_email_delivery >> /tmp/auth_analysis_data
    analyze_callback_attempts >> /tmp/auth_analysis_data
    analyze_errors >> /tmp/auth_analysis_data
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        analyze_response_times
        analyze_user_patterns
    fi
    
    generate_summary_statistics
    
    if [ "$OUTPUT_FORMAT" = "console" ]; then
        generate_recommendations
        check_system_health
        
        echo "Analysis completed at $(date)"
        echo ""
        echo "💡 Tip: Run with 'json' as second parameter for machine-readable output"
        echo "Example: $0 1h json"
    fi
    
    # Cleanup
    rm -f /tmp/auth_analysis_data
}

# Show usage if invalid parameters
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [timeframe] [format]"
    echo ""
    echo "Parameters:"
    echo "  timeframe  Time period to analyze (default: 1h)"
    echo "             Examples: 30m, 1h, 6h, 1d"
    echo "  format     Output format: console or json (default: console)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Analyze last hour, console output"
    echo "  $0 6h                 # Analyze last 6 hours, console output"
    echo "  $0 1h json            # Analyze last hour, JSON output"
    echo ""
    exit 0
fi

# Run main function
main 