defmodule EventasaurusWeb.Admin.CategoryFormLive do
  @moduledoc """
  Admin form for creating and editing categories.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.Categories.Category

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:action, socket.assigns.live_action)
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
  def handle_event("generate_slug", %{"name" => name}, socket) do
    slug = generate_slug_from_name(name)

    # Update the changeset with the generated slug
    category_params = %{
      "slug" => slug,
      "name" => name
    }

    changeset =
      socket.assigns.category
      |> Categories.change_category(category_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  defp save_category(socket, :new, category_params) do
    case Categories.create_category(category_params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created successfully")
         |> push_navigate(to: ~p"/admin/categories")}

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
         |> push_navigate(to: ~p"/admin/categories")}

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
