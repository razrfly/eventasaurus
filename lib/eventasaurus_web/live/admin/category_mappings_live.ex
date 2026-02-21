defmodule EventasaurusWeb.Admin.CategoryMappingsLive do
  @moduledoc """
  Admin interface for managing category mappings.
  Provides CRUD operations for source-to-category mappings with filtering and search.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Categories.CategoryMappings
  alias EventasaurusDiscovery.Categories.CategoryMapping

  @impl true
  def mount(_params, _session, socket) do
    stats = CategoryMappings.get_stats()
    sources = CategoryMappings.list_sources()

    socket =
      socket
      |> assign(:page_title, "Category Mappings")
      |> assign(:stats, stats)
      |> assign(:sources, sources)
      |> assign(:selected_source, nil)
      |> assign(:search_query, "")
      |> assign(:mapping_type_filter, nil)
      |> assign(:show_inactive, true)
      |> assign(:editing_mapping, nil)
      |> assign(:changeset, nil)
      |> load_mappings()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_source = params["source"]

    socket =
      socket
      |> assign(:selected_source, selected_source)
      |> load_mappings()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_source", %{"source" => source}, socket) do
    source = if source == "", do: nil, else: source
    {:noreply, push_patch(socket, to: ~p"/admin/categories/mappings?#{%{source: source}}")}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    type = if type == "", do: nil, else: type

    {:noreply,
     socket
     |> assign(:mapping_type_filter, type)
     |> load_mappings()}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> load_mappings()}
  end

  @impl true
  def handle_event("toggle_inactive", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_inactive, !socket.assigns.show_inactive)
     |> load_mappings()}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    mapping = CategoryMappings.get_mapping!(id)
    changeset = CategoryMappings.change_mapping(mapping)

    {:noreply,
     socket
     |> assign(:editing_mapping, mapping)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_mapping, nil)
     |> assign(:changeset, nil)}
  end

  @impl true
  def handle_event("save", %{"category_mapping" => mapping_params}, socket) do
    mapping = socket.assigns.editing_mapping

    case CategoryMappings.update_mapping(mapping, mapping_params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Mapping updated successfully")
         |> assign(:editing_mapping, nil)
         |> assign(:changeset, nil)
         |> assign(:stats, CategoryMappings.get_stats())
         |> load_mappings()}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    mapping = CategoryMappings.get_mapping!(id)

    result =
      if mapping.is_active do
        CategoryMappings.deactivate_mapping(mapping)
      else
        CategoryMappings.activate_mapping(mapping)
      end

    case result do
      {:ok, _mapping} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Mapping #{if mapping.is_active, do: "deactivated", else: "activated"}"
         )
         |> assign(:stats, CategoryMappings.get_stats())
         |> load_mappings()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update mapping")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    mapping = CategoryMappings.get_mapping!(id)

    case CategoryMappings.delete_mapping(mapping) do
      {:ok, _mapping} ->
        {:noreply,
         socket
         |> put_flash(:info, "Mapping deleted")
         |> assign(:stats, CategoryMappings.get_stats())
         |> load_mappings()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete mapping")}
    end
  end

  @impl true
  def handle_event("refresh_cache", _params, socket) do
    count = CategoryMappings.refresh_cache()

    {:noreply,
     socket
     |> put_flash(:info, "Cache refreshed with #{count} mappings")
     |> assign(:stats, CategoryMappings.get_stats())}
  end

  @impl true
  def handle_event("new_mapping", _params, socket) do
    changeset = CategoryMappings.change_mapping(%CategoryMapping{})

    {:noreply,
     socket
     |> assign(:editing_mapping, %CategoryMapping{})
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("create", %{"category_mapping" => mapping_params}, socket) do
    case CategoryMappings.create_mapping(mapping_params) do
      {:ok, _mapping} ->
        {:noreply,
         socket
         |> put_flash(:info, "Mapping created successfully")
         |> assign(:editing_mapping, nil)
         |> assign(:changeset, nil)
         |> assign(:stats, CategoryMappings.get_stats())
         |> assign(:sources, CategoryMappings.list_sources())
         |> load_mappings()}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp load_mappings(socket) do
    mappings =
      cond do
        socket.assigns.selected_source ->
          CategoryMappings.list_mappings_by_source(socket.assigns.selected_source)

        true ->
          CategoryMappings.list_mappings()
      end

    # Apply type filter
    mappings =
      case socket.assigns.mapping_type_filter do
        nil -> mappings
        type -> Enum.filter(mappings, &(&1.mapping_type == type))
      end

    # Apply search filter
    mappings =
      if socket.assigns.search_query != "" do
        query = String.downcase(socket.assigns.search_query)

        Enum.filter(mappings, fn m ->
          String.contains?(String.downcase(m.external_term), query) ||
            String.contains?(String.downcase(m.category_slug), query)
        end)
      else
        mappings
      end

    # Apply inactive filter
    mappings =
      if socket.assigns.show_inactive do
        mappings
      else
        Enum.filter(mappings, & &1.is_active)
      end

    assign(socket, :mappings, mappings)
  end
end
