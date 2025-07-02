defmodule EventasaurusWeb.ProfileHTML do
  use EventasaurusWeb, :html
  import Phoenix.HTML.Link

  embed_templates "profile_html/*"

  alias EventasaurusApp.Accounts.User

  @doc """
  Generate a formatted display name for the user.
  """
  def display_name(user) do
    User.display_name(user)
  end

  @doc """
  Generate a profile link with optional custom text and CSS classes

  ## Examples
      <%= profile_link(@user) %>
      <%= profile_link(@user, "View Profile", class: "text-blue-500") %>
  """
  def profile_link(user, text \\ nil, opts \\ [])

  def profile_link(%User{} = user, text, opts) do
    link_text = text || display_name(user)
    link_class = Keyword.get(opts, :class, "text-blue-600 hover:text-blue-800")

    link(link_text,
      to: User.profile_url(user),
      class: link_class,
      title: "View #{display_name(user)}'s profile"
    )
  end

  def profile_link(nil, _text, _opts), do: ""

  @doc """
  Generate a short profile link (uses /u/:username)
  """
  def short_profile_link(user, text \\ nil, opts \\ [])

  def short_profile_link(%User{} = user, text, opts) do
    link_text = text || display_name(user)
    link_class = Keyword.get(opts, :class, "text-blue-600 hover:text-blue-800")

    link(link_text,
      to: User.short_profile_url(user),
      class: link_class,
      title: "View #{display_name(user)}'s profile"
    )
  end

  def short_profile_link(nil, _text, _opts), do: ""

  @doc """
  Generate a profile handle link (@username format)
  """
  def profile_handle_link(user, opts \\ [])

  def profile_handle_link(%User{} = user, opts) do
    link_class = Keyword.get(opts, :class, "text-gray-600 hover:text-gray-800")

    link(User.profile_handle(user),
      to: User.profile_url(user),
      class: link_class,
      title: "View #{display_name(user)}'s profile"
    )
  end

  def profile_handle_link(nil, _opts), do: ""

  @doc """
  Generate profile URL for use in templates
  """
  def profile_url(%User{} = user), do: User.profile_url(user)
  def profile_url(nil), do: "#"

  @doc """
  Generate short profile URL for use in templates
  """
  def short_profile_url(%User{} = user), do: User.short_profile_url(user)
  def short_profile_url(nil), do: "#"

  @doc """
  Generate shareable profile URL with domain
  """
  def shareable_profile_url(user, base_url \\ nil)

  def shareable_profile_url(%User{} = user, base_url) do
    case base_url do
      nil -> User.shareable_profile_url(user)
      url -> User.shareable_profile_url(user, url)
    end
  end

  def shareable_profile_url(nil, _base_url), do: ""

  @doc """
  Format social media URL from handle.
  """
  def social_url(handle, platform) when is_binary(handle) and handle != "" do
    # Remove @ symbol if present
    clean_handle = String.replace(handle, ~r/^@/, "")

    case platform do
      :instagram -> "https://instagram.com/#{clean_handle}"
      :x -> "https://x.com/#{clean_handle}"
      :youtube ->
        # Handle both @username and full URLs
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://youtube.com/@#{clean_handle}"
        end
      :tiktok -> "https://tiktok.com/@#{clean_handle}"
      :linkedin ->
        # Handle both username and full URLs
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://linkedin.com/in/#{clean_handle}"
        end
      _ -> "#"
    end
  end

  def social_url(_, _), do: nil

  @doc """
  Get the appropriate icon for a social platform.
  """
  def social_icon(platform) do
    case platform do
      :instagram -> "🔗"  # Could be replaced with actual icons
      :x -> "🔗"
      :youtube -> "🔗"
      :tiktok -> "🔗"
      :linkedin -> "🔗"
      _ -> "🔗"
    end
  end

  @doc """
  Format website URL to ensure it has a protocol.
  """
  def format_website_url(url) when is_binary(url) and url != "" do
    if String.starts_with?(url, ["http://", "https://"]) do
      url
    else
      "https://#{url}"
    end
  end

  def format_website_url(_), do: nil

  @doc """
  Get a list of social media platforms that the user has configured.
  """
  def social_links(user) do
    [
      {:instagram, user.instagram_handle},
      {:x, user.x_handle},
      {:youtube, user.youtube_handle},
      {:tiktok, user.tiktok_handle},
      {:linkedin, user.linkedin_handle}
    ]
    |> Enum.filter(fn {_platform, handle} ->
      handle && String.trim(handle) != ""
    end)
  end

  @doc """
  Get social platform display name.
  """
  def platform_name(platform) do
    case platform do
      :instagram -> "Instagram"
      :x -> "X"
      :youtube -> "YouTube"
      :tiktok -> "TikTok"
      :linkedin -> "LinkedIn"
      _ -> to_string(platform)
    end
  end

  @doc """
  Generate SEO meta tags for profile pages
  """
  def profile_meta_tags(%User{} = user) do
    User.profile_meta_tags(user)
  end

  def profile_meta_tags(nil), do: %{}
end
