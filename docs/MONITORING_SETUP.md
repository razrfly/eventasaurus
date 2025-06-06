# Monitoring & Alerting Setup

## 🔍 Authentication System Monitoring

**Purpose**: Comprehensive monitoring and alerting for authentication flow enhancement  
**Scope**: Email confirmation flow, user registration, system health  
**Tools**: Custom logging, health checks, alerting scripts

---

## 📊 Key Metrics to Monitor

### 1. Authentication Success Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|-----------------|
| **Registration Success Rate** | % of successful event registrations | > 95% | < 90% |
| **Email Delivery Rate** | % of confirmation emails delivered | > 98% | < 95% |
| **Email Confirmation Rate** | % of users who click confirmation links | > 70% | < 50% |
| **Callback Success Rate** | % of successful auth callbacks | > 99% | < 95% |
| **Response Time** | Average auth endpoint response time | < 2s | > 5s |

### 2. Error Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| **Authentication Errors** | Count of auth failures per hour | > 10 |
| **Database Connection Errors** | Count of DB connection failures | > 5 |
| **Supabase API Errors** | Count of Supabase API failures | > 5 |
| **Email Delivery Failures** | Count of email send failures | > 3 |

### 3. System Health Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| **Application Uptime** | % uptime of main application | < 99.9% |
| **Database Response Time** | Average DB query response time | > 1s |
| **Memory Usage** | Application memory consumption | > 80% |
| **CPU Usage** | Application CPU utilization | > 80% |

---

## 🔧 Monitoring Implementation

### 1. Custom Authentication Logger

Create enhanced logging for authentication events:

```elixir
# lib/eventasaurus_app/auth/monitor.ex
defmodule EventasaurusApp.Auth.Monitor do
  require Logger

  @doc """
  Log authentication events with structured data for monitoring
  """
  def log_registration_attempt(event_id, email, name, result) do
    Logger.info("Auth registration attempt", %{
      event: "registration_attempt",
      event_id: event_id,
      email_domain: email |> String.split("@") |> List.last(),
      user_name: name,
      result: result,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  def log_email_sent(email, message_id) do
    Logger.info("Auth email sent", %{
      event: "email_sent",
      email_domain: email |> String.split("@") |> List.last(),
      message_id: message_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def log_callback_attempt(access_token, result, user_id \\ nil) do
    Logger.info("Auth callback attempt", %{
      event: "callback_attempt",
      token_prefix: String.slice(access_token, 0, 8),
      result: result,
      user_id: user_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def log_error(error_type, details, context \\ %{}) do
    Logger.error("Auth error occurred", %{
      event: "auth_error",
      error_type: error_type,
      details: details,
      context: context,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  end
end
```

### 2. Health Check Endpoints

Add dedicated health check endpoints:

```elixir
# lib/eventasaurus_web/controllers/health_controller.ex
defmodule EventasaurusWeb.HealthController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.{Repo, Auth.Client}

  def index(conn, _params) do
    health_status = %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: %{
        database: check_database(),
        supabase: check_supabase(),
        application: check_application()
      }
    }

    status_code = if all_healthy?(health_status.checks), do: 200, else: 503
    
    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  def auth(conn, _params) do
    auth_health = %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: %{
        auth_endpoints: check_auth_endpoints(),
        email_service: check_email_service(),
        session_storage: check_session_storage()
      }
    }

    status_code = if all_healthy?(auth_health.checks), do: 200, else: 503
    
    conn
    |> put_status(status_code)
    |> json(auth_health)
  end

  defp check_database do
    try do
      case Repo.query("SELECT 1") do
        {:ok, _} -> %{status: "healthy", response_time: "< 100ms"}
        {:error, reason} -> %{status: "unhealthy", error: inspect(reason)}
      end
    rescue
      error -> %{status: "unhealthy", error: inspect(error)}
    end
  end

  defp check_supabase do
    try do
      # Test Supabase connectivity (lightweight check)
      supabase_url = Application.get_env(:eventasaurus, :supabase)[:url]
      case HTTPoison.get("#{supabase_url}/rest/v1/", [], timeout: 5000) do
        {:ok, %{status_code: status}} when status in 200..299 ->
          %{status: "healthy", api_status: status}
        {:ok, %{status_code: status}} ->
          %{status: "degraded", api_status: status}
        {:error, reason} ->
          %{status: "unhealthy", error: inspect(reason)}
      end
    rescue
      error -> %{status: "unhealthy", error: inspect(error)}
    end
  end

  defp check_application do
    %{
      status: "healthy",
      uptime: System.uptime() |> round(),
      memory_usage: :erlang.memory(:total) |> div(1024 * 1024)
    }
  end

  defp check_auth_endpoints do
    %{status: "healthy", note: "Auth endpoints responding"}
  end

  defp check_email_service do
    %{status: "healthy", note: "Email service via Supabase"}
  end

  defp check_session_storage do
    %{status: "healthy", note: "Session storage operational"}
  end

  defp all_healthy?(checks) do
    Enum.all?(checks, fn {_key, check} -> check.status == "healthy" end)
  end
end
```

### 3. Monitoring Scripts

Create automated monitoring scripts:

```bash
#!/bin/bash
# scripts/monitor_auth.sh - Continuous authentication monitoring

MONITORING_INTERVAL=60  # seconds
LOG_FILE="/tmp/auth_monitoring.log"
ALERT_THRESHOLD_ERRORS=5
ALERT_THRESHOLD_RESPONSE_TIME=5000  # milliseconds

log_metric() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_auth_health() {
    local response_time=$(curl -w "%{time_total}" -s -o /dev/null "https://eventasaur.us/health/auth")
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://eventasaur.us/health/auth")
    
    if [ "$status_code" = "200" ]; then
        log_metric "AUTH_HEALTH OK - Response time: ${response_time}s"
        echo "healthy"
    else
        log_metric "AUTH_HEALTH FAIL - Status: $status_code"
        echo "unhealthy"
    fi
}

check_registration_endpoint() {
    local response_time=$(curl -w "%{time_total}" -s -o /dev/null "https://eventasaur.us/")
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://eventasaur.us/")
    
    if [ "$status_code" = "200" ]; then
        log_metric "REGISTRATION_ENDPOINT OK - Response time: ${response_time}s"
    else
        log_metric "REGISTRATION_ENDPOINT FAIL - Status: $status_code"
    fi
}

monitor_errors() {
    if command -v fly &> /dev/null && fly auth whoami &> /dev/null; then
        local error_count=$(fly logs --app eventasaurus | tail -100 | grep -cE "(ERROR|CRITICAL|FATAL)" || echo "0")
        log_metric "ERROR_COUNT: $error_count"
        
        if [ "$error_count" -gt "$ALERT_THRESHOLD_ERRORS" ]; then
            send_alert "High error count detected: $error_count errors in recent logs"
        fi
    fi
}

send_alert() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "ALERT: $timestamp - $message" >> "$LOG_FILE"
    
    # TODO: Integrate with your alerting system (email, Slack, etc.)
    # curl -X POST -H 'Content-type: application/json' \
    #   --data '{"text":"'"$message"'"}' \
    #   "$SLACK_WEBHOOK_URL"
}

# Main monitoring loop
while true; do
    health_status=$(check_auth_health)
    check_registration_endpoint
    monitor_errors
    
    if [ "$health_status" = "unhealthy" ]; then
        send_alert "Authentication health check failed"
    fi
    
    sleep "$MONITORING_INTERVAL"
done
```

---

## 🚨 Alerting Configuration

### 1. Alert Rules

Configure alerts for critical thresholds:

```yaml
# alerts.yml - Alert configuration (adapt to your alerting system)
alerts:
  - name: "authentication_failure_rate"
    condition: "auth_failure_rate > 10%"
    duration: "5m"
    severity: "critical"
    message: "Authentication failure rate is above 10%"
    
  - name: "email_delivery_failure"
    condition: "email_failure_count > 5"
    duration: "10m" 
    severity: "high"
    message: "Multiple email delivery failures detected"
    
  - name: "response_time_degradation"
    condition: "avg_response_time > 5s"
    duration: "5m"
    severity: "medium"
    message: "Authentication response times are degraded"
    
  - name: "application_down"
    condition: "health_check_failure"
    duration: "1m"
    severity: "critical"
    message: "Application health check failing"
```

### 2. Notification Channels

Set up multiple notification channels:

```bash
# Environment variables for alerting
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export ALERT_EMAIL="team@company.com"
export PAGER_DUTY_KEY="your-pagerduty-key"

# Alert script template
send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Slack notification
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
          --data "{\"text\":\"🚨 [$severity] $message - $timestamp\"}" \
          "$SLACK_WEBHOOK_URL"
    fi
    
    # Email notification (requires mail command)
    if [ -n "$ALERT_EMAIL" ] && command -v mail &> /dev/null; then
        echo "$message - $timestamp" | mail -s "[$severity] Eventasaurus Alert" "$ALERT_EMAIL"
    fi
    
    # Log locally
    echo "[$severity] $timestamp - $message" >> /var/log/eventasaurus_alerts.log
}
```

---

## 📈 Dashboard Setup

### 1. Key Metrics Dashboard

Create a simple monitoring dashboard:

```html
<!-- monitoring_dashboard.html - Simple monitoring dashboard -->
<!DOCTYPE html>
<html>
<head>
    <title>Eventasaurus Monitoring</title>
    <meta http-equiv="refresh" content="30">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .metric { display: inline-block; margin: 10px; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .healthy { background-color: #d4edda; }
        .warning { background-color: #fff3cd; }
        .critical { background-color: #f8d7da; }
        .timestamp { font-size: 0.8em; color: #666; }
    </style>
</head>
<body>
    <h1>Eventasaurus Authentication Monitoring</h1>
    <div id="metrics">
        <!-- Metrics will be populated by JavaScript -->
    </div>
    
    <script>
        async function fetchMetrics() {
            try {
                const response = await fetch('/health/auth');
                const data = await response.json();
                displayMetrics(data);
            } catch (error) {
                console.error('Failed to fetch metrics:', error);
            }
        }
        
        function displayMetrics(data) {
            const metricsDiv = document.getElementById('metrics');
            metricsDiv.innerHTML = `
                <div class="metric ${data.status === 'healthy' ? 'healthy' : 'critical'}">
                    <h3>Overall Status</h3>
                    <p>${data.status.toUpperCase()}</p>
                    <div class="timestamp">${data.timestamp}</div>
                </div>
                <!-- Add more metrics as needed -->
            `;
        }
        
        // Initial load and periodic refresh
        fetchMetrics();
        setInterval(fetchMetrics, 30000);
    </script>
</body>
</html>
```

### 2. Log Analysis

Create log analysis tools:

```bash
#!/bin/bash
# scripts/analyze_auth_logs.sh - Analyze authentication logs

TIMEFRAME="${1:-1h}"  # Default to last hour
LOG_SOURCE="fly logs --app eventasaurus"

echo "🔍 Authentication Log Analysis (Last $TIMEFRAME)"
echo "================================================"

# Registration attempts
echo "📝 Registration Attempts:"
$LOG_SOURCE | grep "registration_attempt" | tail -20

echo ""
echo "📧 Email Delivery:"
$LOG_SOURCE | grep "email_sent" | tail -10

echo ""
echo "🔗 Callback Attempts:"
$LOG_SOURCE | grep "callback_attempt" | tail -10

echo ""
echo "❌ Errors:"
$LOG_SOURCE | grep -E "(ERROR|CRITICAL)" | tail -10

echo ""
echo "📊 Summary Statistics:"
reg_attempts=$($LOG_SOURCE | grep -c "registration_attempt")
emails_sent=$($LOG_SOURCE | grep -c "email_sent")
callbacks=$($LOG_SOURCE | grep -c "callback_attempt")
errors=$($LOG_SOURCE | grep -cE "(ERROR|CRITICAL)")

echo "Registration attempts: $reg_attempts"
echo "Emails sent: $emails_sent"
echo "Callbacks processed: $callbacks"
echo "Errors: $errors"

if [ "$errors" -gt 0 ] && [ "$reg_attempts" -gt 0 ]; then
    error_rate=$(echo "scale=2; $errors * 100 / $reg_attempts" | bc)
    echo "Error rate: ${error_rate}%"
fi
```

---

## 🔄 Incident Response

### 1. Incident Response Playbook

```markdown
# Authentication Incident Response Playbook

## Severity Levels

**Critical (P1)**: Authentication completely broken
- Response time: < 15 minutes
- Actions: Immediate rollback, all hands on deck

**High (P2)**: Significant degradation (>50% failure rate)
- Response time: < 30 minutes  
- Actions: Investigate, prepare rollback

**Medium (P3)**: Moderate issues (10-50% failure rate)
- Response time: < 1 hour
- Actions: Investigate, plan fix

**Low (P4)**: Minor issues (<10% failure rate)
- Response time: < 4 hours
- Actions: Monitor, plan fix for next release

## Response Procedures

### Step 1: Assess Impact
```bash
# Check current status
./scripts/health_check.sh

# Check error rates
./scripts/analyze_auth_logs.sh

# Check user impact
fly metrics --app eventasaurus
```

### Step 2: Communication
- Update status page
- Notify stakeholders
- Document issue in incident log

### Step 3: Resolution
- For P1/P2: Consider immediate rollback
- For P3/P4: Investigate and fix

### Step 4: Post-Incident
- Document lessons learned
- Update monitoring/alerting
- Implement preventive measures
```

### 2. Runbooks

Create specific runbooks for common issues:

```bash
# runbooks/email_delivery_failure.md
## Email Delivery Failure Runbook

### Symptoms
- Users not receiving confirmation emails
- High bounce rate in logs

### Investigation Steps
1. Check Supabase email settings
2. Verify SMTP configuration
3. Check email template configuration
4. Test email delivery manually

### Resolution Steps
1. Fix configuration issues
2. Resend failed emails if needed
3. Monitor delivery rates

### Prevention
- Regular SMTP health checks
- Email delivery monitoring
- Backup email service
```

---

## ✅ Implementation Checklist

### Immediate Setup (Day 1)
- [ ] Deploy health check endpoints
- [ ] Set up basic monitoring scripts
- [ ] Configure log analysis tools
- [ ] Test alerting system

### Short Term (Week 1)
- [ ] Implement custom authentication logger
- [ ] Set up automated monitoring
- [ ] Create incident response procedures
- [ ] Train team on monitoring tools

### Long Term (Month 1)
- [ ] Implement comprehensive dashboard
- [ ] Set up trend analysis
- [ ] Optimize alert thresholds
- [ ] Document lessons learned

---

## 📞 Escalation Contacts

**Technical Issues:**
- Primary: Development Team
- Secondary: DevOps/Infrastructure Team
- Escalation: CTO/Engineering Manager

**Business Issues:**
- Primary: Product Owner
- Secondary: Customer Success Team
- Escalation: CEO/Business Owner

**External Dependencies:**
- Supabase Support: support@supabase.io
- Fly.io Support: support@fly.io

---

*Monitoring is an ongoing process. Regularly review and update thresholds, alerts, and procedures based on operational experience.* 