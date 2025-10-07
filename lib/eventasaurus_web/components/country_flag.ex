defmodule EventasaurusWeb.Components.CountryFlag do
  use Phoenix.Component

  @doc """
  Renders a country flag emoji based on country code.

  ## Examples

      <CountryFlag.flag country_code="US" />
      <CountryFlag.flag country_code="GB" size="lg" />
  """
  attr :country_code, :string, required: true
  attr :size, :string, default: "md"
  attr :class, :string, default: ""

  def flag(assigns) do
    size_class =
      case assigns.size do
        "sm" -> "text-base"
        "md" -> "text-xl"
        "lg" -> "text-2xl"
        "xl" -> "text-3xl"
        _ -> "text-xl"
      end

    assigns = assign(assigns, :size_class, size_class)
    assigns = assign(assigns, :flag_emoji, country_code_to_flag(assigns.country_code))

    ~H"""
    <span class={["inline-block", @size_class, @class]} title={@country_code}>
      <%= @flag_emoji %>
    </span>
    """
  end

  # Convert country code to flag emoji
  # Uses Unicode regional indicator symbols
  defp country_code_to_flag(country_code) when is_binary(country_code) do
    country_code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(fn char ->
      # Regional indicator symbols start at 0x1F1E6 (A)
      # Add 0x1F1E6 - ?A to get the correct offset
      char + 0x1F1E6 - ?A
    end)
    |> List.to_string()
  end

  defp country_code_to_flag(_), do: "🏳️"
end
