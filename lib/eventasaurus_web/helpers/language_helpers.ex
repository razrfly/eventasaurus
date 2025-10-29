defmodule EventasaurusWeb.Helpers.LanguageHelpers do
  @moduledoc """
  Language helpers for web components to display localized content.
  """

  alias EventasaurusDiscovery.PublicEvents

  @doc """
  Get the localized title for an event based on current language preference.
  Handles both regular Events and PublicEvents.
  """
  def get_event_title(event, language \\ "en")

  def get_event_title(
        %{__struct__: EventasaurusDiscovery.PublicEvents.PublicEvent} = event,
        language
      ) do
    PublicEvents.get_title(event, language: language || "en")
  end

  def get_event_title(%{title: title}, _language) when is_binary(title), do: title
  def get_event_title(_, _), do: "Untitled Event"

  @doc """
  Get the localized description for an event based on current language preference.
  Handles both regular Events and PublicEvents.
  """
  def get_event_description(event, language \\ "en")

  def get_event_description(
        %{__struct__: EventasaurusDiscovery.PublicEvents.PublicEvent} = event,
        language
      ) do
    PublicEvents.get_description(event, language: language || "en")
  end

  def get_event_description(%{description: description}, _language) when is_binary(description),
    do: description

  def get_event_description(_, _), do: ""

  @doc """
  Get available languages for an event's title.
  """
  def get_event_title_languages(
        %{__struct__: EventasaurusDiscovery.PublicEvents.PublicEvent} = event
      ) do
    PublicEvents.get_title_languages(event)
  end

  def get_event_title_languages(_), do: ["en"]

  @doc """
  Get available languages for an event's description.
  """
  def get_event_description_languages(
        %{__struct__: EventasaurusDiscovery.PublicEvents.PublicEvent} = event
      ) do
    PublicEvents.get_description_languages(event)
  end

  def get_event_description_languages(_), do: ["en"]

  @doc """
  Check if an event has content in a specific language.
  """
  def event_has_language?(
        %{__struct__: EventasaurusDiscovery.PublicEvents.PublicEvent} = event,
        language
      )
      when is_binary(language) do
    PublicEvents.has_language?(event, language)
  end

  def event_has_language?(_event, _language), do: false

  @doc """
  Get language preference from socket assigns.
  """
  def get_language_from_assigns(%{language: language}), do: language
  def get_language_from_assigns(_), do: "en"

  @doc """
  Generate language switching links.
  """
  def language_switch_params(current_params, new_language) do
    Map.put(current_params, "lang", new_language)
  end

  @doc """
  Convert language code to flag emoji.
  Maps common language codes to their primary country code for flag emoji display.
  """
  def language_flag(lang) do
    country_code = language_to_country_code(lang)
    country_code_to_flag(country_code)
  end

  @doc """
  Get language name display (uppercase language code).
  """
  def language_name(lang) do
    String.upcase(lang)
  end

  @doc """
  Map language codes to their most common country codes for flag display.
  """
  def language_to_country_code(lang) do
    case String.downcase(lang) do
      "en" -> "GB"
      "es" -> "ES"
      "fr" -> "FR"
      "de" -> "DE"
      "it" -> "IT"
      "pt" -> "PT"
      "pl" -> "PL"
      "nl" -> "NL"
      "ru" -> "RU"
      "ja" -> "JP"
      "zh" -> "CN"
      "ko" -> "KR"
      "ar" -> "SA"
      "tr" -> "TR"
      "sv" -> "SE"
      "da" -> "DK"
      "fi" -> "FI"
      "no" -> "NO"
      "cs" -> "CZ"
      "el" -> "GR"
      "he" -> "IL"
      "hi" -> "IN"
      "id" -> "ID"
      "ms" -> "MY"
      "th" -> "TH"
      "vi" -> "VN"
      "uk" -> "UA"
      "ro" -> "RO"
      "hu" -> "HU"
      "sk" -> "SK"
      "bg" -> "BG"
      "hr" -> "HR"
      "sr" -> "RS"
      "sl" -> "SI"
      "lt" -> "LT"
      "lv" -> "LV"
      "et" -> "EE"
      lang -> String.upcase(lang)
    end
  end

  @doc """
  Convert 2-letter country code to Unicode flag emoji.
  Uses Regional Indicator Symbols (🇦 = U+1F1E6, 🇿 = U+1F1FF).
  """
  def country_code_to_flag("XX"), do: "🌐"

  def country_code_to_flag(code) when is_binary(code) and byte_size(code) == 2 do
    code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(fn char ->
      char - ?A + 0x1F1E6
    end)
    |> List.to_string()
  end

  def country_code_to_flag(_), do: "🌐"
end
