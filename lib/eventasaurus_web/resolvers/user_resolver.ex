defmodule EventasaurusWeb.Resolvers.UserResolver do
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Avatars
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event

  @spec search_users_for_organizers(any(), map(), map()) :: {:ok, [map()]} | {:error, String.t()}
  def search_users_for_organizers(_parent, args, %{context: %{current_user: current_user}}) do
    %{query: query, slug: slug} = args
    limit = Map.get(args, :limit, 20)

    with %Event{} = event <- Events.get_event_by_slug(slug),
         true <- Events.user_is_organizer?(event, current_user) do
      results =
        Accounts.search_users_for_organizers(query,
          limit: limit,
          exclude_user_id: current_user.id,
          event_id: event.id,
          requesting_user_id: current_user.id
        )
        |> Enum.map(fn user ->
          Map.put(user, :avatar_url, Avatars.generate_user_avatar(user))
        end)

      {:ok, results}
    else
      nil -> {:error, "Event not found"}
      false -> {:error, "Unauthorized"}
    end
  end
end
