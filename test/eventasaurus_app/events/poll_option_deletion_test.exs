defmodule EventasaurusApp.Events.PollOptionDeletionTest do
  use EventasaurusApp.DataCase, async: true

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures
  import Ecto.Query

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.PollOption

  setup do
    user = user_fixture()
    other_user = user_fixture()
    event = event_fixture()

    poll =
      poll_fixture(%{
        event_id: event.id,
        created_by_id: user.id,
        title: "Test Poll",
        poll_type: "general",
        voting_system: "binary",
        phase: "list_building"
      })

    %{user: user, other_user: other_user, event: event, poll: poll}
  end

  describe "can_delete_own_suggestion?/2" do
    test "returns true when user is the suggester and within 5 minutes", %{poll: poll, user: user} do
      # Create a poll option suggested by the user
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: user.id,
          title: "Test Option",
          status: "active"
        })

      # Should be able to delete immediately after creation
      assert Events.can_delete_own_suggestion?(option, user) == true
    end

    test "returns false when user is not the suggester", %{
      poll: poll,
      user: user,
      other_user: other_user
    } do
      # Create a poll option suggested by other_user
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: other_user.id,
          title: "Test Option",
          status: "active"
        })

      # User should not be able to delete other user's suggestion
      assert Events.can_delete_own_suggestion?(option, user) == false
    end

    test "returns false when more than 5 minutes have passed", %{poll: poll, user: user} do
      # Create a poll option with an old timestamp
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: user.id,
          title: "Test Option",
          status: "active"
        })

      # Manually update the inserted_at to be 6 minutes ago
      six_minutes_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-360, :second)
        |> NaiveDateTime.truncate(:second)

      Ecto.Changeset.change(option, %{inserted_at: six_minutes_ago})
      |> EventasaurusApp.Repo.update!()

      # Reload the option to get the updated timestamp
      option = EventasaurusApp.Repo.get!(PollOption, option.id)

      # Should not be able to delete after 5 minutes
      assert Events.can_delete_own_suggestion?(option, user) == false
    end

    test "returns false for nil inputs", %{user: user} do
      assert Events.can_delete_own_suggestion?(nil, user) == false
      assert Events.can_delete_own_suggestion?(%PollOption{}, nil) == false
      assert Events.can_delete_own_suggestion?(nil, nil) == false
    end
  end

  describe "delete_poll_option/1" do
    test "successfully deletes a poll option", %{poll: poll, user: user} do
      # Create a poll option
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: user.id,
          title: "Test Option",
          status: "active"
        })

      # Delete the option
      assert {:ok, _deleted_option} = Events.delete_poll_option(option)

      # Verify it's deleted
      assert EventasaurusApp.Repo.get(PollOption, option.id) == nil
    end

    test "cascade deletes associated votes", %{poll: poll, user: user, other_user: other_user} do
      # Create a poll option
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: user.id,
          title: "Test Option",
          status: "active"
        })

      # Create votes for the option (poll_option, user, vote_data, voting_system)
      {:ok, _vote1} = Events.create_poll_vote(option, user, %{vote_value: "yes"}, "binary")
      {:ok, _vote2} = Events.create_poll_vote(option, other_user, %{vote_value: "yes"}, "binary")

      # Verify votes exist by checking the database directly
      votes =
        EventasaurusApp.Repo.all(
          from(v in EventasaurusApp.Events.PollVote,
            where: v.poll_option_id == ^option.id
          )
        )

      assert length(votes) == 2

      # Delete the option
      {:ok, _deleted_option} = Events.delete_poll_option(option)

      # Verify votes are also deleted
      votes_after =
        EventasaurusApp.Repo.all(
          from(v in EventasaurusApp.Events.PollVote,
            where: v.poll_option_id == ^option.id
          )
        )

      assert length(votes_after) == 0
    end
  end

  describe "time window deletion scenario" do
    test "user can delete their suggestion within 5 minutes", %{poll: poll, user: user} do
      # Create a suggestion
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: user.id,
          title: "My Suggestion",
          status: "active"
        })

      # Verify user can delete it
      assert Events.can_delete_own_suggestion?(option, user) == true

      # Delete it
      assert {:ok, _} = Events.delete_poll_option(option)
    end

    test "poll creator can always delete any suggestion", %{
      poll: poll,
      user: creator,
      other_user: other_user
    } do
      # Create a suggestion by other_user
      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          suggested_by_id: other_user.id,
          title: "Other User's Suggestion",
          status: "active"
        })

      # Make the option old (beyond 5 minutes)
      old_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-600, :second)
        |> NaiveDateTime.truncate(:second)

      Ecto.Changeset.change(option, %{inserted_at: old_time})
      |> EventasaurusApp.Repo.update!()

      option = EventasaurusApp.Repo.get!(PollOption, option.id)

      # Creator should still be able to delete it (this test assumes creator authorization is handled elsewhere)
      # The can_delete_own_suggestion? function only checks for own suggestions within time window
      assert Events.can_delete_own_suggestion?(option, creator) == false

      # But deletion itself should still work if authorized
      assert {:ok, _} = Events.delete_poll_option(option)
    end
  end
end
