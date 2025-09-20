defmodule EventasaurusWeb.Helpers.LanguageHelpers do
  @moduledoc """
  Language helpers for web components to display localized content.
  """

  alias EventasaurusDiscovery.PublicEvents

  @doc """
  Get the localized title for an event based on current language preference.
  """
  def get_event_title(event, language \\ "en") do
    PublicEvents.get_title(event, language: language)
  end

  @doc """
  Get the localized description for an event based on current language preference.
  """
  def get_event_description(event, language \\ "en") do
    PublicEvents.get_description(event, language: language)
  end

  @doc """
  Get available languages for an event's title.
  """
  def get_event_title_languages(event) do
    PublicEvents.get_title_languages(event)
  end

  @doc """
  Get available languages for an event's description.
  """
  def get_event_description_languages(event) do
    PublicEvents.get_description_languages(event)
  end

  @doc """
  Check if an event has content in a specific language.
  """
  def event_has_language?(event, language) do
    PublicEvents.has_language?(event, language)
  end

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
end