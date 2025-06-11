defmodule EventasaurusApp.Avatars do
  @moduledoc """
  Avatar generation utilities using DiceBear API.
  """

  @doc """
  Generates an avatar URL for a given seed.

  The seed can be any string - typically a user ID, email, or name.
  DiceBear will generate a consistent avatar for the same seed.

  ## Examples

      iex> EventasaurusApp.Avatars.generate_url("user123")
      "https://api.dicebear.com/9.x/dylan/svg?seed=user123"

      iex> EventasaurusApp.Avatars.generate_url("user@example.com", size: 100)
      "https://api.dicebear.com/9.x/dylan/svg?seed=user%40example.com&size=100"
  """
  def generate_url(seed, options \\ %{}) do
    config = Application.get_env(:eventasaurus, :avatars)

    base_url = Keyword.get(config, :base_url)
    style = Keyword.get(config, :style)
    format = Keyword.get(config, :format)
    default_options = Keyword.get(config, :default_options, %{})

    # Merge default options with provided options
    merged_options = Map.merge(default_options, options)

        # URL encode the seed (using query format for proper encoding)
    encoded_seed = URI.encode_query([seed: to_string(seed)]) |> String.replace("seed=", "")

    # Build the base URL
    url = "#{base_url}/#{style}/#{format}?seed=#{encoded_seed}"

    # Add any additional options as query parameters
    if map_size(merged_options) > 0 do
      query_params =
        merged_options
        |> Enum.map(fn {key, value} -> "#{key}=#{URI.encode(to_string(value))}" end)
        |> Enum.join("&")

      "#{url}&#{query_params}"
    else
      url
    end
  end

  @doc """
  Generates an avatar URL using a user's email as the seed.
  """
  def generate_user_avatar(user_or_email, options \\ %{})

  def generate_user_avatar(%{email: email}, options) do
    generate_url(email, options)
  end

  def generate_user_avatar(email, options) when is_binary(email) do
    generate_url(email, options)
  end

  @doc """
  Generates an avatar URL using a user's ID as the seed.
  """
  def generate_user_avatar_by_id(user_id, options \\ %{}) do
    generate_url("user_#{user_id}", options)
  end

  @doc """
  Generates an avatar URL for an event using the event ID as seed.
  """
  def generate_event_avatar(event_id, options \\ %{}) do
    generate_url("event_#{event_id}", options)
  end

  @doc """
  Get the current avatar style configuration.
  """
  def current_style do
    config = Application.get_env(:eventasaurus, :avatars)
    Keyword.get(config, :style)
  end

  @doc """
  Get available DiceBear styles.
  """
  def available_styles do
    [
      "adventurer",
      "avataaars",
      "bottts",
      "croodles",
      "dylan",
      "fun-emoji",
      "lorelei",
      "micah",
      "miniavs",
      "notionists",
      "open-peeps",
      "personas"
    ]
  end

  @doc """
  Validate if a style is supported.
  """
  def valid_style?(style) do
    style in available_styles()
  end
end
