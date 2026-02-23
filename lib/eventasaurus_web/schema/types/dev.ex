defmodule EventasaurusWeb.Schema.Types.Dev do
  use Absinthe.Schema.Notation

  object :dev_quick_login_users do
    field(:personal, non_null(list_of(non_null(:dev_user))))
    field(:organizers, non_null(list_of(non_null(:dev_user))))
    field(:participants, non_null(list_of(non_null(:dev_user))))
  end

  object :dev_user do
    field(:id, non_null(:id))
    field(:name, :string)
    field(:email, non_null(:string))
    field(:label, non_null(:string))
  end
end
