defmodule EventasaurusWeb.ChangelogComponents do
  @moduledoc """
  Components for the Changelog page.

  Supports Sanity CMS change types: new, improved, enhanced, fixed, updated

  Uses shared tag colors from SharedProductComponents for consistency
  with the Roadmap page.
  """
  use Phoenix.Component
  use EventasaurusWeb, :html

  import EventasaurusWeb.Components.SharedProductComponents,
    only: [tag_color: 1, tag_strip_color: 1]

  @doc """
  Renders the main timeline container.
  """
  attr :entries, :list, required: true

  def timeline(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <div class="space-y-0" role="list" aria-label="Changelog entries">
        <.timeline_entry :for={entry <- @entries} entry={entry} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a single timeline entry.
  """
  attr :entry, :map, required: true

  def timeline_entry(assigns) do
    # Get strip color from first tag (like roadmap) or fall back to indigo
    first_tag = List.first(assigns.entry[:tags] || [])
    strip_color = if first_tag, do: tag_strip_color(first_tag), else: "bg-indigo-500"
    assigns = assign(assigns, :strip_color, strip_color)

    ~H"""
    <article class="group flex flex-col md:flex-row gap-6 md:gap-8" role="listitem" aria-labelledby={"entry-#{@entry.id}"}>
      <%!-- Date Column (Fixed Width on Desktop) --%>
      <div class="md:w-32 md:shrink-0 md:text-right pt-2">
        <time class="text-sm font-semibold text-zinc-900 sticky top-4 block" datetime={@entry[:iso_date] || @entry.date}>
          <%= @entry.date %>
        </time>
      </div>

      <%!-- Timeline Column (Fixed Width with Line and Dot) --%>
      <div class="hidden md:flex flex-col items-center w-8 shrink-0 relative" aria-hidden="true">
        <%!-- Continuous vertical line --%>
        <div class="absolute top-0 bottom-0 w-px bg-zinc-200"></div>
        <%!-- Dot marker --%>
        <div class="w-3 h-3 bg-indigo-600 rounded-full ring-4 ring-white relative z-10 mt-2.5 shadow-sm"></div>
      </div>

      <%!-- Content Column --%>
      <div class="flex-1 pb-12">
        <div class="bg-white rounded-2xl p-6 shadow-sm border border-zinc-200/60 hover:shadow-md transition-shadow relative overflow-hidden group">
           <%!-- Colorful Left Strip (matches roadmap style) --%>
           <div class={["absolute top-0 left-0 w-1 h-full", @strip_color]}></div>

           <div class="pl-2">
             <%!-- Mobile Date (visible only on small screens) --%>
             <time class="md:hidden text-sm font-semibold text-zinc-500 mb-2 block" datetime={@entry[:iso_date] || @entry.date}>
               <%= @entry.date %>
             </time>

             <%!-- Tags (from Sanity) --%>
             <%= if @entry[:tags] && length(@entry.tags) > 0 do %>
               <div class="flex flex-wrap gap-2 mb-3">
                 <%= for tag <- @entry.tags do %>
                   <.tag_badge tag={tag} />
                 <% end %>
               </div>
             <% end %>

             <h3 id={"entry-#{@entry.id}"} class="text-xl font-bold text-zinc-900 mb-2 group-hover:text-indigo-600 transition-colors"><%= @entry.title %></h3>
             <p class="text-zinc-600 mb-6 leading-relaxed"><%= @entry.summary %></p>

             <%!-- Optional Image --%>
             <%= if @entry[:image] do %>
               <figure class="mb-6 rounded-lg overflow-hidden border border-zinc-100 shadow-sm">
                 <img src={@entry.image} alt={"Screenshot for #{@entry.title}"} class="w-full h-auto object-cover" loading="lazy" />
               </figure>
             <% end %>

             <%!-- Changes List --%>
             <ul class="space-y-3" aria-label="List of changes">
               <%= for change <- @entry.changes do %>
                 <.change_item change={change} />
               <% end %>
             </ul>
           </div>
        </div>
      </div>
    </article>
    """
  end

  @doc """
  Renders a tag badge (e.g., polling, scheduling, groups).
  Colors vary by tag category.
  """
  attr :tag, :string, required: true

  def tag_badge(assigns) do
    {bg_color, text_color, ring_color} = tag_color(assigns.tag)

    assigns =
      assigns
      |> assign(:bg_color, bg_color)
      |> assign(:text_color, text_color)
      |> assign(:ring_color, ring_color)

    ~H"""
    <span class={["inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset", @bg_color, @text_color, @ring_color]}>
      <%= @tag %>
    </span>
    """
  end

  # Note: tag_color/1 is now imported from SharedProductComponents
  # for consistency with the Roadmap page

  @doc """
  Renders a single change item in the list with type-specific icon.

  Supports Sanity types: new, improved, enhanced, fixed, updated
  """
  attr :change, :map, required: true

  def change_item(assigns) do
    {icon_path, icon_color, label} = change_type_config(assigns.change.type)

    assigns =
      assigns
      |> assign(:icon_path, icon_path)
      |> assign(:icon_color, icon_color)
      |> assign(:label, label)

    ~H"""
    <li class="flex items-start gap-3 text-sm text-zinc-700">
      <div class="flex items-center gap-2 shrink-0">
        <div class={["flex-none p-1 rounded-full", @icon_color]} aria-hidden="true">
          <svg class="w-3.5 h-3.5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
            <%= Phoenix.HTML.raw(@icon_path) %>
          </svg>
        </div>
        <span class={["text-xs font-medium uppercase tracking-wide", label_color(@change.type)]}><%= @label %></span>
      </div>
      <span class="leading-6"><%= @change.description %></span>
    </li>
    """
  end

  # Returns {icon_path, bg_color, label} for each change type
  defp change_type_config(type) do
    case type do
      "new" ->
        # Plus icon - emerald/green
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />),
         "bg-emerald-100 text-emerald-600", "New"}

      "improved" ->
        # Arrow up icon - blue
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />),
         "bg-blue-100 text-blue-600", "Improved"}

      "enhanced" ->
        # Sparkles icon - violet
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456z" />),
         "bg-violet-100 text-violet-600", "Enhanced"}

      "fixed" ->
        # Wrench icon - amber/yellow
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z" />),
         "bg-amber-100 text-amber-600", "Fixed"}

      "updated" ->
        # Refresh icon - cyan
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99" />),
         "bg-cyan-100 text-cyan-600", "Updated"}

      "removed" ->
        # Trash icon - red
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />),
         "bg-red-100 text-red-600", "Removed"}

      "security" ->
        # Lock icon - purple
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />),
         "bg-purple-100 text-purple-600", "Security"}

      _ ->
        # Default info icon - gray
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z" />),
         "bg-zinc-100 text-zinc-500", "Update"}
    end
  end

  # Returns text color class for the label
  defp label_color(type) do
    case type do
      "new" -> "text-emerald-600"
      "improved" -> "text-blue-600"
      "enhanced" -> "text-violet-600"
      "fixed" -> "text-amber-600"
      "updated" -> "text-cyan-600"
      "removed" -> "text-red-600"
      "security" -> "text-purple-600"
      _ -> "text-zinc-500"
    end
  end
end
