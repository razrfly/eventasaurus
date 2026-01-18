defmodule EventasaurusDiscovery.Sources.Shared.JsonSanitizer do
  @moduledoc """
  Shared utility for converting Elixir data structures to JSON-safe formats.

  Handles non-JSON-encodable types that may appear in scraper data:
  - DateTime, Date, Time structs → ISO8601 strings
  - Geocoder structs (Coords, Bounds, Location) → plain maps
  - Any other structs → plain maps via Map.from_struct/1
  - Recursive handling for nested maps and lists

  ## Usage

      alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

      # In transformer metadata:
      metadata: %{
        _raw_upstream: JsonSanitizer.sanitize(raw_data)
      }

  ## Why This Exists

  When storing data in JSONB columns, Elixir structs must be converted to
  plain maps/primitives. This module provides consistent sanitization across
  all scraper transformers, preventing Jason.Encoder protocol errors.
  """

  @doc """
  Recursively converts data to JSON-safe format.

  ## Examples

      iex> JsonSanitizer.sanitize(%DateTime{...})
      "2025-01-18T12:00:00Z"

      iex> JsonSanitizer.sanitize(%Geocoder.Coords{lat: 51.5, lon: -0.1, ...})
      %{lat: 51.5, lon: -0.1, bounds: %{...}, location: %{...}}

      iex> JsonSanitizer.sanitize(%{nested: %DateTime{...}})
      %{nested: "2025-01-18T12:00:00Z"}
  """
  @spec sanitize(any()) :: any()
  def sanitize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def sanitize(%Date{} = d), do: Date.to_iso8601(d)
  def sanitize(%Time{} = t), do: Time.to_iso8601(t)

  # Handle Geocoder structs by converting to maps recursively
  def sanitize(%Geocoder.Coords{} = coords) do
    coords |> Map.from_struct() |> sanitize()
  end

  def sanitize(%Geocoder.Bounds{} = bounds) do
    bounds |> Map.from_struct() |> sanitize()
  end

  def sanitize(%Geocoder.Location{} = location) do
    location |> Map.from_struct() |> sanitize()
  end

  # Handle any other structs by converting to maps
  def sanitize(%{__struct__: _} = struct) do
    struct |> Map.from_struct() |> sanitize()
  end

  def sanitize(data) when is_map(data) do
    Map.new(data, fn {key, value} -> {key, sanitize(value)} end)
  end

  def sanitize(data) when is_list(data) do
    Enum.map(data, &sanitize/1)
  end

  def sanitize(data), do: data
end
