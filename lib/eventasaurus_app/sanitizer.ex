defmodule EventasaurusApp.Sanitizer do
  @moduledoc """
  Input sanitization and validation utilities for the polling system.
  
  Provides functions to sanitize user inputs, validate data formats,
  and prevent injection attacks.
  """

  @doc """
  Sanitizes poll title and description inputs.
  """
  def sanitize_poll_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.slice(0, 500)  # Limit length
    |> sanitize_html()
  end

  def sanitize_poll_text(nil), do: nil
  def sanitize_poll_text(_), do: {:error, "Invalid text format"}

  @doc """
  Sanitizes poll option titles.
  """
  def sanitize_option_title(title) when is_binary(title) do
    title
    |> String.trim()
    |> String.slice(0, 200)  # Limit length
    |> sanitize_html()
  end

  def sanitize_option_title(nil), do: nil
  def sanitize_option_title(_), do: {:error, "Invalid title format"}

  @doc """
  Sanitizes metadata fields for poll options.
  """
  def sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      sanitized_key = sanitize_metadata_key(key)
      sanitized_value = sanitize_metadata_value(value)
      Map.put(acc, sanitized_key, sanitized_value)
    end)
  end

  def sanitize_metadata(nil), do: %{}
  def sanitize_metadata(_), do: {:error, "Invalid metadata format"}

  @doc """
  Sanitizes vote values to prevent injection.
  """
  def sanitize_vote_value(value) when is_binary(value) do
    case value do
      v when v in ["yes", "maybe", "no"] -> v
      _ -> {:error, "Invalid vote value"}
    end
  end

  def sanitize_vote_value(value) when is_number(value) do
    # For star ratings or numeric votes
    cond do
      value >= 1 and value <= 5 -> value
      true -> {:error, "Invalid numeric vote value"}
    end
  end

  def sanitize_vote_value(_), do: {:error, "Invalid vote value type"}

  @doc """
  Sanitizes user input for search and filtering.
  """
  def sanitize_search_input(input) when is_binary(input) do
    input
    |> String.trim()
    |> String.slice(0, 100)  # Limit search length
    |> remove_special_chars()
  end

  def sanitize_search_input(nil), do: ""
  def sanitize_search_input(_), do: {:error, "Invalid search input"}

  @doc """
  Validates and sanitizes email addresses.
  """
  def sanitize_email(email) when is_binary(email) do
    email = String.trim(email) |> String.downcase()
    
    if valid_email?(email) do
      email
    else
      {:error, "Invalid email format"}
    end
  end

  def sanitize_email(nil), do: nil
  def sanitize_email(_), do: {:error, "Invalid email format"}

  @doc """
  Validates and sanitizes URLs.
  """
  def sanitize_url(url) when is_binary(url) do
    url = String.trim(url)
    
    if valid_url?(url) do
      url
    else
      {:error, "Invalid URL format"}
    end
  end

  def sanitize_url(nil), do: nil
  def sanitize_url(_), do: {:error, "Invalid URL format"}

  @doc """
  Sanitizes integer inputs with range validation.
  """
  def sanitize_integer(value, min \\ nil, max \\ nil) do
    case Integer.parse(to_string(value)) do
      {int, ""} ->
        cond do
          min != nil and int < min -> {:error, "Value too small"}
          max != nil and int > max -> {:error, "Value too large"}
          true -> int
        end
      _ ->
        {:error, "Invalid integer format"}
    end
  end

  # Private functions

  defp sanitize_html(text) do
    # Basic HTML sanitization - remove potentially dangerous tags
    text
    |> String.replace(~r/<script[^>]*>.*?<\/script>/i, "")
    |> String.replace(~r/<iframe[^>]*>.*?<\/iframe>/i, "")
    |> String.replace(~r/<object[^>]*>.*?<\/object>/i, "")
    |> String.replace(~r/<embed[^>]*>/i, "")
    |> String.replace(~r/<link[^>]*>/i, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/i, "")
    |> String.replace(~r/javascript:/i, "")
    |> String.replace(~r/on\w+\s*=/i, "")
  end

  defp sanitize_metadata_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.slice(0, 50)
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "")
  end

  defp sanitize_metadata_key(key) when is_atom(key) do
    key |> to_string() |> sanitize_metadata_key()
  end

  defp sanitize_metadata_key(_), do: "invalid_key"

  defp sanitize_metadata_value(value) when is_binary(value) do
    sanitize_html(value) |> String.slice(0, 1000)
  end

  defp sanitize_metadata_value(value) when is_number(value), do: value
  defp sanitize_metadata_value(value) when is_boolean(value), do: value
  defp sanitize_metadata_value(value) when is_list(value) do
    Enum.map(value, &sanitize_metadata_value/1)
  end

  defp sanitize_metadata_value(value) when is_map(value) do
    sanitize_metadata(value)
  end

  defp sanitize_metadata_value(_), do: nil

  defp remove_special_chars(text) do
    String.replace(text, ~r/[<>\"'&]/, "")
  end

  defp valid_email?(email) do
    String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end

  defp valid_url?(url) do
    String.match?(url, ~r/^https?:\/\/[^\s]+$/)
  end
end