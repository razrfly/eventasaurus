defmodule EventasaurusWeb.CheckoutHTML do
  use EventasaurusWeb, :html

  alias EventasaurusApp.Events.Order

  embed_templates "checkout_html/*"

  @doc """
  Formats the order total for display
  """
  def format_price(amount_cents, currency \\ "usd") do
    case currency do
      "usd" -> "$#{:erlang.float_to_binary(amount_cents / 100, decimals: 2)}"
      "eur" -> "€#{:erlang.float_to_binary(amount_cents / 100, decimals: 2)}"
      _ -> "#{:erlang.float_to_binary(amount_cents / 100, decimals: 2)} #{String.upcase(currency)}"
    end
  end

  @doc """
  Gets the pricing snapshot details for display
  """
  def get_pricing_details(%Order{pricing_snapshot: nil}), do: %{}
  def get_pricing_details(%Order{pricing_snapshot: snapshot}) when is_map(snapshot), do: snapshot
  def get_pricing_details(_), do: %{}

  @doc """
  Determines if the order used flexible pricing
  """
  def flexible_pricing?(%Order{} = order) do
    pricing_details = get_pricing_details(order)
    Map.get(pricing_details, "pricing_model") == "flexible"
  end

  @doc """
  Gets the custom price paid for flexible pricing orders
  """
  def custom_price_cents(%Order{} = order) do
    pricing_details = get_pricing_details(order)
    Map.get(pricing_details, "custom_price_cents")
  end

  @doc """
  Gets the tip amount for the order
  """
  def tip_cents(%Order{} = order) do
    pricing_details = get_pricing_details(order)
    Map.get(pricing_details, "tip_cents", 0)
  end
end
