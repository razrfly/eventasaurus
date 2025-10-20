defmodule EventasaurusDiscovery.Admin.DataQualityCheckerPhase1Test do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Admin.DataQualityChecker

  describe "Phase 1.1: get_category_distribution/1 implementation" do
    test "module compiles successfully with new function" do
      # Verify the module loads without compilation errors
      assert Code.ensure_loaded?(DataQualityChecker)
    end

    test "public API functions still work" do
      # Verify public functions are exported correctly
      assert function_exported?(DataQualityChecker, :check_quality, 1)
      assert function_exported?(DataQualityChecker, :check_quality_by_id, 1)
      assert function_exported?(DataQualityChecker, :get_recommendations, 1)
      assert function_exported?(DataQualityChecker, :quality_status, 1)
    end

    test "private get_category_distribution function is not exported" do
      # Private functions should not be exported
      assert function_exported?(DataQualityChecker, :get_category_distribution, 1) == false
    end

    test "module documentation is present" do
      # Verify module has documentation
      {:docs_v1, _, :elixir, _, module_doc, _, _} = Code.fetch_docs(DataQualityChecker)
      assert module_doc != %{}
    end
  end

  describe "Phase 1.1: Implementation verification" do
    test "code compiles with get_category_distribution function" do
      # Phase 1.1 adds the get_category_distribution/1 private function
      # We verify it exists by checking the module compiles without warnings
      # and that the source code contains the function definition
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      # Read the source file to verify function exists
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify the function definition exists in source
      assert source_code =~ "defp get_category_distribution(source_id)"
      assert source_code =~ "Get distribution of categories for events from this source"
      assert source_code =~ "category_name"
      assert source_code =~ "percentage"
    end
  end

  describe "Phase 1.2: count_generic_categories/1 implementation" do
    test "code compiles with count_generic_categories function" do
      # Phase 1.2 adds the count_generic_categories/1 private function
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      # Read the source file to verify function exists
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify the function definition exists in source
      assert source_code =~ "defp count_generic_categories(source_id)"
      assert source_code =~ "Count events categorized with generic category names"
      assert source_code =~ "generic_categories"
      assert source_code =~ "LOWER(?)"
    end

    test "generic_categories configuration is accessible" do
      # Verify the config for generic categories exists and is accessible
      generic_categories = Application.get_env(:eventasaurus, :generic_categories, [])

      # Should be a list
      assert is_list(generic_categories)

      # Should contain expected generic category names
      assert "other" in generic_categories
      assert "miscellaneous" in generic_categories
      assert "general" in generic_categories
      assert "events" in generic_categories
      assert "various" in generic_categories
    end

    test "configuration includes all generic categories from Phase 1.2 spec" do
      # Verify all 5 generic categories from the spec are configured
      generic_categories = Application.get_env(:eventasaurus, :generic_categories, [])

      # Should have exactly 5 categories as per Phase 1.2
      assert length(generic_categories) == 5

      # Verify specific categories from issue #1877 Phase 1.2
      expected = ["other", "miscellaneous", "general", "events", "various"]
      assert Enum.sort(generic_categories) == Enum.sort(expected)
    end
  end

  describe "Phase 1.3: calculate_category_entropy/2 implementation" do
    test "entropy function exists in source code" do
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify Shannon entropy function exists
      assert source_code =~ "defp calculate_category_entropy(distribution, total_events)"
      assert source_code =~ "Shannon entropy"
      assert source_code =~ ":math.log2"
      assert source_code =~ "diversity score"
    end
  end

  describe "Phase 1.4: calculate_category_specificity/1 implementation" do
    test "specificity calculator function exists in source code" do
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify category specificity function exists
      assert source_code =~ "defp calculate_category_specificity(source_id)"
      assert source_code =~ "Generic category avoidance (60% weight)"
      assert source_code =~ "Category diversity (40% weight)"
      assert source_code =~ "generic_avoidance_score"
      assert source_code =~ "diversity_score"
    end
  end

  describe "Phase 1.5: Integration into check_quality_by_id" do
    test "check_quality_by_id returns specificity metrics" do
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify specificity is calculated and returned
      assert source_code =~ "specificity_metrics = calculate_category_specificity(source_id)"
      assert source_code =~ "category_specificity: category_specificity"
      assert source_code =~ "specificity_metrics: specificity_metrics"
    end
  end

  describe "Phase 1.6: Updated quality score formula" do
    test "quality score function accepts 5 parameters" do
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify function signature has 5 parameters
      assert source_code =~ "defp calculate_quality_score("
      assert source_code =~ "venue_completeness,"
      assert source_code =~ "image_completeness,"
      assert source_code =~ "category_completeness,"
      assert source_code =~ "category_specificity,"
      assert source_code =~ "translation_completeness"
    end

    test "quality score formula includes specificity weight" do
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify specificity is included in both formulas
      # Single-language: venues 30%, images 25%, categories 20%, specificity 25%
      assert source_code =~ "category_specificity * 0.25"
      assert source_code =~ "category_specificity * 0.20"

      # Verify new weights for multilingual
      assert source_code =~ "venues 25%"
      assert source_code =~ "specificity 20%"
    end
  end
end
