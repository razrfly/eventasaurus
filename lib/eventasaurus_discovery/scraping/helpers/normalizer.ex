defmodule EventasaurusDiscovery.Scraping.Helpers.Normalizer do
  @moduledoc """
  Text normalization and sanitization utilities for scraped data.
  """

  @doc """
  Normalizes text by trimming whitespace and removing excessive spaces.
  """
  def normalize_text(nil), do: nil

  def normalize_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/[\x00-\x1f\x7f]/, "")
  end

  def normalize_text(_), do: nil

  @doc """
  Creates a URL-safe slug from text.
  """
  def create_slug(nil), do: nil

  def create_slug(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  @doc """
  Normalizes a phone number to a consistent format.
  """
  def normalize_phone(nil), do: nil

  def normalize_phone(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/[^0-9]/, "")

    case String.length(digits) do
      10 ->
        format_us_phone(digits)

      11 ->
        if String.starts_with?(digits, "1") do
          format_us_phone(String.slice(digits, 1..-1//1))
        else
          phone
        end

      _ ->
        phone
    end
  end

  defp format_us_phone(digits) do
    area = String.slice(digits, 0..2)
    prefix = String.slice(digits, 3..5)
    number = String.slice(digits, 6..9)
    "(#{area}) #{prefix}-#{number}"
  end

  @doc """
  Normalizes a URL by ensuring it has a protocol.
  """
  def normalize_url(nil), do: nil

  def normalize_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url

      String.starts_with?(url, "//") ->
        "https:" <> url

      true ->
        "https://" <> url
    end
  end

  @doc """
  Extracts and normalizes social media handles.
  """
  def extract_social_handle(nil), do: nil

  def extract_social_handle(url) when is_binary(url) do
    cond do
      String.contains?(url, "facebook.com") ->
        extract_facebook_handle(url)

      String.contains?(url, "instagram.com") ->
        extract_instagram_handle(url)

      String.contains?(url, "twitter.com") or String.contains?(url, "x.com") ->
        extract_twitter_handle(url)

      true ->
        url
    end
  end

  defp extract_facebook_handle(url) do
    url
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> case do
      nil -> nil
      handle -> "@" <> String.replace(handle, ~r/\?.*/, "")
    end
  end

  defp extract_instagram_handle(url) do
    url
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> Enum.find(&(&1 not in ["www.instagram.com", "instagram.com", "https:", "http:"]))
    |> case do
      nil -> nil
      handle -> "@" <> String.replace(handle, ~r/\?.*/, "")
    end
  end

  defp extract_twitter_handle(url) do
    url
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> case do
      nil -> nil
      handle -> "@" <> String.replace(handle, ~r/\?.*/, "")
    end
  end

  @doc """
  Cleans HTML content by removing tags and entities.
  """
  def clean_html(nil), do: nil

  def clean_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    # Handles ALL HTML entities (400+ entities)
    |> HtmlEntities.decode()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Capitalizes each word in a string (title case).
  """
  def title_case(nil), do: nil

  def title_case(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
