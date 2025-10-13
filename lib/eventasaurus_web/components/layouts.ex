defmodule EventasaurusWeb.Layouts do
  use EventasaurusWeb, :html
  import EventasaurusWeb.RadiantComponents

  embed_templates "layouts/*"

  @doc """
  Get the base URL for the application from endpoint configuration.
  Used for generating absolute URLs in hreflang tags and structured data.
  """
  def get_base_url do
    endpoint = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint, [])
    url_config = Keyword.get(endpoint, :url, [])

    scheme = Keyword.get(url_config, :scheme, "https")
    host = Keyword.get(url_config, :host, "wombie.com")
    port = Keyword.get(url_config, :port)

    # Only include port if not standard (80 for http, 443 for https)
    if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) || is_nil(port) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
