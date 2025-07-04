defmodule EventasaurusWeb.Helpers.AvatarHelper do
  @moduledoc """
  Helper functions for rendering avatars in templates.
  """

  alias EventasaurusApp.Avatars
  alias EventasaurusApp.Accounts.User
  import Phoenix.HTML.Tag

  @doc """
  Renders an avatar image tag for a user.

  ## Examples

      <%= avatar_img(@user) %>
      <%= avatar_img(@user, size: 50, class: "rounded-full") %>
      <%= avatar_img(@user.email, size: 32, alt: "User avatar") %>
  """
  def avatar_img(user_or_email, options \\ [])

  def avatar_img(%User{} = user, options) do
    options = normalize_opts(options)
    {img_options, avatar_options} = split_options(options)

    src = Avatars.generate_user_avatar(user, avatar_options)
    alt = Keyword.get(img_options, :alt, user.name || "User avatar")

    img_options =
      img_options
      |> Keyword.put(:src, src)
      |> Keyword.put(:alt, alt)
      |> Keyword.put_new(:class, "avatar")

    tag(:img, img_options)
  end

  def avatar_img(email, options) when is_binary(email) do
    options = normalize_opts(options)
    {img_options, avatar_options} = split_options(options)

    src = Avatars.generate_user_avatar(email, avatar_options)
    alt = Keyword.get(img_options, :alt, "User avatar")

    img_options =
      img_options
      |> Keyword.put(:src, src)
      |> Keyword.put(:alt, alt)
      |> Keyword.put_new(:class, "avatar")

    tag(:img, img_options)
  end

  def avatar_img(_, _), do: ""

    @doc """
  Renders an avatar URL for use in other contexts.

  Accepts options as either a keyword list or map.

  ## Examples

      <div style="background-image: url(<%= avatar_url(@user) %>)"></div>
      <%= avatar_url(@user, size: 100) %>
      <%= avatar_url(@user, %{size: 100, backgroundColor: "blue"}) %>
  """
  def avatar_url(user_or_email, options \\ [])

  def avatar_url(%User{} = user, options) do
    options = normalize_opts(options)
    Avatars.generate_user_avatar(user, options)
  end

  def avatar_url(email, options) when is_binary(email) do
    options = normalize_opts(options)
    Avatars.generate_user_avatar(email, options)
  end

  def avatar_url(_, _), do: ""

  @doc """
  Renders an event avatar for the event host/organizers.

  ## Examples

      <%= event_avatar_img(@event) %>
      <%= event_avatar_img(@event, size: 64) %>
  """
  def event_avatar_img(event, options \\ []) do
    options = normalize_opts(options)
    {img_options, avatar_options} = split_options(options)

    src = Avatars.generate_event_avatar(event.id, avatar_options)
    alt = Keyword.get(img_options, :alt, "#{event.title} avatar")

    img_options =
      img_options
      |> Keyword.put(:src, src)
      |> Keyword.put(:alt, alt)
      |> Keyword.put_new(:class, "avatar")

    tag(:img, img_options)
  end

  @doc """
  Renders an avatar component with a specific size preset.

  ## Examples

      <%= avatar_img_size(@user, :sm) %>  # 32px
      <%= avatar_img_size(@user, :md) %>  # 48px
      <%= avatar_img_size(@user, :lg) %>  # 64px
      <%= avatar_img_size(@user, :xl) %>  # 96px
  """
  def avatar_img_size(user_or_email, size_preset, options \\ [])

  def avatar_img_size(user_or_email, :xs, options) do
    merged_options = merge_size_options([size: 24, class: "w-6 h-6 rounded-full"], options)
    avatar_img(user_or_email, merged_options)
  end

  def avatar_img_size(user_or_email, :sm, options) do
    merged_options = merge_size_options([size: 32, class: "w-8 h-8 rounded-full"], options)
    avatar_img(user_or_email, merged_options)
  end

  def avatar_img_size(user_or_email, :md, options) do
    merged_options = merge_size_options([size: 48, class: "w-12 h-12 rounded-full"], options)
    avatar_img(user_or_email, merged_options)
  end

  def avatar_img_size(user_or_email, :lg, options) do
    merged_options = merge_size_options([size: 64, class: "w-16 h-16 rounded-full"], options)
    avatar_img(user_or_email, merged_options)
  end

  def avatar_img_size(user_or_email, :xl, options) do
    merged_options = merge_size_options([size: 96, class: "w-24 h-24 rounded-full"], options)
    avatar_img(user_or_email, merged_options)
  end

  def avatar_img_size(user_or_email, _size, options) do
    options = normalize_opts(options)
    avatar_img(user_or_email, options)
  end

  # Private helper to normalize options from map to keyword list
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(opts), do: opts

  # Private helper to merge size options while preserving and concatenating classes
  defp merge_size_options(base_options, user_options) do
    user_options = normalize_opts(user_options)
    base_class = Keyword.get(base_options, :class, "")
    user_class = Keyword.get(user_options, :class, "")

    combined_class = case {base_class, user_class} do
      {"", ""} -> ""
      {base, ""} -> base
      {"", user} -> user
      {base, user} -> "#{base} #{user}"
    end

    base_options
    |> Keyword.merge(user_options)
    |> Keyword.put(:class, combined_class)
  end

  # Private helper to split avatar generation options from img tag options
  defp split_options(options) do
    avatar_keys = [:size, :backgroundColor, :backgroundBorderRadius, :radius, :scale]

    {avatar_opts, img_opts} = Enum.split_with(options, fn {key, _} ->
      key in avatar_keys
    end)

    {img_opts, Map.new(avatar_opts)}
  end
end
