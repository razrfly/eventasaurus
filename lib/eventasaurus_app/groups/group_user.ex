defmodule EventasaurusApp.Groups.GroupUser do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.SoftDelete.Schema

  schema "group_users" do
    field(:role, :string)

    belongs_to(:group, EventasaurusApp.Groups.Group)
    belongs_to(:user, EventasaurusApp.Accounts.User)

    # Deletion metadata fields
    field(:deletion_reason, :string)
    belongs_to(:deleted_by_user, EventasaurusApp.Accounts.User, foreign_key: :deleted_by_user_id)

    timestamps()
    soft_delete_schema()
  end

  @doc false
  def changeset(group_user, attrs) do
    group_user
    |> cast(attrs, [:group_id, :user_id, :role, :deletion_reason, :deleted_by_user_id])
    |> validate_required([:group_id, :user_id])
    |> validate_inclusion(:role, ["admin", "member"])
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:deleted_by_user_id)
    |> unique_constraint([:group_id, :user_id])
  end
end
