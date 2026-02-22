defmodule EventasaurusWeb.Schema.Types.ParticipantSuggestion do
  use Absinthe.Schema.Notation

  enum :recommendation_level do
    value(:highly_recommended, description: "Top pick — frequent co-attendee")
    value(:recommended, description: "Recommended — attended together before")
    value(:suggested, description: "Suggested — some overlap")
  end

  object :participant_suggestion do
    field(:user_id, non_null(:id))
    field(:name, :string)
    field(:username, :string)
    field(:participation_count, non_null(:integer))
    field(:total_score, non_null(:float))
    field(:recommendation_level, non_null(:recommendation_level))

    field :masked_email, :string do
      resolve(fn participant, _, _ ->
        {:ok, mask_email(participant.email)}
      end)
    end

    field :avatar_url, non_null(:string) do
      resolve(fn participant, _, _ ->
        # Use PNG format (not SVG) so iOS AsyncImage can render it
        seed = URI.encode_www_form(to_string(participant.email || participant.user_id))
        url = "https://api.dicebear.com/9.x/dylan/png?seed=#{seed}&size=80"
        {:ok, url}
      end)
    end
  end

  defp mask_email(nil), do: nil

  defp mask_email(email) when is_binary(email) do
    case String.split(email, "@") do
      [local, domain] ->
        masked_local =
          if String.length(local) <= 1 do
            "*"
          else
            String.first(local) <> String.duplicate("*", String.length(local) - 1)
          end

        masked_local <> "@" <> domain

      _ ->
        "***"
    end
  end
end
