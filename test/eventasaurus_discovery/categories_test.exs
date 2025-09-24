defmodule EventasaurusDiscovery.CategoriesTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Categories.Category

  describe "categories" do
    test "can create and retrieve categories" do
      # Create a test category
      attrs = %{
        name: "Test Category",
        slug: "test-category",
        description: "A test category",
        icon: "🎯",
        color: "#123456",
        display_order: 99
      }

      {:ok, category} =
        %Category{}
        |> Category.changeset(attrs)
        |> Repo.insert()

      assert category.name == "Test Category"
      assert category.slug == "test-category"
      assert category.color == "#123456"

      # Retrieve it
      found = Repo.get_by(Category, slug: "test-category")
      assert found.id == category.id
    end

    test "validates hex color format" do
      invalid_attrs = %{
        name: "Invalid Color",
        slug: "invalid-color",
        color: "not-a-hex-color"
      }

      changeset =
        %Category{}
        |> Category.changeset(invalid_attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "must be a valid hex color" in Enum.map(errors[:color] || [], fn {msg, _} -> msg end)
    end

    test "enforces unique slug constraint" do
      attrs = %{
        name: "Duplicate Test",
        slug: "duplicate-test"
      }

      {:ok, _first} =
        %Category{}
        |> Category.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %Category{}
        |> Category.changeset(attrs)
        |> Repo.insert()

      errors = errors_on(changeset)
      assert "has already been taken" in Enum.map(errors[:slug] || [], fn {msg, _} -> msg end)
    end
  end
end
