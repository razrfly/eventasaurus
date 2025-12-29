defmodule EventasaurusWeb.Plugs.CSPPlug do
  @moduledoc """
  Content Security Policy plug that configures allowed sources for various content types.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Generate a nonce for this request
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", build_csp_header(nonce))
  end

  defp build_csp_header(nonce) do
    # Base CSP directives
    directives = %{
      "default-src" => "'self'",
      "script-src" =>
        "'self' 'nonce-#{nonce}' 'unsafe-inline' 'unsafe-eval' https://unpkg.com https://js.stripe.com https://challenges.cloudflare.com https://maps.googleapis.com https://maps.gstatic.com https://eu-assets.i.posthog.com https://esm.sh https://plausible.io blob:",
      "style-src" =>
        "'self' 'nonce-#{nonce}' 'unsafe-inline' https://fonts.googleapis.com https://rsms.me",
      "font-src" => "'self' https://fonts.gstatic.com https://rsms.me data:",
      "img-src" => "'self' data: blob: https: http:",
      "connect-src" =>
        "'self' https://api.stripe.com https://challenges.cloudflare.com https://maps.googleapis.com https://eu.i.posthog.com https://eu-assets.i.posthog.com https://plausible.io http://localhost:5746 http://localhost:5747",
      "frame-src" => "'self' https://js.stripe.com https://challenges.cloudflare.com",
      "frame-ancestors" => "'none'",
      "object-src" => "'none'",
      "base-uri" => "'self'",
      "form-action" => "'self'",
      "worker-src" => "'self' blob:",
      "child-src" => "'self' blob:"
    }

    # Convert to CSP header string
    directives
    |> Enum.map(fn {directive, sources} -> "#{directive} #{sources}" end)
    |> Enum.join("; ")
  end
end
