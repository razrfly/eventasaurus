defmodule EventasaurusWeb.Services.MovieConfigTest do
  use ExUnit.Case, async: true
  alias EventasaurusWeb.Services.MovieConfig

  describe "get_api_key/0" do
    test "returns error when TMDB_API_KEY is not set" do
      System.delete_env("TMDB_API_KEY")
      assert {:error, "TMDB_API_KEY environment variable is not set"} = MovieConfig.get_api_key()
    end

    test "returns error when TMDB_API_KEY is empty" do
      System.put_env("TMDB_API_KEY", "")
      assert {:error, "TMDB_API_KEY environment variable is empty"} = MovieConfig.get_api_key()
    end

    test "returns key when TMDB_API_KEY is set" do
      System.put_env("TMDB_API_KEY", "test_key_123")
      assert {:ok, "test_key_123"} = MovieConfig.get_api_key()
    end
  end

  describe "get_api_key!/0" do
    test "raises when TMDB_API_KEY is not set" do
      System.delete_env("TMDB_API_KEY")

      assert_raise RuntimeError, ~r/TMDB API Key Error/, fn ->
        MovieConfig.get_api_key!()
      end
    end

    test "returns key when TMDB_API_KEY is set" do
      System.put_env("TMDB_API_KEY", "test_key_123")
      assert "test_key_123" = MovieConfig.get_api_key!()
    end
  end

  describe "validate_config!/0" do
    test "raises when configuration is invalid" do
      System.delete_env("TMDB_API_KEY")

      assert_raise RuntimeError, ~r/TMDB Configuration Error/, fn ->
        MovieConfig.validate_config!()
      end
    end

    test "succeeds when configuration is valid" do
      System.put_env("TMDB_API_KEY", "test_key_123")
      assert :ok = MovieConfig.validate_config!()
    end
  end

  describe "build_image_url/2" do
    test "returns nil for nil path" do
      assert nil == MovieConfig.build_image_url(nil, "w500")
    end

    test "returns nil for empty path" do
      assert nil == MovieConfig.build_image_url("", "w500")
    end

    test "returns nil for invalid path format" do
      assert nil == MovieConfig.build_image_url("invalid-path", "w500")
      assert nil == MovieConfig.build_image_url("/invalid", "w500")
      assert nil == MovieConfig.build_image_url("/path-without-extension", "w500")
    end

    test "builds correct URL for valid TMDB path" do
      expected = "https://image.tmdb.org/t/p/w500/abc123.jpg"
      assert expected == MovieConfig.build_image_url("/abc123.jpg", "w500")
    end

    test "builds correct URL for different sizes" do
      path = "/abc123.jpg"

      assert "https://image.tmdb.org/t/p/w300/abc123.jpg" ==
               MovieConfig.build_image_url(path, "w300")

      assert "https://image.tmdb.org/t/p/original/abc123.jpg" ==
               MovieConfig.build_image_url(path, "original")
    end

    test "works with different valid file extensions" do
      assert "https://image.tmdb.org/t/p/w500/test.png" ==
               MovieConfig.build_image_url("/test.png", "w500")

      assert "https://image.tmdb.org/t/p/w500/test.webp" ==
               MovieConfig.build_image_url("/test.webp", "w500")

      assert "https://image.tmdb.org/t/p/w500/test.jpeg" ==
               MovieConfig.build_image_url("/test.jpeg", "w500")
    end

    test "handles paths with valid special characters" do
      assert "https://image.tmdb.org/t/p/w500/test_123-abc.jpg" ==
               MovieConfig.build_image_url("/test_123-abc.jpg", "w500")

      assert "https://image.tmdb.org/t/p/w500/test.name.jpg" ==
               MovieConfig.build_image_url("/test.name.jpg", "w500")
    end

    test "returns nil for non-string arguments" do
      assert nil == MovieConfig.build_image_url(123, "w500")
      assert nil == MovieConfig.build_image_url("/test.jpg", 500)
    end
  end

  describe "build_api_url/1" do
    test "builds correct API URL" do
      expected = "https://api.themoviedb.org/3/movie/123"
      assert expected == MovieConfig.build_api_url("/movie/123")
    end

    test "handles leading slash correctly" do
      assert MovieConfig.build_api_url("/search/movie") ==
               MovieConfig.build_api_url("search/movie")
    end
  end

  describe "configuration getters" do
    test "get_api_base_url/0 returns correct URL" do
      assert "https://api.themoviedb.org/3" == MovieConfig.get_api_base_url()
    end

    test "get_image_base_url/0 returns correct URL" do
      assert "https://image.tmdb.org/t/p" == MovieConfig.get_image_base_url()
    end

    test "get_timeout_config/0 returns reasonable values" do
      config = MovieConfig.get_timeout_config()
      assert is_list(config)
      assert config[:timeout] > 0
      assert config[:recv_timeout] > 0
    end

    test "get_rate_limit_config/0 returns sensible limits" do
      config = MovieConfig.get_rate_limit_config()
      assert is_map(config)
      # Should be under TMDB's limit
      assert config.max_requests_per_second <= 50
      assert config.max_requests_per_second > 0
      assert config.window_seconds > 0
    end

    test "get_cache_config/0 returns valid cache settings" do
      config = MovieConfig.get_cache_config()
      assert is_map(config)
      assert config.ttl_milliseconds > 0
      assert is_atom(config.table_name)
    end

    test "get_api_headers/0 returns proper headers" do
      headers = MovieConfig.get_api_headers()
      assert is_list(headers)
      assert {"Accept", "application/json"} in headers
    end
  end

  describe "log_config_status/0" do
    test "executes log_config_status without errors when API key is present" do
      System.put_env("TMDB_API_KEY", "test_key_123456789")
      assert :ok = MovieConfig.log_config_status()
    end

    test "executes log_config_status without errors when API key is missing" do
      System.delete_env("TMDB_API_KEY")
      assert :ok = MovieConfig.log_config_status()
    end
  end
end
