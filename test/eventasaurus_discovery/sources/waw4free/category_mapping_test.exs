defmodule EventasaurusDiscovery.Sources.Waw4free.CategoryMappingTest do
  use EventasaurusApp.DataCase
  alias EventasaurusDiscovery.Categories.CategoryMapper
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusApp.Repo
  import Ecto.Query

  @moduledoc """
  Tests for waw4free.yml category mappings.

  Verifies that Polish categories from waw4free.pl are correctly mapped
  to internal category system using priv/category_mappings/waw4free.yml.
  """

  setup do
    # Create category lookup map from database
    categories =
      Repo.all(from(c in Category, where: c.is_active == true, select: {c.slug, {c.id, true}}))
      |> Map.new()

    {:ok, category_lookup: categories}
  end

  describe "Direct Polish category mappings" do
    test "maps koncerty to concerts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["koncerty"], lookup)

      assert length(result) > 0
      {category_id, is_primary} = List.first(result)
      assert is_primary == true

      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end

    test "maps warsztaty to education", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["warsztaty"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "education"
    end

    test "maps wystawy to arts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["wystawy"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "exhibitions"
    end

    test "maps teatr to theatre", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["teatr"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "performances"
    end

    test "maps sport to sports", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["sport"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "sports"
    end

    test "maps dla-dzieci to family", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["dla-dzieci"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "family"
    end

    test "maps festiwale to festivals", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["festiwale"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "festivals"
    end

    test "maps inne to other", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["inne"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "other"
    end
  end

  describe "Singular form mappings" do
    test "maps koncert (singular) to concerts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["koncert"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end

    test "maps warsztat (singular) to education", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["warsztat"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "education"
    end

    test "maps festiwal (singular) to festivals", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["festiwal"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "festivals"
    end
  end

  describe "Related Polish terms" do
    test "maps muzyka to concerts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["muzyka"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end

    test "maps spektakl to theatre", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["spektakl"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "performances"
    end

    test "maps galeria to arts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["galeria"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "exhibitions"
    end

    test "maps rodzinne to family", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["rodzinne"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "family"
    end

    test "maps edukacyjne to education", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["edukacyjne"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "education"
    end

    test "maps sportowe to sports", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["sportowe"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "sports"
    end
  end

  describe "Case insensitivity" do
    test "maps KONCERTY (uppercase) to concerts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["KONCERTY"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end

    test "maps KoNcErTy (mixed case) to concerts", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["KoNcErTy"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end

    test "maps Festiwale (capitalized) to festivals", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["Festiwale"], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "festivals"
    end
  end

  describe "Whitespace handling" do
    test "handles leading/trailing whitespace", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["  koncerty  "], lookup)

      assert length(result) > 0
      {category_id, _} = List.first(result)

      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end

    test "handles multiple categories with whitespace", %{category_lookup: lookup} do
      result =
        CategoryMapper.map_categories(
          "waw4free",
          [" koncerty ", " festiwale ", " teatr "],
          lookup
        )

      # Should have 3 unique categories mapped
      assert length(result) == 3
    end
  end

  describe "Multiple categories" do
    test "maps multiple categories correctly", %{category_lookup: lookup} do
      result =
        CategoryMapper.map_categories(
          "waw4free",
          ["koncerty", "festiwale", "teatr"],
          lookup
        )

      # Should have 3 categories
      assert length(result) == 3

      # First should be primary
      {_first_id, is_primary} = List.first(result)
      assert is_primary == true

      # Rest should be secondary
      rest = Enum.drop(result, 1)

      for {_id, is_primary} <- rest do
        assert is_primary == false
      end

      # Check actual categories
      category_ids = Enum.map(result, fn {id, _} -> id end)
      categories = Repo.all(from(c in Category, where: c.id in ^category_ids))
      slugs = Enum.map(categories, & &1.slug)

      assert "concerts" in slugs
      assert "festivals" in slugs
      assert "performances" in slugs
    end

    test "removes duplicate categories", %{category_lookup: lookup} do
      # koncerty and muzyka both map to concerts
      result =
        CategoryMapper.map_categories("waw4free", ["koncerty", "muzyka", "koncert"], lookup)

      # Should only have 1 category despite 3 inputs
      assert length(result) == 1

      {category_id, _} = List.first(result)
      category = Repo.get!(Category, category_id)
      assert category.slug == "concerts"
    end
  end

  describe "Pattern matching" do
    test "matches jazz pattern to concerts", %{category_lookup: lookup} do
      # Pattern: "jazz|blues|soul" -> concerts, arts
      result = CategoryMapper.map_categories("waw4free", ["jazzowe"], lookup)

      # Should match pattern and return categories
      assert length(result) > 0

      category_ids = Enum.map(result, fn {id, _} -> id end)
      categories = Repo.all(from(c in Category, where: c.id in ^category_ids))
      slugs = Enum.map(categories, & &1.slug)

      assert "concerts" in slugs
    end

    test "matches dzieci pattern to family", %{category_lookup: lookup} do
      # Pattern: "dzieci|dziecko|rodzin" -> family, education
      result = CategoryMapper.map_categories("waw4free", ["dziecko"], lookup)

      assert length(result) > 0

      category_ids = Enum.map(result, fn {id, _} -> id end)
      categories = Repo.all(from(c in Category, where: c.id in ^category_ids))
      slugs = Enum.map(categories, & &1.slug)

      assert "family" in slugs
    end

    test "matches plener pattern to festivals", %{category_lookup: lookup} do
      # Pattern: "plener|outdoor|open.?air" -> festivals, community
      result = CategoryMapper.map_categories("waw4free", ["plenerowe"], lookup)

      assert length(result) > 0

      category_ids = Enum.map(result, fn {id, _} -> id end)
      categories = Repo.all(from(c in Category, where: c.id in ^category_ids))
      slugs = Enum.map(categories, & &1.slug)

      assert "festivals" in slugs
    end
  end

  describe "Edge cases" do
    test "returns empty list for unrecognized category", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", ["nieznana-kategoria"], lookup)

      assert result == []
    end

    test "handles empty category list", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", [], lookup)

      assert result == []
    end

    test "handles nil category", %{category_lookup: lookup} do
      result = CategoryMapper.map_categories("waw4free", nil, lookup)

      assert result == []
    end

    test "filters out inactive categories", %{category_lookup: _lookup} do
      # Create a custom lookup with an inactive category
      custom_lookup = %{
        "concerts" => {999_999, false}
      }

      result = CategoryMapper.map_categories("waw4free", ["koncerty"], custom_lookup)

      # Should not return inactive category
      assert result == []
    end
  end

  describe "Real waw4free.pl examples" do
    test "handles event with multiple Polish tags", %{category_lookup: lookup} do
      # Typical waw4free event might have: "koncerty, muzyka, plenerowe"
      result =
        CategoryMapper.map_categories("waw4free", ["koncerty", "muzyka", "plenerowe"], lookup)

      assert length(result) > 0

      # First should be primary
      {_first_id, is_primary} = List.first(result)
      assert is_primary == true

      # Check categories include concerts and festivals
      category_ids = Enum.map(result, fn {id, _} -> id end)
      categories = Repo.all(from(c in Category, where: c.id in ^category_ids))
      slugs = Enum.map(categories, & &1.slug)

      assert "concerts" in slugs
    end

    test "handles dobrowolna zrzutka (voluntary donation) pattern", %{category_lookup: lookup} do
      # Pattern: "dobrowolna zrzutka" -> community
      result = CategoryMapper.map_categories("waw4free", ["dobrowolna zrzutka"], lookup)

      assert length(result) > 0

      category_ids = Enum.map(result, fn {id, _} -> id end)
      categories = Repo.all(from(c in Category, where: c.id in ^category_ids))
      slugs = Enum.map(categories, & &1.slug)

      assert "community" in slugs
    end
  end

  describe "YAML file validation" do
    test "waw4free.yml exists in category_mappings directory" do
      priv_dir = :code.priv_dir(:eventasaurus)
      yaml_path = Path.join([priv_dir, "category_mappings", "waw4free.yml"])

      assert File.exists?(yaml_path),
             "waw4free.yml not found at #{yaml_path}"
    end

    test "waw4free.yml has valid structure" do
      priv_dir = :code.priv_dir(:eventasaurus)
      yaml_path = Path.join([priv_dir, "category_mappings", "waw4free.yml"])

      {:ok, yaml_content} = YamlElixir.read_from_file(yaml_path)

      assert Map.has_key?(yaml_content, "mappings"),
             "YAML file missing 'mappings' key"

      mappings = yaml_content["mappings"]
      assert is_map(mappings), "mappings should be a map"

      # Verify all 8 main categories are present
      required_categories = [
        "koncerty",
        "warsztaty",
        "wystawy",
        "teatr",
        "sport",
        "dla-dzieci",
        "festiwale",
        "inne"
      ]

      for category <- required_categories do
        assert Map.has_key?(mappings, category),
               "Missing mapping for category: #{category}"
      end
    end

    test "waw4free.yml has patterns section" do
      priv_dir = :code.priv_dir(:eventasaurus)
      yaml_path = Path.join([priv_dir, "category_mappings", "waw4free.yml"])

      {:ok, yaml_content} = YamlElixir.read_from_file(yaml_path)

      assert Map.has_key?(yaml_content, "patterns"),
             "YAML file missing 'patterns' key"

      patterns = yaml_content["patterns"]
      assert is_list(patterns), "patterns should be a list"
      assert length(patterns) > 0, "patterns list should not be empty"

      # Verify pattern structure
      first_pattern = List.first(patterns)
      assert Map.has_key?(first_pattern, "match"), "Pattern missing 'match' key"
      assert Map.has_key?(first_pattern, "categories"), "Pattern missing 'categories' key"
    end
  end
end
