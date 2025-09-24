defmodule EventasaurusApp.Events.EventDateOptionTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventDateOption

  describe "event_date_options" do
    setup do
      poll = insert(:event_date_poll)
      %{poll: poll}
    end

    test "create_event_date_option/2 creates an option with valid data", %{poll: poll} do
      tomorrow = Date.utc_today() |> Date.add(1)

      assert {:ok, %EventDateOption{} = option} = Events.create_event_date_option(poll, tomorrow)
      assert option.event_date_poll_id == poll.id
      assert option.date == tomorrow
    end

    test "create_event_date_option/2 accepts string dates", %{poll: poll} do
      tomorrow_string = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      assert {:ok, %EventDateOption{} = option} =
               Events.create_event_date_option(poll, tomorrow_string)

      assert option.event_date_poll_id == poll.id
      assert Date.to_iso8601(option.date) == tomorrow_string
    end

    test "create_event_date_option/2 fails with past date", %{poll: poll} do
      yesterday = Date.utc_today() |> Date.add(-1)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Events.create_event_date_option(poll, yesterday)

      assert "cannot be in the past" in errors_on(changeset).date
    end

    test "create_event_date_option/2 prevents duplicate dates", %{poll: poll} do
      tomorrow = Date.utc_today() |> Date.add(1)

      # Create first option
      assert {:ok, _option} = Events.create_event_date_option(poll, tomorrow)

      # Try to create duplicate
      assert {:error, %Ecto.Changeset{} = changeset} =
               Events.create_event_date_option(poll, tomorrow)

      assert "date already exists for this poll" in errors_on(changeset).event_date_poll_id
    end

    test "create_date_options_from_range/3 creates multiple options", %{poll: poll} do
      start_date = Date.utc_today() |> Date.add(1)
      end_date = Date.utc_today() |> Date.add(5)

      assert {:ok, options} = Events.create_date_options_from_range(poll, start_date, end_date)
      assert length(options) == 5
      assert Enum.all?(options, fn option -> option.event_date_poll_id == poll.id end)
    end

    test "create_date_options_from_list/2 creates options from list", %{poll: poll} do
      dates = [
        Date.utc_today() |> Date.add(1),
        Date.utc_today() |> Date.add(3),
        Date.utc_today() |> Date.add(5)
      ]

      assert {:ok, options} = Events.create_date_options_from_list(poll, dates)
      assert length(options) == 3
      assert Enum.all?(options, fn option -> option.event_date_poll_id == poll.id end)
    end

    test "list_event_date_options/1 returns options sorted by date", %{poll: poll} do
      # Create options in reverse order
      {:ok, _option3} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(5))
      {:ok, _option1} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(1))
      {:ok, _option2} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(3))

      options = Events.list_event_date_options(poll)
      assert length(options) == 3

      # Check they're sorted by date
      dates = Enum.map(options, & &1.date)
      assert dates == Enum.sort(dates, &(Date.compare(&1, &2) != :gt))
    end

    test "get_event_date_option!/1 returns option with preloaded poll", %{poll: poll} do
      {:ok, option} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(1))

      retrieved_option = Events.get_event_date_option!(option.id)
      assert retrieved_option.id == option.id
      assert retrieved_option.event_date_poll.id == poll.id
    end

    test "update_event_date_option/2 updates option", %{poll: poll} do
      {:ok, option} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(1))
      new_date = Date.utc_today() |> Date.add(2)

      assert {:ok, updated_option} = Events.update_event_date_option(option, %{date: new_date})
      assert updated_option.date == new_date
    end

    test "delete_event_date_option/1 removes option", %{poll: poll} do
      {:ok, option} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(1))

      assert {:ok, %EventDateOption{}} = Events.delete_event_date_option(option)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event_date_option!(option.id) end
    end

    test "delete_all_date_options/1 removes all options for poll", %{poll: poll} do
      {:ok, _option1} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(1))
      {:ok, _option2} = Events.create_event_date_option(poll, Date.utc_today() |> Date.add(2))

      {count, _} = Events.delete_all_date_options(poll)
      assert count == 2
      assert Events.list_event_date_options(poll) == []
    end

    test "date_option_exists?/2 checks if date exists in poll", %{poll: poll} do
      tomorrow = Date.utc_today() |> Date.add(1)
      day_after = Date.utc_today() |> Date.add(2)

      {:ok, _option} = Events.create_event_date_option(poll, tomorrow)

      assert Events.date_option_exists?(poll, tomorrow) == true
      assert Events.date_option_exists?(poll, day_after) == false
    end

    test "update_event_date_options/2 preserves existing votes when adding new dates", %{
      poll: poll
    } do
      # Create initial date options
      date1 = Date.utc_today() |> Date.add(1)
      date2 = Date.utc_today() |> Date.add(2)
      date3 = Date.utc_today() |> Date.add(3)

      {:ok, option1} = Events.create_event_date_option(poll, date1)
      {:ok, option2} = Events.create_event_date_option(poll, date2)

      # Create votes for existing options
      user = insert(:user)
      {:ok, vote1} = Events.create_event_date_vote(option1, user, :yes)
      {:ok, vote2} = Events.create_event_date_vote(option2, user, :if_need_be)

      # Update to add a new date while keeping existing ones
      # Keep date1 and date2, add date3
      new_dates = [date1, date2, date3]

      assert {:ok, updated_options} = Events.update_event_date_options(poll, new_dates)
      assert length(updated_options) == 3

      # Verify existing votes are preserved
      existing_vote1 = Events.get_event_date_vote!(vote1.id)
      existing_vote2 = Events.get_event_date_vote!(vote2.id)

      assert existing_vote1.vote_type == :yes
      assert existing_vote2.vote_type == :if_need_be

      # Verify new date option was created
      assert Enum.any?(updated_options, fn opt -> opt.date == date3 end)
    end

    test "update_event_date_options/2 removes votes when dates are removed", %{poll: poll} do
      # Create initial date options
      date1 = Date.utc_today() |> Date.add(1)
      date2 = Date.utc_today() |> Date.add(2)
      date3 = Date.utc_today() |> Date.add(3)

      {:ok, option1} = Events.create_event_date_option(poll, date1)
      {:ok, option2} = Events.create_event_date_option(poll, date2)
      {:ok, option3} = Events.create_event_date_option(poll, date3)

      # Create votes for all options
      user = insert(:user)
      {:ok, vote1} = Events.create_event_date_vote(option1, user, :yes)
      {:ok, vote2} = Events.create_event_date_vote(option2, user, :if_need_be)
      {:ok, vote3} = Events.create_event_date_vote(option3, user, :no)

      # Update to remove date2, keep date1 and date3
      new_dates = [date1, date3]

      assert {:ok, updated_options} = Events.update_event_date_options(poll, new_dates)
      assert length(updated_options) == 2

      # Verify vote for removed option is deleted (due to foreign key cascade)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event_date_vote!(vote2.id) end

      # Verify votes for kept options are preserved
      existing_vote1 = Events.get_event_date_vote!(vote1.id)
      existing_vote3 = Events.get_event_date_vote!(vote3.id)

      assert existing_vote1.vote_type == :yes
      assert existing_vote3.vote_type == :no
    end

    test "update_event_date_options/2 handles no changes gracefully", %{poll: poll} do
      # Create initial date options
      date1 = Date.utc_today() |> Date.add(1)
      date2 = Date.utc_today() |> Date.add(2)

      {:ok, option1} = Events.create_event_date_option(poll, date1)
      {:ok, option2} = Events.create_event_date_option(poll, date2)

      # Create votes
      user = insert(:user)
      {:ok, vote1} = Events.create_event_date_vote(option1, user, :yes)
      {:ok, vote2} = Events.create_event_date_vote(option2, user, :if_need_be)

      # Update with same dates (no changes)
      same_dates = [date1, date2]

      assert {:ok, updated_options} = Events.update_event_date_options(poll, same_dates)
      assert length(updated_options) == 2

      # Verify all votes are preserved
      existing_vote1 = Events.get_event_date_vote!(vote1.id)
      existing_vote2 = Events.get_event_date_vote!(vote2.id)

      assert existing_vote1.vote_type == :yes
      assert existing_vote2.vote_type == :if_need_be
    end
  end

  describe "event_date_option validations" do
    test "changeset with valid attributes" do
      changeset =
        EventDateOption.changeset(%EventDateOption{}, %{
          event_date_poll_id: 1,
          date: Date.utc_today() |> Date.add(1)
        })

      assert changeset.valid?
    end

    test "changeset requires event_date_poll_id and date" do
      changeset = EventDateOption.changeset(%EventDateOption{}, %{})

      assert "can't be blank" in errors_on(changeset).event_date_poll_id
      assert "can't be blank" in errors_on(changeset).date
    end

    test "changeset validates date is not in past" do
      changeset =
        EventDateOption.changeset(%EventDateOption{}, %{
          event_date_poll_id: 1,
          date: Date.utc_today() |> Date.add(-1)
        })

      refute changeset.valid?
      assert "cannot be in the past" in errors_on(changeset).date
    end

    test "changeset allows today's date" do
      changeset =
        EventDateOption.changeset(%EventDateOption{}, %{
          event_date_poll_id: 1,
          date: Date.utc_today()
        })

      assert changeset.valid?
    end
  end

  describe "event_date_option helper functions" do
    test "past?/1 correctly identifies past dates" do
      yesterday = Date.utc_today() |> Date.add(-1)
      option = %EventDateOption{date: yesterday}

      assert EventDateOption.past?(option) == true
    end

    test "today?/1 correctly identifies today's date" do
      today = Date.utc_today()
      option = %EventDateOption{date: today}

      assert EventDateOption.today?(option) == true
    end

    test "future?/1 correctly identifies future dates" do
      tomorrow = Date.utc_today() |> Date.add(1)
      option = %EventDateOption{date: tomorrow}

      assert EventDateOption.future?(option) == true
    end

    test "to_display_string/1 returns formatted date string" do
      tomorrow = Date.utc_today() |> Date.add(1)
      option = %EventDateOption{date: tomorrow}

      assert EventDateOption.to_display_string(option) == Date.to_string(tomorrow)
    end

    test "compare/2 compares two date options" do
      tomorrow = Date.utc_today() |> Date.add(1)
      day_after = Date.utc_today() |> Date.add(2)

      option1 = %EventDateOption{date: tomorrow}
      option2 = %EventDateOption{date: day_after}

      assert EventDateOption.compare(option1, option2) == :lt
      assert EventDateOption.compare(option2, option1) == :gt
      assert EventDateOption.compare(option1, option1) == :eq
    end
  end
end
