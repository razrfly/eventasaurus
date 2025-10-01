defmodule EventasaurusWeb.Admin.CategoryIndexLive do
  @moduledoc """
  Admin interface for managing event categories.
  Lists all categories with their metadata and usage statistics.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Categories

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Category Management")
      |> assign(:search_query, "")
      |> assign(:show_inactive, true)
      |> load_categories()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search_query, query) |> load_categories()}
  end

  @impl true
  def handle_event("toggle_inactive", _params, socket) do
    {:noreply, assign(socket, :show_inactive, !socket.assigns.show_inactive) |> load_categories()}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    category = Categories.get_category!(id, active_only: false)

    case Categories.update_category(category, %{is_active: !category.is_active}) do
      {:ok, _category} ->
        {:noreply,
          socket
          |> put_flash(:info, "Category #{if category.is_active, do: "deactivated", else: "activated"} successfully")
          |> load_categories()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update category")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Categories.get_category!(id, active_only: false)

    case Categories.delete_category(category) do
      {:ok, _category} ->
        {:noreply,
          socket
          |> put_flash(:info, "Category deleted successfully")
          |> load_categories()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete category. It may be in use by events.")}
    end
  end

  defp load_categories(socket) do
    categories = Categories.list_categories_with_counts(
      active_only: false,
      locale: "en"
    )

    # Apply search filter
    categories =
      if socket.assigns.search_query != "" do
        query = String.downcase(socket.assigns.search_query)
        Enum.filter(categories, fn cat ->
          String.contains?(String.downcase(cat.name), query) ||
          String.contains?(String.downcase(cat.slug), query)
        end)
      else
        categories
      end

    # Apply inactive filter
    categories =
      if socket.assigns.show_inactive do
        categories
      else
        Enum.filter(categories, & &1.is_active)
      end

    assign(socket, :categories, categories)
  end
end
