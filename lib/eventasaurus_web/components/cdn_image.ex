defmodule EventasaurusWeb.Components.CDNImage do
  @moduledoc """
  A reusable image component with CDN transformation and automatic fallback support.

  This component wraps images with Cloudflare CDN transformations and provides
  client-side fallback to the original URL if the CDN transformation fails
  (e.g., when quota is exceeded).

  ## Features

  - Automatic CDN URL wrapping with configurable transformations
  - Client-side fallback using `onerror` handler
  - Supports all standard img attributes

  ## Usage

      <.cdn_img
        src={event.cover_image_url}
        alt={event.title}
        width={400}
        height={300}
        fit="cover"
        quality={85}
        class="w-full h-full object-cover"
        loading="lazy"
      />

  ## Disabling CDN (when quota exceeded)

  To disable CDN transformations temporarily:

      fly secrets set CDN_FORCE_DISABLED=true

  To re-enable when the month resets:

      fly secrets unset CDN_FORCE_DISABLED

  ## Attributes

  - `src` - The original image URL (required)
  - `alt` - Alt text for accessibility (required)
  - `width` - CDN transformation width
  - `height` - CDN transformation height
  - `fit` - CDN transformation fit mode ("cover", "contain", etc.)
  - `quality` - CDN transformation quality (1-100)
  - `format` - CDN transformation format ("webp", "avif", etc.)
  - `class` - CSS classes for the img element
  - `loading` - Loading strategy ("lazy", "eager")
  - `referrerpolicy` - Referrer policy for external images
  """

  use Phoenix.Component
  alias Eventasaurus.CDN

  @doc """
  Renders an image with CDN transformation and fallback support.

  The component uses a simple onerror handler to automatically switch
  to the fallback URL when CDN transformations fail.
  """
  attr :src, :string, required: true, doc: "Original image URL"
  attr :alt, :string, required: true, doc: "Alt text for accessibility"
  attr :width, :integer, default: nil, doc: "CDN transformation width"
  attr :height, :integer, default: nil, doc: "CDN transformation height"
  attr :fit, :string, default: nil, doc: "CDN transformation fit mode"
  attr :quality, :integer, default: 85, doc: "CDN transformation quality"
  attr :format, :string, default: nil, doc: "CDN transformation format"
  attr :class, :string, default: "", doc: "CSS classes"
  attr :loading, :string, default: "lazy", doc: "Loading strategy"
  attr :referrerpolicy, :string, default: "no-referrer", doc: "Referrer policy"
  attr :rest, :global, doc: "Additional HTML attributes"

  def cdn_image(assigns) do
    # Build CDN transformation options
    opts =
      []
      |> maybe_add(:width, assigns.width)
      |> maybe_add(:height, assigns.height)
      |> maybe_add(:fit, assigns.fit)
      |> maybe_add(:quality, assigns.quality)
      |> maybe_add(:format, assigns.format)

    # Get both CDN and fallback URLs
    urls = CDN.url_with_fallback(assigns.src, opts)

    assigns =
      assigns
      |> assign(:cdn_src, urls.src)
      |> assign(:fallback_src, urls.fallback)

    ~H"""
    <%= if @cdn_src do %>
      <img
        src={@cdn_src}
        alt={@alt}
        class={@class}
        loading={@loading}
        referrerpolicy={@referrerpolicy}
        data-fallback-src={@fallback_src}
        onerror="this.onerror=null; if(this.dataset.fallbackSrc && this.src !== this.dataset.fallbackSrc) { this.src = this.dataset.fallbackSrc; }"
        {@rest}
      />
    <% else %>
      <div class={["flex items-center justify-center bg-gray-200", @class]}>
        <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
        </svg>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders a simple image with CDN transformation.

  This is a simpler version without the fallback UI placeholder,
  suitable for cases where you want to handle missing images differently.
  """
  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :fit, :string, default: nil
  attr :quality, :integer, default: 85
  attr :format, :string, default: nil
  attr :class, :string, default: ""
  attr :loading, :string, default: "lazy"
  attr :referrerpolicy, :string, default: "no-referrer"
  attr :rest, :global

  def cdn_img(assigns) do
    opts =
      []
      |> maybe_add(:width, assigns.width)
      |> maybe_add(:height, assigns.height)
      |> maybe_add(:fit, assigns.fit)
      |> maybe_add(:quality, assigns.quality)
      |> maybe_add(:format, assigns.format)

    urls = CDN.url_with_fallback(assigns.src, opts)

    assigns =
      assigns
      |> assign(:cdn_src, urls.src)
      |> assign(:fallback_src, urls.fallback)

    ~H"""
    <img
      src={@cdn_src}
      alt={@alt}
      class={@class}
      loading={@loading}
      referrerpolicy={@referrerpolicy}
      data-fallback-src={@fallback_src}
      onerror="this.onerror=null; if(this.dataset.fallbackSrc && this.src !== this.dataset.fallbackSrc) { this.src = this.dataset.fallbackSrc; }"
      {@rest}
    />
    """
  end

  # Helper to conditionally add options
  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
