defmodule EventasaurusWeb.Helpers.CategoryHelpers do
  @moduledoc """
  Shared helper functions for category display logic.
  Ensures consistent category selection across all pages.
  """

  @doc """
  Gets the preferred category from a list of categories.

  Rules:
  1. Never show "Other" if any other category exists
  2. Prioritize categories by predefined order
  3. Return the first non-"Other" category if available

  ## Examples

      iex> get_preferred_category([%{name: "Other"}, %{name: "Theatre"}])
      %{name: "Theatre"}

      iex> get_preferred_category([%{name: "Festivals"}, %{name: "Theatre"}])
      %{name: "Festivals"}
  """
  def get_preferred_category(nil), do: nil
  def get_preferred_category([]), do: nil
  def get_preferred_category(categories) when is_list(categories) do
    # Priority order for categories (most specific/relevant first)
    priority_order = [
      "Concerts",
      "Theatre",
      "Comedy",
      "Sports",
      "Film",
      "Arts",
      "Festivals",
      "Education",
      "Business",
      "Family",
      "Food & Drink",
      "Nightlife",
      "Community",
      "Other"  # Always last priority
    ]

    # Sort categories by priority order
    sorted_categories = Enum.sort_by(categories, fn category ->
      category_name = Map.get(category, :name) || Map.get(category, "name")

      # Find index in priority order, default to 999 if not found
      priority_index = Enum.find_index(priority_order, &(&1 == category_name))
      priority_index || 999
    end)

    # Return first category that isn't "Other", or first category if all are "Other"
    case sorted_categories do
      [] -> nil
      [single] -> single
      multiple ->
        # Find first non-"Other" category
        non_other = Enum.find(multiple, fn cat ->
          name = Map.get(cat, :name) || Map.get(cat, "name")
          name != "Other"
        end)

        # Return non-"Other" if found, otherwise return first (should never be only "Other" categories)
        non_other || List.first(multiple)
    end
  end

  @doc """
  Checks if a category list contains only "Other" categories.
  """
  def only_other_categories?(nil), do: false
  def only_other_categories?([]), do: false
  def only_other_categories?(categories) when is_list(categories) do
    Enum.all?(categories, fn cat ->
      name = Map.get(cat, :name) || Map.get(cat, "name")
      name == "Other"
    end)
  end
end