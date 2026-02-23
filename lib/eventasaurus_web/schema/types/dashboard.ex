defmodule EventasaurusWeb.Schema.Types.Dashboard do
  use Absinthe.Schema.Notation

  object :dashboard_venue do
    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:address, :string)
    field(:latitude, :float)
    field(:longitude, :float)
  end

  object :dashboard_event do
    field(:id, non_null(:id))
    field(:title, non_null(:string))
    field(:slug, non_null(:string))
    field(:tagline, :string)
    field(:description, :string)
    field(:starts_at, :datetime)
    field(:ends_at, :datetime)
    field(:timezone, :string)
    field(:status, non_null(:event_status))
    field(:cover_image_url, :string)
    field(:is_virtual, non_null(:boolean))
    field(:user_role, non_null(:string))
    field(:user_status, :string)
    field(:can_manage, non_null(:boolean))
    field(:participant_count, non_null(:integer))
    field(:venue, :dashboard_venue)
    field(:created_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :dashboard_filter_counts do
    field(:upcoming, non_null(:integer))
    field(:past, non_null(:integer))
    field(:archived, non_null(:integer))
    field(:created, non_null(:integer))
    field(:participating, non_null(:integer))
  end

  object :dashboard_events_result do
    field(:events, non_null(list_of(non_null(:dashboard_event))))
    field(:filter_counts, non_null(:dashboard_filter_counts))
  end
end
