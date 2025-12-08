defmodule EventasaurusWeb.ChangelogComponents do
  @moduledoc """
  Components for the Changelog page.
  """
  use Phoenix.Component
  use EventasaurusWeb, :html

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
        <div class="bg-white rounded-2xl p-6 shadow-sm border border-zinc-200/60 hover:shadow-md transition-shadow relative">

           <%!-- Mobile Date (visible only on small screens) --%>
           <time class="md:hidden text-sm font-semibold text-zinc-500 mb-2 block" datetime={@entry[:iso_date] || @entry.date}>
             <%= @entry.date %>
           </time>

           <%!-- Header: Badges & Title --%>
           <div class="flex flex-wrap gap-2 mb-3" role="list" aria-label="Change types">
              <%= for type <- unique_change_types(@entry.changes) do %>
                 <.change_badge type={type} />
              <% end %>
           </div>

           <h3 id={"entry-#{@entry.id}"} class="text-xl font-bold text-zinc-900 mb-2"><%= @entry.title %></h3>
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
    </article>
    """
  end

  @doc """
  Renders a badge for the change type.
  """
  attr :type, :string, required: true
  
  def change_badge(assigns) do
    {color_classes, label, icon_path} = case assigns.type do
      "added" ->
        {"bg-emerald-50 text-emerald-700 ring-emerald-600/20", "New",
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456zM16.894 20.567L16.5 21.75l-.394-1.183a2.25 2.25 0 00-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 001.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 001.423 1.423l1.183.394-1.183.394a2.25 2.25 0 00-1.423 1.423z" />)}
      "fixed" ->
        {"bg-yellow-50 text-yellow-700 ring-yellow-600/20", "Fix",
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z" />)}
      "changed" ->
        {"bg-blue-50 text-blue-700 ring-blue-600/20", "Improvement",
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />)}
      "removed" ->
        {"bg-red-50 text-red-700 ring-red-600/20", "Removed",
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />)}
      "security" ->
        {"bg-purple-50 text-purple-700 ring-purple-600/20", "Security",
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />)}
      _ ->
        {"bg-zinc-50 text-zinc-700 ring-zinc-600/20", "Update",
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z" />)}
    end
    
    assigns = assigns 
             |> assign(:color_classes, color_classes)
             |> assign(:label, label)
             |> assign(:icon_path, icon_path)

    ~H"""
    <span class={["inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset", @color_classes]}>
      <svg class="mr-1.5 h-3 w-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
        <%= Phoenix.HTML.raw(@icon_path) %>
      </svg>
      <%= @label %>
    </span>
    """
  end

  @doc """
  Renders a single change item in the list.
  """
  attr :change, :map, required: true
  
  def change_item(assigns) do
    {icon_path, icon_color} = case assigns.change.type do
      "added" ->
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />), "text-emerald-600"}
      "fixed" ->
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z" />), "text-yellow-600"}
      "changed" ->
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />), "text-blue-600"}
      "removed" ->
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />), "text-red-600"}
      "security" ->
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />), "text-purple-600"}
      _ ->
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />), "text-zinc-400"}
    end

    assigns = assigns
              |> assign(:icon_path, icon_path)
              |> assign(:icon_color, icon_color)

    ~H"""
    <li class="flex items-start gap-3 text-sm text-zinc-600">
      <div class={["mt-1 flex-none p-1 rounded-full bg-zinc-50 border border-zinc-100", @icon_color]} aria-hidden="true">
         <svg class="w-3 h-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" aria-hidden="true">
           <%= Phoenix.HTML.raw(@icon_path) %>
         </svg>
      </div>
      <span class="leading-6"><%= @change.description %></span>
    </li>
    """
  end

  defp unique_change_types(changes) do
    changes
    |> Enum.map(& &1.type)
    |> Enum.uniq()
  end
end
