defmodule EventasaurusWeb.Components.OpenGraphComponent do
  @moduledoc """
  Component for rendering Open Graph and Twitter Card meta tags for social media sharing.

  ## Open Graph Protocol
  The Open Graph protocol enables any web page to become a rich object in a social graph.
  Used by Facebook, LinkedIn, and other social platforms.

  ## Twitter Cards
  Twitter Cards allow you to attach rich photos, videos and media experiences to Tweets.
  Used by Twitter/X platform.

  ## References
  - Open Graph Protocol: https://ogp.me/
  - Twitter Cards: https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
  - Facebook Sharing Debugger: https://developers.facebook.com/tools/debug/
  """

  use Phoenix.Component

  @doc """
  Renders Open Graph and Twitter Card meta tags for social media sharing.

  ## Attributes
    - `type`: Open Graph type (default: "website", for events use "event")
    - `title`: Page/event title (required)
    - `description`: Page/event description (required)
    - `image_url`: Full URL to preview image (required)
    - `image_width`: Image width in pixels (default: 1200)
    - `image_height`: Image height in pixels (default: 630)
    - `url`: Full canonical URL of the page (required)
    - `site_name`: Site name (default: "Eventasaurus")
    - `locale`: Content locale (default: "en_US")
    - `twitter_card`: Twitter card type (default: "summary_large_image")
    - `twitter_site`: Twitter @username of site (optional)

  ## Examples

      # For an event page
      <.open_graph_tags
        type="event"
        title="Arctic Monkeys Live in Kraków"
        description="Experience an unforgettable night with Arctic Monkeys"
        image_url="https://eventasaurus.com/images/events/arctic-monkeys.jpg"
        url="https://eventasaurus.com/events/arctic-monkeys-krakow-241215"
      />

      # For a city page
      <.open_graph_tags
        title="Events in Kraków"
        description="Discover concerts, festivals, and cultural events in Kraków"
        image_url="https://eventasaurus.com/images/cities/krakow.jpg"
        url="https://eventasaurus.com/cities/krakow"
      />

  ## Image Recommendations

  - **Aspect Ratio**: 1.91:1 (1200x630px recommended)
  - **Minimum Size**: 600x315px
  - **Maximum Size**: 8MB
  - **Formats**: JPG, PNG, WebP, GIF
  - **Best Practices**:
    - Use high-quality images
    - Avoid text overlay that may be cropped
    - Test with Facebook Sharing Debugger and Twitter Card Validator
  """
  attr :type, :string, default: "website", doc: "Open Graph type (website, article, event, etc.)"
  attr :title, :string, required: true, doc: "Page or event title"
  attr :description, :string, required: true, doc: "Page or event description"
  attr :image_url, :string, required: true, doc: "Full URL to preview image"
  attr :image_width, :integer, default: 1200, doc: "Image width in pixels"
  attr :image_height, :integer, default: 630, doc: "Image height in pixels"
  attr :url, :string, required: true, doc: "Full canonical URL of the page"
  attr :site_name, :string, default: "Eventasaurus", doc: "Site name"
  attr :locale, :string, default: "en_US", doc: "Content locale (e.g., en_US, pl_PL)"
  attr :twitter_card, :string, default: "summary_large_image", doc: "Twitter card type"
  attr :twitter_site, :string, default: nil, doc: "Twitter @username of site"

  def open_graph_tags(assigns) do
    # Ensure URLs are absolute
    assigns =
      assigns
      |> ensure_absolute_url(:image_url)
      |> ensure_absolute_url(:url)

    ~H"""
    <!-- Open Graph meta tags -->
    <meta property="og:type" content={@type} />
    <meta property="og:title" content={@title} />
    <meta property="og:description" content={@description} />
    <meta property="og:image" content={@image_url} />
    <meta property="og:image:width" content={@image_width} />
    <meta property="og:image:height" content={@image_height} />
    <meta property="og:url" content={@url} />
    <meta property="og:site_name" content={@site_name} />
    <meta property="og:locale" content={@locale} />

    <!-- Twitter Card meta tags -->
    <meta name="twitter:card" content={@twitter_card} />
    <meta name="twitter:title" content={@title} />
    <meta name="twitter:description" content={@description} />
    <meta name="twitter:image" content={@image_url} />
    <%= if @twitter_site do %>
      <meta name="twitter:site" content={@twitter_site} />
    <% end %>

    <!-- Standard meta description for SEO -->
    <meta name="description" content={@description} />
    """
  end

  # Ensure URL is absolute (starts with http:// or https://)
  defp ensure_absolute_url(assigns, key) do
    url = Map.get(assigns, key)

    if url && is_binary(url) && !String.starts_with?(url, ["http://", "https://"]) do
      # If URL is relative, make it absolute using the app's URL
      base_url = get_base_url()
      Map.put(assigns, key, "#{base_url}#{url}")
    else
      assigns
    end
  end

  # Get the base URL for the application
  defp get_base_url do
    # Get from endpoint configuration
    endpoint = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint, [])
    url_config = Keyword.get(endpoint, :url, [])

    scheme = Keyword.get(url_config, :scheme, "https")
    host = Keyword.get(url_config, :host, "eventasaurus.com")
    port = Keyword.get(url_config, :port, 443)

    # Only include port if not standard (80 for http, 443 for https)
    if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
