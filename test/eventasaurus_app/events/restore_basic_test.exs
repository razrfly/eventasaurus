defmodule EventasaurusApp.Events.RestoreBasicTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events.Restore
  alias EventasaurusApp.Events.{Event, SoftDelete}
  alias EventasaurusApp.Repo

  import Ecto.Query

  describe "Restore module compilation and basic functionality" do
    test "module compiles and can be loaded" do
      # Test that the module loads without errors
      assert Code.ensure_loaded?(EventasaurusApp.Events.Restore)
    end

    test "get_restoration_stats/0 returns expected structure" do
      stats = Restore.get_restoration_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_restored)
      assert Map.has_key?(stats, :restored_in_period)
      assert Map.has_key?(stats, :period_days)
      assert Map.has_key?(stats, :cutoff_date)

      # Test default values
      assert stats.period_days == 30
      assert stats.total_restored == 0
      assert stats.restored_in_period == 0
    end

    test "get_restoration_stats/1 respects custom options" do
      stats = Restore.get_restoration_stats(days_back: 7)

      assert stats.period_days == 7
      assert is_struct(stats.cutoff_date, DateTime)
    end

    test "eligible_for_restoration?/1 handles non-existent event" do
      assert {:error, :event_not_found} = Restore.eligible_for_restoration?(99999)
    end

    test "restore_event/2 handles non-existent event" do
      assert {:error, :event_not_found} = Restore.restore_event(99999, 1)
    end

    test "restore_event/2 handles non-existent user" do
      # This will fail on user lookup, which is expected behavior
      assert {:error, :user_not_found} = Restore.restore_event(1, 99999)
    end
  end
end
