defmodule EventasaurusWeb.Admin.CategoryFormLive do
  @moduledoc """
  Admin form for creating and editing categories.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.Categories.Category

  @impl true
  def mount(params, _session, socket) do
    # Set index path based on environment
    index_path = if Mix.env() == :dev, do: ~p"/dev/categories", else: ~p"/admin/categories"

    socket =
      socket
      |> assign(:action, socket.assigns.live_action)
      |> assign(:index_path, index_path)
      |> load_form(params)
      |> assign(:parent_categories, list_parent_categories())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"category" => category_params}, socket) do
    changeset =
      socket.assigns.category
      |> Categories.change_category(category_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.action, category_params)
  end

  @impl true
  def handle_event("generate_slug", %{"value" => name}, socket) when is_binary(name) do
    slug = generate_slug_from_name(name)

    # Get current form params and update slug
    current_params = socket.assigns.form.params
    updated_params = Map.put(current_params, "slug", slug)

    changeset =
      socket.assigns.category
      |> Categories.change_category(updated_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("generate_slug", _params, socket) do
    # Ignore if value is not a string
    {:noreply, socket}
  end

  defp save_category(socket, :new, category_params) do
    case Categories.create_category(category_params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created successfully")
         |> push_navigate(to: socket.assigns.index_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_category(socket, :edit, category_params) do
    case Categories.update_category(socket.assigns.category, category_params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated successfully")
         |> push_navigate(to: socket.assigns.index_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp load_form(socket, %{"id" => id}) do
    category = Categories.get_category!(id, active_only: false)
    changeset = Categories.change_category(category)

    socket
    |> assign(:page_title, "Edit Category")
    |> assign(:category, category)
    |> assign(:form, to_form(changeset))
  end

  defp load_form(socket, _params) do
    category = %Category{}
    changeset = Categories.change_category(category)

    socket
    |> assign(:page_title, "New Category")
    |> assign(:category, category)
    |> assign(:form, to_form(changeset))
  end

  defp list_parent_categories do
    Categories.list_categories(active_only: false, locale: "en")
    |> Enum.map(&{&1.name, &1.id})
  end

  defp generate_slug_from_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
