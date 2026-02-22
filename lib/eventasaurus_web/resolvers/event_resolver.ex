defmodule EventasaurusWeb.Resolvers.EventResolver do
  @moduledoc """
  Resolvers for event-related GraphQL queries and mutations.
  """

  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts

  def my_events(_parent, args, %{context: %{current_user: user}}) do
    opts =
      case args[:limit] do
        nil -> []
        limit -> [limit: limit]
      end

    events = Events.list_events_by_user(user, opts)
    {:ok, events}
  end

  def my_event(_parent, _args, %{context: %{authorized_event: event}}) do
    {:ok, event}
  end

  def create_event(_parent, %{input: input}, %{context: %{current_user: user}}) do
    attrs = input_to_attrs(input)

    case Events.create_event_with_organizer(attrs, user) do
      {:ok, event} ->
        {:ok, %{event: event, errors: []}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok, %{event: nil, errors: format_changeset_errors(changeset)}}

      {:error, _reason} ->
        {:ok, %{event: nil, errors: [%{field: "base", message: "Could not create event"}]}}
    end
  end

  def update_event(_parent, %{input: input}, %{context: %{authorized_event: event}}) do
    attrs = input_to_attrs(input)

    case Events.update_event(event, attrs) do
      {:ok, updated_event} ->
        {:ok, %{event: updated_event, errors: []}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok, %{event: nil, errors: format_changeset_errors(changeset)}}
    end
  end

  def delete_event(_parent, _args, %{context: %{authorized_event: event, current_user: user}}) do
    case Events.soft_delete_event(event.id, "Deleted via GraphQL API", user.id) do
      {:ok, _} ->
        {:ok, %{success: true, errors: []}}

      {:error, reason} ->
        {:ok, %{success: false, errors: [%{field: "base", message: humanize_error(reason)}]}}
    end
  end

  def publish_event(_parent, _args, %{context: %{authorized_event: event}}) do
    case Events.publish_event(event) do
      {:ok, updated_event} ->
        {:ok, %{event: updated_event, errors: []}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok, %{event: nil, errors: format_changeset_errors(changeset)}}

      {:error, reason} ->
        {:ok, %{event: nil, errors: [%{field: "base", message: humanize_error(reason)}]}}
    end
  end

  def cancel_event(_parent, _args, %{context: %{authorized_event: event}}) do
    case Events.update_event(event, %{status: :canceled}) do
      {:ok, updated_event} ->
        {:ok, %{event: updated_event, errors: []}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok, %{event: nil, errors: format_changeset_errors(changeset)}}
    end
  end

  def add_organizer(_parent, %{email: email}, %{context: %{authorized_event: event}}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, %{success: false, errors: [%{field: "email", message: "No user found with that email"}]}}

      user ->
        case Events.add_user_to_event(event, user, "organizer") do
          {:ok, _} ->
            {:ok, %{success: true, errors: []}}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:ok, %{success: false, errors: format_changeset_errors(changeset)}}

          {:error, _} ->
            {:ok, %{success: false, errors: [%{field: "base", message: "Could not add organizer"}]}}
        end
    end
  end

  def remove_organizer(_parent, %{user_id: user_id}, %{context: %{authorized_event: event}}) do
    organizers = Events.list_event_organizers(event)

    if length(organizers) <= 1 do
      {:ok, %{success: false, errors: [%{field: "base", message: "Cannot remove the last organizer"}]}}
    else
      user = Enum.find(organizers, &(to_string(&1.id) == to_string(user_id)))

      if user do
        Events.remove_user_from_event(event, user)
        {:ok, %{success: true, errors: []}}
      else
        {:ok, %{success: false, errors: [%{field: "userId", message: "User is not an organizer of this event"}]}}
      end
    end
  end

  # Convert GraphQL input to Ecto-friendly attrs map.
  # Maps field names from the GraphQL convention to the DB column names.
  defp input_to_attrs(input) do
    input
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn
      {:starts_at, v} -> {:start_at, v}
      other -> other
    end)
    |> Enum.into(%{})
  end

  defp humanize_error(:event_not_found), do: "Event not found"
  defp humanize_error(:not_found), do: "Event not found"
  defp humanize_error(:already_deleted), do: "Event has already been deleted"
  defp humanize_error(:unauthorized), do: "You are not authorized to perform this action"
  defp humanize_error(:invalid_params), do: "Invalid parameters"
  defp humanize_error(_reason), do: "An unexpected error occurred"

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{field: to_string(field), message: message}
      end)
    end)
  end
end
