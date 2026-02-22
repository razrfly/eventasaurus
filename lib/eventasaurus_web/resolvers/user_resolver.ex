defmodule EventasaurusWeb.Resolvers.UserResolver do
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Events

  def search_users_for_organizers(_parent, args, %{context: %{current_user: current_user}}) do
    %{query: query, slug: slug} = args
    limit = Map.get(args, :limit, 20)

    case Events.get_event_by_slug(slug) do
      nil ->
        {:error, "Event not found"}

      event ->
        results =
          Accounts.search_users_for_organizers(query,
            limit: limit,
            exclude_user_id: current_user.id,
            event_id: event.id,
            requesting_user_id: current_user.id
          )
          |> Enum.map(fn user ->
            Map.put(user, :avatar_url, User.avatar_url(user))
          end)

        {:ok, results}
    end
  end
end
