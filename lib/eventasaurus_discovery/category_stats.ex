defmodule EventasaurusDiscovery.CategoryStats do
  @moduledoc """
  Context module for category statistics and discovery queries.
  """
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Categories.PublicEventCategory
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  @doc """
  Lists top categories by number of upcoming events.

  ## Options
    * `:min_events` - Minimum number of events required (default: 5)
    * `:limit` - Maximum number of categories to return (default: 12)
  """
  def list_top_categories_by_events(opts \\ []) do
    min_events = Keyword.get(opts, :min_events, 5)
    limit = Keyword.get(opts, :limit, 12)

    from(c in Category,
      inner_join: pec in PublicEventCategory,
      on: pec.category_id == c.id,
      inner_join: pe in PublicEvent,
      on: pec.event_id == pe.id,
      where: c.is_active == true and c.slug != "other",
      where: pe.starts_at > ^NaiveDateTime.utc_now(),
      group_by: c.id,
      having: count(pe.id) >= ^min_events,
      order_by: [desc: count(pe.id)],
      limit: ^limit,
      select: %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        icon: c.icon,
        color: c.color,
        translations: c.translations,
        event_count: count(pe.id)
      }
    )
    |> Repo.all()
  end
end
