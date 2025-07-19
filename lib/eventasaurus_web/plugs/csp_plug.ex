defmodule EventasaurusWeb.Plugs.CSPPlug do
  @moduledoc """
  Content Security Policy plug that configures allowed sources for various content types.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    csp_header = build_csp_header()
    put_resp_header(conn, "content-security-policy", csp_header)
  end

  defp build_csp_header do
    # Base CSP directives
    directives = %{
      "default-src" => "'self'",
      "script-src" => "'self' 'unsafe-inline' 'unsafe-eval' https://unpkg.com https://js.stripe.com https://challenges.cloudflare.com https://maps.googleapis.com https://maps.gstatic.com",
      "style-src" => "'self' 'unsafe-inline' https://fonts.googleapis.com",
      "font-src" => "'self' https://fonts.gstatic.com data:",
      "img-src" => "'self' data: blob: https: http:",
      "connect-src" => "'self' https://*.supabase.co wss://*.supabase.co https://api.stripe.com https://challenges.cloudflare.com https://maps.googleapis.com https://eu.i.posthog.com",
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