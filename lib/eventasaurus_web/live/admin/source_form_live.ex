defmodule EventasaurusWeb.Admin.SourceFormLive do
  @moduledoc """
  Admin form for creating and editing event sources.
  """
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.TokenHelpers, only: [get_current_valid_token: 1]

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Services.UploadService
  alias EventasaurusDiscovery.Sources.Source

  @impl true
  def mount(params, session, socket) do
    source =
      case params["id"] do
        nil -> %Source{}
        id -> Repo.get!(Source, id)
      end

    changeset = Source.changeset(source, %{})

    # Get the Supabase access token from session
    access_token = get_current_valid_token(session)

    # Log warning if token is missing
    if is_nil(access_token) do
      require Logger
      Logger.warning("Supabase access token is nil. Image uploads will not work.")
    end

    socket =
      socket
      |> assign(:page_title, if(source.id, do: "Edit Source", else: "New Source"))
      |> assign(:source, source)
      |> assign(:form, to_form(changeset))
      |> assign(:allowed_domains, Source.allowed_domains())
      |> assign(:logo_url, source.logo_url)
      |> assign(:supabase_access_token, access_token || "")
      |> allow_upload(:logo, accept: ~w(.jpg .jpeg .png .gif .webp), max_entries: 1)

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
    access_token = socket.assigns.supabase_access_token

    # Handle logo upload first
    case handle_logo_upload(socket, access_token) do
      {:ok, logo_url} ->
        # Add uploaded URL to params
        updated_params =
          params
          |> normalize_params()
          |> maybe_put_removed_logo(socket)
          |> maybe_put_url(:logo_url, logo_url || socket.assigns.logo_url)

        save_source(socket, socket.assigns.source.id, updated_params)

      {:error, :no_token} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Unable to upload logo: You must be logged in to upload images. Please refresh the page and try again."
         )
         |> assign(:form, to_form(Source.changeset(socket.assigns.source, params)))}

      {:error, %{message: "Bucket not found"}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Storage bucket not configured. Please contact an administrator to set up R2 Storage."
         )
         |> assign(:form, to_form(Source.changeset(socket.assigns.source, params)))}

      {:error, error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to upload logo: #{inspect(error)}")
         |> assign(:form, to_form(Source.changeset(socket.assigns.source, params)))}
    end
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

  defp maybe_put_removed_logo(params, socket) do
    # If logo_url was removed (assign is nil but source has a value), set it to nil in params
    if is_nil(socket.assigns.logo_url) and not is_nil(socket.assigns.source.logo_url) do
      Map.put(params, "logo_url", nil)
    else
      params
    end
  end

  # Upload handling functions

  defp handle_logo_upload(socket, access_token) do
    case uploaded_entries(socket, :logo) do
      {[_ | _], []} ->
        # Check if we have a valid access token
        if is_nil(access_token) or access_token == "" do
          {:error, :no_token}
        else
          slug = socket.assigns.source.slug || "new"

          results =
            UploadService.upload_liveview_files(
              socket,
              :logo,
              "sources",
              "source_#{slug}_logo",
              access_token
            )

          case results do
            {:ok, [url]} -> {:ok, url}
            {:ok, []} -> {:ok, nil}
            {:error, error} -> {:error, error}
            [error: error] -> {:error, error}
            other -> {:error, "Upload failed: #{inspect(other)}"}
          end
        end

      {[], []} ->
        {:ok, nil}

      {[], errors} ->
        error_msg = Enum.map_join(errors, ", ", & &1.ref)
        {:error, "Logo upload errors: #{error_msg}"}
    end
  end

  defp maybe_put_url(params, _key, nil), do: params

  defp maybe_put_url(params, key, url) when is_binary(url) do
    Map.put(params, Atom.to_string(key), url)
  end
end
