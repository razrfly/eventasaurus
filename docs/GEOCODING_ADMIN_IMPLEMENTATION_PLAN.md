# Geocoding Provider Admin Dashboard - Implementation Plan

## Overview

This document provides detailed implementation options for **Part 3** of the Multi-Provider Geocoding System (#1672): creating an admin dashboard to manage geocoding provider configuration, ordering, and monitoring.

### Current State

- **Configuration**: Hardcoded in `config/runtime.exs` with environment variable toggles
- **Providers**: 8 total (6 free providers, 2 paid Google providers)
- **Priority**: Static priorities (1-6 for free, 97-99 for paid)
- **Enable/Disable**: Via environment variables (e.g., `MAPBOX_ENABLED=true`)
- **Monitoring**: Existing `GeocodingDashboardLive` shows performance metrics

### Desired State

- **Dynamic Management**: Admin UI to reorder providers without code changes
- **Runtime Control**: Enable/disable providers dynamically
- **Visual Priority**: Drag-and-drop interface for priority management
- **Performance Integration**: Display real-time success rates alongside configuration
- **Testing Support**: Easy A/B testing of provider configurations

---

## Implementation Options

### Option A: Database-Backed Configuration (Recommended)

**Architecture**: Store provider configuration in Postgres database, read at runtime with caching.

#### Schema Design

```elixir
defmodule EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider do
  use Ecto.Schema
  import Ecto.Changeset

  schema "geocoding_providers" do
    field :name, :string              # "mapbox", "here", etc.
    field :display_name, :string      # "Mapbox", "HERE", etc.
    field :module, :string             # "EventasaurusDiscovery.Geocoding.Providers.Mapbox"
    field :priority, :integer          # 1-99, lower = higher priority
    field :enabled, :boolean, default: true
    field :paused, :boolean, default: false  # Temporary pause vs permanent disable

    # Metadata
    field :cost_per_call, :decimal     # For cost tracking
    field :free_tier_limit, :integer   # Requests/month
    field :rate_limit, :string         # "100K/month", "1 req/sec"
    field :description, :text

    # Performance tracking (denormalized for quick access)
    field :last_success_at, :utc_datetime
    field :last_failure_at, :utc_datetime
    field :recent_success_rate, :decimal  # Last 24h success rate

    timestamps()
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :display_name, :module, :priority, :enabled,
                    :paused, :cost_per_call, :free_tier_limit, :rate_limit,
                    :description])
    |> validate_required([:name, :display_name, :module, :priority])
    |> validate_number(:priority, greater_than: 0, less_than: 100)
    |> unique_constraint(:name)
    |> unique_constraint(:priority)
  end
end
```

#### Migration Strategy

```elixir
defmodule EventasaurusApp.Repo.Migrations.CreateGeocodingProviders do
  use Ecto.Migration

  def up do
    create table(:geocoding_providers) do
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :module, :string, null: false
      add :priority, :integer, null: false
      add :enabled, :boolean, default: true, null: false
      add :paused, :boolean, default: false, null: false

      add :cost_per_call, :decimal, precision: 10, scale: 6
      add :free_tier_limit, :integer
      add :rate_limit, :string
      add :description, :text

      add :last_success_at, :utc_datetime
      add :last_failure_at, :utc_datetime
      add :recent_success_rate, :decimal, precision: 5, scale: 2

      timestamps()
    end

    create unique_index(:geocoding_providers, [:name])
    create unique_index(:geocoding_providers, [:priority])
    create index(:geocoding_providers, [:enabled])
    create index(:geocoding_providers, [:priority, :enabled])

    # Seed with current configuration from runtime.exs
    execute """
    INSERT INTO geocoding_providers (name, display_name, module, priority, enabled, cost_per_call, free_tier_limit, rate_limit, description, inserted_at, updated_at)
    VALUES
      ('mapbox', 'Mapbox', 'EventasaurusDiscovery.Geocoding.Providers.Mapbox', 1, true, 0, 100000, '100K/month', 'High quality, global coverage', NOW(), NOW()),
      ('here', 'HERE', 'EventasaurusDiscovery.Geocoding.Providers.Here', 2, true, 0, 250000, '250K/month', 'High quality, generous rate limits', NOW(), NOW()),
      ('geoapify', 'Geoapify', 'EventasaurusDiscovery.Geocoding.Providers.Geoapify', 3, true, 0, 90000, '90K/month', 'Good quality', NOW(), NOW()),
      ('locationiq', 'LocationIQ', 'EventasaurusDiscovery.Geocoding.Providers.LocationIQ', 4, true, 0, 150000, '150K/month', 'OSM-based', NOW(), NOW()),
      ('openstreetmap', 'OpenStreetMap', 'EventasaurusDiscovery.Geocoding.Providers.OpenStreetMap', 5, true, 0, NULL, '1 req/sec', 'Free, rate-limited', NOW(), NOW()),
      ('photon', 'Photon', 'EventasaurusDiscovery.Geocoding.Providers.Photon', 6, true, 0, NULL, 'Unlimited', 'Community service', NOW(), NOW()),
      ('google_maps', 'Google Maps', 'EventasaurusDiscovery.Geocoding.Providers.GoogleMaps', 97, false, 0.005, NULL, 'Pay-per-use', 'High quality, paid', NOW(), NOW()),
      ('google_places', 'Google Places', 'EventasaurusDiscovery.Geocoding.Providers.GooglePlaces', 99, false, 0.034, NULL, 'Pay-per-use', 'Highest quality, paid', NOW(), NOW())
    """
  end

  def down do
    drop table(:geocoding_providers)
  end
end
```

#### Context Module

```elixir
defmodule EventasaurusDiscovery.Geocoding.ProviderConfig do
  @moduledoc """
  Context for managing geocoding provider configuration.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

  # Cache TTL: 60 seconds (balance between freshness and performance)
  @cache_ttl 60_000
  @cache_key "geocoding_providers_active"

  @doc """
  Get all active providers ordered by priority.
  Cached for performance.
  """
  def list_active_providers do
    case Cachex.get(:geocoding_cache, @cache_key) do
      {:ok, nil} ->
        providers = fetch_active_providers()
        Cachex.put(:geocoding_cache, @cache_key, providers, ttl: @cache_ttl)
        providers

      {:ok, providers} ->
        providers
    end
  end

  defp fetch_active_providers do
    from(p in GeocodingProvider,
      where: p.enabled == true and p.paused == false,
      order_by: [asc: p.priority]
    )
    |> Repo.all()
    |> Enum.map(&provider_to_config/1)
  end

  defp provider_to_config(provider) do
    {String.to_existing_atom("Elixir.#{provider.module}"),
     [enabled: true, priority: provider.priority]}
  end

  @doc """
  List all providers for admin interface (including disabled).
  """
  def list_all_providers do
    from(p in GeocodingProvider, order_by: [asc: p.priority])
    |> Repo.all()
  end

  @doc """
  Update provider priority (used for drag-and-drop reordering).
  """
  def update_priority(provider_id, new_priority) do
    Repo.transaction(fn ->
      provider = Repo.get!(GeocodingProvider, provider_id)

      # Shift other providers to make room
      from(p in GeocodingProvider,
        where: p.priority >= ^new_priority and p.id != ^provider_id
      )
      |> Repo.update_all(inc: [priority: 1])

      # Update target provider
      provider
      |> GeocodingProvider.changeset(%{priority: new_priority})
      |> Repo.update!()

      # Clear cache
      invalidate_cache()
    end)
  end

  @doc """
  Toggle provider enabled/disabled state.
  """
  def toggle_enabled(provider_id) do
    provider = Repo.get!(GeocodingProvider, provider_id)

    provider
    |> GeocodingProvider.changeset(%{enabled: !provider.enabled})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        invalidate_cache()
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Pause provider temporarily (for testing/troubleshooting).
  """
  def pause_provider(provider_id) do
    provider = Repo.get!(GeocodingProvider, provider_id)

    provider
    |> GeocodingProvider.changeset(%{paused: true})
    |> Repo.update()
    |> tap(fn _ -> invalidate_cache() end)
  end

  def resume_provider(provider_id) do
    provider = Repo.get!(GeocodingProvider, provider_id)

    provider
    |> GeocodingProvider.changeset(%{paused: false})
    |> Repo.update()
    |> tap(fn _ -> invalidate_cache() end)
  end

  @doc """
  Bulk reorder providers (used after drag-and-drop).
  """
  def reorder_providers(provider_priority_map) when is_map(provider_priority_map) do
    Repo.transaction(fn ->
      Enum.each(provider_priority_map, fn {provider_id, new_priority} ->
        from(p in GeocodingProvider, where: p.id == ^provider_id)
        |> Repo.update_all(set: [priority: new_priority])
      end)

      invalidate_cache()
    end)
  end

  defp invalidate_cache do
    Cachex.del(:geocoding_cache, @cache_key)
  end
end
```

#### LiveView Admin Interface

```elixir
defmodule EventasaurusWeb.Admin.GeocodingProviderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Geocoding.ProviderConfig
  alias EventasaurusDiscovery.Metrics.GeocodingStats

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Geocoding Provider Management")
      |> load_providers()
      |> load_performance_stats()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    case ProviderConfig.toggle_enabled(id) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider status updated")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update provider")}
    end
  end

  @impl true
  def handle_event("pause_provider", %{"id" => id}, socket) do
    case ProviderConfig.pause_provider(id) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider paused")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to pause provider")}
    end
  end

  @impl true
  def handle_event("resume_provider", %{"id" => id}, socket) do
    case ProviderConfig.resume_provider(id) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider resumed")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resume provider")}
    end
  end

  @impl true
  def handle_event("reorder", %{"order" => order}, socket) do
    # order is a list of provider IDs in new order
    priority_map =
      order
      |> Enum.with_index(1)
      |> Map.new(fn {id, priority} -> {String.to_integer(id), priority} end)

    case ProviderConfig.reorder_providers(priority_map) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider order updated")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reorder providers")}
    end
  end

  @impl true
  def handle_event("refresh_stats", _params, socket) do
    {:noreply, load_performance_stats(socket)}
  end

  defp load_providers(socket) do
    providers = ProviderConfig.list_all_providers()
    assign(socket, :providers, providers)
  end

  defp load_performance_stats(socket) do
    case GeocodingStats.performance_summary() do
      {:ok, stats} ->
        assign(socket, :performance_stats, stats)

      {:error, _} ->
        assign(socket, :performance_stats, nil)
    end
  end
end
```

#### UI Template with Drag-and-Drop

```heex
<div class="px-4 sm:px-6 lg:px-8">
  <div class="sm:flex sm:items-center">
    <div class="sm:flex-auto">
      <h1 class="text-2xl font-semibold text-gray-900">Geocoding Provider Management</h1>
      <p class="mt-2 text-sm text-gray-700">
        Configure provider priority, enable/disable providers, and monitor performance.
      </p>
    </div>
    <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
      <button
        type="button"
        phx-click="refresh_stats"
        class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
      >
        <.icon name="hero-arrow-path" class="h-4 w-4 mr-2" /> Refresh Stats
      </button>
    </div>
  </div>

  <!-- Provider List with Drag-and-Drop -->
  <div class="mt-8">
    <div class="bg-white shadow overflow-hidden sm:rounded-md">
      <ul
        id="provider-list"
        phx-hook="Sortable"
        data-sortable-handle=".drag-handle"
        class="divide-y divide-gray-200"
      >
        <%= for provider <- @providers do %>
          <li
            id={"provider-#{provider.id}"}
            data-id={provider.id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50"
          >
            <div class="flex items-center justify-between">
              <!-- Drag Handle -->
              <div class="flex items-center flex-1">
                <button class="drag-handle cursor-move mr-4 text-gray-400 hover:text-gray-600">
                  <.icon name="hero-bars-3" class="h-6 w-6" />
                </button>

                <!-- Provider Info -->
                <div class="flex-1">
                  <div class="flex items-center">
                    <h3 class="text-lg font-medium text-gray-900">
                      <%= provider.display_name %>
                    </h3>
                    <span class={"ml-3 px-2 py-1 text-xs font-medium rounded-full #{if provider.enabled && !provider.paused, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                      <%= if provider.enabled && !provider.paused, do: "Active", else: "Inactive" %>
                    </span>
                    <%= if provider.paused do %>
                      <span class="ml-2 px-2 py-1 text-xs font-medium rounded-full bg-yellow-100 text-yellow-800">
                        Paused
                      </span>
                    <% end %>
                  </div>

                  <div class="mt-1 flex items-center text-sm text-gray-500">
                    <span>Priority: <%= provider.priority %></span>
                    <span class="mx-2">•</span>
                    <span><%= provider.rate_limit %></span>
                    <%= if provider.cost_per_call && provider.cost_per_call > 0 do %>
                      <span class="mx-2">•</span>
                      <span>$<%= provider.cost_per_call %>/call</span>
                    <% else %>
                      <span class="mx-2">•</span>
                      <span class="text-green-600">Free</span>
                    <% end %>
                  </div>

                  <!-- Performance Stats -->
                  <%= if @performance_stats do %>
                    <div class="mt-2 flex items-center text-sm">
                      <%= if provider_stats = get_provider_stats(@performance_stats, provider.name) do %>
                        <span class="text-gray-600">
                          Success Rate:
                          <span class={"font-medium #{success_rate_color(provider_stats.success_rate)}"}>
                            <%= Float.round(provider_stats.success_rate, 1) %>%
                          </span>
                        </span>
                        <span class="mx-2 text-gray-400">•</span>
                        <span class="text-gray-600">
                          Calls: <%= provider_stats.total_calls %>
                        </span>
                      <% else %>
                        <span class="text-gray-400">No recent activity</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Actions -->
              <div class="ml-4 flex items-center space-x-2">
                <%= if provider.enabled && !provider.paused do %>
                  <button
                    type="button"
                    phx-click="pause_provider"
                    phx-value-id={provider.id}
                    class="inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                  >
                    <.icon name="hero-pause" class="h-4 w-4 mr-1" /> Pause
                  </button>
                <% end %>

                <%= if provider.paused do %>
                  <button
                    type="button"
                    phx-click="resume_provider"
                    phx-value-id={provider.id}
                    class="inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                  >
                    <.icon name="hero-play" class="h-4 w-4 mr-1" /> Resume
                  </button>
                <% end %>

                <button
                  type="button"
                  phx-click="toggle_enabled"
                  phx-value-id={provider.id}
                  class={"inline-flex items-center px-3 py-1 border shadow-sm text-sm font-medium rounded-md #{if provider.enabled, do: "border-red-300 text-red-700 bg-white hover:bg-red-50", else: "border-green-300 text-green-700 bg-white hover:bg-green-50"}"}
                >
                  <%= if provider.enabled, do: "Disable", else: "Enable" %>
                </button>
              </div>
            </div>
          </li>
        <% end %>
      </ul>
    </div>
  </div>

  <!-- Help Text -->
  <div class="mt-4 bg-blue-50 border border-blue-200 rounded-md p-4">
    <div class="flex">
      <div class="flex-shrink-0">
        <.icon name="hero-information-circle" class="h-5 w-5 text-blue-400" />
      </div>
      <div class="ml-3">
        <h3 class="text-sm font-medium text-blue-800">How to use</h3>
        <div class="mt-2 text-sm text-blue-700">
          <ul class="list-disc pl-5 space-y-1">
            <li>Drag providers to reorder priority (lower number = higher priority)</li>
            <li>Use "Enable/Disable" to permanently enable/disable a provider</li>
            <li>Use "Pause/Resume" to temporarily pause a provider for testing</li>
            <li>Monitor success rates to identify underperforming providers</li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</div>
```

#### JavaScript Hook for Drag-and-Drop

```javascript
// assets/js/hooks/sortable.js
import Sortable from 'sortablejs';

export const SortableHook = {
  mounted() {
    const hook = this;
    const sortable = new Sortable(this.el, {
      animation: 150,
      handle: '.drag-handle',
      ghostClass: 'bg-blue-50',
      dragClass: 'opacity-50',
      onEnd: function(evt) {
        // Get new order of provider IDs
        const order = Array.from(evt.to.children).map(el => el.dataset.id);

        // Send to server
        hook.pushEvent('reorder', { order: order });
      }
    });

    this.sortable = sortable;
  },

  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }
};
```

#### Pros

✅ **Production-Ready**: Robust, scalable solution
✅ **Runtime Configuration**: No restarts needed
✅ **Performance**: Cached reads, minimal DB overhead
✅ **Audit Trail**: Track all configuration changes via timestamps
✅ **A/B Testing**: Easy to test different configurations
✅ **Performance Integration**: Store denormalized metrics for quick access
✅ **Multi-Environment**: Different configs per environment

#### Cons

❌ **Migration Required**: Requires database migration and data seeding
❌ **Complexity**: More moving parts than config-file approach
❌ **Cache Management**: Need to carefully manage cache invalidation

---

### Option B: Enhanced Configuration File with Hot-Reload

**Architecture**: Keep configuration in a dedicated Elixir config module, add hot-reload capability and admin UI to modify the file.

#### Configuration Module

```elixir
defmodule EventasaurusDiscovery.Geocoding.RuntimeConfig do
  @moduledoc """
  Runtime-reloadable geocoding provider configuration.
  Configuration stored in separate file: config/geocoding_providers.exs
  """

  use GenServer
  require Logger

  @config_file "config/geocoding_providers.exs"
  @refresh_interval :timer.seconds(30)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_providers do
    GenServer.call(__MODULE__, :get_providers)
  end

  def reload_config do
    GenServer.cast(__MODULE__, :reload)
  end

  def update_provider(name, attrs) do
    GenServer.call(__MODULE__, {:update_provider, name, attrs})
  end

  def reorder_providers(new_order) do
    GenServer.call(__MODULE__, {:reorder, new_order})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = load_config()
    schedule_reload()
    {:ok, state}
  end

  @impl true
  def handle_call(:get_providers, _from, state) do
    providers =
      state.providers
      |> Enum.filter(& &1.enabled)
      |> Enum.sort_by(& &1.priority)
      |> Enum.map(&provider_to_config/1)

    {:reply, providers, state}
  end

  @impl true
  def handle_call({:update_provider, name, attrs}, _from, state) do
    providers =
      Enum.map(state.providers, fn provider ->
        if provider.name == name do
          Map.merge(provider, attrs)
        else
          provider
        end
      end)

    new_state = %{state | providers: providers}

    case write_config(new_state) do
      :ok ->
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:reorder, new_order}, _from, state) do
    # new_order is list of provider names in desired order
    providers =
      new_order
      |> Enum.with_index(1)
      |> Enum.map(fn {name, priority} ->
        provider = Enum.find(state.providers, &(&1.name == name))
        %{provider | priority: priority}
      end)

    new_state = %{state | providers: providers}

    case write_config(new_state) do
      :ok ->
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:reload, _state) do
    new_state = load_config()
    Logger.info("Reloaded geocoding provider configuration")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:reload, _state) do
    new_state = load_config()
    schedule_reload()
    {:noreply, new_state}
  end

  # Private Functions

  defp load_config do
    case File.read(@config_file) do
      {:ok, content} ->
        {result, _} = Code.eval_string(content)
        result

      {:error, :enoent} ->
        Logger.warning("Config file not found, using defaults")
        default_config()
    end
  end

  defp write_config(state) do
    config_content = """
    # Geocoding Provider Configuration
    # This file is auto-generated by the admin interface
    # Last updated: #{DateTime.utc_now()}

    %{
      providers: [
    #{Enum.map_join(state.providers, ",\n", &format_provider/1)}
      ]
    }
    """

    File.write(@config_file, config_content)
  end

  defp format_provider(p) do
    """
        %{
          name: "#{p.name}",
          display_name: "#{p.display_name}",
          module: #{p.module},
          priority: #{p.priority},
          enabled: #{p.enabled},
          cost_per_call: #{p.cost_per_call || 0},
          rate_limit: "#{p.rate_limit}",
          description: "#{p.description}"
        }
    """
  end

  defp provider_to_config(provider) do
    {provider.module, [enabled: provider.enabled, priority: provider.priority]}
  end

  defp schedule_reload do
    Process.send_after(self(), :reload, @refresh_interval)
  end

  defp default_config do
    %{
      providers: [
        %{name: "mapbox", display_name: "Mapbox", module: EventasaurusDiscovery.Geocoding.Providers.Mapbox, priority: 1, enabled: true, cost_per_call: 0, rate_limit: "100K/month", description: "High quality"},
        # ... other providers
      ]
    }
  end
end
```

#### Configuration File Format

```elixir
# config/geocoding_providers.exs
# Last updated: 2025-01-15 10:30:00 UTC

%{
  providers: [
    %{
      name: "mapbox",
      display_name: "Mapbox",
      module: EventasaurusDiscovery.Geocoding.Providers.Mapbox,
      priority: 1,
      enabled: true,
      cost_per_call: 0,
      rate_limit: "100K/month",
      description: "High quality, global coverage"
    },
    %{
      name: "here",
      display_name: "HERE",
      module: EventasaurusDiscovery.Geocoding.Providers.Here,
      priority: 2,
      enabled: true,
      cost_per_call: 0,
      rate_limit: "250K/month",
      description: "High quality, generous rate limits"
    },
    # ... other providers
  ]
}
```

#### Admin Interface

Similar LiveView UI as Option A, but calls `RuntimeConfig.update_provider/2` and `RuntimeConfig.reorder_providers/1` instead of database operations.

#### Pros

✅ **Simple**: No database migration required
✅ **Version Control**: Configuration in Git
✅ **Fast Reads**: In-memory access via GenServer
✅ **Hot Reload**: Changes apply without restart
✅ **Portable**: Easy to copy configs between environments

#### Cons

❌ **File System Dependency**: Requires write access to config file
❌ **No Audit Trail**: Can't track who changed what when
❌ **Concurrency**: Race conditions if multiple admins edit simultaneously
❌ **Deployment**: Config file changes might be overwritten on deploy
❌ **Limited Scalability**: Not suitable for multi-node clusters

---

### Option C: Hybrid Approach (Config + Database Overlay)

**Architecture**: Keep default configuration in `runtime.exs`, but allow database overrides for runtime modifications.

#### How It Works

1. **Base Configuration**: Providers defined in `runtime.exs` as defaults
2. **Override Table**: Database table stores only overrides (priority changes, enable/disable)
3. **Merge Strategy**: At runtime, merge database overrides with config defaults
4. **Fallback**: If database unavailable, use config defaults

#### Schema

```elixir
defmodule EventasaurusDiscovery.Geocoding.Schema.ProviderOverride do
  use Ecto.Schema

  schema "geocoding_provider_overrides" do
    field :name, :string              # References provider in config
    field :priority_override, :integer
    field :enabled_override, :boolean
    field :paused, :boolean, default: false

    timestamps()
  end
end
```

#### Configuration Resolver

```elixir
defmodule EventasaurusDiscovery.Geocoding.ConfigResolver do
  @moduledoc """
  Resolves geocoding provider configuration by merging config defaults
  with database overrides.
  """

  def get_providers do
    base_providers = Application.get_env(:eventasaurus, :geocoding)[:providers]
    overrides = load_overrides()

    base_providers
    |> Enum.map(fn {module, opts} ->
      name = module_to_name(module)
      apply_overrides({module, opts}, Map.get(overrides, name))
    end)
    |> Enum.filter(fn {_module, opts} -> opts[:enabled] end)
    |> Enum.sort_by(fn {_module, opts} -> opts[:priority] end)
  end

  defp load_overrides do
    case Repo.all(ProviderOverride) do
      overrides when is_list(overrides) ->
        Map.new(overrides, fn o -> {o.name, o} end)

      _ ->
        %{}
    end
  rescue
    _ -> %{}  # Fallback if DB unavailable
  end

  defp apply_overrides({module, opts}, nil), do: {module, opts}
  defp apply_overrides({module, opts}, override) do
    new_opts =
      opts
      |> Keyword.put(:priority, override.priority_override || opts[:priority])
      |> Keyword.put(:enabled, override.enabled_override && !override.paused)

    {module, new_opts}
  end
end
```

#### Pros

✅ **Best of Both Worlds**: Config defaults + runtime overrides
✅ **Graceful Degradation**: Falls back to config if DB unavailable
✅ **Version Control**: Base config in Git
✅ **Flexibility**: Runtime changes without losing defaults
✅ **Easy Rollback**: Delete overrides to restore defaults

#### Cons

❌ **Complexity**: Two sources of truth to manage
❌ **Confusion**: Admins must understand override vs default
❌ **Testing**: More complex testing scenarios

---

## UI/UX Considerations

### Drag-and-Drop Libraries

**Recommended: SortableJS**
- **Pros**: Lightweight (7KB), no dependencies, touch support, great Phoenix integration
- **Cons**: Not as feature-rich as larger libraries
- **Installation**: `npm install sortablejs`

**Alternative: react-beautiful-dnd** (if using React in admin)
- **Pros**: Excellent UX, accessibility, animations
- **Cons**: React dependency, larger bundle size

**Alternative: dnd-kit** (modern React alternative)
- **Pros**: Modern, modular, excellent accessibility
- **Cons**: Requires React, more setup

### Real-Time Updates

**Option 1: PubSub + LiveView**
```elixir
# Broadcast config changes to all connected admin sessions
Phoenix.PubSub.broadcast(
  EventasaurusApp.PubSub,
  "geocoding:config",
  {:config_updated, provider_id}
)

# In LiveView
def handle_info({:config_updated, _id}, socket) do
  {:noreply, load_providers(socket)}
end
```

**Option 2: Periodic Polling**
```javascript
// In LiveView, refresh every 30 seconds
setInterval(() => {
  this.pushEvent('refresh_stats', {});
}, 30000);
```

### Performance Metrics Display

Integrate with existing `GeocodingStats` module:

```elixir
defp enrich_providers_with_stats(providers) do
  case GeocodingStats.performance_summary() do
    {:ok, stats} ->
      Enum.map(providers, fn provider ->
        provider_stats = find_stats(stats.by_provider, provider.name)
        Map.put(provider, :stats, provider_stats)
      end)

    {:error, _} ->
      providers
  end
end
```

Display in UI:
- Success rate badge (green >95%, yellow 85-95%, red <85%)
- Last 24h call volume
- Average response time
- Recent errors

---

## Testing Strategy

### Unit Tests

```elixir
defmodule EventasaurusDiscovery.Geocoding.ProviderConfigTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  describe "list_active_providers/0" do
    test "returns only enabled providers in priority order" do
      # Create test providers
      insert(:geocoding_provider, name: "test1", priority: 2, enabled: true)
      insert(:geocoding_provider, name: "test2", priority: 1, enabled: true)
      insert(:geocoding_provider, name: "test3", priority: 3, enabled: false)

      providers = ProviderConfig.list_active_providers()

      assert length(providers) == 2
      assert Enum.at(providers, 0) |> elem(1) |> Keyword.get(:priority) == 1
    end

    test "excludes paused providers" do
      insert(:geocoding_provider, name: "test1", enabled: true, paused: true)

      assert ProviderConfig.list_active_providers() == []
    end
  end

  describe "reorder_providers/1" do
    test "updates priorities correctly" do
      p1 = insert(:geocoding_provider, name: "test1", priority: 1)
      p2 = insert(:geocoding_provider, name: "test2", priority: 2)

      {:ok, _} = ProviderConfig.reorder_providers(%{
        p1.id => 2,
        p2.id => 1
      })

      assert Repo.get!(GeocodingProvider, p1.id).priority == 2
      assert Repo.get!(GeocodingProvider, p2.id).priority == 1
    end

    test "invalidates cache after reorder" do
      # Test cache invalidation
    end
  end
end
```

### Integration Tests

```elixir
defmodule EventasaurusWeb.Admin.GeocodingProviderLiveTest do
  use EventasaurusWeb.ConnCase
  import Phoenix.LiveViewTest

  test "displays all providers", %{conn: conn} do
    insert(:geocoding_provider, name: "mapbox", display_name: "Mapbox")

    {:ok, view, html} = live(conn, ~p"/admin/geocoding/providers")

    assert html =~ "Mapbox"
  end

  test "toggles provider enabled status", %{conn: conn} do
    provider = insert(:geocoding_provider, enabled: true)

    {:ok, view, _html} = live(conn, ~p"/admin/geocoding/providers")

    view
    |> element("#provider-#{provider.id} button", "Disable")
    |> render_click()

    assert Repo.get!(GeocodingProvider, provider.id).enabled == false
  end

  test "reorders providers via drag-and-drop", %{conn: conn} do
    p1 = insert(:geocoding_provider, priority: 1)
    p2 = insert(:geocoding_provider, priority: 2)

    {:ok, view, _html} = live(conn, ~p"/admin/geocoding/providers")

    view
    |> render_hook("reorder", %{order: [p2.id, p1.id]})

    assert Repo.get!(GeocodingProvider, p1.id).priority == 2
    assert Repo.get!(GeocodingProvider, p2.id).priority == 1
  end
end
```

### E2E Tests (Playwright/Wallaby)

```elixir
test "admin can reorder providers with drag-and-drop", %{session: session} do
  session
  |> visit("/admin/geocoding/providers")
  |> assert_has(css(".provider-item", count: 8))
  |> drag_element(css("#provider-2"), to: css("#provider-1"))
  |> assert_has(css("#provider-1 + #provider-2"))  # Verify new order
end
```

---

## Migration & Rollout Plan

### Phase 1: Preparation (Week 1)

1. **Decision**: Choose Option A, B, or C based on requirements
2. **Design Review**: Review schema/architecture with team
3. **Dependency Setup**: Install SortableJS, update LiveView hooks
4. **Testing Setup**: Create test factories and fixtures

### Phase 2: Implementation (Week 2-3)

**Option A Timeline:**
- Day 1-2: Database migration + schema
- Day 3-4: Context module + caching
- Day 5-7: LiveView admin interface
- Day 8-9: Drag-and-drop integration
- Day 10-11: Performance metrics integration
- Day 12-14: Testing + refinement

**Option B Timeline:**
- Day 1-2: GenServer + config file format
- Day 3-4: LiveView admin interface
- Day 5-6: File write operations + locking
- Day 7-8: Drag-and-drop integration
- Day 9-10: Hot-reload mechanism
- Day 11-14: Testing + refinement

### Phase 3: Testing (Week 4)

1. **Unit Tests**: All context functions
2. **Integration Tests**: LiveView interactions
3. **E2E Tests**: Drag-and-drop workflows
4. **Performance Tests**: Cache effectiveness, query performance
5. **User Acceptance**: Admin team testing

### Phase 4: Deployment (Week 5)

1. **Staging Deployment**: Deploy to staging with test data
2. **Data Migration**: Seed production providers from runtime.exs
3. **Monitoring Setup**: Track config changes, performance impact
4. **Production Deployment**: Deploy during low-traffic period
5. **Validation**: Verify providers working correctly

### Phase 5: Documentation & Handoff (Week 6)

1. **Admin Documentation**: How to use the interface
2. **Developer Documentation**: How to add new providers
3. **Runbook**: Troubleshooting common issues
4. **Training**: Train admin team on new interface

---

## Recommended Approach

**For Production: Option A (Database-Backed Configuration)**

**Rationale:**
1. **Scalability**: Works in multi-node clusters
2. **Audit Trail**: Track all configuration changes
3. **Performance**: Efficient caching with minimal overhead
4. **Flexibility**: Easy to extend with additional features (scheduling, A/B testing)
5. **Production-Ready**: Robust error handling and rollback capabilities

**For Rapid Prototyping: Option B (Config File)**

**Rationale:**
1. **Speed**: Faster initial implementation
2. **Simplicity**: Fewer moving parts
3. **Version Control**: Configuration changes tracked in Git
4. **Good Enough**: Sufficient for single-node deployments

**For Conservative Approach: Option C (Hybrid)**

**Rationale:**
1. **Safety**: Always has config fallback
2. **Flexibility**: Runtime changes without losing defaults
3. **Gradual Migration**: Can start with overrides and migrate to full DB later

---

## Success Metrics

After implementation, track:

1. **Configuration Changes**: Frequency of provider reordering/toggling
2. **Performance Impact**: Provider success rates before/after changes
3. **Cost Optimization**: Reduction in paid provider usage
4. **Admin Efficiency**: Time spent managing provider configuration
5. **System Reliability**: Geocoding success rate trends

---

## Future Enhancements

Once basic admin interface is working:

1. **Automatic Failover**: Auto-disable providers with low success rates
2. **Cost Tracking**: Real-time cost monitoring with alerts
3. **A/B Testing**: Test different provider orders simultaneously
4. **Scheduled Changes**: Configure provider priorities for different times
5. **Geographic Routing**: Different provider priorities per region
6. **Load Balancing**: Distribute requests across providers with similar priority
7. **Smart Retry**: Provider-specific retry strategies based on error types

---

## Questions to Answer Before Implementation

1. **Multi-Node Deployment**: Will Eventasaurus run on multiple nodes?
   - If yes → Option A
   - If no → Option B acceptable

2. **Change Frequency**: How often will admins change provider configuration?
   - Daily/weekly → Need good UI (all options)
   - Monthly/rarely → Option B sufficient

3. **Audit Requirements**: Need to track who changed what and when?
   - Yes → Option A
   - No → Option B or C

4. **Version Control**: Should config changes be in Git?
   - Yes → Option B or C
   - No → Option A

5. **Budget**: How much time available for implementation?
   - 2-3 weeks → Option A
   - 1-2 weeks → Option B
   - 3-4 weeks → Option C

---

## Conclusion

This document provides three detailed approaches to implementing the geocoding provider admin dashboard. Each option has been designed with real implementation details, code examples, and testing strategies.

**Recommendation**: Start with **Option A (Database-Backed)** for production systems, as it provides the most flexibility and scalability for long-term success. The initial investment in database schema and caching will pay off with easier maintenance and better performance characteristics.

For additional context, see:
- Original Issue: #1672
- Audit Document: `docs/AUDIT_MULTI_PROVIDER_GEOCODING.md`
- Implementation Summary: `docs/IMPLEMENTATION_SUMMARY.md`
