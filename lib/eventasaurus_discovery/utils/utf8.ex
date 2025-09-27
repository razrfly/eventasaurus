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
      # IMPORTANT: For production issues with Ticketmaster data
      # We need to handle partial UTF-8 sequences that get truncated
      # Common issue: en-dash (—) being truncated to 0xe2 0x20 instead of 0xe2 0x80 0x93

      # First, try to fix known problematic patterns
      # The pattern we're seeing is 0xe2 (start of en-dash) followed by wrong bytes
      # This happens when UTF-8 multi-byte sequences get corrupted
      fixed = string
        # Fix truncated en-dash where next bytes are wrong (e.g., 0xe2 0x20 0x46)
        # Just replace the broken 0xe2 with a regular dash
        |> fix_broken_utf8_sequences()

      # Now validate the fixed string
      if String.valid?(fixed) do
        fixed
      else
        # If still invalid, use Erlang's unicode module to clean it
        case :unicode.characters_to_binary(fixed, :utf8) do
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
  end

  def ensure_valid_utf8(nil), do: nil
  def ensure_valid_utf8(other), do: to_string(other) |> ensure_valid_utf8()

  # Fix broken UTF-8 sequences by detecting and replacing them
  defp fix_broken_utf8_sequences(binary) do
    # Use regex to find and replace broken UTF-8 sequences
    # 0xe2 is the start of many 3-byte UTF-8 sequences (including en-dash and em-dash)
    # When followed by bytes that don't form valid UTF-8, replace with a dash
    binary
    |> :binary.bin_to_list()
    |> fix_bytes([])
    |> :binary.list_to_bin()
  end

  defp fix_bytes([], acc), do: Enum.reverse(acc)

  # Detect 0xe2 followed by invalid continuation bytes
  # In UTF-8, 0xe2 should be followed by bytes in range 0x80-0xBF
  defp fix_bytes([0xe2, b2, b3 | rest], acc) when b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF do
    # This looks like valid UTF-8, keep it
    fix_bytes([b3 | rest], [b2, 0xe2 | acc])
  end

  # Detect 0xe2 followed by non-continuation bytes (like 0x20)
  # This is broken - replace with dash and keep the following bytes
  defp fix_bytes([0xe2, b2 | rest], acc) when b2 < 0x80 or b2 > 0xBF do
    # Replace 0xe2 with " - " and keep processing from b2
    fix_bytes([b2 | rest], [32, 45, 32 | acc])  # " - "
  end

  # Detect standalone 0xe2 at end
  defp fix_bytes([0xe2], acc) do
    fix_bytes([], [32, 45, 32 | acc])  # " - "
  end

  # Valid UTF-8 or other bytes, keep as-is
  defp fix_bytes([byte | rest], acc) do
    fix_bytes(rest, [byte | acc])
  end

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