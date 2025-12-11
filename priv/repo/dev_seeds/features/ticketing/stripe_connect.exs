defmodule DevSeeds.StripeConnect do
  @moduledoc """
  Seeds Stripe Connect test accounts for development.

  IMPORTANT: These are TEST MODE Stripe Connect accounts. They allow testing
  the purchase flow without going through the Stripe OAuth flow.

  The stripe_user_id values are real Stripe test account IDs. They may need
  to be updated periodically if the test accounts expire or are regenerated.

  To get a new test account ID:
  1. Go to http://localhost:4000/stripe/connect (logged in as the organizer)
  2. Complete the Stripe Connect OAuth flow
  3. Update the stripe_user_id value below

  Last updated: 2025-12-11
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Stripe.StripeConnectAccount
  alias EventasaurusApp.Accounts.User
  import Ecto.Query

  # Load helpers
  Code.require_file("../../support/helpers.exs", __DIR__)
  alias DevSeeds.Helpers

  @doc """
  Seeds Stripe Connect accounts for test organizers.

  This enables ticket purchasing in development without requiring
  each developer to go through the Stripe OAuth flow.
  """
  def seed do
    Helpers.section("Seeding Stripe Connect Test Accounts")

    stripe_accounts = [
      %{
        email: "community_builder@example.com",
        stripe_user_id: "acct_1Sd9pZEJFR2dxbke",
        description: "Phase 2 threshold/kickstarter events organizer"
      }
    ]

    Enum.each(stripe_accounts, fn account_data ->
      create_stripe_connect_account(account_data)
    end)

    Helpers.success("Stripe Connect accounts seeded")
  end

  defp create_stripe_connect_account(%{email: email, stripe_user_id: stripe_user_id} = data) do
    description = Map.get(data, :description, "")

    # Find the user
    case Repo.one(from u in User, where: u.email == ^email) do
      nil ->
        Helpers.log("User #{email} not found - skipping Stripe Connect setup", :yellow)
        Helpers.log("  Run ticketing seeds first: mix run priv/repo/dev_seeds/features/ticketing/ticket_scenarios.exs", :yellow)

      user ->
        # Check if they already have a connected (non-disconnected) Stripe account
        existing = Repo.one(
          from sca in StripeConnectAccount,
            where: sca.user_id == ^user.id and is_nil(sca.disconnected_at)
        )

        cond do
          existing && existing.stripe_user_id == stripe_user_id ->
            Helpers.log("#{email} already has Stripe Connect: #{stripe_user_id}", :green)

          existing ->
            # Update the existing account with new stripe_user_id
            existing
            |> Ecto.Changeset.change(%{stripe_user_id: stripe_user_id})
            |> Repo.update!()
            Helpers.log("#{email} Stripe Connect updated: #{stripe_user_id}", :green)

          true ->
            # Create new Stripe Connect account
            %StripeConnectAccount{}
            |> StripeConnectAccount.changeset(%{
              user_id: user.id,
              stripe_user_id: stripe_user_id,
              connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.insert!()
            Helpers.log("#{email} Stripe Connect created: #{stripe_user_id} (#{description})", :green)
        end
    end
  end
end

# Allow direct execution of this script
if __ENV__.file == Path.absname(__ENV__.file) do
  DevSeeds.StripeConnect.seed()
end
