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
    PublicEvents.get_title(event, language: language)
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
    PublicEvents.get_description(event, language: language)
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
end
