defmodule EventasaurusWeb.Admin.SourceFormLive do
  @moduledoc """
  Admin form for creating and editing event sources.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Services.UploadService
  alias EventasaurusDiscovery.Sources.Source

  require Logger

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
      |> assign(:logo_url, source.logo_url)
      # Use standard server-side upload (same as working group uploads)
      |> allow_upload(:logo,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 5_000_000
      )

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
    # Check if there's a new upload
    {completed, _in_progress} = Phoenix.LiveView.uploaded_entries(socket, :logo)

    # Handle logo upload using same approach as working group uploads
    logo_url =
      cond do
        # New upload - use UploadService (same as groups)
        length(completed) > 0 ->
          source_id = socket.assigns.source.id || "new"
          # access_token not needed for R2, just pass nil
          results = UploadService.upload_liveview_files(
            socket,
            :logo,
            "sources",
            "source_#{source_id}",
            nil
          )

          case results do
            [{:ok, url} | _] -> url
            _ -> socket.assigns.logo_url
          end

        # Logo was removed
        is_nil(socket.assigns.logo_url) ->
          nil

        # Keep existing logo
        true ->
          socket.assigns.logo_url
      end

    updated_params =
      params
      |> normalize_params()
      |> maybe_put_url(:logo_url, logo_url)

    save_source(socket, socket.assigns.source.id, updated_params)
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  @impl true
  def handle_event("remove_logo", _params, socket) do
    changeset =
      socket.assigns.source
      |> Source.changeset(%{"logo_url" => nil})
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:logo_url, nil)
     |> assign(:form, to_form(changeset))}
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
    |> normalize_aggregation()
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

  defp normalize_aggregation(params) do
    # Set aggregate_on_index based on whether aggregation_type has a value
    aggregation_type = params["aggregation_type"]
    has_aggregation = aggregation_type && aggregation_type != ""

    Map.put(params, "aggregate_on_index", has_aggregation)
  end

  defp maybe_put_url(params, _key, nil), do: params

  defp maybe_put_url(params, key, url) when is_binary(url) do
    Map.put(params, Atom.to_string(key), url)
  end
end
