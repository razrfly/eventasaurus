defmodule EventasaurusWeb.Api.V1.Mobile.ProfileController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Accounts.User

  @doc """
  GET /api/v1/mobile/profile

  Returns the current authenticated user's profile.
  """
  def show(conn, _params) do
    user = conn.assigns.user

    json(conn, %{
      user: %{
        id: user.id,
        name: user.name,
        email: user.email,
        username: user.username,
        bio: user.bio,
        avatar_url: User.avatar_url(user),
        profile_url: User.profile_url(user)
      }
    })
  end
end
