defmodule EventasaurusApp.FamiliesTest do
  use ExUnit.Case, async: true

  alias EventasaurusApp.Families

  describe "random_family_name/0" do
    test "returns a string" do
      assert is_binary(Families.random_family_name())
    end

    test "returns a name from the list" do
      name = Families.random_family_name()
      assert name in Families.list_family_names()
    end
  end

  describe "list_family_names/0" do
    test "returns a non-empty list" do
      names = Families.list_family_names()
      assert is_list(names)
      assert length(names) > 0
    end

    test "contains all canonical Slapstick names" do
      names = Families.list_family_names()

      for canonical <- ~w(Daffodil Oriole Raspberry Chipmunk Pachysandra
                          Bauxite Uranium Oyster Chickadee Hollyhock) do
        assert canonical in names, "Missing canonical name: #{canonical}"
      end
    end

    test "contains 46 families" do
      assert length(Families.list_family_names()) == 46
    end
  end

  describe "valid_family_name?/1" do
    test "returns true for valid names" do
      assert Families.valid_family_name?("Daffodil")
      assert Families.valid_family_name?("Capybara")
    end

    test "returns false for invalid names" do
      refute Families.valid_family_name?("NotAFamily")
      refute Families.valid_family_name?("")
    end

    test "returns false for non-string values" do
      refute Families.valid_family_name?(nil)
      refute Families.valid_family_name?(123)
    end
  end
end
