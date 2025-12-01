defmodule EventasaurusWeb.Admin.SourceFormLive do
  @moduledoc """
  Admin form for creating and editing event sources.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Services.R2Client
  alias EventasaurusDiscovery.Sources.Source

  # Use the unified Uploads module which respects UPLOADS_STRATEGY env var
  import EventasaurusWeb.Uploads, only: [image_upload_config: 0, get_uploaded_url: 2]

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
      |> assign(:upload_folder, "sources")
      # Use unified upload config - respects UPLOADS_STRATEGY env var
      # Set UPLOADS_STRATEGY=local for local storage, or leave unset for R2 in production
      |> allow_upload(:logo, image_upload_config())

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
    # Get uploaded URL using unified Uploads module
    # This respects UPLOADS_STRATEGY env var (local vs r2)
    uploaded_url = get_uploaded_url(socket, :logo)
    old_logo_url = socket.assigns.source.logo_url

    # Delete old image from R2 if new one is uploaded
    maybe_delete_old_image(uploaded_url, old_logo_url)

    # Determine final logo URL
    logo_url =
      cond do
        # New upload completed
        uploaded_url != nil -> uploaded_url
        # Logo was removed
        is_nil(socket.assigns.logo_url) -> nil
        # Keep existing logo
        true -> socket.assigns.logo_url
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

  # Delete old image from R2 when a new one is uploaded
  # Only deletes R2 images (relative paths like "sources/logo.jpg")
  # Does NOT delete external URLs or nil values
  defp maybe_delete_old_image(new_url, old_url)
       when is_binary(new_url) and is_binary(old_url) do
    # Only delete if it's a relative path (R2 image), not an external URL
    if is_r2_path?(old_url) do
      # Fire and forget - don't block on deletion result
      Task.start(fn ->
        case R2Client.delete(old_url) do
          :ok ->
            require Logger
            Logger.info("Deleted old image from R2: #{old_url}")

          {:error, reason} ->
            require Logger

            Logger.warning(
              "Failed to delete old image from R2: #{old_url}, reason: #{inspect(reason)}"
            )
        end
      end)
    end
  end

  defp maybe_delete_old_image(_new_url, _old_url), do: :ok

  # Check if a URL is an R2 path (relative path or full CDN URL)
  # Handles both relative paths (sources/logo.jpg) and CDN URLs (https://cdn2.wombie.com/sources/logo.jpg)
  defp is_r2_path?(url) when is_binary(url) do
    cdn_url = Application.get_env(:eventasaurus, :r2)[:cdn_url] || "https://cdn2.wombie.com"

    String.starts_with?(url, cdn_url) or
      (not String.starts_with?(url, "http://") and
         not String.starts_with?(url, "https://") and
         not String.starts_with?(url, "/"))
  end

  defp is_r2_path?(_), do: false
end
