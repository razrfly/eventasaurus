defmodule EventasaurusDiscovery.Categories.PublicEventCategory do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "public_event_categories" do
    belongs_to(:event, EventasaurusDiscovery.PublicEvents.PublicEvent, foreign_key: :event_id)
    belongs_to(:category, EventasaurusDiscovery.Categories.Category)

    field(:is_primary, :boolean, default: false)
    field(:source, :string)
    field(:confidence, :float, default: 1.0)

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(event_category, attrs) do
    event_category
    |> cast(attrs, [:event_id, :category_id, :is_primary, :source, :confidence])
    |> validate_required([:event_id, :category_id])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_inclusion(:source, [
      "ticketmaster",
      "bandsintown",
      "karnet",
      "manual",
      "migration",
      nil
    ])
    |> unique_constraint([:event_id, :category_id])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:category_id)
  end

  @doc """
  Ensures only one primary category per event
  """
  def validate_single_primary(changeset, repo) do
    if get_change(changeset, :is_primary) == true do
      event_id = get_field(changeset, :event_id)

      # Check if another primary exists
      query =
        from(ec in __MODULE__,
          where: ec.event_id == ^event_id and ec.is_primary == true,
          select: count(ec.id)
        )

      case repo.one(query) do
        0 -> changeset
        _ -> add_error(changeset, :is_primary, "event already has a primary category")
      end
    else
      changeset
    end
  end
end
