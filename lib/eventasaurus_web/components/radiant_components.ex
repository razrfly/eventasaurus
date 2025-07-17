defmodule EventasaurusWeb.RadiantComponents do
  @moduledoc """
  Components inspired by the Radiant Tailwind UI template
  """
  use Phoenix.Component

  @doc """
  Container component that provides consistent padding and max-width
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def container(assigns) do
    ~H"""
    <div class={["px-6 lg:px-8", @class]}>
      <div class="mx-auto max-w-2xl lg:max-w-7xl">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Main heading component with Radiant styling
  """
  attr :class, :string, default: ""
  attr :as, :string, default: "h2"
  attr :dark, :boolean, default: false
  slot :inner_block, required: true

  def heading(assigns) do
    assigns =
      assign(assigns, :classes, [
        "text-4xl font-medium tracking-tighter text-pretty text-gray-950 sm:text-6xl",
        assigns.dark && "text-white",
        assigns.class
      ])

    case assigns.as do
      "h1" -> ~H"<h1 class={@classes}><%= render_slot(@inner_block) %></h1>"
      "h2" -> ~H"<h2 class={@classes}><%= render_slot(@inner_block) %></h2>"
      "h3" -> ~H"<h3 class={@classes}><%= render_slot(@inner_block) %></h3>"
      "h4" -> ~H"<h4 class={@classes}><%= render_slot(@inner_block) %></h4>"
      "h5" -> ~H"<h5 class={@classes}><%= render_slot(@inner_block) %></h5>"
      "h6" -> ~H"<h6 class={@classes}><%= render_slot(@inner_block) %></h6>"
      _ -> ~H"<h2 class={@classes}><%= render_slot(@inner_block) %></h2>"
    end
  end

  @doc """
  Subheading component with Radiant styling
  """
  attr :class, :string, default: ""
  attr :as, :string, default: "h3"
  attr :dark, :boolean, default: false
  slot :inner_block, required: true

  def subheading(assigns) do
    assigns =
      assign(assigns, :classes, [
        "font-mono text-xs/5 font-semibold tracking-widest uppercase",
        (assigns.dark && "text-gray-400") || "text-gray-500",
        assigns.class
      ])

    case assigns.as do
      "h1" -> ~H"<h1 class={@classes}><%= render_slot(@inner_block) %></h1>"
      "h2" -> ~H"<h2 class={@classes}><%= render_slot(@inner_block) %></h2>"
      "h3" -> ~H"<h3 class={@classes}><%= render_slot(@inner_block) %></h3>"
      "h4" -> ~H"<h4 class={@classes}><%= render_slot(@inner_block) %></h4>"
      "h5" -> ~H"<h5 class={@classes}><%= render_slot(@inner_block) %></h5>"
      "h6" -> ~H"<h6 class={@classes}><%= render_slot(@inner_block) %></h6>"
      "p" -> ~H"<p class={@classes}><%= render_slot(@inner_block) %></p>"
      _ -> ~H"<h3 class={@classes}><%= render_slot(@inner_block) %></h3>"
    end
  end

  @doc """
  Button component with Radiant styling
  """
  attr :href, :string, default: nil
  attr :variant, :string, default: "primary"
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def radiant_button(assigns) do
    variant_classes = %{
      "primary" =>
        "inline-flex items-center justify-center px-4 py-2 rounded-full border border-transparent bg-gray-950 shadow-md text-base font-medium whitespace-nowrap text-white hover:bg-gray-800",
      "secondary" =>
        "relative inline-flex items-center justify-center px-4 py-2 rounded-full border border-transparent bg-white/15 shadow-md ring-1 ring-gray-200 text-base font-medium whitespace-nowrap text-gray-950 hover:bg-white/20"
    }

    assigns =
      assign(
        assigns,
        :variant_class,
        variant_classes[assigns.variant] || variant_classes["primary"]
      )

    ~H"""
    <%= if @href do %>
      <a href={@href} class={[@variant_class, @class]} {@rest}>
        <%= render_slot(@inner_block) %>
      </a>
    <% else %>
      <button class={[@variant_class, @class]} {@rest}>
        <%= render_slot(@inner_block) %>
      </button>
    <% end %>
    """
  end

  @doc """
  Feature card component
  """
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, default: nil
  attr :class, :string, default: ""

  def feature_card(assigns) do
    ~H"""
    <div class={["bg-white rounded-2xl border border-gray-200 p-8 shadow-sm", @class]}>
      <%= if @icon do %>
        <div class="mb-4">
          <div class="inline-flex items-center justify-center w-12 h-12 bg-gray-100 rounded-lg">
            <span class="text-2xl"><%= @icon %></span>
          </div>
        </div>
      <% end %>
      <h3 class="text-xl font-semibold text-gray-900 mb-3"><%= @title %></h3>
      <p class="text-gray-600 leading-relaxed"><%= @description %></p>
    </div>
    """
  end

  @doc """
  Logo placeholder component
  """
  attr :name, :string, required: true
  attr :class, :string, default: ""

  def logo_placeholder(assigns) do
    ~H"""
    <div class={["flex items-center justify-center h-12 px-6 bg-gray-100 rounded-lg", @class]}>
      <span class="text-sm font-medium text-gray-600"><%= @name %></span>
    </div>
    """
  end

  @doc """
  Testimonial card component
  """
  attr :quote, :string, required: true
  attr :author, :string, required: true
  attr :title, :string, required: true
  attr :company, :string, required: true
  attr :class, :string, default: ""

  def testimonial_card(assigns) do
    ~H"""
    <div class={["bg-white rounded-2xl border border-gray-200 p-8 shadow-sm", @class]}>
      <blockquote class="text-lg text-gray-700 mb-6">
        "<%= @quote %>"
      </blockquote>
      <div class="flex items-center">
        <div class="w-12 h-12 bg-gray-300 rounded-full flex items-center justify-center mr-4">
          <span class="text-sm font-medium text-gray-600">
            <%= String.first(@author) %>
          </span>
        </div>
        <div>
          <div class="font-semibold text-gray-900"><%= @author %></div>
          <div class="text-sm text-gray-600"><%= @title %>, <%= @company %></div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Hero section with gradient background
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def hero_section(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class="absolute inset-2 bottom-0 rounded-4xl ring-1 ring-black/5 ring-inset bg-gradient-to-b from-gray-50 to-white"></div>
      <.container class="relative">
        <%= render_slot(@inner_block) %>
      </.container>
    </div>
    """
  end

  @doc """
  Section with background
  """
  attr :class, :string, default: ""
  attr :background, :string, default: "white"
  slot :inner_block, required: true

  def section(assigns) do
    bg_classes = %{
      "white" => "bg-white",
      "gray" => "bg-gray-50",
      "gradient" => "bg-gradient-to-b from-white from-50% to-gray-100"
    }

    assigns = assign(assigns, :bg_class, bg_classes[assigns.background] || bg_classes["white"])

    ~H"""
    <div class={[@bg_class, @class]}>
      <.container>
        <%= render_slot(@inner_block) %>
      </.container>
    </div>
    """
  end

  @doc """
  Direct gradient application component (like Radiant's Gradient)
  """
  attr :class, :string, default: ""
  attr :theme, :string, default: "default"
  attr :rest, :global
  slot :inner_block, required: false

  def gradient(assigns) do
    theme_gradients = %{
      "default" => "bg-gradient-to-br from-yellow-100 via-pink-300 to-purple-500",
      "minimal" => "bg-gradient-to-br from-gray-50 via-gray-100 to-gray-200",
      "cosmic" => "bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-900",
      "velocity" => "bg-gradient-to-br from-red-400 via-orange-400 to-yellow-400",
      "professional" => "bg-gradient-to-br from-blue-50 via-indigo-50 to-blue-100"
    }

    assigns =
      assign(
        assigns,
        :gradient_class,
        theme_gradients[assigns.theme] || theme_gradients["default"]
      )

    ~H"""
    <div class={[
      @gradient_class,
      "sm:bg-gradient-to-r",
      @class
    ]} {@rest}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Ambient background gradient component (like Radiant's GradientBackground)
  Creates positioned gradient blobs for ambient lighting effects
  """
  attr :class, :string, default: ""
  attr :theme, :string, default: "default"
  attr :rest, :global

  def gradient_background(assigns) do
    assigns = assign_new(assigns, :theme, fn -> "default" end)

    theme_gradients = %{
      "default" => %{
        primary: "bg-gradient-to-br from-green-200 via-yellow-200 to-pink-300",
        secondary: "bg-gradient-to-br from-purple-200 via-pink-200 to-green-200"
      },
      "forest" => %{
        primary: "bg-gradient-to-br from-emerald-200 via-green-300 to-teal-200",
        secondary: "bg-gradient-to-br from-lime-200 via-emerald-200 to-cyan-200"
      },
      "sunset" => %{
        primary: "bg-gradient-to-br from-orange-200 via-pink-300 to-purple-300",
        secondary: "bg-gradient-to-br from-yellow-200 via-orange-200 to-red-300"
      },
      "ocean" => %{
        primary: "bg-gradient-to-br from-blue-200 via-cyan-300 to-teal-200",
        secondary: "bg-gradient-to-br from-indigo-200 via-blue-200 to-cyan-200"
      },
      "cosmic" => %{
        primary: "bg-gradient-to-br from-purple-300 via-pink-300 to-indigo-300",
        secondary: "bg-gradient-to-br from-violet-200 via-purple-200 to-pink-300"
      },
      "minimal" => %{
        primary: "bg-gradient-to-br from-gray-100 via-gray-200 to-gray-300",
        secondary: "bg-gradient-to-br from-slate-100 via-gray-100 to-zinc-200"
      }
    }

    gradients = theme_gradients[assigns.theme] || theme_gradients["default"]
    assigns = assign(assigns, :gradients, gradients)

    ~H"""
    <div class="relative h-full w-full">
      <div class={[
        "absolute -top-40 -right-32 h-72 w-72 transform-gpu md:right-10",
        @gradients.primary,
        "rotate-[-15deg] rounded-full blur-3xl opacity-50"
      ]}>
      </div>
      <div class={[
        "absolute top-80 -left-32 h-64 w-64 transform-gpu",
        @gradients.secondary,
        "rotate-[25deg] rounded-full blur-3xl opacity-40"
      ]}>
      </div>
    </div>
    """
  end
end
