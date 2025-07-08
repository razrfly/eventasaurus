defmodule EventasaurusWeb.Services.RichDataManagerIntegrationTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.Services.TmdbRichDataProvider
  alias EventasaurusWeb.Services.GooglePlacesRichDataProvider

  describe "provider registration" do
    test "both TMDB and Google Places providers are registered" do
      providers = RichDataManager.list_providers()
      provider_ids = Enum.map(providers, fn {provider_id, _module, _status} -> provider_id end)

      assert :tmdb in provider_ids
      assert :google_places in provider_ids
    end
  end

  describe "content type support" do
    test "TMDB supports movie and tv content" do
      supported_types = TmdbRichDataProvider.supported_types()
      assert :movie in supported_types
      assert :tv in supported_types
    end

    test "Google Places supports activity, restaurant, and venue content" do
      supported_types = GooglePlacesRichDataProvider.supported_types()
      assert :activity in supported_types
      assert :restaurant in supported_types
      assert :venue in supported_types
    end
  end

  describe "provider behavior compliance" do
    test "Google Places provider implements all required behaviors" do
      # Test that the provider module implements the required functions
      assert function_exported?(GooglePlacesRichDataProvider, :provider_id, 0)
      assert function_exported?(GooglePlacesRichDataProvider, :provider_name, 0)
      assert function_exported?(GooglePlacesRichDataProvider, :supported_types, 0)
      assert function_exported?(GooglePlacesRichDataProvider, :validate_config, 0)
      assert function_exported?(GooglePlacesRichDataProvider, :search, 2)
      assert function_exported?(GooglePlacesRichDataProvider, :get_details, 3)
      assert function_exported?(GooglePlacesRichDataProvider, :get_cached_details, 3)
    end

    test "TMDB provider implements all required behaviors" do
      # Test that the provider module implements the required functions
      assert function_exported?(TmdbRichDataProvider, :provider_id, 0)
      assert function_exported?(TmdbRichDataProvider, :provider_name, 0)
      assert function_exported?(TmdbRichDataProvider, :supported_types, 0)
      assert function_exported?(TmdbRichDataProvider, :validate_config, 0)
      assert function_exported?(TmdbRichDataProvider, :search, 2)
      assert function_exported?(TmdbRichDataProvider, :get_details, 3)
      assert function_exported?(TmdbRichDataProvider, :get_cached_details, 3)
    end
  end

  describe "configuration validation" do
    test "Google Places provider validates configuration" do
      result = GooglePlacesRichDataProvider.validate_config()

      # Should return either :ok or {:error, reason}
      assert result == :ok or match?({:error, _}, result)
    end

    test "TMDB provider validates configuration" do
      result = TmdbRichDataProvider.validate_config()

      # Should return either :ok or {:error, reason}
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "basic functionality" do
    test "Google Places provider can handle search requests" do
      # Test that search doesn't crash (but might return empty due to no API key in test)
      result = GooglePlacesRichDataProvider.search("test location", %{type: :restaurant})

      # Should return either {:ok, results} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "TMDB provider can handle search requests" do
      # Test that search doesn't crash (but might return empty due to no API key in test)
      result = TmdbRichDataProvider.search("test movie", %{})

      # Should return either {:ok, results} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "manager functionality" do
    test "RichDataManager can search across providers" do
      # Test that the manager can coordinate searches
      result = RichDataManager.search("test", %{})

      # Should return either {:ok, results} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "RichDataManager can validate all providers" do
      # Test that the manager can validate provider configurations
      result = RichDataManager.validate_providers()

      # Should return either {:ok, results} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "RichDataManager can check health of providers" do
      # Test that the manager can check provider health
      result = RichDataManager.health_check()

      # Should return either {:ok, status} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
