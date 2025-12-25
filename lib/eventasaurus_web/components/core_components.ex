defmodule EventasaurusWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Phoenix.LiveView.JS

  # Alias for currency helpers
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  @doc """
  Renders a component that wraps an element to provide focus management.

  ## Examples

      <.focus_wrap id="my-modal">
        <div>Content</div>
      </.focus_wrap>
  """
  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def focus_wrap(assigns) do
    ~H"""
    <div id={@id} class={@class} {@rest}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

      <.modal id="confirm" on_confirm={JS.push("delete")} on_cancel={JS.patch(~p"/posts")}>
        This is a modal.
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, :any, default: nil
  attr :on_confirm, :any, default: nil
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true
  slot :title
  slot :confirm
  slot :cancel

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      class={if @show, do: "relative z-50", else: "relative z-50 hidden"}
      style={if @show, do: "display: block;", else: "display: none;"}
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div class="fixed inset-0 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-2 sm:p-4">
          <div class="w-full max-w-sm sm:max-w-md md:max-w-lg lg:max-w-2xl xl:max-w-3xl">
            <div
              id={"#{@id}-container"}
              phx-window-keydown={@on_cancel}
              phx-key="escape"
              phx-click-away={@on_cancel}
              class={[
                "shadow-zinc-700/10 ring-zinc-700/10 relative rounded-xl sm:rounded-2xl bg-white p-4 sm:p-6 lg:p-8 shadow-lg ring-1 transition",
                if(@show, do: "block", else: "hidden")
              ]}
            >
              <div class="absolute top-4 right-4 sm:top-6 sm:right-6">
                <button
                  phx-click={@on_cancel}
                  type="button"
                  class="-m-2 sm:-m-3 flex-none p-2 sm:p-3 opacity-40 hover:opacity-60 transition-opacity"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5 text-zinc-500" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <header :if={@title != []}>
                  <h1 class="text-lg sm:text-xl font-semibold leading-6 sm:leading-8 text-zinc-800 pr-8">
                    <%= render_slot(@title) %>
                  </h1>
                </header>
                <%= render_slot(@inner_block) %>
                <div :if={@confirm != [] or @cancel != []} class="mt-6 flex flex-col-reverse sm:flex-row sm:items-center sm:justify-between gap-3 sm:gap-5">
                  <.button
                    :for={confirm <- @confirm}
                    id={"#{@id}-confirm"}
                    phx-click={@on_confirm}
                    phx-disable-with
                    disabled={@disabled}
                    class="w-full sm:w-auto py-3 sm:py-2 px-4 sm:px-3 order-first"
                  >
                    <%= render_slot(confirm) %>
                  </.button>
                  <.link
                    :for={cancel <- @cancel}
                    phx-click={@on_cancel}
                    class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700 text-center py-2 sm:py-0 order-last"
                  >
                    <%= render_slot(cancel) %>
                  </.link>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      style={
        case @kind do
          :info -> "position: fixed !important; top: 1rem !important; right: 1rem !important; z-index: 9999 !important; max-width: 24rem !important; width: 100% !important; background: white !important; border-radius: 0.5rem !important; box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05) !important; pointer-events: auto !important; padding: 1rem !important; border: 0 !important; outline: 0 !important; margin: 0 !important; font-family: Inter, sans-serif !important; color: #1f2937 !important; background-color: #ffffff !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;"
          :error -> "position: fixed !important; top: 5rem !important; right: 1rem !important; z-index: 9999 !important; max-width: 24rem !important; width: 100% !important; background: white !important; border-radius: 0.5rem !important; box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05) !important; pointer-events: auto !important; padding: 1rem !important; border: 0 !important; outline: 0 !important; margin: 0 !important; font-family: Inter, sans-serif !important; color: #1f2937 !important; background-color: #ffffff !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;"
        end
      }
      {@rest}
    >
      <div style="display: flex !important; align-items: flex-start !important; border: 0 !important; outline: 0 !important; margin: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;">
        <div style="flex-shrink: 0 !important; border: 0 !important; outline: 0 !important; margin: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;">
          <span style="font-size: 1.25rem !important; line-height: 1 !important; border: 0 !important; outline: 0 !important; margin: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;">
            <%= if @kind == :info, do: "🎉", else: "⚠️" %>
          </span>
        </div>
        <div style="margin-left: 0.75rem !important; flex: 1 !important; border: 0 !important; outline: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;">
          <p :if={@title} style="font-size: 0.875rem !important; font-weight: 600 !important; color: #1f2937 !important; margin: 0 !important; font-family: Inter, sans-serif !important; border: 0 !important; outline: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;">
            <%= @title %>
          </p>
          <p style={"font-size: 0.875rem !important; color: #6b7280 !important; margin: 0 !important; font-family: Inter, sans-serif !important; border: 0 !important; outline: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important; #{@title && "margin-top: 0.25rem !important;"}"}>
            <%= msg %>
          </p>
        </div>
        <div style="margin-left: 1rem !important; flex-shrink: 0 !important; border: 0 !important; outline: 0 !important; padding: 0 !important; border-style: none !important; border-width: 0 !important; box-sizing: border-box !important;">
          <button
            type="button"
            style="color: #374151 !important; background: #f9fafb !important; border: 1px solid #e5e7eb !important; outline: 0 !important; padding: 0.25rem !important; cursor: pointer !important; border-radius: 0.375rem !important; margin: 0 !important; border-style: solid !important; border-width: 1px !important; box-sizing: border-box !important; transition: all 0.2s ease !important; display: flex !important; align-items: center !important; justify-content: center !important; width: 1.5rem !important; height: 1.5rem !important; font-size: 1rem !important; font-weight: bold !important; font-family: Inter, sans-serif !important;"
            onmouseover="this.style.background='#e5e7eb'; this.style.color='#111827';"
            onmouseout="this.style.background='#f9fafb'; this.style.color='#374151';"
            aria-label={gettext("close")}
          >
            ×
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a group of flash notices.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash :if={Phoenix.Flash.get(@flash, :info)} kind={:info} title="Success!" flash={@flash} />
    <.flash :if={Phoenix.Flash.get(@flash, :error)} kind={:error} title="Error!" flash={@flash} />
    <.flash
      :if={false}
      id="client-error"
      kind={:error}
      title="Error!"
      phx-disconnected={show(".phx-client-error #client-error")}
      phx-error={show(".phx-client-error #client-error")}
      hidden
    >
      The connection to the server has been lost. We've sent the form data to the server, but it may
      have been lost in processing. Please check below, or reload the page and try again.
    </.flash>
    <.flash
      :if={false}
      id="server-error"
      kind={:error}
      title="Error!"
      phx-disconnected={show(".phx-server-error #server-error")}
      phx-error={show(".phx-server-error #server-error")}
      hidden
    >
      There was an error processing your request. Please try again later.
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-8 mt-8">
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols dirname disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> Phoenix.HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="mt-1 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "min-h-[6rem] phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders field-specific errors from a form field.

  Displays validation errors for a specific form field with consistent styling.
  Errors are hidden by default until the field has been interacted with (via phx-no-feedback).

  ## Examples

      <.field_error field={@form[:title]} />
      <.field_error field={@form[:date_certainty]} class="mt-2" />

  """
  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :class, :string, default: "", doc: "additional CSS classes"

  def field_error(assigns) do
    ~H"""
    <div
      :if={@field.errors != []}
      class={["text-sm text-red-600 phx-no-feedback:hidden", @class]}
    >
      <p :for={msg <- Enum.map(@field.errors, &translate_error(&1))}>
        <%= msg %>
      </p>
    </div>
    """
  end

  @doc """
  Renders field-specific errors from an Ecto changeset.

  Similar to `field_error/1` but works directly with changesets instead of form fields.
  Use this in components where the form data is passed as a changeset rather than a form.

  ## Examples

      <.changeset_error changeset={@changeset} field={:date_certainty} />
      <.changeset_error changeset={@changeset} field={:venue_certainty} class="mt-2" />

  """
  attr :changeset, :map, required: true, doc: "an Ecto.Changeset struct"
  attr :field, :atom, required: true, doc: "the field name as an atom"
  attr :class, :string, default: "", doc: "additional CSS classes"

  def changeset_error(assigns) do
    errors =
      if assigns[:changeset] do
        Keyword.get_values(assigns.changeset.errors, assigns.field)
      else
        []
      end

    assigns = assign(assigns, :errors, errors)

    ~H"""
    <div :if={@errors != []} class={["text-sm text-red-600", @class]}>
      <p :for={{msg, _opts} <- @errors}>
        <%= msg %>
      </p>
    </div>
    """
  end

  @doc """
  Renders a taxation type selector component for event classification.

  This component allows users to select between "ticketless", "ticketed_event", and "contribution_collection"
  taxation types with interactive help tooltips and comprehensive error handling.
  """
  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :value, :string, default: "ticketless", doc: "the current selected value"
  attr :errors, :list, default: [], doc: "list of error tuples for this field"
  attr :required, :boolean, default: false, doc: "whether the field is required"
  attr :class, :string, default: "", doc: "additional CSS classes for the container"
  attr :reasoning, :string, default: "", doc: "explanation for why this default was chosen"

  attr :hide_ticketless, :boolean,
    default: false,
    doc: "whether to hide the ticketless option (when tickets exist)"

  def taxation_type_selector(assigns) do
    ~H"""
    <div class={"taxation-type-selector #{@class}"} phx-hook="TaxationTypeValidator" id={"#{@field.name}-taxation-selector"}>
      <!-- Error container for validation messages -->
      <%= if @errors != [] do %>
        <div data-role="error-container" class="mb-2">
          <%= for {error, _} <- @errors do %>
            <div class="flex items-center gap-2 text-red-700 bg-red-50 border border-red-200 p-3 rounded-md" role="alert" aria-live="polite" aria-atomic="true">
              <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4 flex-shrink-0" />
              <div class="flex-1">
                <span class="text-sm font-medium">
                  <%= case error do %>
                    <% "can't be blank" -> %>
                      Please select a taxation type for your event
                    <% "is invalid" -> %>
                      Please choose either Ticketless Event, Ticketed Event, or Contribution Collection
                    <% error -> %>
                      <%= error %>
                  <% end %>
                </span>
                <div class="text-xs text-red-600 mt-1">
                  Need help deciding? Click "Click for detailed information" below for guidance.
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>



      <div class="space-y-2" role="radiogroup" aria-required={if @required, do: "true", else: "false"}>

        <!-- Ticketless Event Option (hidden when tickets exist) -->
        <%= unless @hide_ticketless do %>
          <label class="flex items-center gap-2 p-2 border border-gray-200 rounded-md hover:bg-gray-50 cursor-pointer transition-colors group focus-within:ring-2 focus-within:ring-blue-500">
            <input
              type="radio"
              name={@field.name}
              value="ticketless"
              checked={@value == "ticketless"}
              class="h-4 w-4 text-blue-600 border-gray-300 focus:ring-blue-500 focus:ring-2"
              aria-describedby="ticketless-event-description"
            />
            <div class="w-4 h-4 text-gray-500">
              <svg fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <div class="flex-1">
              <div class="text-sm font-medium text-gray-900 group-hover:text-blue-900">Ticketless Event</div>
              <div id="ticketless-event-description" class="text-xs text-gray-600">
                Free events with no payment processing
              </div>
            </div>
          </label>
        <% end %>

        <!-- Ticketed Event Option -->
        <label class="flex items-center gap-2 p-2 border border-gray-200 rounded-md hover:bg-gray-50 cursor-pointer transition-colors group focus-within:ring-2 focus-within:ring-blue-500">
          <input
            type="radio"
            name={@field.name}
            value="ticketed_event"
            checked={@value == "ticketed_event"}
            class="h-4 w-4 text-blue-600 border-gray-300 focus:ring-blue-500 focus:ring-2"
            aria-describedby="ticketed-event-description"
          />
          <!-- Ticket Icon -->
          <div class="w-4 h-4 text-gray-500 group-hover:text-blue-600">
            <svg fill="currentColor" viewBox="0 0 24 24">
              <path d="M22 10v4a1 1 0 01-.6.92l-1.83.73a2.5 2.5 0 000 4.7l1.83.73A1 1 0 0122 22H2a1 1 0 01-.6-.92l1.83-.73a2.5 2.5 0 000-4.7L1.4 14.92A1 1 0 012 14v-4a1 1 0 01.6-.92l1.83-.73a2.5 2.5 0 000-4.7L2.6 2.92A1 1 0 012 2h20a1 1 0 01.6.92l-1.83.73a2.5 2.5 0 000 4.7l1.83.73A1 1 0 0122 10zM20 11.18l-1.83-.73a4.5 4.5 0 010-8.45L20 1.18v10zm-2 1.64a4.5 4.5 0 010 8.45V12.82zm-2-8.64v14.64H8V4.18h8zM6 12.82a4.5 4.5 0 010-8.45V12.82zM4 1.18L5.83 2a4.5 4.5 0 010 8.45L4 11.18v-10z"/>
            </svg>
          </div>
          <div class="flex-1">
            <div class="text-sm font-medium text-gray-900 group-hover:text-blue-900">Ticketed Event</div>
            <div id="ticketed-event-description" class="text-xs text-gray-600">
              Paid tickets with standard taxation
            </div>
          </div>
        </label>

        <!-- Contribution Collection Option -->
        <label class="flex items-center gap-2 p-2 border border-gray-200 rounded-md hover:bg-gray-50 cursor-pointer transition-colors group focus-within:ring-2 focus-within:ring-blue-500">
          <input
            type="radio"
            name={@field.name}
            value="contribution_collection"
            checked={@value == "contribution_collection"}
            class="h-4 w-4 text-blue-600 border-gray-300 focus:ring-blue-500 focus:ring-2"
            aria-describedby="contribution-collection-description"
          />
          <!-- Donation/Heart Icon -->
          <div class="w-4 h-4 text-gray-500 group-hover:text-blue-600">
            <svg fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
            </svg>
          </div>
          <div class="flex-1">
            <div class="text-sm font-medium text-gray-900 group-hover:text-blue-900">Contribution Collection</div>
            <div id="contribution-collection-description" class="text-xs text-gray-600">
              Donation-based events and fundraising
            </div>
          </div>
        </label>
      </div>


    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= EventasaurusApp.Accounts.User.username_slug(user) %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col slot"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal"><%= col[:label] %></th>
            <th class="relative p-0 pb-4"><span class="sr-only"><%= gettext("Actions") %></span></th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500"><%= item.title %></dt>
          <dd class="text-zinc-700"><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <a
        href={Phoenix.VerifiedRoutes.unverified_path(EventasaurusWeb.Endpoint, :get, @navigate)}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        <%= render_slot(@inner_block) %>
      </a>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Renders the Wombie logo with the Pacifico font.

  ## Examples

      <.logo />
      <.logo class="text-3xl" />
      <.logo href="/dashboard" />
      <.logo theme={:cosmic} />
  """
  attr :class, :string, default: "text-2xl"
  attr :href, :string, default: "/"
  attr :text_color, :string, default: nil
  attr :theme, :atom, default: nil

  def logo(assigns) do
    # Calculate emoji size (20% bigger than text)
    size_map = %{
      "text-xs" => "text-sm",
      "text-sm" => "text-base",
      "text-base" => "text-lg",
      "text-lg" => "text-xl",
      "text-xl" => "text-2xl",
      "text-2xl" => "text-3xl",
      "text-3xl" => "text-4xl",
      "text-4xl" => "text-5xl",
      "text-5xl" => "text-6xl",
      "text-6xl" => "text-7xl"
    }

    emoji_size = Map.get(size_map, assigns.class, "text-3xl")

    # Determine text color based on theme or explicit text_color
    text_color =
      cond do
        assigns.text_color -> assigns.text_color
        assigns.theme && EventasaurusWeb.ThemeHelpers.dark_theme?(assigns.theme) -> "text-white"
        true -> "text-gray-900 dark:text-white"
      end

    # Use bear emoji for Wombie branding
    wombie_emoji = "🐻"

    assigns =
      assign(assigns,
        emoji_size: emoji_size,
        computed_text_color: text_color,
        wombie_emoji: wombie_emoji
      )

    ~H"""
    <a href={@href} class="inline-flex items-center gap-2 group">
      <span class={[@emoji_size, "transition-transform group-hover:scale-110 leading-none flex items-center"]}><%= @wombie_emoji %></span>
      <span class={[
        @class,
        "font-knewave font-bold tracking-wide transition-all duration-300 leading-none flex items-center",
        "group-hover:bg-gradient-to-r group-hover:from-green-500 group-hover:via-yellow-500 group-hover:to-pink-500",
        "group-hover:bg-clip-text group-hover:text-transparent",
        @computed_text_color
      ]}>
        Wombie
      </span>
    </a>
    """
  end

  @doc """
  Renders a currency select component with all supported currencies.
  Uses Stripe integration by default with fallback to hardcoded list.

  ## Examples

      <.currency_select
        name="user[default_currency]"
        id="user_default_currency"
        value={@user.default_currency}
        prompt="Select Currency"
      />

      <.currency_select
        name="user[default_currency]"
        id="user_default_currency"
        value={@user.default_currency}
        use_stripe_data={true}
      />
  """
  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :value, :string, default: nil
  attr :prompt, :string, default: "Select Currency"
  attr :class, :string, default: nil
  attr :required, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :use_stripe_data, :boolean, default: true
  attr :rest, :global

  def currency_select(assigns) do
    grouped_options =
      if assigns[:use_stripe_data] do
        CurrencyHelpers.grouped_currencies_from_stripe()
      else
        CurrencyHelpers.supported_currencies()
      end

    assigns = assign(assigns, grouped_options: grouped_options)

    ~H"""
    <select
      name={@name}
      id={@id}
      class={[
        "mt-2 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2",
        "text-gray-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500",
        "disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500",
        @class
      ]}
      required={@required}
      disabled={@disabled}
      {@rest}
    >
      <option value="" :if={@prompt}><%= @prompt %></option>
      <optgroup :for={{group_name, currencies} <- @grouped_options} label={group_name}>
        <option
          :for={{code, name} <- currencies}
          value={code}
          selected={code == @value}
        >
          <%= name %>
        </option>
      </optgroup>
    </select>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(EventasaurusWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EventasaurusWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders the event timeline component.
  """
  attr :events, :list, required: true
  attr :context, :atom, required: true
  attr :loading, :boolean, default: false
  attr :filters, :map, default: %{}
  attr :filter_counts, :map, default: %{}
  attr :config, :map, default: %{}

  def event_timeline(assigns) do
    EventasaurusWeb.EventTimelineComponent.event_timeline(assigns)
  end

  @doc """
  Renders a language switcher for multi-language pages.

  Only displays when multiple languages are available. Emits "change_language"
  event with the selected language code.

  ## Examples

      <.language_switcher
        available_languages={@available_languages}
        current_language={@language}
      />

      <.language_switcher
        available_languages={["en", "pl", "de"]}
        current_language="en"
        class="ml-4"
      />
  """
  attr :available_languages, :list, required: true
  attr :current_language, :string, required: true
  attr :class, :string, default: ""

  def language_switcher(assigns) do
    alias EventasaurusWeb.Helpers.LanguageHelpers

    ~H"""
    <%= if length(@available_languages) > 1 do %>
      <div class={["flex bg-gray-100 rounded-lg p-1", @class]}>
        <%= for lang <- @available_languages do %>
          <button
            phx-click="change_language"
            phx-value-language={lang}
            class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @current_language == lang, do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
            title={LanguageHelpers.language_name(lang)}
          >
            <%= LanguageHelpers.language_flag(lang) %> <%= String.upcase(lang) %>
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end
end
