defmodule EventasaurusDiscovery.Http.BlockingDetector do
  @moduledoc """
  Detects blocking patterns in HTTP responses.

  This module analyzes HTTP responses to determine if a request was blocked
  by anti-bot systems like Cloudflare, CAPTCHAs, or rate limiters.

  ## Blocking Types

  - `:cloudflare` - Cloudflare protection (challenge pages, cf-ray headers)
  - `:captcha` - Generic CAPTCHA challenges (reCAPTCHA, hCaptcha, etc.)
  - `:rate_limit` - Rate limiting (429 status, Retry-After headers)
  - `:access_denied` - Generic access denied (403 without specific patterns)

  ## Usage

      alias EventasaurusDiscovery.Http.BlockingDetector

      # Check a response
      case BlockingDetector.detect(status_code, headers, body) do
        :ok -> # Response is valid, not blocked
        {:blocked, :cloudflare} -> # Cloudflare challenge detected
        {:blocked, :captcha} -> # CAPTCHA detected
        {:blocked, :rate_limit, retry_after} -> # Rate limited, retry after N seconds
        {:blocked, :access_denied} -> # Generic 403
      end

      # Quick check if blocked
      if BlockingDetector.blocked?(status_code, headers, body) do
        # Handle blocking
      end

  ## Detection Methods

  1. **Status Code Analysis** - 403, 429, 503 indicate potential blocking
  2. **Header Analysis** - cf-ray, cf-mitigated, Retry-After headers
  3. **Body Pattern Matching** - Challenge page HTML patterns, CAPTCHA scripts
  """

  @type headers :: [{String.t(), String.t()}]
  @type blocking_type :: :cloudflare | :captcha | :rate_limit | :access_denied
  @type detection_result :: :ok | {:blocked, blocking_type()} | {:blocked, :rate_limit, integer()}

  # Cloudflare-specific patterns in response body
  @cloudflare_body_patterns [
    # Challenge page indicators
    "Just a moment...",
    "Checking your browser",
    "checking if the site connection is secure",
    "challenge-platform",
    "cf-browser-verification",
    "_cf_chl_opt",
    "cf-spinner",
    # Cloudflare branding
    "Cloudflare Ray ID",
    "cloudflare.com/5xx-error-landing",
    "data-cf-beacon",
    # JavaScript challenge
    "cf_chl_prog",
    "cf-please-wait"
  ]

  # Cloudflare header indicators
  @cloudflare_headers [
    "cf-ray",
    "cf-mitigated",
    "cf-cache-status"
  ]

  # CAPTCHA patterns (various providers)
  @captcha_body_patterns [
    # Google reCAPTCHA
    "g-recaptcha",
    "grecaptcha",
    "recaptcha/api.js",
    "recaptcha/enterprise.js",
    # hCaptcha
    "h-captcha",
    "hcaptcha.com/1/api.js",
    # Generic CAPTCHA indicators
    "captcha-container",
    "captcha_challenge",
    "solve this puzzle",
    "verify you are human",
    "prove you're not a robot",
    "human verification"
  ]

  # Rate limiting header
  @rate_limit_header "retry-after"

  @doc """
  Detects if a response indicates blocking.

  Returns:
  - `:ok` - Response is valid, not blocked
  - `{:blocked, type}` - Blocked with specific type
  - `{:blocked, :rate_limit, seconds}` - Rate limited with retry delay

  ## Examples

      iex> BlockingDetector.detect(200, [], "<html>Normal page</html>")
      :ok

      iex> BlockingDetector.detect(403, [{"cf-ray", "abc123"}], "Just a moment...")
      {:blocked, :cloudflare}

      iex> BlockingDetector.detect(429, [{"Retry-After", "60"}], "")
      {:blocked, :rate_limit, 60}
  """
  @spec detect(integer(), headers(), String.t()) :: detection_result()
  def detect(status_code, headers, body) do
    normalized_headers = normalize_headers(headers)

    cond do
      # Check rate limiting first (429)
      rate_limited?(status_code, normalized_headers) ->
        retry_after = get_retry_after(normalized_headers)
        {:blocked, :rate_limit, retry_after}

      # Check Cloudflare blocking
      cloudflare_blocked?(status_code, normalized_headers, body) ->
        {:blocked, :cloudflare}

      # Check CAPTCHA
      captcha_detected?(body) ->
        {:blocked, :captcha}

      # Generic 403 without specific patterns
      status_code == 403 ->
        {:blocked, :access_denied}

      # Service unavailable might indicate blocking
      status_code == 503 and has_cloudflare_headers?(normalized_headers) ->
        {:blocked, :cloudflare}

      # Not blocked
      true ->
        :ok
    end
  end

  @doc """
  Quick check if a response is blocked.

  Returns `true` if any blocking pattern is detected, `false` otherwise.

  ## Examples

      iex> BlockingDetector.blocked?(200, [], "<html>Normal</html>")
      false

      iex> BlockingDetector.blocked?(403, [{"cf-ray", "abc"}], "")
      true
  """
  @spec blocked?(integer(), headers(), String.t()) :: boolean()
  def blocked?(status_code, headers, body) do
    case detect(status_code, headers, body) do
      :ok -> false
      {:blocked, _} -> true
      {:blocked, _, _} -> true
    end
  end

  @doc """
  Checks if a response appears to be from Cloudflare.

  This checks headers only and does not require body analysis.
  Useful for quick checks without body inspection.

  ## Examples

      iex> BlockingDetector.cloudflare_response?([{"cf-ray", "abc123"}])
      true

      iex> BlockingDetector.cloudflare_response?([{"content-type", "text/html"}])
      false
  """
  @spec cloudflare_response?(headers()) :: boolean()
  def cloudflare_response?(headers) do
    headers
    |> normalize_headers()
    |> has_cloudflare_headers?()
  end

  @doc """
  Extracts blocking details for logging/metrics.

  Returns a map with detection details useful for debugging and monitoring.

  ## Examples

      iex> BlockingDetector.details(403, [{"cf-ray", "abc"}], "Just a moment...")
      %{
        blocked: true,
        type: :cloudflare,
        indicators: [:cf_ray_header, :challenge_page],
        status_code: 403
      }
  """
  @spec details(integer(), headers(), String.t()) :: map()
  def details(status_code, headers, body) do
    normalized_headers = normalize_headers(headers)
    indicators = collect_indicators(status_code, normalized_headers, body)

    case detect(status_code, headers, body) do
      :ok ->
        %{
          blocked: false,
          type: nil,
          indicators: [],
          status_code: status_code
        }

      {:blocked, type} ->
        %{
          blocked: true,
          type: type,
          indicators: indicators,
          status_code: status_code
        }

      {:blocked, :rate_limit, retry_after} ->
        %{
          blocked: true,
          type: :rate_limit,
          indicators: indicators,
          status_code: status_code,
          retry_after: retry_after
        }
    end
  end

  # Private functions

  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, value} ->
      {String.downcase(key), value}
    end)
  end

  defp rate_limited?(status_code, _headers) when status_code == 429, do: true
  defp rate_limited?(_status_code, _headers), do: false

  defp get_retry_after(headers) do
    case List.keyfind(headers, @rate_limit_header, 0) do
      {_, value} -> parse_retry_after(value)
      nil -> 60
    end
  end

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> 60
    end
  end

  defp cloudflare_blocked?(status_code, headers, body) do
    # Cloudflare blocking typically has:
    # 1. Status 403 or 503
    # 2. cf-ray header present
    # 3. Challenge page patterns in body

    has_cf_status = status_code in [403, 503]
    has_cf_headers = has_cloudflare_headers?(headers)
    has_cf_body = has_cloudflare_body_patterns?(body)

    # Cloudflare if we have headers + (body patterns OR blocking status)
    has_cf_headers and (has_cf_body or has_cf_status)
  end

  defp has_cloudflare_headers?(headers) do
    Enum.any?(@cloudflare_headers, fn header ->
      List.keymember?(headers, header, 0)
    end)
  end

  defp has_cloudflare_body_patterns?(body) when is_binary(body) do
    body_lower = String.downcase(body)

    Enum.any?(@cloudflare_body_patterns, fn pattern ->
      String.contains?(body_lower, String.downcase(pattern))
    end)
  end

  defp has_cloudflare_body_patterns?(_), do: false

  defp captcha_detected?(body) when is_binary(body) do
    body_lower = String.downcase(body)

    Enum.any?(@captcha_body_patterns, fn pattern ->
      String.contains?(body_lower, String.downcase(pattern))
    end)
  end

  defp captcha_detected?(_), do: false

  defp collect_indicators(status_code, headers, body) do
    indicators = []

    # Status code indicators
    indicators =
      case status_code do
        403 -> [:status_403 | indicators]
        429 -> [:status_429 | indicators]
        503 -> [:status_503 | indicators]
        _ -> indicators
      end

    # Header indicators
    indicators =
      if has_cloudflare_headers?(headers) do
        [:cf_headers | indicators]
      else
        indicators
      end

    indicators =
      if List.keymember?(headers, @rate_limit_header, 0) do
        [:retry_after_header | indicators]
      else
        indicators
      end

    # Body indicators
    indicators =
      if has_cloudflare_body_patterns?(body) do
        [:cf_challenge_page | indicators]
      else
        indicators
      end

    indicators =
      if captcha_detected?(body) do
        [:captcha_detected | indicators]
      else
        indicators
      end

    Enum.reverse(indicators)
  end
end
