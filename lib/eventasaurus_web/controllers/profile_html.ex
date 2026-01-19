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
      :instagram ->
        "https://instagram.com/#{clean_handle}"

      :x ->
        "https://x.com/#{clean_handle}"

      :youtube ->
        # Handle both @username and full URLs
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://youtube.com/@#{clean_handle}"
        end

      :tiktok ->
        "https://tiktok.com/@#{clean_handle}"

      :linkedin ->
        # Handle both username and full URLs
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://linkedin.com/in/#{clean_handle}"
        end

      _ ->
        "#"
    end
  end

  def social_url(_, _), do: nil

  @doc """
  Get the appropriate icon for a social platform.
  """
  def social_icon(platform) do
    case platform do
      # Could be replaced with actual icons
      :instagram -> "🔗"
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

  @doc """
  Format a join date for display
  """
  def format_join_date(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    month_name = Calendar.strftime(date, "%B")
    "Joined #{month_name} #{date.year}"
  end

  def format_join_date(%NaiveDateTime{} = naive_datetime) do
    date = NaiveDateTime.to_date(naive_datetime)
    month_name = Calendar.strftime(date, "%B")
    "Joined #{month_name} #{date.year}"
  end

  def format_join_date(nil), do: ""

  @doc """
  Format event date for display in event cards (24-hour format)
  """
  def format_event_date(datetime, timezone \\ nil)

  def format_event_date(%DateTime{} = datetime, timezone) do
    case timezone do
      tz when is_binary(tz) ->
        try do
          datetime
          |> DateTime.shift_zone!(tz)
          |> Calendar.strftime("%a, %b %d, %H:%M")
        rescue
          _ -> Calendar.strftime(datetime, "%a, %b %d, %H:%M UTC")
        end

      _ ->
        Calendar.strftime(datetime, "%a, %b %d, %H:%M UTC")
    end
  end

  def format_event_date(nil, _timezone), do: "Date TBD"

  @doc """
  Get event cover image URL, with fallbacks
  """
  def event_cover_image_url(event) do
    cond do
      event.cover_image_url && event.cover_image_url != "" ->
        event.cover_image_url

      event.external_image_data && Map.get(event.external_image_data, "url") ->
        Map.get(event.external_image_data, "url")

      true ->
        # Fallback gradient based on event title
        seed = :erlang.phash2(event.title || "event")
        "https://api.dicebear.com/9.x/shapes/svg?seed=#{seed}&backgroundColor=gradient"
    end
  end

  @doc """
  Get event status badge color
  """
  def event_status_color(status) do
    case status do
      :confirmed -> "bg-green-100 text-green-800"
      :draft -> "bg-gray-100 text-gray-800"
      :polling -> "bg-blue-100 text-blue-800"
      :threshold -> "bg-yellow-100 text-yellow-800"
      :canceled -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  @doc """
  Get human readable event status
  """
  def event_status_text(status) do
    case status do
      :confirmed -> "Confirmed"
      :draft -> "Draft"
      :polling -> "Polling"
      :threshold -> "Threshold"
      :canceled -> "Canceled"
      _ -> to_string(status)
    end
  end

  @doc """
  Format event location for display
  """
  def format_event_location(event) do
    cond do
      event.venue && event.venue.name ->
        event.venue.name

      Map.get(event, :virtual_venue_url) && event.virtual_venue_url != "" ->
        "Virtual Event"

      Map.get(event, :is_virtual) == true ->
        "Virtual Event"

      true ->
        "Location TBD"
    end
  end
end
