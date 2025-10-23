defmodule EventasaurusWeb.VenueImageProxyController do
  @moduledoc """
  Proxies venue images from external providers to work around CORS and referrer restrictions.

  Google Places Photo URLs have restrictions:
  - Referrer restrictions (only work from specific domains)
  - CORS restrictions (can't be loaded directly in browsers)
  - May expire after some time

  This proxy fetches the images server-side and serves them through our domain.
  """
  use EventasaurusWeb, :controller
  require Logger

  @max_image_size 10_000_000  # 10MB
  @timeout 10_000  # 10 seconds

  def show(conn, %{"provider" => provider, "id" => image_id}) do
    # Decode the image URL from base64
    case Base.url_decode64(image_id, padding: false) do
      {:ok, image_url} ->
        fetch_and_serve_image(conn, provider, image_url)

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid image ID"})
    end
  end

  defp fetch_and_serve_image(conn, provider, image_url) do
    Logger.info("Proxying #{provider} image: #{String.slice(image_url, 0, 100)}...")

    # Fetch the image from the external URL
    case fetch_image(image_url) do
      {:ok, image_data, content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=86400")  # Cache for 24 hours
        |> put_resp_header("x-image-provider", provider)
        |> send_resp(200, image_data)

      {:error, reason} ->
        Logger.warning("Failed to fetch image from #{provider}: #{inspect(reason)}")

        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Failed to fetch image", reason: inspect(reason)})
    end
  end

  defp fetch_image(url) do
    # Validate URL is safe to fetch (prevent SSRF attacks)
    case validate_image_url(url) do
      :ok ->
        fetch_validated_image(url)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_image_url(url) do
    uri = URI.parse(url)

    # Reject non-HTTP(S) schemes
    if uri.scheme not in ["http", "https"] do
      {:error, :invalid_scheme}
    # Check if host is allowed
    else
      if is_allowed_image_host?(uri) do
        :ok
      else
        {:error, :forbidden_host}
      end
    end
  end

  defp is_allowed_image_host?(uri) do
    case uri.host do
      # Block localhost
      host when host in ["localhost", "127.0.0.1", "::1"] ->
        false

      # Check for private IP ranges
      host when is_binary(host) ->
        not is_private_ip?(host)

      _ ->
        false
    end
  end

  defp is_private_ip?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {10, _, _, _}} -> true  # 10.0.0.0/8
      {:ok, {172, b, _, _}} when b >= 16 and b <= 31 -> true  # 172.16.0.0/12
      {:ok, {192, 168, _, _}} -> true  # 192.168.0.0/16
      {:ok, {169, 254, _, _}} -> true  # Cloud metadata 169.254.0.0/16
      {:ok, {127, _, _, _}} -> true  # Loopback
      _ -> false
    end
  end

  defp fetch_validated_image(url) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (compatible; EventasaurusBot/1.0)"},
      {"Accept", "image/*"}
    ]

    case HTTPoison.get(url, headers, timeout: @timeout, recv_timeout: @timeout, follow_redirect: true, max_redirect: 3) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
        # Check content type
        content_type =
          headers
          |> Enum.find(fn {k, _v} -> String.downcase(k) == "content-type" end)
          |> case do
            {_k, v} -> v
            nil -> "image/jpeg"  # Default fallback
          end

        # Validate content type is an image
        if String.starts_with?(content_type, "image/") do
          # Check size
          if byte_size(body) <= @max_image_size do
            {:ok, body, content_type}
          else
            {:error, :image_too_large}
          end
        else
          {:error, :invalid_content_type}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
