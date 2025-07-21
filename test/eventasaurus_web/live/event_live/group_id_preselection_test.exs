defmodule EventasaurusWeb.EventLive.GroupIdPreselectionTest do
  use EventasaurusWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  
  alias EventasaurusApp.Groups
  alias EventasaurusApp.Accounts
  
  setup do
    # Create a test user
    {:ok, user} = Accounts.register_user(%{
      email: "test@example.com",
      password: "password123456"
    })
    
    # Create a test group with the user as creator
    {:ok, group} = Groups.create_group_with_creator(%{
      name: "Test Group",
      slug: "test-group"
    }, user)
    
    %{user: user, group: group}
  end
  
  describe "group_id preselection from URL params" do
    test "correctly preselects group when group_id is passed as string", %{conn: conn, user: user, group: group} do
      # Log in the user
      conn = log_in_user(conn, user)
      
      # Navigate to new event page with group_id as string parameter
      {:ok, view, _html} = live(conn, "/events/new?group_id=#{group.id}")
      
      # Check that the group is preselected in the form
      assert has_element?(view, "select[name='event[group_id]'] option[selected][value='#{group.id}']")
    end
    
    test "does not preselect group if user is not a member", %{conn: conn, group: group} do
      # Create another user who is not a member of the group
      {:ok, other_user} = Accounts.register_user(%{
        email: "other@example.com",
        password: "password123456"
      })
      
      # Log in as the other user
      conn = log_in_user(conn, other_user)
      
      # Navigate to new event page with group_id parameter
      {:ok, view, _html} = live(conn, "/events/new?group_id=#{group.id}")
      
      # Check that no group is preselected
      assert has_element?(view, "select[name='event[group_id]'] option[selected][value='']")
    end
    
    test "handles invalid group_id gracefully", %{conn: conn, user: user} do
      # Log in the user
      conn = log_in_user(conn, user)
      
      # Navigate with invalid group_id
      {:ok, view, _html} = live(conn, "/events/new?group_id=invalid")
      
      # Should not crash and should have no group selected
      assert has_element?(view, "select[name='event[group_id]'] option[selected][value='']")
    end
  end
end