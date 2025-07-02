defmodule EventasaurusWeb.Helpers.CurrencyHelpers do
  @moduledoc """
  Helpers for formatting and handling currency across the application.
  """

  @currency_symbols %{
    # Major Global Currencies
    "usd" => "$",
    "eur" => "€",
    "gbp" => "£",
    "jpy" => "¥",

    # North America & Oceania
    "cad" => "C$",
    "aud" => "A$",
    "nzd" => "NZ$",

    # Europe
    "chf" => "CHF",
    "sek" => "SEK",
    "nok" => "NOK",
    "dkk" => "DKK",
    "pln" => "zł",
    "czk" => "CZK",
    "huf" => "HUF",
    "ron" => "RON",
    "bgn" => "BGN",
    "hrk" => "HRK",

    # Asia
    "cny" => "¥",
    "krw" => "₩",
    "inr" => "₹",
    "sgd" => "S$",
    "hkd" => "HK$",
    "thb" => "฿",
    "myr" => "RM",
    "php" => "₱",
    "idr" => "Rp",
    "vnd" => "₫",

    # Middle East & Africa
    "aed" => "د.إ",
    "sar" => "﷼",
    "ils" => "₪",
    "zar" => "R",
    "egp" => "£",

    # Latin America
    "brl" => "R$",
    "mxn" => "$",
    "ars" => "$",
    "clp" => "$",
    "cop" => "$",
    "pen" => "S/",
    "uyu" => "$",

    # Additional European
    "rub" => "₽",
    "try" => "₺",
    "uah" => "₴",

    # Other Notable
    "bob" => "Bs",
    "pyg" => "₲",
    "gel" => "₾",
    "azn" => "₼",
    "byn" => "Br",
    "kzt" => "₸",
    "uzs" => "сўм",
    "all" => "L",
    "mkd" => "ден",
    "rsd" => "din",
    "bam" => "KM"
  }

  @currency_names %{
    # Major Global Currencies
    "usd" => "US Dollar",
    "eur" => "Euro",
    "gbp" => "British Pound",
    "jpy" => "Japanese Yen",

    # North America & Oceania
    "cad" => "Canadian Dollar",
    "aud" => "Australian Dollar",
    "nzd" => "New Zealand Dollar",

    # Europe
    "chf" => "Swiss Franc",
    "sek" => "Swedish Krona",
    "nok" => "Norwegian Krone",
    "dkk" => "Danish Krone",
    "pln" => "Polish Złoty",
    "czk" => "Czech Koruna",
    "huf" => "Hungarian Forint",
    "ron" => "Romanian Leu",
    "bgn" => "Bulgarian Lev",
    "hrk" => "Croatian Kuna",

    # Asia
    "cny" => "Chinese Yuan",
    "krw" => "South Korean Won",
    "inr" => "Indian Rupee",
    "sgd" => "Singapore Dollar",
    "hkd" => "Hong Kong Dollar",
    "thb" => "Thai Baht",
    "myr" => "Malaysian Ringgit",
    "php" => "Philippine Peso",
    "idr" => "Indonesian Rupiah",
    "vnd" => "Vietnamese Dong",

    # Middle East & Africa
    "aed" => "UAE Dirham",
    "sar" => "Saudi Riyal",
    "ils" => "Israeli Shekel",
    "zar" => "South African Rand",
    "egp" => "Egyptian Pound",

    # Latin America
    "brl" => "Brazilian Real",
    "mxn" => "Mexican Peso",
    "ars" => "Argentine Peso",
    "clp" => "Chilean Peso",
    "cop" => "Colombian Peso",
    "pen" => "Peruvian Sol",
    "uyu" => "Uruguayan Peso",

    # Additional European
    "rub" => "Russian Ruble",
    "try" => "Turkish Lira",
    "uah" => "Ukrainian Hryvnia",

    # Other Notable
    "bob" => "Bolivian Boliviano",
    "pyg" => "Paraguayan Guaraní",
    "gel" => "Georgian Lari",
    "azn" => "Azerbaijani Manat",
    "byn" => "Belarusian Ruble",
    "kzt" => "Kazakhstani Tenge",
    "uzs" => "Uzbekistani Som",
    "all" => "Albanian Lek",
    "mkd" => "Macedonian Denar",
    "rsd" => "Serbian Dinar",
    "bam" => "Bosnia and Herzegovina Convertible Mark"
  }

  @doc """
  Formats cents to currency string with symbol using Decimal for precision.

  ## Examples

      iex> format_currency(1250, "usd")
      "$12.50"

      iex> format_currency(-500, "eur")
      "-€5.00"

      iex> format_currency(0, "gbp")
      "£0.00"
  """
  def format_currency(cents, currency) when is_integer(cents) do
    symbol = Map.get(@currency_symbols, String.downcase(currency), "$")

    if cents < 0 do
      dollars =
        Decimal.new(abs(cents))
        |> Decimal.div(100)
        |> Decimal.round(2)
      formatted = format_decimal_to_currency(dollars)
      "-#{symbol}#{formatted}"
    else
      dollars =
        Decimal.new(cents)
        |> Decimal.div(100)
        |> Decimal.round(2)
      formatted = format_decimal_to_currency(dollars)
      "#{symbol}#{formatted}"
    end
  end

  def format_currency(_, _), do: "$0.00"

  # Helper to format a Decimal to always show 2 decimal places.
  defp format_decimal_to_currency(decimal) do
    # Convert to string and ensure 2 decimal places
    str = Decimal.to_string(decimal, :normal)
    case String.split(str, ".") do
      [whole] -> "#{whole}.00"
      [whole, fractional] when byte_size(fractional) == 1 -> "#{whole}.#{fractional}0"
      [whole, fractional] -> "#{whole}.#{String.slice(fractional, 0, 2)}"
    end
  end

  @doc """
  Parses a currency string to cents with support for various symbols and thousands separators.

  ## Examples

      iex> parse_currency("$12.50")
      1250

      iex> parse_currency("C$1,234.56")
      123456

      iex> parse_currency("€5.99")
      599

      iex> parse_currency("invalid")
      nil
  """
  def parse_currency(amount_str) when is_binary(amount_str) do
    # Remove currency symbols (including multi-character ones) and thousands separators
    clean_amount =
      amount_str
      |> String.replace(~r/(C\$|A\$|[$€£¥])/u, "")
      |> String.replace(",", "")
      |> String.trim()

    case Float.parse(clean_amount) do
      {amount, _} when amount >= 0 -> round(amount * 100)
      {amount, _} when amount < 0 -> round(amount * 100)  # Allow negative amounts
      :error -> nil  # Return nil instead of 0 for invalid input
    end
  end

  def parse_currency(_), do: nil

  @doc """
  Gets the currency symbol for a given currency code.

  ## Examples

      iex> currency_symbol("usd")
      "$"

      iex> currency_symbol("eur")
      "€"
  """
  def currency_symbol(currency) when is_binary(currency) do
    Map.get(@currency_symbols, String.downcase(currency), "$")
  end

  def currency_symbol(_), do: "$"

  @doc """
  Gets the currency name for a given currency code.

  ## Examples

      iex> currency_name("usd")
      "US Dollar"

      iex> currency_name("eur")
      "Euro"
  """
  def currency_name(currency) when is_binary(currency) do
    Map.get(@currency_names, String.downcase(currency), "US Dollar")
  end

  def currency_name(_), do: "US Dollar"

  @doc """
  Returns grouped currencies organized by region, similar to timezone grouping.
  Returns a list of {group_name, [currency_options]} for optgroup rendering.
  """
  def supported_currencies do
    [
      {"Major Currencies", [
        {"usd", "US Dollar ($)"},
        {"eur", "Euro (€)"},
        {"gbp", "British Pound (£)"},
        {"jpy", "Japanese Yen (¥)"},
        {"cad", "Canadian Dollar (C$)"},
        {"aud", "Australian Dollar (A$)"}
      ]},
      {"European Currencies", [
        {"chf", "Swiss Franc (CHF)"},
        {"sek", "Swedish Krona (SEK)"},
        {"nok", "Norwegian Krone (NOK)"},
        {"dkk", "Danish Krone (DKK)"},
        {"pln", "Polish Złoty (zł)"},
        {"czk", "Czech Koruna (CZK)"},
        {"huf", "Hungarian Forint (HUF)"},
        {"ron", "Romanian Leu (RON)"},
        {"bgn", "Bulgarian Lev (BGN)"},
        {"hrk", "Croatian Kuna (HRK)"},
        {"rub", "Russian Ruble (₽)"},
        {"try", "Turkish Lira (₺)"},
        {"uah", "Ukrainian Hryvnia (₴)"}
      ]},
      {"Asia & Pacific", [
        {"cny", "Chinese Yuan (¥)"},
        {"krw", "South Korean Won (₩)"},
        {"inr", "Indian Rupee (₹)"},
        {"sgd", "Singapore Dollar (S$)"},
        {"hkd", "Hong Kong Dollar (HK$)"},
        {"thb", "Thai Baht (฿)"},
        {"myr", "Malaysian Ringgit (RM)"},
        {"php", "Philippine Peso (₱)"},
        {"idr", "Indonesian Rupiah (Rp)"},
        {"vnd", "Vietnamese Dong (₫)"},
        {"nzd", "New Zealand Dollar (NZ$)"}
      ]},
      {"Americas", [
        {"mxn", "Mexican Peso ($)"},
        {"brl", "Brazilian Real (R$)"},
        {"ars", "Argentine Peso ($)"},
        {"clp", "Chilean Peso ($)"},
        {"cop", "Colombian Peso ($)"},
        {"pen", "Peruvian Sol (S/)"},
        {"uyu", "Uruguayan Peso ($)"}
      ]},
      {"Middle East & Africa", [
        {"aed", "UAE Dirham (د.إ)"},
        {"sar", "Saudi Riyal (﷼)"},
        {"ils", "Israeli Shekel (₪)"},
        {"zar", "South African Rand (R)"},
        {"egp", "Egyptian Pound (£)"}
      ]},
      {"Other", [
        {"bob", "Bolivian Boliviano (Bs)"},
        {"pyg", "Paraguayan Guaraní (₲)"},
        {"gel", "Georgian Lari (₾)"},
        {"azn", "Azerbaijani Manat (₼)"},
        {"byn", "Belarusian Ruble (Br)"},
        {"kzt", "Kazakhstani Tenge (₸)"},
        {"uzs", "Uzbekistani Som (сўм)"},
        {"all", "Albanian Lek (L)"},
        {"mkd", "Macedonian Denar (ден)"},
        {"rsd", "Serbian Dinar (din)"},
        {"bam", "Bosnia and Herzegovina Convertible Mark (KM)"}
      ]}
    ]
  end

  @doc """
  Returns a flat list of currencies for backwards compatibility.
  """
  def supported_currencies_flat do
    supported_currencies()
    |> Enum.flat_map(fn {_group, currencies} -> currencies end)
  end

  @doc """
  Returns only the currency codes (without names) for validation purposes.
  """
  def supported_currency_codes do
    supported_currencies_flat()
    |> Enum.map(fn {code, _name} -> code end)
  end

  @doc """
  Formats price for input fields (as decimal string).

  ## Examples

      iex> format_price_for_input(%{"price" => "12.50"})
      "12.50"

      iex> format_price_for_input(%{})
      ""
  """
  def format_price_for_input(form_data) when is_map(form_data) do
    Map.get(form_data, "price", "")
  end

  def format_price_for_input(_), do: ""

  @doc """
  Formats price from cents to decimal string for form inputs.
  Always shows 2 decimal places.

  ## Examples

      iex> format_price_from_cents(1250)
      "12.50"

      iex> format_price_from_cents(500)
      "5.00"

  """
  def format_price_from_cents(price_cents) when is_integer(price_cents) and price_cents >= 0 do
    dollars = Decimal.new(price_cents) |> Decimal.div(100) |> Decimal.round(2)
    format_decimal_to_currency(dollars)
  end

  def format_price_from_cents(_), do: ""

  @doc """
  Parses a price string to cents.

  ## Examples

      iex> parse_price_to_cents("12.50")
      {:ok, 1250}

      iex> parse_price_to_cents("5")
      {:ok, 500}

      iex> parse_price_to_cents("invalid")
      :error
  """
  def parse_price_to_cents(price_str) when is_binary(price_str) do
    case Float.parse(String.trim(price_str)) do
      {amount, _} when amount >= 0 -> {:ok, round(amount * 100)}
      {amount, _} when amount < 0 -> {:ok, round(amount * 100)}
      :error -> :error
    end
  end

  def parse_price_to_cents(_), do: :error
end
