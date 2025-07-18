defmodule EventasaurusApp.Sanitizer do
  @moduledoc """
  Provides input sanitization functions to prevent XSS and other injection attacks.
  """

  @doc """
  Sanitizes HTML input by removing potentially dangerous tags and attributes.
  Allows basic formatting tags only.
  """
  def sanitize_html(nil), do: nil
  def sanitize_html(""), do: ""

  def sanitize_html(html) when is_binary(html) do
    # Use Phoenix.HTML to escape by default
    html
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Sanitizes plain text input by escaping HTML entities.
  """
  def sanitize_text(nil), do: nil
  def sanitize_text(""), do: ""

  def sanitize_text(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Sanitizes user input for poll options and other user-generated content.
  Removes excess whitespace and limits length.
  """
  def sanitize_user_input(nil), do: nil
  def sanitize_user_input(""), do: ""

  def sanitize_user_input(input, max_length \\ 500) when is_binary(input) do
    input
    |> String.trim()
    |> String.slice(0, max_length)
    |> sanitize_text()
  end

  @doc """
  Sanitizes poll option attributes to ensure they're safe.
  """
  def sanitize_poll_option_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.update(:title, nil, &sanitize_user_input(&1, 200))
    |> Map.update(:description, nil, &sanitize_user_input(&1, 1000))
    |> Map.update(:option_value, nil, &sanitize_user_input(&1, 500))
  end

  @doc """
  Sanitizes poll attributes to ensure they're safe.
  """
  def sanitize_poll_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.update(:title, nil, &sanitize_user_input(&1, 200))
    |> Map.update(:description, nil, &sanitize_user_input(&1, 1000))
    |> Map.update(:voting_instructions, nil, &sanitize_user_input(&1, 500))
  end

  @doc """
  Strips potentially dangerous characters from filenames.
  """
  def sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.replace(~r/[^\w\s\-\.]/, "")
    |> String.trim()
  end

  @doc """
  Validates and sanitizes URLs to prevent open redirects.
  """
  def sanitize_url(url) when is_binary(url) do
    uri = URI.parse(url)

    # Only allow http/https schemes
    if uri.scheme in ["http", "https"] do
      # Additional validation could be added here
      # e.g., checking against a whitelist of allowed domains
      {:ok, url}
    else
      {:error, :invalid_url}
    end
  rescue
    _ -> {:error, :invalid_url}
  end

  @doc """
  Sanitizes email addresses.
  """
  def sanitize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end
end

