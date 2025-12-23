defmodule EventasaurusWeb.Helpers.SocialCardHelpers do
  @moduledoc """
  Shared helpers for social card generation across events, polls, and cities.

  This module consolidates common logic for:
  - Hash parsing and validation
  - SVG to PNG conversion
  - Response handling
  - Error handling
  """

  require Logger

  alias Eventasaurus.Services.SvgConverter
  alias Eventasaurus.SocialCards.HashGenerator

  @doc """
  Parses the hash from route parameters, handling both clean and combined formats.

  ## Parameters
    - hash: The hash parameter from the route
    - rest: The rest parameter (usually containing ["png"])

  ## Returns
    - String: The cleaned hash value

  ## Examples
      iex> parse_hash("abc123", ["png"])
      "abc123"

      iex> parse_hash("abc123", ["png", "extra"])
      "abc123"
  """
  @spec parse_hash(String.t(), list()) :: String.t()
  def parse_hash(hash, rest) do
    if rest == ["png"] do
      # Hash is clean, rest contains the extension
      hash
    else
      # Fallback: extract hash from combined parameter
      combined =
        if is_list(rest) and length(rest) > 0 do
          "#{hash}.#{Enum.join(rest, ".")}"
        else
          hash
        end

      String.replace_suffix(combined, ".png", "")
    end
  end

  @doc """
  Validates that the provided hash matches the generated hash for the data.

  ## Parameters
    - data: The event, poll, or city struct
    - final_hash: The hash to validate
    - type: The type of data (:event, :poll, or :city)

  ## Returns
    - boolean: true if hash is valid, false otherwise
  """
  @spec validate_hash(map(), String.t(), atom()) :: boolean()
  def validate_hash(data, final_hash, type \\ :event) do
    HashGenerator.validate_hash(data, final_hash, type)
  end

  @doc """
  Generates a social card PNG from SVG content.

  ## Parameters
    - svg_content: The SVG content to convert
    - slug: The slug for logging and file naming
    - data: The event/poll/city data for additional context

  ## Returns
    - {:ok, png_data} on success
    - {:error, reason} on failure
  """
  @spec generate_png(String.t(), String.t(), map()) :: {:ok, binary()} | {:error, any()}
  def generate_png(svg_content, slug, data) do
    # Check for system dependencies first
    case SvgConverter.verify_rsvg_available() do
      :ok ->
        # Convert SVG to PNG
        case SvgConverter.svg_to_png(svg_content, slug, data) do
          {:ok, png_path} ->
            # Read the PNG file
            case File.read(png_path) do
              {:ok, png_data} ->
                Logger.info(
                  "Successfully generated social card PNG for slug #{slug} (#{byte_size(png_data)} bytes)"
                )

                # Clean up the temporary file
                SvgConverter.cleanup_temp_file(png_path)
                {:ok, png_data}

              {:error, reason} ->
                Logger.error("Failed to read PNG file for slug #{slug}: #{inspect(reason)}")
                SvgConverter.cleanup_temp_file(png_path)
                {:error, :read_failed}
            end

          {:error, reason} ->
            Logger.error("Failed to convert SVG to PNG for slug #{slug}: #{inspect(reason)}")
            {:error, :conversion_failed}
        end

      {:error, :command_not_found} ->
        Logger.error(
          "rsvg-convert command not found - social card generation unavailable. Install librsvg2-bin package."
        )

        {:error, :dependency_missing}
    end
  end

  @doc """
  Sends a successful PNG response with caching headers.

  ## Parameters
    - conn: The Phoenix connection
    - png_data: The PNG binary data
    - final_hash: The hash for the ETag header

  ## Returns
    - conn: The updated connection
  """
  @spec send_png_response(Plug.Conn.t(), binary(), String.t()) :: Plug.Conn.t()
  def send_png_response(conn, png_data, final_hash) do
    import Plug.Conn

    conn
    |> put_resp_content_type("image/png")
    # Cache for 1 year since hash ensures freshness
    |> put_resp_header("cache-control", "public, max-age=31536000")
    |> put_resp_header("etag", "\"#{final_hash}\"")
    |> send_resp(200, png_data)
  end

  @doc """
  Sends an error response based on the error type.

  ## Parameters
    - conn: The Phoenix connection
    - error: The error atom (:dependency_missing, :conversion_failed, etc.)

  ## Returns
    - conn: The updated connection
  """
  @spec send_error_response(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  def send_error_response(conn, :dependency_missing) do
    import Plug.Conn

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(
      503,
      "Social card generation temporarily unavailable - missing system dependency"
    )
  end

  def send_error_response(conn, _error) do
    import Plug.Conn
    send_resp(conn, 500, "Failed to generate social card")
  end

  @doc """
  Sends a redirect response for hash mismatches.

  Computes the expected hash internally from the data and type.

  ## Parameters
    - conn: The Phoenix connection
    - data: The event/poll/city struct
    - slug: The slug for logging
    - received_hash: The hash that was received in the request
    - type: The type of data (:event, :poll, :city, :activity, :venue, :performer, :source_aggregation)

  ## Returns
    - conn: The updated connection
  """
  @spec send_hash_mismatch_redirect(
          Plug.Conn.t(),
          map(),
          String.t(),
          String.t(),
          atom()
        ) ::
          Plug.Conn.t()
  def send_hash_mismatch_redirect(conn, data, slug, received_hash, type) do
    import Plug.Conn

    expected_hash = HashGenerator.generate_hash(data, type)

    Logger.warning(
      "Hash mismatch for #{type} #{slug}. Expected: #{expected_hash}, Got: #{received_hash}"
    )

    # Get the correct URL with current hash
    current_url = HashGenerator.generate_url_path(data, type)

    conn
    |> put_resp_header("location", current_url)
    |> send_resp(301, "Social card URL has been updated")
  end
end
