defmodule Eventasaurus.Utils.Text do
  @moduledoc """
  Shared text utilities for formatting and truncation.
  """

  @doc """
  Truncates text to the specified maximum length, ensuring the result
  never exceeds max_length by reserving space for ellipsis.

  Attempts to break at word boundaries when possible to avoid cutting words.

  ## Examples

      iex> Eventasaurus.Utils.Text.truncate_text("Hello world", 20)
      "Hello world"

      iex> Eventasaurus.Utils.Text.truncate_text("This is a very long text", 10)
      "This is..."

      iex> Eventasaurus.Utils.Text.truncate_text("Supercalifragilisticexpialidocious", 10)
      "Superc..."

  """
  @spec truncate_text(String.t() | nil, pos_integer()) :: String.t()
  def truncate_text(nil, _max_length), do: ""
  def truncate_text(text, _max_length) when not is_binary(text), do: to_string(text)

  def truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      # Reserve 3 characters for ellipsis to ensure we never exceed max_length
      truncate_limit = max_length - 3

      # Get the text up to our truncate limit
      truncated = String.slice(text, 0, truncate_limit)

      # Try to break at word boundary
      words = String.split(truncated, " ")

      if length(words) > 1 do
        # Drop the last word (might be incomplete) and rejoin
        words
        |> Enum.drop(-1)
        |> Enum.join(" ")
        |> Kernel.<>("...")
      else
        # Only one word or no spaces, just add ellipsis
        truncated <> "..."
      end
    end
  end
end
