defmodule EventasaurusApp.Groups.GroupJoinRequest do
  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusApp.Groups.Group
  alias EventasaurusApp.Accounts.User

  schema "group_join_requests" do
    belongs_to :group, Group
    belongs_to :user, User
    field :status, :string, default: "pending"
    field :message, :string
    belongs_to :reviewed_by, User, foreign_key: :reviewed_by_id
    field :reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ["pending", "approved", "denied", "cancelled"]

  @doc false
  def changeset(group_join_request, attrs) do
    group_join_request
    |> cast(attrs, [:group_id, :user_id, :status, :message, :reviewed_by_id, :reviewed_at])
    |> validate_required([:group_id, :user_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:reviewed_by_id)
    |> unique_constraint([:group_id, :user_id],
      name: :group_join_requests_unique_pending,
      message: "You already have a pending request for this group"
    )
    |> validate_review_fields()
  end

  defp validate_review_fields(changeset) do
    status = get_field(changeset, :status)
    reviewed_by_id = get_field(changeset, :reviewed_by_id)
    reviewed_at = get_field(changeset, :reviewed_at)

    cond do
      status in ["approved", "denied"] and is_nil(reviewed_by_id) ->
        add_error(changeset, :reviewed_by_id, "must be present when status is #{status}")

      status in ["approved", "denied"] and is_nil(reviewed_at) ->
        add_error(changeset, :reviewed_at, "must be present when status is #{status}")

      status in ["pending", "cancelled"] and not is_nil(reviewed_by_id) ->
        add_error(changeset, :reviewed_by_id, "must be nil when status is #{status}")

      status in ["pending", "cancelled"] and not is_nil(reviewed_at) ->
        add_error(changeset, :reviewed_at, "must be nil when status is #{status}")

      true ->
        changeset
    end
  end

  def valid_statuses, do: @valid_statuses
end