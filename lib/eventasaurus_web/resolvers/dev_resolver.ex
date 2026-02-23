defmodule EventasaurusWeb.Resolvers.DevResolver do
  alias EventasaurusWeb.Dev.DevAuth

  def quick_login_users(_parent, _args, _resolution) do
    if DevAuth.enabled?() do
      users = DevAuth.list_quick_login_users()

      result = %{
        personal: map_users(users.personal),
        organizers: map_users(users.organizers),
        participants: map_users(users.participants)
      }

      {:ok, result}
    else
      {:error, "Dev mode is not enabled"}
    end
  end

  defp map_users(user_tuples) do
    Enum.map(user_tuples, fn {user, label} ->
      %{
        id: user.id,
        name: user.name,
        email: user.email,
        label: label
      }
    end)
  end
end
