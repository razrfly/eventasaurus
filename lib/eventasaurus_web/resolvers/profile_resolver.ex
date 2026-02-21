defmodule EventasaurusWeb.Resolvers.ProfileResolver do
  @moduledoc """
  Resolvers for profile-related GraphQL queries.
  """

  def my_profile(_parent, _args, %{context: %{current_user: user}}) when not is_nil(user) do
    {:ok, user}
  end

  def my_profile(_parent, _args, _resolution) do
    {:ok, nil}
  end
end
