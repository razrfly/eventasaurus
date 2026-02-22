defmodule EventasaurusWeb.Schema.Types.User do
  use Absinthe.Schema.Notation

  alias EventasaurusApp.Accounts.User

  object :user do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:username, :string)
    field(:bio, :string)
    field(:default_currency, :string)
    field(:timezone, :string)

    field :email, :string do
      resolve(fn user, _, %{context: context} ->
        # Only show email to the user themselves
        if context[:current_user] && context.current_user.id == user.id do
          {:ok, user.email}
        else
          {:ok, nil}
        end
      end)
    end

    field :avatar_url, non_null(:string) do
      resolve(fn user, _, _ ->
        {:ok, User.avatar_url(user)}
      end)
    end

    field :profile_url, :string do
      resolve(fn user, _, _ ->
        {:ok, User.profile_url(user)}
      end)
    end
  end

  object :user_search_result do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:username, :string)

    field :email, :string do
      resolve(fn user, _, %{context: context} ->
        if context[:current_user] do
          {:ok, Map.get(user, :email)}
        else
          {:ok, nil}
        end
      end)
    end

    field(:avatar_url, :string)
  end
end
