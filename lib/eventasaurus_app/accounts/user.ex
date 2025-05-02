defmodule EventasaurusApp.Accounts.User do
  @moduledoc """
  Schema representing a user in the application.
  This is a virtual schema that maps to Supabase auth users.
  """

  use Ecto.Schema

  # This schema doesn't have a database backing and is used to represent
  # user data coming from Supabase Auth
  @primary_key {:id, :string, autogenerate: false}
  embedded_schema do
    field :email, :string
    field :name, :string
    field :user_metadata, :map
    field :app_metadata, :map
    field :role, :string

    timestamps()
  end

  @doc """
  Create a User struct from Supabase Auth user data.
  """
  def from_supabase(user_data) do
    %__MODULE__{
      id: user_data["id"] || user_data[:id],
      email: user_data["email"] || user_data[:email],
      name: get_in(user_data, ["user_metadata", "name"]) || get_in(user_data, [:user_metadata, :name]),
      user_metadata: user_data["user_metadata"] || user_data[:user_metadata] || %{},
      app_metadata: user_data["app_metadata"] || user_data[:app_metadata] || %{},
      role: get_in(user_data, ["app_metadata", "role"]) || get_in(user_data, [:app_metadata, :role])
    }
  end
end
