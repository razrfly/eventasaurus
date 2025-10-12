# Geocoding Provider Admin Dashboard - MVP Implementation

## Overview

Streamlined MVP for managing geocoding provider configuration via admin dashboard. Focus: minimal database schema, core functionality only.

## Core Principle

**Keep it simple.** Only store what's actually needed in the database. Everything else belongs in code.

---

## Database Schema (Minimal)

### Ecto Schema

```elixir
# lib/eventasaurus_discovery/geocoding/schema/geocoding_provider.ex
defmodule EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider do
  use Ecto.Schema
  import Ecto.Changeset

  schema "geocoding_providers" do
    field :name, :string         # "mapbox", "here", "geoapify", etc.
    field :priority, :integer    # 1-99 (lower = higher priority)
    field :enabled, :boolean     # on/off toggle
    timestamps()
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :priority, :enabled])
    |> validate_required([:name, :priority])
    |> validate_number(:priority, greater_than: 0, less_than: 100)
    |> unique_constraint(:name)
    |> unique_constraint(:priority)
  end
end
```

### Migration

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_create_geocoding_providers.exs
defmodule EventasaurusApp.Repo.Migrations.CreateGeocodingProviders do
  use Ecto.Migration

  def up do
    create table(:geocoding_providers) do
      add :name, :string, null: false
      add :priority, :integer, null: false
      add :enabled, :boolean, default: true, null: false
      timestamps()
    end

    create unique_index(:geocoding_providers, [:name])
    create unique_index(:geocoding_providers, [:priority])
    create index(:geocoding_providers, [:enabled, :priority])

    # Seed from current runtime.exs configuration
    execute """
    INSERT INTO geocoding_providers (name, priority, enabled, inserted_at, updated_at)
    VALUES
      ('mapbox', 1, true, NOW(), NOW()),
      ('here', 2, true, NOW(), NOW()),
      ('geoapify', 3, true, NOW(), NOW()),
      ('locationiq', 4, true, NOW(), NOW()),
      ('openstreetmap', 5, true, NOW(), NOW()),
      ('photon', 6, true, NOW(), NOW()),
      ('google_maps', 97, false, NOW(), NOW()),
      ('google_places', 99, false, NOW(), NOW())
    """
  end

  def down do
    drop table(:geocoding_providers)
  end
end
```

---

## Inferred Data (Not in Database)

### Provider Module Names

Derive from `name` field:

```elixir
defp name_to_module("mapbox") do
  EventasaurusDiscovery.Geocoding.Providers.Mapbox
end

defp name_to_module("here") do
  EventasaurusDiscovery.Geocoding.Providers.Here
end

# Generic for standard names:
defp name_to_module(name) do
  module_name =
    name
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")

  Module.concat([EventasaurusDiscovery.Geocoding.Providers, module_name])
end
```

### Display Names

Helper function in LiveView:

```elixir
# Special cases that don't follow simple capitalization
@display_names %{
  "here" => "HERE",
  "openstreetmap" => "OpenStreetMap",
  "locationiq" => "LocationIQ",
  "geoapify" => "Geoapify"
}

defp display_name(name) do
  Map.get(@display_names, name, String.capitalize(name))
end
```

### Provider Metadata

Belongs in the provider module itself:

```elixir
defmodule EventasaurusDiscovery.Geocoding.Providers.Mapbox do
  @behaviour EventasaurusDiscovery.Geocoding.Provider

  @metadata %{
    cost_per_call: 0,
    free_tier_limit: 100_000,
    rate_limit: "100K/month",
    description: "High quality, global coverage"
  }

  def metadata, do: @metadata

  # ... geocoding implementation
end
```

**Why?**
- Metadata is tightly coupled to the provider code
- Changes with provider updates, not admin decisions
- No DB bloat
- Type-safe with structs if needed

---

## Context Module

```elixir
# lib/eventasaurus_discovery/geocoding/provider_config.ex
defmodule EventasaurusDiscovery.Geocoding.ProviderConfig do
  @moduledoc """
  Manages geocoding provider configuration (MVP version).
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

  @doc """
  Get active providers for geocoding system.
  Returns list of {module, opts} tuples.
  """
  def list_active_providers do
    from(p in GeocodingProvider,
      where: p.enabled == true,
      order_by: [asc: p.priority]
    )
    |> Repo.all()
    |> Enum.map(&provider_to_config/1)
  end

  @doc """
  List all providers for admin interface.
  """
  def list_all_providers do
    from(p in GeocodingProvider, order_by: [asc: p.priority])
    |> Repo.all()
  end

  @doc """
  Toggle provider enabled/disabled.
  """
  def toggle_enabled(provider_id) do
    provider = Repo.get!(GeocodingProvider, provider_id)

    provider
    |> GeocodingProvider.changeset(%{enabled: !provider.enabled})
    |> Repo.update()
  end

  @doc """
  Bulk reorder providers after drag-and-drop.
  Priority map: %{provider_id => new_priority}
  """
  def reorder_providers(priority_map) when is_map(priority_map) do
    Repo.transaction(fn ->
      Enum.each(priority_map, fn {provider_id, new_priority} ->
        from(p in GeocodingProvider, where: p.id == ^provider_id)
        |> Repo.update_all(set: [priority: new_priority])
      end)
    end)
  end

  # Private

  defp provider_to_config(provider) do
    module = name_to_module(provider.name)
    {module, [enabled: true, priority: provider.priority]}
  end

  defp name_to_module(name) do
    module_name =
      name
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    Module.concat([EventasaurusDiscovery.Geocoding.Providers, module_name])
  end
end
```

---

## Admin LiveView

```elixir
# lib/eventasaurus_web/live/admin/geocoding_provider_live.ex
defmodule EventasaurusWeb.Admin.GeocodingProviderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Geocoding Providers")
      |> load_providers()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    case ProviderConfig.toggle_enabled(id) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider updated")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update provider")}
    end
  end

  @impl true
  def handle_event("reorder", %{"order" => order}, socket) do
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

  defp load_providers(socket) do
    providers = ProviderConfig.list_all_providers()
    assign(socket, :providers, providers)
  end

  # Display name helper
  @display_names %{
    "here" => "HERE",
    "openstreetmap" => "OpenStreetMap",
    "locationiq" => "LocationIQ",
    "geoapify" => "Geoapify"
  }

  defp display_name(name) do
    Map.get(@display_names, name, String.capitalize(name))
  end
end
```

---

## UI Template

```heex
<div class="px-4 sm:px-6 lg:px-8">
  <div class="sm:flex sm:items-center">
    <div class="sm:flex-auto">
      <h1 class="text-2xl font-semibold text-gray-900">Geocoding Providers</h1>
      <p class="mt-2 text-sm text-gray-700">
        Manage provider priority and availability
      </p>
    </div>
  </div>

  <div class="mt-8">
    <ul
      id="provider-list"
      phx-hook="Sortable"
      data-sortable-handle=".drag-handle"
      class="space-y-2"
    >
      <%= for provider <- @providers do %>
        <li
          id={"provider-#{provider.id}"}
          data-id={provider.id}
          class="bg-white shadow rounded-lg px-4 py-4 flex items-center justify-between hover:bg-gray-50"
        >
          <div class="flex items-center flex-1">
            <!-- Drag Handle -->
            <button class="drag-handle cursor-move mr-4 text-gray-400 hover:text-gray-600">
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </button>

            <!-- Provider Info -->
            <div class="flex-1">
              <div class="flex items-center">
                <h3 class="text-lg font-medium text-gray-900">
                  <%= display_name(provider.name) %>
                </h3>
                <span class="ml-3 text-sm text-gray-500">
                  Priority: <%= provider.priority %>
                </span>
              </div>
            </div>
          </div>

          <!-- Actions -->
          <button
            type="button"
            phx-click="toggle_enabled"
            phx-value-id={provider.id}
            class={"px-4 py-2 text-sm font-medium rounded-md #{if provider.enabled, do: "bg-green-100 text-green-800 hover:bg-green-200", else: "bg-gray-100 text-gray-800 hover:bg-gray-200"}"}
          >
            <%= if provider.enabled, do: "Enabled", else: "Disabled" %>
          </button>
        </li>
      <% end %>
    </ul>
  </div>

  <div class="mt-4 bg-blue-50 border border-blue-200 rounded-md p-4">
    <p class="text-sm text-blue-700">
      💡 Drag providers to change priority order. Lower priority numbers are tried first.
    </p>
  </div>
</div>
```

---

## JavaScript Hook (SortableJS)

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
      onEnd: function(evt) {
        const order = Array.from(evt.to.children).map(el => el.dataset.id);
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

Install SortableJS:
```bash
npm install sortablejs
```

Register hook in `app.js`:
```javascript
import { SortableHook } from "./hooks/sortable"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: { Sortable: SortableHook }
})
```

---

## Integration with Geocoding System

Update `MultiProvider` to read from database:

```elixir
defmodule EventasaurusDiscovery.Geocoding.MultiProvider do
  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  def geocode(address, city) do
    # Get providers from database instead of config
    providers = ProviderConfig.list_active_providers()

    # Rest of implementation unchanged
    try_providers(providers, address, city)
  end

  # ... rest of implementation
end
```

---

## Testing

### Unit Tests

```elixir
defmodule EventasaurusDiscovery.Geocoding.ProviderConfigTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Geocoding.ProviderConfig
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

  describe "list_active_providers/0" do
    test "returns only enabled providers in priority order" do
      insert(:geocoding_provider, name: "test1", priority: 2, enabled: true)
      insert(:geocoding_provider, name: "test2", priority: 1, enabled: true)
      insert(:geocoding_provider, name: "test3", priority: 3, enabled: false)

      providers = ProviderConfig.list_active_providers()

      assert length(providers) == 2
      assert Enum.at(providers, 0) |> elem(1) |> Keyword.get(:priority) == 1
    end
  end

  describe "toggle_enabled/1" do
    test "toggles provider enabled status" do
      provider = insert(:geocoding_provider, enabled: true)

      {:ok, updated} = ProviderConfig.toggle_enabled(provider.id)

      assert updated.enabled == false
    end
  end

  describe "reorder_providers/1" do
    test "updates priorities correctly" do
      p1 = insert(:geocoding_provider, priority: 1)
      p2 = insert(:geocoding_provider, priority: 2)

      {:ok, _} = ProviderConfig.reorder_providers(%{
        p1.id => 2,
        p2.id => 1
      })

      assert Repo.get!(GeocodingProvider, p1.id).priority == 2
      assert Repo.get!(GeocodingProvider, p2.id).priority == 1
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
    insert(:geocoding_provider, name: "mapbox", priority: 1)

    {:ok, _view, html} = live(conn, ~p"/admin/geocoding/providers")

    assert html =~ "Mapbox"
  end

  test "toggles provider enabled status", %{conn: conn} do
    provider = insert(:geocoding_provider, enabled: true)

    {:ok, view, _html} = live(conn, ~p"/admin/geocoding/providers")

    view
    |> element("button[phx-value-id='#{provider.id}']")
    |> render_click()

    assert Repo.get!(GeocodingProvider, provider.id).enabled == false
  end

  test "reorders providers via drag-and-drop", %{conn: conn} do
    p1 = insert(:geocoding_provider, priority: 1)
    p2 = insert(:geocoding_provider, priority: 2)

    {:ok, view, _html} = live(conn, ~p"/admin/geocoding/providers")

    render_hook(view, "reorder", %{order: [p2.id, p1.id]})

    assert Repo.get!(GeocodingProvider, p1.id).priority == 2
    assert Repo.get!(GeocodingProvider, p2.id).priority == 1
  end
end
```

---

## What's NOT in MVP

### Future Enhancements (Phase 2+)

**Provider Metadata Display**
- Show cost, rate limits, descriptions in UI
- Read from provider module's `metadata/0` function
- No database changes needed

**Performance Metrics**
- Integrate with existing `GeocodingStats` module
- Display success rates, call counts, response times
- Query from existing logs, no new tables

**Pause/Resume**
- Not needed - `enabled=false` achieves the same goal
- If really needed, add `paused` boolean later

**Cost Tracking**
- Real-time cost calculations
- Budget alerts and limits
- Separate feature, separate PR

**Automatic Failover**
- Auto-disable providers with low success rates
- Configurable thresholds
- Separate feature, requires metrics first

**A/B Testing**
- Test different provider orders simultaneously
- Split traffic between configurations
- Advanced feature for later

**Geographic Routing**
- Different provider priorities per region
- Query-based routing logic
- Complex feature, future consideration

---

## Implementation Timeline

**Week 1**
- Day 1: Migration + schema + seed data
- Day 2: Context module with 4 functions
- Day 3-4: LiveView interface
- Day 5: Drag-and-drop integration

**Week 2**
- Day 6: Unit tests
- Day 7: Integration tests
- Day 8: Integration with geocoding system
- Day 9: Manual testing + bug fixes
- Day 10: Deploy to staging + production

**Total: 1-2 weeks**

---

## Success Metrics

After MVP deployment:

1. **Functionality**: Can reorder providers without code changes ✓
2. **Usage**: Admin changes configuration at least once per month
3. **Reliability**: No geocoding failures due to config changes
4. **Performance**: Provider query time <1ms (8 rows, no joins)
5. **Maintainability**: New providers can be added via admin UI

---

## Appendix: Why This Approach?

### Simplicity Wins
- 3 fields vs 12+ fields in original design
- No premature optimization (caching, denormalization)
- YAGNI principle applied rigorously

### Database for Configuration, Code for Metadata
- **Database**: Things that change at runtime (priority, enabled)
- **Code**: Things that change with deployments (costs, limits, descriptions)

### Easy to Extend
- Want metadata display? Read from provider modules
- Want performance metrics? Query existing logs
- Want caching? Add later when needed (it won't be)

### Low Risk
- Minimal schema changes
- Easy to rollback
- Incremental deployment possible
