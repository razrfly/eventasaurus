defmodule EventasaurusWeb.Schema.Middleware.AuthorizeOrganizer do
  @moduledoc """
  Absinthe middleware that checks if the current user is an organizer
  of the event specified by :event_slug in the arguments.

  Returns NOT_FOUND for both missing events and unauthorized access
  (error masking per audit point #4).
  """

  @behaviour Absinthe.Middleware

  alias EventasaurusApp.Events

  @impl true
  def call(resolution, _config) do
    user = resolution.context[:current_user]

    # Extract event_slug from args — supports both top-level and nested input patterns
    event_slug =
      resolution.arguments[:event_slug] ||
        resolution.arguments[:slug] ||
        get_in(resolution.arguments, [:input, :event_slug])

    case authorize(user, event_slug) do
      {:ok, event} ->
        # Put the resolved event in context so the resolver doesn't need to re-fetch
        context = Map.put(resolution.context, :authorized_event, event)
        %{resolution | context: context}

      :error ->
        resolution
        |> Absinthe.Resolution.put_result({:error, message: "NOT_FOUND", code: "NOT_FOUND"})
    end
  end

  defp authorize(nil, _slug), do: :error
  defp authorize(_user, nil), do: :error

  defp authorize(user, slug) do
    case Events.get_event_by_slug(slug) do
      nil ->
        :error

      event ->
        if Events.user_is_organizer?(event, user) do
          {:ok, event}
        else
          :error
        end
    end
  end
end
