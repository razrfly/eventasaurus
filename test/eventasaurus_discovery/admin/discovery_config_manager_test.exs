defmodule EventasaurusDiscovery.Admin.DiscoveryConfigManagerTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Repo

  describe "enable_city/1" do
    test "enables discovery for a city with default config" do
      city = insert(:city)

      assert {:ok, updated_city} = DiscoveryConfigManager.enable_city(city.id)
      assert updated_city.discovery_enabled == true
      assert updated_city.discovery_config != nil
      assert updated_city.discovery_config.schedule.cron == "0 0 * * *"
      assert updated_city.discovery_config.sources == []
    end

    test "returns error for non-existent city" do
      assert {:error, :not_found} = DiscoveryConfigManager.enable_city(999_999)
    end
  end

  describe "disable_city/1" do
    test "disables discovery for a city" do
      city = insert(:city, discovery_enabled: true)

      assert {:ok, updated_city} = DiscoveryConfigManager.disable_city(city.id)
      assert updated_city.discovery_enabled == false
    end
  end

  describe "enable_source/3" do
    test "enables a new source for a city" do
      city = insert(:city, discovery_enabled: true)

      settings = %{limit: 100, radius: 50}
      assert {:ok, updated_city} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", settings)

      source = Enum.find(updated_city.discovery_config.sources, &(&1.name == "bandsintown"))
      assert source != nil
      assert source.enabled == true
      assert source.settings == %{limit: 100, radius: 50}
    end

    test "updates existing source" do
      city = insert(:city, discovery_enabled: true)

      # Enable first time
      {:ok, _} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{limit: 100})

      # Enable again with different settings
      {:ok, updated_city} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{limit: 200})

      sources = updated_city.discovery_config.sources
      assert length(sources) == 1
      assert hd(sources).settings == %{limit: 200}
    end

    test "returns error for invalid source" do
      city = insert(:city, discovery_enabled: true)

      assert {:error, :invalid_source} = DiscoveryConfigManager.enable_source(city.id, "invalid-source", %{})
    end
  end

  describe "disable_source/2" do
    test "disables an enabled source" do
      city = insert(:city, discovery_enabled: true)
      {:ok, _} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{})

      assert {:ok, updated_city} = DiscoveryConfigManager.disable_source(city.id, "bandsintown")

      source = Enum.find(updated_city.discovery_config.sources, &(&1.name == "bandsintown"))
      assert source.enabled == false
    end

    test "returns error for non-existent source" do
      city = insert(:city, discovery_enabled: true)

      assert {:error, :source_not_found} = DiscoveryConfigManager.disable_source(city.id, "bandsintown")
    end
  end

  describe "update_source_settings/3" do
    test "updates settings for a source" do
      city = insert(:city, discovery_enabled: true)
      {:ok, _} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{limit: 100})

      assert {:ok, updated_city} = DiscoveryConfigManager.update_source_settings(city.id, "bandsintown", %{radius: 50})

      source = Enum.find(updated_city.discovery_config.sources, &(&1.name == "bandsintown"))
      assert source.settings == %{limit: 100, radius: 50}
    end
  end

  describe "update_source_stats/3" do
    test "updates stats after successful run" do
      city = insert(:city, discovery_enabled: true)
      {:ok, _} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{})

      assert {:ok, updated_city} = DiscoveryConfigManager.update_source_stats(city.id, "bandsintown", :success)

      source = Enum.find(updated_city.discovery_config.sources, &(&1.name == "bandsintown"))
      assert source.stats.run_count == 1
      assert source.stats.success_count == 1
      assert source.stats.error_count == 0
      assert source.last_run_at != nil
      assert source.next_run_at != nil
    end

    test "updates stats after failed run" do
      city = insert(:city, discovery_enabled: true)
      {:ok, _} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{})

      assert {:ok, updated_city} = DiscoveryConfigManager.update_source_stats(city.id, "bandsintown", {:error, "timeout"})

      source = Enum.find(updated_city.discovery_config.sources, &(&1.name == "bandsintown"))
      assert source.stats.run_count == 1
      assert source.stats.success_count == 0
      assert source.stats.error_count == 1
      assert source.stats.last_error == "timeout"
    end
  end

  describe "list_discovery_enabled_cities/0" do
    test "returns only cities with discovery enabled" do
      city1 = insert(:city, discovery_enabled: true)
      city2 = insert(:city, discovery_enabled: false)
      city3 = insert(:city, discovery_enabled: true)

      cities = DiscoveryConfigManager.list_discovery_enabled_cities()
      city_ids = Enum.map(cities, & &1.id)

      assert city1.id in city_ids
      assert city3.id in city_ids
      refute city2.id in city_ids
    end
  end

  describe "get_due_sources/1" do
    test "returns sources that are due to run" do
      city = insert(:city, discovery_enabled: true)
      {:ok, city} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{})

      # Reload to get embedded config
      city = Repo.get!(City, city.id)

      sources = DiscoveryConfigManager.get_due_sources(city)
      assert length(sources) == 1
      assert hd(sources).name == "bandsintown"
    end

    test "does not return sources not due to run" do
      city = insert(:city, discovery_enabled: true)
      {:ok, _} = DiscoveryConfigManager.enable_source(city.id, "bandsintown", %{})

      # Update to set next_run in future
      {:ok, city} = DiscoveryConfigManager.update_source_stats(city.id, "bandsintown", :success)

      sources = DiscoveryConfigManager.get_due_sources(city)
      assert length(sources) == 0
    end
  end
end
