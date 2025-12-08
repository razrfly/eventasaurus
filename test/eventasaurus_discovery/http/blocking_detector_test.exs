defmodule EventasaurusDiscovery.Http.BlockingDetectorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Http.BlockingDetector

  # Sample blocked HTML responses for testing
  @cloudflare_challenge_page """
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>Just a moment...</title>
    <style>
      .cf-browser-verification { display: block; }
    </style>
  </head>
  <body>
    <div class="cf-browser-verification">
      <h1>Checking your browser before accessing the site.</h1>
      <p>This process is automatic. Your browser will redirect shortly.</p>
      <div id="cf-spinner">
        <div id="challenge-platform"></div>
      </div>
      <noscript>Please enable JavaScript to continue.</noscript>
    </div>
    <script>
      var _cf_chl_opt = {chlApiUrl: "/cdn-cgi/challenge-platform"};
    </script>
  </body>
  </html>
  """

  @cloudflare_error_page """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Access Denied | Cloudflare</title>
  </head>
  <body>
    <div class="main-wrapper">
      <h1>Access Denied</h1>
      <p>The owner of this website has banned your access based on your browser's signature.</p>
      <p>Cloudflare Ray ID: 8a1234567890abcd</p>
      <a href="https://cloudflare.com/5xx-error-landing">Visit Cloudflare</a>
    </div>
  </body>
  </html>
  """

  @recaptcha_page """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Verification Required</title>
    <script src="https://www.google.com/recaptcha/api.js" async defer></script>
  </head>
  <body>
    <h1>Please verify you are human</h1>
    <form>
      <div class="g-recaptcha" data-sitekey="abc123"></div>
      <button type="submit">Submit</button>
    </form>
  </body>
  </html>
  """

  @hcaptcha_page """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Human Verification</title>
    <script src="https://hcaptcha.com/1/api.js" async defer></script>
  </head>
  <body>
    <h1>Prove you're not a robot</h1>
    <div class="h-captcha" data-sitekey="xyz789"></div>
  </body>
  </html>
  """

  @normal_page """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Welcome to Our Site</title>
  </head>
  <body>
    <h1>Hello World</h1>
    <p>This is a normal page with real content.</p>
  </body>
  </html>
  """

  @rate_limit_page """
  <!DOCTYPE html>
  <html>
  <head><title>Too Many Requests</title></head>
  <body>
    <h1>Rate Limited</h1>
    <p>You have made too many requests. Please try again later.</p>
  </body>
  </html>
  """

  describe "detect/3" do
    test "returns :ok for normal 200 response" do
      assert :ok = BlockingDetector.detect(200, [], @normal_page)
    end

    test "returns :ok for 200 with normal headers" do
      headers = [
        {"Content-Type", "text/html"},
        {"Server", "nginx"}
      ]

      assert :ok = BlockingDetector.detect(200, headers, @normal_page)
    end

    test "detects Cloudflare challenge page with cf-ray header" do
      headers = [{"cf-ray", "8a1234567890abcd-IAD"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, @cloudflare_challenge_page)
    end

    test "detects Cloudflare by body patterns even with 200 status but cf headers" do
      headers = [{"cf-ray", "8a1234567890abcd-IAD"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(200, headers, @cloudflare_challenge_page)
    end

    test "detects Cloudflare error page" do
      headers = [{"cf-ray", "8a1234567890abcd-IAD"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, @cloudflare_error_page)
    end

    test "detects Cloudflare with cf-mitigated header" do
      headers = [{"cf-mitigated", "challenge"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, "")
    end

    test "detects Cloudflare 503 with cf headers" do
      headers = [{"cf-ray", "abc123"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(503, headers, "Service Unavailable")
    end

    test "detects reCAPTCHA" do
      assert {:blocked, :captcha} = BlockingDetector.detect(200, [], @recaptcha_page)
    end

    test "detects hCaptcha" do
      assert {:blocked, :captcha} = BlockingDetector.detect(200, [], @hcaptcha_page)
    end

    test "detects generic CAPTCHA text" do
      body = "<html><body><h1>Please solve this puzzle to continue</h1></body></html>"
      assert {:blocked, :captcha} = BlockingDetector.detect(200, [], body)
    end

    test "detects rate limiting with 429 status" do
      assert {:blocked, :rate_limit, 60} = BlockingDetector.detect(429, [], @rate_limit_page)
    end

    test "parses Retry-After header for rate limiting" do
      headers = [{"Retry-After", "120"}]
      assert {:blocked, :rate_limit, 120} = BlockingDetector.detect(429, headers, "")
    end

    test "defaults to 60 seconds when Retry-After is invalid" do
      headers = [{"Retry-After", "invalid"}]
      assert {:blocked, :rate_limit, 60} = BlockingDetector.detect(429, headers, "")
    end

    test "detects generic 403 as access_denied" do
      body = "<html><body>Access Denied</body></html>"
      assert {:blocked, :access_denied} = BlockingDetector.detect(403, [], body)
    end

    test "handles case-insensitive headers" do
      headers = [{"CF-RAY", "abc123"}, {"CF-CACHE-STATUS", "DYNAMIC"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, @cloudflare_challenge_page)
    end

    test "handles mixed case body patterns" do
      body = "<html><body>JUST A MOMENT... checking your browser</body></html>"
      headers = [{"cf-ray", "abc123"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, body)
    end

    test "returns :ok for 404 (not found is not blocking)" do
      assert :ok = BlockingDetector.detect(404, [], "<html>Not Found</html>")
    end

    test "returns :ok for 500 server error (not blocking)" do
      assert :ok = BlockingDetector.detect(500, [], "<html>Server Error</html>")
    end

    test "handles nil body gracefully" do
      assert :ok = BlockingDetector.detect(200, [], nil)
    end

    test "handles empty body" do
      assert :ok = BlockingDetector.detect(200, [], "")
    end
  end

  describe "blocked?/3" do
    test "returns false for normal response" do
      refute BlockingDetector.blocked?(200, [], @normal_page)
    end

    test "returns true for Cloudflare blocked response" do
      headers = [{"cf-ray", "abc123"}]
      assert BlockingDetector.blocked?(403, headers, @cloudflare_challenge_page)
    end

    test "returns true for rate limited response" do
      assert BlockingDetector.blocked?(429, [], "")
    end

    test "returns true for CAPTCHA response" do
      assert BlockingDetector.blocked?(200, [], @recaptcha_page)
    end

    test "returns true for generic 403" do
      assert BlockingDetector.blocked?(403, [], "Access Denied")
    end
  end

  describe "cloudflare_response?/1" do
    test "returns true when cf-ray header present" do
      headers = [{"cf-ray", "abc123-IAD"}]
      assert BlockingDetector.cloudflare_response?(headers)
    end

    test "returns true when cf-cache-status header present" do
      headers = [{"cf-cache-status", "DYNAMIC"}]
      assert BlockingDetector.cloudflare_response?(headers)
    end

    test "returns true when cf-mitigated header present" do
      headers = [{"cf-mitigated", "challenge"}]
      assert BlockingDetector.cloudflare_response?(headers)
    end

    test "returns false without Cloudflare headers" do
      headers = [{"Server", "nginx"}, {"Content-Type", "text/html"}]
      refute BlockingDetector.cloudflare_response?(headers)
    end

    test "handles empty headers" do
      refute BlockingDetector.cloudflare_response?([])
    end

    test "handles case-insensitive headers" do
      headers = [{"CF-Ray", "abc123"}]
      assert BlockingDetector.cloudflare_response?(headers)
    end
  end

  describe "details/3" do
    test "returns detailed info for Cloudflare blocking" do
      headers = [{"cf-ray", "abc123"}]
      details = BlockingDetector.details(403, headers, @cloudflare_challenge_page)

      assert details.blocked == true
      assert details.type == :cloudflare
      assert details.status_code == 403
      assert :status_403 in details.indicators
      assert :cf_headers in details.indicators
      assert :cf_challenge_page in details.indicators
    end

    test "returns detailed info for rate limiting" do
      headers = [{"Retry-After", "300"}]
      details = BlockingDetector.details(429, headers, "")

      assert details.blocked == true
      assert details.type == :rate_limit
      assert details.status_code == 429
      assert details.retry_after == 300
      assert :status_429 in details.indicators
      assert :retry_after_header in details.indicators
    end

    test "returns detailed info for CAPTCHA" do
      details = BlockingDetector.details(200, [], @recaptcha_page)

      assert details.blocked == true
      assert details.type == :captcha
      assert details.status_code == 200
      assert :captcha_detected in details.indicators
    end

    test "returns detailed info for normal response" do
      details = BlockingDetector.details(200, [], @normal_page)

      assert details.blocked == false
      assert details.type == nil
      assert details.status_code == 200
      assert details.indicators == []
    end

    test "returns detailed info for generic 403" do
      details = BlockingDetector.details(403, [], "Access Denied")

      assert details.blocked == true
      assert details.type == :access_denied
      assert details.status_code == 403
      assert :status_403 in details.indicators
    end
  end

  describe "real-world Cloudflare patterns" do
    test "detects 'checking if the site connection is secure'" do
      body = """
      <html>
        <head><title>Just a moment...</title></head>
        <body>
          <h1>Checking if the site connection is secure</h1>
          <p>www.example.com needs to review the security of your connection before proceeding.</p>
        </body>
      </html>
      """

      headers = [{"cf-ray", "abc123"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, body)
    end

    test "detects cf-please-wait spinner" do
      body = """
      <html>
        <body>
          <div id="cf-please-wait">
            <div class="cf-spinner"></div>
          </div>
        </body>
      </html>
      """

      headers = [{"cf-ray", "abc123"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, body)
    end

    test "detects data-cf-beacon" do
      body = """
      <html>
        <body>
          <script defer src="https://static.cloudflareinsights.com/beacon.min.js"
                  data-cf-beacon='{"token": "abc123"}'></script>
        </body>
      </html>
      """

      # data-cf-beacon alone with cf headers indicates Cloudflare infrastructure
      headers = [{"cf-ray", "abc123"}]
      assert {:blocked, :cloudflare} = BlockingDetector.detect(403, headers, body)
    end
  end

  describe "edge cases" do
    test "Cloudflare with body but no cf headers returns access_denied for 403" do
      # If we have Cloudflare body patterns but no CF headers,
      # it's suspicious but we can't confirm it's Cloudflare
      assert {:blocked, :access_denied} = BlockingDetector.detect(403, [], @cloudflare_challenge_page)
    end

    test "normal page with cf headers but 200 status is not blocked" do
      # Many legitimate sites use Cloudflare CDN and have cf headers
      headers = [{"cf-ray", "abc123"}, {"cf-cache-status", "HIT"}]
      assert :ok = BlockingDetector.detect(200, headers, @normal_page)
    end

    test "CAPTCHA takes precedence over normal 200 status" do
      # If there's a CAPTCHA on a 200 response, it's still blocking
      assert {:blocked, :captcha} = BlockingDetector.detect(200, [], @recaptcha_page)
    end

    test "rate limit takes precedence over body patterns" do
      # 429 with CAPTCHA body should still be rate_limit
      headers = [{"Retry-After", "60"}]
      assert {:blocked, :rate_limit, 60} = BlockingDetector.detect(429, headers, @recaptcha_page)
    end
  end
end
