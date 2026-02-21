defmodule EventasaurusWeb.Schema.Types.ParticipantSuggestion do
  use Absinthe.Schema.Notation

  object :participant_suggestion do
    field(:user_id, non_null(:id))
    field(:name, :string)
    field(:email, non_null(:string))
    field(:username, :string)
    field(:participation_count, non_null(:integer))
    field(:total_score, non_null(:float))
    field(:recommendation_level, non_null(:string))

    field :avatar_url, non_null(:string) do
      resolve(fn participant, _, _ ->
        # Use PNG format (not SVG) so iOS AsyncImage can render it
        seed = URI.encode(participant.email)
        url = "https://api.dicebear.com/9.x/dylan/png?seed=#{seed}&size=80"
        {:ok, url}
      end)
    end
  end
end
