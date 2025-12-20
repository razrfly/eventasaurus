defmodule EventasaurusWeb.Components.Activity.HeroCardBackground do
  @moduledoc """
  Reusable background component for hero cards.

  Provides consistent background handling with image or gradient fallback,
  used across all hero card components.

  ## Features

  - Image background with gradient overlay
  - Theme-based gradient fallback when no image
  - CDN integration for optimized images
  - Consistent styling across all hero cards

  ## Usage

      alias EventasaurusWeb.Components.Activity.HeroCardBackground

      # With image
      <HeroCardBackground.background
        image_url={@cover_image_url}
        theme={:music}
      />

      # Gradient only (no image)
      <HeroCardBackground.background theme={:trivia} />
  """
  use Phoenix.Component

  alias Eventasaurus.CDN
  alias EventasaurusWeb.Components.Activity.HeroCardTheme

  @doc """
  Renders the background layer for a hero card.

  ## Attributes

    * `:image_url` - Optional. Image URL for the background.
    * `:theme` - Required. Theme atom for gradient styling.
    * `:image_width` - Optional. CDN image width. Defaults to 1200.
    * `:image_quality` - Optional. CDN image quality. Defaults to 85.
    * `:class` - Optional. Additional CSS classes.
  """
  attr :image_url, :string, default: nil, doc: "Background image URL"
  attr :theme, :atom, required: true, doc: "Theme for gradient styling"
  attr :image_width, :integer, default: 1200, doc: "CDN image width"
  attr :image_quality, :integer, default: 85, doc: "CDN image quality"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def background(assigns) do
    ~H"""
    <%= if @image_url do %>
      <div class={["absolute inset-0", @class]}>
        <img
          src={CDN.url(@image_url, width: @image_width, quality: @image_quality)}
          alt=""
          class="w-full h-full object-cover"
          aria-hidden="true"
        />
        <div class={"absolute inset-0 #{HeroCardTheme.overlay_class(@theme)}"} />
      </div>
    <% else %>
      <div class={["absolute inset-0", HeroCardTheme.gradient_class(@theme), @class]} />
    <% end %>
    """
  end
end
