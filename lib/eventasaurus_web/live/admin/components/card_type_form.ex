defmodule EventasaurusWeb.Admin.Components.CardTypeForm do
  @moduledoc """
  Reusable form component for editing mock data based on card type behaviour.

  Dynamically renders form fields based on the card type's `form_fields/0` callback.
  This eliminates the need for per-card-type form templates in the main LiveView.
  """

  use Phoenix.Component

  alias EventasaurusWeb.Admin.CardTypeRegistry

  @doc """
  Renders an edit form based on the card type's field definitions.

  ## Attributes

    * `:card_type` - The atom card type (e.g., :movie, :venue)
    * `:mock_data` - The current mock data map
    * `:card_type_config` - The CardTypeConfig for this card type
  """
  attr :card_type, :atom, required: true
  attr :mock_data, :map, required: true
  attr :card_type_config, :map, required: true

  def edit_form(assigns) do
    fields = CardTypeRegistry.form_fields(assigns.card_type)
    form_param_key = CardTypeRegistry.form_param_key(assigns.card_type)
    update_event = CardTypeRegistry.update_event_name(assigns.card_type)

    assigns =
      assigns
      |> assign(:fields, fields)
      |> assign(:form_param_key, form_param_key)
      |> assign(:update_event, update_event)

    ~H"""
    <form phx-change={@update_event} class="space-y-3">
      <.render_fields fields={@fields} mock_data={@mock_data} form_param_key={@form_param_key} />
    </form>
    """
  end

  @doc """
  Renders a read-only display of mock data based on card type.

  ## Attributes

    * `:card_type` - The atom card type
    * `:mock_data` - The current mock data map
    * `:card_type_config` - The CardTypeConfig for this card type
  """
  attr :card_type, :atom, required: true
  attr :mock_data, :map, required: true
  attr :card_type_config, :map, required: true

  def display(assigns) do
    fields = CardTypeRegistry.form_fields(assigns.card_type)

    assigns = assign(assigns, :fields, fields)

    ~H"""
    <div class="mt-2 text-sm text-blue-700">
      <%= for field <- @fields do %>
        <p class="font-mono">
          <strong><%= field.label %>:</strong> <%= get_display_value(@mock_data, field) %>
        </p>
      <% end %>
      <%= if @card_type_config.supports_themes? do %>
        <p class="text-xs text-blue-600 mt-1">
          <%= if @card_type == :poll do %>
            Poll cards inherit the style from their parent event. Click "Edit Data" to customize.
          <% else %>
            Event cards use the selected style. Click "Edit Data" to customize.
          <% end %>
        </p>
      <% else %>
        <p class="text-xs text-blue-600 mt-1">
          <%= @card_type_config.label %> cards use the <%= @card_type_config.style_name %> brand style. Click "Edit Data" to customize.
        </p>
      <% end %>
    </div>
    """
  end

  # Private helpers

  defp render_fields(assigns) do
    ~H"""
    <%= for field <- @fields do %>
      <.render_field field={field} mock_data={@mock_data} form_param_key={@form_param_key} />
    <% end %>
    """
  end

  defp render_field(%{field: %{type: :select} = field} = assigns) do
    value = get_value(assigns.mock_data, field.path)
    assigns = assign(assigns, :value, value)

    ~H"""
    <div>
      <label class="block text-xs font-medium text-blue-700"><%= @field.label %></label>
      <select
        name={"#{@form_param_key}[#{@field.name}]"}
        class="mt-1 block w-full px-2 py-1 text-sm border border-blue-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
      >
        <%= for {val, label} <- @field.options do %>
          <option value={val} selected={@value == val}><%= label %></option>
        <% end %>
      </select>
    </div>
    """
  end

  defp render_field(%{field: %{type: :number} = field} = assigns) do
    value = get_value(assigns.mock_data, field.path)
    assigns = assign(assigns, :value, value)

    ~H"""
    <div>
      <label class="block text-xs font-medium text-blue-700"><%= @field.label %></label>
      <input
        type="number"
        name={"#{@form_param_key}[#{@field.name}]"}
        value={@value}
        min={Map.get(@field, :min)}
        max={Map.get(@field, :max)}
        step={Map.get(@field, :step)}
        class="mt-1 block w-full px-2 py-1 text-sm border border-blue-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
      />
    </div>
    """
  end

  defp render_field(%{field: %{type: :textarea} = field} = assigns) do
    value = get_value(assigns.mock_data, field.path)
    assigns = assign(assigns, :value, value)

    ~H"""
    <div>
      <label class="block text-xs font-medium text-blue-700"><%= @field.label %></label>
      <textarea
        name={"#{@form_param_key}[#{@field.name}]"}
        rows="3"
        class="mt-1 block w-full px-2 py-1 text-sm border border-blue-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
      ><%= @value %></textarea>
      <%= if hint = Map.get(@field, :hint) do %>
        <p class="text-xs text-blue-500 mt-1"><%= hint %></p>
      <% end %>
    </div>
    """
  end

  defp render_field(%{field: field} = assigns) do
    # Default to text input
    value = get_value(assigns.mock_data, field.path)
    assigns = assign(assigns, :value, value)

    ~H"""
    <div>
      <label class="block text-xs font-medium text-blue-700"><%= @field.label %></label>
      <input
        type="text"
        name={"#{@form_param_key}[#{@field.name}]"}
        value={@value}
        class="mt-1 block w-full px-2 py-1 text-sm border border-blue-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
      />
      <%= if hint = Map.get(@field, :hint) do %>
        <p class="text-xs text-blue-500 mt-1"><%= hint %></p>
      <% end %>
    </div>
    """
  end

  # Get value from nested map using path
  defp get_value(data, path) when is_list(path) do
    get_in(data, Enum.map(path, &to_access_key/1))
  end

  defp get_value(data, key) when is_atom(key) do
    Map.get(data, key)
  end

  # Convert keys to proper access format.
  # All paths from card type modules use atom keys, so String.to_existing_atom is safe.
  # Fallback to String.to_atom for defensive handling of edge cases.
  defp to_access_key(key) when is_atom(key), do: key

  defp to_access_key(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> String.to_atom(key)
    end
  end

  # Get display value for read-only display
  defp get_display_value(data, %{path: path, type: :select, options: options}) do
    value = get_value(data, path)

    case Enum.find(options, fn {val, _label} -> val == value end) do
      {_val, label} -> label
      nil -> value || "N/A"
    end
  end

  defp get_display_value(data, %{path: [:release_date, :year]} = _field) do
    case get_in(data, [:release_date]) do
      %Date{year: year} -> year
      nil -> "N/A"
    end
  end

  defp get_display_value(data, %{path: [:metadata, :vote_average]} = _field) do
    case get_in(data, [:metadata, :vote_average]) do
      nil -> "N/A"
      rating -> "★ #{rating}"
    end
  end

  defp get_display_value(data, %{path: path, name: :runtime}) do
    case get_value(data, path) do
      nil -> "N/A"
      runtime -> "#{runtime} min"
    end
  end

  defp get_display_value(data, %{path: path}) do
    case get_value(data, path) do
      nil -> "N/A"
      value -> value
    end
  end
end
