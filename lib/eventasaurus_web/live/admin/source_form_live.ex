defmodule EventasaurusWeb.Admin.SourceFormLive do
  @moduledoc """
  Admin form for creating and editing event sources.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source

  @impl true
  def mount(params, _session, socket) do
    source =
      case params["id"] do
        nil -> %Source{}
        id -> Repo.get!(Source, id)
      end

    changeset = Source.changeset(source, %{})

    socket =
      socket
      |> assign(:page_title, if(source.id, do: "Edit Source", else: "New Source"))
      |> assign(:source, source)
      |> assign(:form, to_form(changeset))
      |> assign(:allowed_domains, Source.allowed_domains())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"source" => params}, socket) do
    params = normalize_params(params)

    changeset =
      socket.assigns.source
      |> Source.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"source" => params}, socket) do
    params = normalize_params(params)
    save_source(socket, socket.assigns.source.id, params)
  end

  defp save_source(socket, nil, params) do
    case Repo.insert(Source.changeset(%Source{}, params)) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source created successfully")
         |> push_navigate(to: ~p"/admin/sources")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_source(socket, _id, params) do
    case Repo.update(Source.changeset(socket.assigns.source, params)) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source updated successfully")
         |> push_navigate(to: ~p"/admin/sources")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp normalize_params(params) do
    params
    |> normalize_domains()
    |> normalize_priority()
  end

  defp normalize_domains(params) do
    case params["domains"] do
      domains when is_binary(domains) ->
        # Split comma-separated string into array (for backwards compatibility)
        domains_list =
          domains
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "domains", domains_list)

      domains when is_list(domains) ->
        # Already a list from multi-select, just ensure it's cleaned
        domains_list =
          domains
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "domains", domains_list)

      _ ->
        params
    end
  end

  defp normalize_priority(params) do
    case params["priority"] do
      priority when is_binary(priority) ->
        case Integer.parse(priority) do
          {int, ""} -> Map.put(params, "priority", int)
          _ -> params
        end

      _ ->
        params
    end
  end
end
