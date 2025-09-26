defmodule EventasaurusWeb.Plugs.LanguagePlug do
  @moduledoc """
  Plug for handling user language preferences.

  Sets the current language based on:
  1. Query parameter (?lang=pl)
  2. Session storage
  3. Cookie (language_preference)
  4. Accept-Language header
  5. Default to "en"
  """

  import Plug.Conn

  @supported_languages ["en", "pl"]
  @default_language "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    language = determine_language(conn)

    conn
    |> put_session(:language, language)
    |> assign(:language, language)
    |> assign(:supported_languages, @supported_languages)
  end

  defp determine_language(conn) do
    # 1. Check query parameter
    case conn.params["lang"] do
      lang when lang in @supported_languages ->
        lang

      _ ->
        # 2. Check session
        case get_session(conn, :language) do
          lang when lang in @supported_languages ->
            lang

          _ ->
            # 3. Check cookie
            case extract_language_from_cookie(conn) do
              lang when lang in @supported_languages ->
                lang

              _ ->
                # 4. Check Accept-Language header
                case extract_language_from_header(conn) do
                  lang when lang in @supported_languages -> lang
                  _ -> @default_language
                end
            end
        end
    end
  end

  defp extract_language_from_cookie(conn) do
    case conn.req_cookies do
      %{"language_preference" => lang} when lang in @supported_languages ->
        lang

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
          |> String.downcase()
          |> String.slice(0..1)
        end)
        |> Enum.find(&(&1 in @supported_languages))

      _ ->
        nil
    end
  end
end
