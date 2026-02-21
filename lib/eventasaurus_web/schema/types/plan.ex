defmodule EventasaurusWeb.Schema.Types.Plan do
  use Absinthe.Schema.Notation

  object :plan do
    field(:slug, non_null(:string))
    field(:title, non_null(:string))
    field(:invite_count, non_null(:integer))
    field(:created_at, non_null(:datetime))
    field(:already_exists, :boolean)
  end
end
