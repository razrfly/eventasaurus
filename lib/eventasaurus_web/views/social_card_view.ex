defmodule EventasaurusWeb.SocialCardView do
  @moduledoc """
  Helper functions for SVG template rendering in social cards.

  This module provides utility functions for safely rendering dynamic content
  in SVG templates, including text escaping, color formatting, and layout calculations.
  """

  @doc """
  Helper function to ensure text fits within specified line limits.
  Truncates text if it exceeds the maximum length for proper display in social cards.
  """
  def truncate_title(title, max_length \\ 60) do
    if String.length(title) <= max_length do
      title
    else
      title
      |> String.slice(0, max_length - 3)
      |> Kernel.<>("...")
    end
  end

    @doc """
  Formats title text for multi-line display in SVG.
  Splits long titles into multiple lines for better readability.

  ## Parameters

    * `title` - The event title to format
    * `line_number` - Which line to return (0, 1, or 2)
    * `max_chars_per_line` - Maximum characters per line (default: 25)

  ## Returns

    * String content for the specified line, or empty string if line doesn't exist
  """
  def format_title(title, line_number, max_chars_per_line \\ 25)

  def format_title(title, line_number, max_chars_per_line) when is_binary(title) do
    words = String.split(title, " ")
    lines = split_into_lines(words, max_chars_per_line, [])

    case Enum.at(lines, line_number) do
      nil -> ""
      line -> svg_escape(line)
    end
  end

  def format_title(_, _, _), do: ""

  # Private helper to split words into lines
  defp split_into_lines([], _max_chars, acc), do: Enum.reverse(acc)
  defp split_into_lines(_words, _max_chars, acc) when length(acc) >= 3 do
    # Limit to 3 lines maximum
    Enum.reverse(acc)
  end
  defp split_into_lines(words, max_chars, acc) do
    {line_words, remaining_words} = take_words_for_line(words, max_chars, [])
    line = Enum.join(line_words, " ")

    case remaining_words do
      [] -> Enum.reverse([line | acc])
      _ -> split_into_lines(remaining_words, max_chars, [line | acc])
    end
  end

  # Take words until we exceed max_chars
  defp take_words_for_line([], _max_chars, acc), do: {Enum.reverse(acc), []}
  defp take_words_for_line([word | rest] = words, max_chars, acc) do
    current_line = Enum.join(Enum.reverse([word | acc]), " ")

    if String.length(current_line) <= max_chars do
      take_words_for_line(rest, max_chars, [word | acc])
    else
      case acc do
        [] -> {[word], rest}  # Single word exceeds limit, take it anyway
        _ -> {Enum.reverse(acc), words}  # Return accumulated words
      end
    end
  end

  @doc """
  Escapes text content for safe use in SVG templates.
  Prevents SVG injection by properly encoding special characters.
  """
  def svg_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def svg_escape(nil), do: ""

  @doc """
  Generates CSS-safe color values from theme colors.
  Ensures color values are properly formatted for SVG gradients.
  """
  def format_color(color) when is_binary(color) do
    # Ensure color starts with # if it's a hex color
    case color do
      "#" <> _rest -> color
      color -> "##{color}"
    end
  end

  def format_color(_), do: "#000000"

  @doc """
  Calculates the optimal font size based on title length.
  Ensures text fits properly within the allocated space.
  """
  def calculate_font_size(title) when is_binary(title) do
    length = String.length(title)

    cond do
      length <= 20 -> "48"
      length <= 40 -> "42"
      length <= 60 -> "36"
      true -> "32"
    end
  end

  def calculate_font_size(_), do: "42"

  @doc """
  Determines if an event has a valid image URL.
  """
  def has_image?(%{cover_image_url: url}) when is_binary(url) and url != "", do: true
  def has_image?(_), do: false

  @doc """
  Gets a safe image URL for SVG rendering.
  Returns the URL if valid, otherwise returns nil.
  """
  def safe_image_url(%{cover_image_url: url}) when is_binary(url) and url != "" do
    svg_escape(url)
  end
  def safe_image_url(_), do: nil

  @doc """
  Gets a local image path for SVG rendering by downloading external images.
  Returns a local file path if successful, otherwise returns nil.
  """
  def local_image_path(%{cover_image_url: url}) when is_binary(url) and url != "" do
    case Eventasaurus.Services.SvgConverter.download_image_locally(url) do
      {:ok, local_path} -> local_path
      {:error, _reason} -> nil
    end
  end
  def local_image_path(_), do: nil
end
