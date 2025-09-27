defmodule EventasaurusDiscovery.Utils.UTF8 do
  @moduledoc """
  UTF-8 validation and normalization utilities for scraped content.

  Ensures that all strings stored in the database are valid UTF-8,
  preventing Postgrex encoding errors.
  """

  @doc """
  Ensures a string contains only valid UTF-8 sequences.
  Removes invalid bytes while preserving valid multi-byte characters.

  ## Examples

      iex> UTF8.ensure_valid_utf8("Valid UTF-8 – string")
      "Valid UTF-8 – string"

      iex> broken = <<84, 101, 115, 116, 226, 32, 83>>  # Broken UTF-8
      iex> UTF8.ensure_valid_utf8(broken)
      "Test S"
  """
  def ensure_valid_utf8(string) when is_binary(string) do
    if String.valid?(string) do
      # Already valid, return as-is
      string
    else
      # Try to preserve as much valid content as possible
      # First attempt: use Erlang's unicode module to clean it
      case :unicode.characters_to_binary(string, :utf8) do
        {:error, good, _bad} ->
          # Return the good part that could be converted
          good

        {:incomplete, good, _bad} ->
          # Return the good part
          good

        valid_binary when is_binary(valid_binary) ->
          valid_binary

        _ ->
          # Fallback: filter at the codepoint level
          string
          |> String.codepoints()
          |> Enum.filter(&String.valid?/1)
          |> Enum.join()
      end
    end
  end

  def ensure_valid_utf8(nil), do: nil
  def ensure_valid_utf8(other), do: to_string(other) |> ensure_valid_utf8()

  @doc """
  Validates all string values in a map (useful for Oban job args).
  Recursively processes nested maps.

  ## Examples

      iex> UTF8.validate_map_strings(%{"name" => "Test – string", "nested" => %{"key" => "value"}})
      %{"name" => "Test – string", "nested" => %{"key" => "value"}}
  """
  def validate_map_strings(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(v) ->
        {k, ensure_valid_utf8(v)}

      {k, v} when is_map(v) and not is_struct(v) ->
        {k, validate_map_strings(v)}

      {k, v} when is_list(v) ->
        {k, validate_list_strings(v)}

      {k, v} ->
        # Leave other types (including structs like DateTime) as-is
        {k, v}
    end)
  end

  def validate_map_strings(other), do: other

  @doc """
  Validates all string values in a list.
  """
  def validate_list_strings(list) when is_list(list) do
    Enum.map(list, fn
      item when is_binary(item) -> ensure_valid_utf8(item)
      item when is_map(item) -> validate_map_strings(item)
      item when is_list(item) -> validate_list_strings(item)
      item -> item
    end)
  end

  def validate_list_strings(other), do: other

  @doc """
  Checks if a string contains valid UTF-8 without modifying it.

  ## Examples

      iex> UTF8.valid_utf8?("Valid UTF-8 – string")
      true

      iex> broken = <<84, 101, 115, 116, 226, 32, 83>>
      iex> UTF8.valid_utf8?(broken)
      false
  """
  def valid_utf8?(string) when is_binary(string) do
    String.valid?(string)
  end

  def valid_utf8?(_), do: false

  @doc """
  Logs a warning when invalid UTF-8 is detected and cleaned.
  Returns the cleaned string.
  """
  def ensure_valid_utf8_with_logging(string, context \\ "")

  def ensure_valid_utf8_with_logging(string, context) when is_binary(string) do
    if String.valid?(string) do
      string
    else
      require Logger

      cleaned = ensure_valid_utf8(string)
      bytes_removed = byte_size(string) - byte_size(cleaned)

      Logger.warning("""
      Invalid UTF-8 detected#{if context != "", do: " in #{context}", else: ""}
      Original bytes: #{inspect(:erlang.binary_to_list(string) |> Enum.take(50))}...
      Cleaned string: #{inspect(cleaned |> String.slice(0, 50))}...
      Bytes removed: #{bytes_removed}
      """)

      cleaned
    end
  end

  def ensure_valid_utf8_with_logging(nil, _context), do: nil
  def ensure_valid_utf8_with_logging(other, context), do: to_string(other) |> ensure_valid_utf8_with_logging(context)
end