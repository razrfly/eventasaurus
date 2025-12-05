defmodule EventasaurusWeb.Admin.SourceIndexLive do
  @moduledoc """
  Admin interface for managing event sources.
  Lists all sources with their configuration and status.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Source Management")
      |> assign(:search_query, "")
      |> assign(:show_inactive, true)
      |> load_sources()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search_query, query) |> load_sources()}
  end

  @impl true
  def handle_event("toggle_inactive", _params, socket) do
    {:noreply, assign(socket, :show_inactive, !socket.assigns.show_inactive) |> load_sources()}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    source = Repo.get!(Source, id)

    case Repo.update(Source.changeset(source, %{is_active: !source.is_active})) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Source #{if source.is_active, do: "deactivated", else: "activated"} successfully"
         )
         |> load_sources()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update source")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    source = Repo.get!(Source, id)

    case Repo.delete(source) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source deleted successfully")
         |> load_sources()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to delete source. It may be in use by events.")}
    end
  end

  defp load_sources(socket) do
    query = from(s in Source, order_by: [desc: s.priority, asc: s.name])

    sources = Repo.replica().all(query)

    # Apply search filter
    sources =
      if socket.assigns.search_query != "" do
        query = String.downcase(socket.assigns.search_query)

        Enum.filter(sources, fn source ->
          String.contains?(String.downcase(source.name), query) ||
            String.contains?(String.downcase(source.slug), query)
        end)
      else
        sources
      end

    # Apply inactive filter
    sources =
      if socket.assigns.show_inactive do
        sources
      else
        Enum.filter(sources, & &1.is_active)
      end

    assign(socket, :sources, sources)
  end
end
