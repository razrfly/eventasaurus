defmodule EventasaurusDiscovery.Utils.UTF8 do
  @moduledoc """
  UTF-8 validation and normalization utilities for scraped content.

  Ensures that all strings stored in the database are valid UTF-8,
  preventing Postgrex encoding errors.
  """

  @doc """
  Ensures a string contains only valid UTF-8 sequences.
  Aggressively fixes known corruption patterns from Ticketmaster and other sources.

  ## Examples

      iex> UTF8.ensure_valid_utf8("Valid UTF-8 – string")
      "Valid UTF-8 – string"

      iex> broken = <<84, 101, 115, 116, 226, 32, 83>>  # Broken UTF-8
      iex> UTF8.ensure_valid_utf8(broken)
      "Test - S"
  """
  def ensure_valid_utf8(nil), do: nil

  def ensure_valid_utf8(string) when is_binary(string) do
    # Fast path: check validity first
    if String.valid?(string) do
      string
    else
      # Aggressively fix known corruption patterns
      fix_corrupt_utf8(string)
    end
  end

  def ensure_valid_utf8(other), do: to_string(other) |> ensure_valid_utf8()

  # Main corruption fixing function
  defp fix_corrupt_utf8(binary) do
    # Use general UTF-8 fixing that handles ANY invalid sequences
    fixed = fix_broken_utf8_sequences(binary)

    # Validate the result
    if String.valid?(fixed) do
      fixed
    else
      # Last resort: normalize with Erlang and, if needed, drop invalid codepoints safely
      case :unicode.characters_to_binary(fixed, :utf8, :utf8) do
        valid when is_binary(valid) ->
          valid

        {:error, good, _bad} ->
          good

        {:incomplete, good, _bad} ->
          good

        _ ->
          # Ultimate fallback: keep only valid UTF-8 codepoints (skip invalid bytes)
          # This bitstring comprehension safely iterates through valid UTF-8 sequences only
          for <<cp::utf8 <- fixed>>, into: "", do: <<cp::utf8>>
      end
    end
  end

  # Fix broken UTF-8 sequences using byte-level analysis
  defp fix_broken_utf8_sequences(binary) do
    # Convert to bytes for detailed analysis and fixing
    binary
    |> :binary.bin_to_list()
    |> fix_bytes([])
    |> :binary.list_to_bin()
  end

  defp fix_bytes([], acc), do: Enum.reverse(acc)

  # Handle ANY multi-byte UTF-8 starter that's incomplete or corrupted
  # UTF-8 byte patterns:
  # 0xC0-0xDF: 2-byte sequence starter (needs 1 continuation byte)
  # 0xE0-0xEF: 3-byte sequence starter (needs 2 continuation bytes)
  # 0xF0-0xF7: 4-byte sequence starter (needs 3 continuation bytes)

  # 2-byte sequence
  defp fix_bytes([b1, b2 | rest], acc) when b1 >= 0xC0 and b1 <= 0xDF do
    if b2 >= 0x80 and b2 <= 0xBF do
      # Valid continuation, keep it
      fix_bytes(rest, [b2, b1 | acc])
    else
      # Invalid continuation, skip the starter byte and continue
      fix_bytes([b2 | rest], acc)
    end
  end

  # 3-byte sequence (like 0xe2 for en-dash)
  defp fix_bytes([b1, b2, b3 | rest], acc) when b1 >= 0xE0 and b1 <= 0xEF do
    if b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF do
      # Valid continuations, keep it
      fix_bytes(rest, [b3, b2, b1 | acc])
    else
      # Invalid continuation, skip the starter and continue
      fix_bytes([b2, b3 | rest], acc)
    end
  end

  # 4-byte sequence
  defp fix_bytes([b1, b2, b3, b4 | rest], acc) when b1 >= 0xF0 and b1 <= 0xF7 do
    if b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF and b4 >= 0x80 and b4 <= 0xBF do
      # Valid continuations, keep it
      fix_bytes(rest, [b4, b3, b2, b1 | acc])
    else
      # Invalid continuation, skip the starter and continue
      fix_bytes([b2, b3, b4 | rest], acc)
    end
  end

  # Handle incomplete sequences at end of string
  defp fix_bytes([b1], acc) when b1 >= 0xC0 do
    # Multi-byte starter at end with no continuation bytes - skip it
    fix_bytes([], acc)
  end

  defp fix_bytes([b1, b2], acc) when b1 >= 0xE0 and b1 <= 0xEF do
    # 3-byte starter with only 1 continuation - skip starter, keep valid byte if ASCII
    if b2 < 0x80 do
      fix_bytes([], [b2 | acc])
    else
      fix_bytes([], acc)
    end
  end

  # Valid ASCII or continuation bytes that aren't part of a sequence
  defp fix_bytes([byte | rest], acc) when byte < 0x80 do
    # Valid ASCII, keep it
    fix_bytes(rest, [byte | acc])
  end

  # Orphaned continuation bytes (0x80-0xBF without starter)
  defp fix_bytes([byte | rest], acc) when byte >= 0x80 and byte <= 0xBF do
    # Skip orphaned continuation bytes
    fix_bytes(rest, acc)
  end

  # Any other byte pattern
  defp fix_bytes([_byte | rest], acc) do
    # Skip invalid bytes
    fix_bytes(rest, acc)
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

  def ensure_valid_utf8_with_logging(other, context),
    do: to_string(other) |> ensure_valid_utf8_with_logging(context)
end
