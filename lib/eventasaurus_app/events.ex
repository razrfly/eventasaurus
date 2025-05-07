defmodule EventasaurusApp.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Event, EventUser}
  alias EventasaurusApp.Accounts.User

  @doc """
  Returns the list of events.
  """
  def list_events do
    Repo.all(Event)
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist.
  """
  def get_event!(id), do: Repo.get!(Event, id) |> Repo.preload([:venue, :users])

  @doc """
  Gets a single event.

  Returns nil if the Event does not exist.
  """
  def get_event(id), do: Repo.get(Event, id) |> maybe_preload()

  defp maybe_preload(nil), do: nil
  defp maybe_preload(event), do: Repo.preload(event, [:venue, :users])

  @doc """
  Gets a single event by slug.

  Returns nil if the Event does not exist.
  """
  def get_event_by_slug(slug) do
    Repo.get_by(Event, slug: slug)
    |> Repo.preload([:venue, :users])
  end

  @doc """
  Gets a single event by slug.

  Raises `Ecto.NoResultsError` if the Event does not exist.
  """
  def get_event_by_slug!(slug) do
    Repo.get_by!(Event, slug: slug)
    |> Repo.preload([:venue, :users])
  end

  @doc """
  Creates an event.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an event.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.
  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  @doc """
  Returns the list of events by a specific user.
  """
  def list_events_by_user(%User{} = user) do
    query = from e in Event,
            join: eu in EventUser, on: e.id == eu.event_id,
            where: eu.user_id == ^user.id,
            preload: [:venue, :users]

    Repo.all(query)
  end

  @doc """
  Adds a user as an organizer to an event.
  """
  def add_user_to_event(%Event{} = event, %User{} = user, role \\ nil) do
    %EventUser{}
    |> EventUser.changeset(%{
      event_id: event.id,
      user_id: user.id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user as an organizer from an event.
  """
  def remove_user_from_event(%Event{} = event, %User{} = user) do
    from(eu in EventUser, where: eu.event_id == ^event.id and eu.user_id == ^user.id)
    |> Repo.delete_all()
  end

  @doc """
  Lists all organizers of an event.
  """
  def list_event_organizers(%Event{} = event) do
    query = from u in User,
            join: eu in EventUser, on: u.id == eu.user_id,
            where: eu.event_id == ^event.id

    Repo.all(query)
  end

  @doc """
  Checks if a user is an organizer of an event.
  """
  def user_is_organizer?(%Event{} = event, %User{} = user) do
    query = from eu in EventUser,
            where: eu.event_id == ^event.id and eu.user_id == ^user.id,
            select: count(eu.id)

    Repo.one(query) > 0
  end

  @doc """
  Creates an event and associates it with a user in a single transaction.
  """
  def create_event_with_organizer(event_attrs, %User{} = user) do
    Repo.transaction(fn ->
      with {:ok, event} <- create_event(event_attrs),
           {:ok, _} <- add_user_to_event(event, user) do
        event |> Repo.preload([:venue, :users])
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
