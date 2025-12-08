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
      <div class="space-y-0">
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
    <div class="group flex flex-col md:flex-row gap-6 md:gap-8">
      <!-- Date Column (Fixed Width on Desktop) -->
      <div class="md:w-32 md:shrink-0 md:text-right pt-2">
        <div class="text-sm font-semibold text-zinc-900 sticky top-4">
          <%= @entry.date %>
        </div>
      </div>
      
      <!-- Timeline Column (Fixed Width with Line) -->
      <div class="hidden md:flex flex-col items-center w-8 shrink-0 relative">
        <!-- Continuous Line -->
        <div class="absolute top-0 bottom-0 w-px bg-zinc-200"></div>
        <!-- Dot -->
        <div class="w-3 h-3 bg-indigo-600 rounded-full ring-4 ring-white relative z-10 mt-2.5 shadow-sm"></div>
      </div>

      <!-- Content Column -->
      <div class="flex-1 pb-12">
        <div class="bg-white rounded-2xl p-6 shadow-sm border border-zinc-200/60 hover:shadow-md transition-shadow relative">
           
           <!-- Mobile Date (visible only on small screens) -->
           <div class="md:hidden text-sm font-semibold text-zinc-500 mb-2">
             <%= @entry.date %>
           </div>

           <!-- Header: Badges & Title -->
           <div class="flex flex-wrap gap-2 mb-3">
              <%= for type <- unique_change_types(@entry.changes) do %>
                 <.change_badge type={type} />
              <% end %>
           </div>
           
           <h3 class="text-xl font-bold text-zinc-900 mb-2"><%= @entry.title %></h3>
           <p class="text-zinc-600 mb-6 leading-relaxed"><%= @entry.summary %></p>
           
           <!-- Optional Image -->
           <%= if @entry[:image] do %>
             <div class="mb-6 rounded-lg overflow-hidden border border-zinc-100 shadow-sm">
               <img src={@entry.image} alt={@entry.title} class="w-full h-auto object-cover" />
             </div>
           <% end %>
           
           <!-- Changes List -->
           <ul class="space-y-3">
             <%= for change <- @entry.changes do %>
               <.change_item change={change} />
             <% end %>
           </ul>
        </div>
      </div>
    </div>
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
        {"bg-rose-50 text-rose-700 ring-rose-600/20", "Fix", 
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />)}
      "changed" -> 
        {"bg-amber-50 text-amber-700 ring-amber-600/20", "Improvement", 
         ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />)}
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
        {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />), "text-rose-600"}
      "changed" -> 
         {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />), "text-amber-600"}
      _ -> 
         {~s(<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />), "text-zinc-400"}
    end

    assigns = assigns
              |> assign(:icon_path, icon_path)
              |> assign(:icon_color, icon_color)

    ~H"""
    <li class="flex items-start gap-3 text-sm text-zinc-600">
      <div class={["mt-1 flex-none p-1 rounded-full bg-zinc-50 border border-zinc-100", @icon_color]}>
         <svg class="w-3 h-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
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
