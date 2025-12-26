defmodule EventasaurusWeb.Plugs.LanguagePlug do
  @moduledoc """
  Plug for handling user language preferences.

  Sets the current language based on:
  1. Query parameter (?lang=fr)
  2. Session storage
  3. Cookie (language_preference)
  4. Accept-Language header
  5. Default to "en"

  Note: This plug no longer hard-codes supported languages.
  Language availability is determined dynamically by the LanguageDiscovery module
  based on country data and available translations.
  """

  import Plug.Conn

  @default_language "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    language = determine_language(conn)

    conn
    |> maybe_put_session_language(language)
    |> assign(:language, language)
  end

  # Only write to session if:
  # 1. Session is available (not skipped for caching)
  # 2. Language has changed from what's in session
  defp maybe_put_session_language(conn, language) do
    cond do
      # Skip session write if session is being skipped for caching
      conn.assigns[:skip_session] ->
        conn

      # Only write if language changed
      get_session(conn, :language) != language ->
        put_session(conn, :language, language)

      # No change needed
      true ->
        conn
    end
  end

  defp determine_language(conn) do
    # 1. Check query parameter
    case get_normalized_language(conn.params["lang"]) do
      lang when is_binary(lang) and byte_size(lang) == 2 ->
        lang

      _ ->
        # 2. Check session
        case get_normalized_language(get_session(conn, :language)) do
          lang when is_binary(lang) and byte_size(lang) == 2 ->
            lang

          _ ->
            # 3. Check cookie
            case extract_language_from_cookie(conn) do
              lang when is_binary(lang) and byte_size(lang) == 2 ->
                lang

              _ ->
                # 4. Check Accept-Language header
                case extract_language_from_header(conn) do
                  lang when is_binary(lang) and byte_size(lang) == 2 ->
                    lang

                  _ ->
                    @default_language
                end
            end
        end
    end
  end

  defp extract_language_from_cookie(conn) do
    case conn.req_cookies do
      %{"language_preference" => lang} ->
        get_normalized_language(lang)

      _ ->
        nil
    end
  end

  defp extract_language_from_header(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        header
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn lang ->
          lang
          |> String.split(";")
          |> List.first()
          |> get_normalized_language()
        end)
        |> Enum.find(&(&1 && byte_size(&1) == 2))

      _ ->
        nil
    end
  end

  # Normalize language code to lowercase 2-letter ISO code
  defp get_normalized_language(nil), do: nil

  defp get_normalized_language(lang) when is_binary(lang) do
    lang
    |> String.downcase()
    |> String.slice(0..1)
  end

  defp get_normalized_language(_), do: nil
end
