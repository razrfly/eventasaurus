defmodule EventasaurusApp.FactoryTest do
  @moduledoc """
  Test suite to verify ExMachina factories are working correctly.
  """

  use EventasaurusApp.DataCase, async: true

  @moduletag :factory_test

  describe "factory setup" do
    test "creates valid user" do
      user = insert(:user)

      assert user.id
      assert user.name =~ "Test User"
      assert user.email =~ "@example.com"
      assert user.supabase_id =~ "supabase_user_"
    end

    test "creates valid venue" do
      venue = insert(:venue)

      assert venue.id
      assert venue.name =~ "Test Venue"
      assert venue.address =~ "Test Street"
      assert venue.city == "Test City"
      assert venue.state == "CA"
    end

    test "creates valid event with venue" do
      event = insert(:event)

      assert event.id
      assert event.title =~ "Test Event"
      assert event.tagline == "An awesome test event"
      assert event.visibility == :public
      assert event.theme == :minimal
      assert event.venue_id

      # Verify the venue association was created
      venue = EventasaurusApp.Repo.preload(event, :venue).venue
      assert venue.name =~ "Test Venue"
    end

    test "creates valid event user relationship" do
      event_user = insert(:event_user)

      assert event_user.id
      assert event_user.role == "organizer"
      assert event_user.event_id
      assert event_user.user_id
    end

    test "creates valid event participant" do
      participant = insert(:event_participant)

      assert participant.id
      assert participant.role == :ticket_holder
      assert participant.status == :accepted
      assert participant.source == "direct_registration"
      assert participant.event_id
      assert participant.user_id
    end
  end

  describe "factory variations" do
    test "creates past event" do
      past_event = insert(:past_event)

      assert DateTime.compare(past_event.start_at, DateTime.utc_now()) == :lt
      assert DateTime.compare(past_event.ends_at, DateTime.utc_now()) == :lt
    end

    test "creates private event" do
      private_event = insert(:private_event)

      assert private_event.visibility == :private
    end

    test "creates online event without venue" do
      online_event = insert(:online_event)

      assert is_nil(online_event.venue_id)
    end

    test "creates themed event" do
      themed_event = insert(:themed_event)

      assert themed_event.theme == :cosmic
      assert themed_event.theme_customizations["colors"]["primary"] == "#6366f1"
    end
  end
end
