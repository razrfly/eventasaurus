defmodule EventasaurusApp.Events.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  # Valid pricing models
  @pricing_models ~w(fixed flexible dynamic)

  schema "tickets" do
    field(:title, :string)
    field(:description, :string)

    # Flexible pricing fields
    field(:base_price_cents, :integer)
    field(:minimum_price_cents, :integer, default: 0)
    field(:suggested_price_cents, :integer)
    field(:pricing_model, :string, default: "fixed")

    field(:currency, :string, default: "usd")
    field(:quantity, :integer)
    field(:starts_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    field(:tippable, :boolean, default: false)

    belongs_to(:event, EventasaurusApp.Events.Event)
    has_many(:orders, EventasaurusApp.Events.Order)

    timestamps()
  end

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :title,
      :description,
      :base_price_cents,
      :minimum_price_cents,
      :suggested_price_cents,
      :pricing_model,
      :currency,
      :quantity,
      :starts_at,
      :ends_at,
      :tippable,
      :event_id
    ])
    |> validate_required([:title, :base_price_cents, :quantity, :event_id])
    |> validate_pricing_fields()
    |> validate_number(:quantity, greater_than: 0, message: "must be greater than 0")
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(
      :currency,
      EventasaurusWeb.Helpers.CurrencyHelpers.supported_currency_codes(),
      message: "must be a supported currency"
    )
    |> validate_inclusion(:pricing_model, @pricing_models,
      message: "must be a valid pricing model"
    )
    |> validate_availability_window()
    |> foreign_key_constraint(:event_id)
  end

  defp validate_pricing_fields(changeset) do
    pricing_model = get_field(changeset, :pricing_model) || "fixed"
    base_price = get_field(changeset, :base_price_cents)
    minimum_price = get_field(changeset, :minimum_price_cents)
    suggested_price = get_field(changeset, :suggested_price_cents)

    changeset
    |> validate_number(:base_price_cents,
      greater_than_or_equal_to: 0,
      message: "cannot be negative"
    )
    |> validate_number(:minimum_price_cents,
      greater_than_or_equal_to: 0,
      message: "cannot be negative"
    )
    |> validate_pricing_relationships(pricing_model, base_price, minimum_price, suggested_price)
  end

  defp validate_pricing_relationships(
         changeset,
         pricing_model,
         base_price,
         minimum_price,
         suggested_price
       ) do
    cond do
      pricing_model == "flexible" && base_price && minimum_price && minimum_price > base_price ->
        add_error(changeset, :minimum_price_cents, "cannot be greater than base price")

      suggested_price && suggested_price < 0 ->
        add_error(changeset, :suggested_price_cents, "cannot be negative")

      suggested_price && minimum_price && suggested_price >= 0 && suggested_price < minimum_price ->
        add_error(changeset, :suggested_price_cents, "should be at least the minimum price")

      suggested_price && base_price && suggested_price >= 0 && suggested_price > base_price * 2 ->
        add_error(
          changeset,
          :suggested_price_cents,
          "suggested price seems too high compared to base price"
        )

      true ->
        changeset
    end
  end

  defp validate_availability_window(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    cond do
      starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt ->
        add_error(changeset, :ends_at, "must be after start time")

      starts_at && DateTime.compare(starts_at, DateTime.utc_now()) == :lt ->
        add_error(changeset, :starts_at, "cannot be in the past")

      ends_at && DateTime.compare(ends_at, DateTime.utc_now()) == :lt ->
        add_error(changeset, :ends_at, "cannot be in the past")

      true ->
        changeset
    end
  end

  def on_sale?(%__MODULE__{starts_at: nil, ends_at: nil}), do: true

  def on_sale?(%__MODULE__{starts_at: starts_at, ends_at: ends_at}) do
    now = DateTime.utc_now()

    starts_at_ok = is_nil(starts_at) || DateTime.compare(now, starts_at) != :lt
    ends_at_ok = is_nil(ends_at) || DateTime.compare(now, ends_at) == :lt

    starts_at_ok && ends_at_ok
  end

  @doc """
  Get the effective price for a ticket, considering pricing model.
  """
  def effective_price(%__MODULE__{pricing_model: "fixed", base_price_cents: base_price}) do
    base_price || 0
  end

  def effective_price(%__MODULE__{pricing_model: "flexible", minimum_price_cents: min_price}) do
    min_price || 0
  end

  def effective_price(%__MODULE__{pricing_model: "dynamic", base_price_cents: base_price}) do
    base_price || 0
  end

  def effective_price(_), do: 0

  @doc """
  Get the maximum allowed price for flexible pricing models.
  """
  def max_flexible_price(%__MODULE__{pricing_model: "flexible", base_price_cents: base_price}) do
    base_price
  end

  def max_flexible_price(_), do: nil

  @doc """
  Check if a ticket supports flexible pricing (pay-what-you-want).
  """
  def flexible_pricing?(%__MODULE__{pricing_model: "flexible"}), do: true
  def flexible_pricing?(_), do: false

  @doc """
  Get the suggested price for a ticket, if any.
  """
  def suggested_price(%__MODULE__{suggested_price_cents: suggested}) when not is_nil(suggested),
    do: suggested

  def suggested_price(%__MODULE__{pricing_model: "flexible", base_price_cents: base})
      when not is_nil(base) do
    # If no explicit suggested price, use base price as suggestion for flexible tickets
    base
  end

  def suggested_price(_), do: nil
end
