# Phased Implementation Plan: Connecting Public Events with Friend Coordination

## Executive Summary

Instead of creating complex "private events" that reference public events, we'll implement a simpler "Attendance Groups" feature that directly addresses the user need: **"I want to go to this public event with my friends."**

## Problem Statement

Users discover public events but lack a seamless way to coordinate attendance with friends. The current proposed solution of creating full "private events" is overengineered and confusing.

## Phased Approach

### Phase 1: MVP - Attendance Groups (1 week)
**Goal:** Enable users to invite friends to attend public events together

#### User Experience Flow

1. **Discovery:** User browses public event page
2. **Action:** Clicks "Invite Friends to Join" button (prominent, next to "I'm Going" button)
3. **Selection:** Modal opens showing:
   - Friend list with search
   - Multi-select checkboxes
   - Optional personal message field
   - "Send Invitations" button
4. **Notification:** Invited friends receive:
   - In-app notification
   - Email: "Sarah invited you to join them at [Event Name]"
5. **Response:** Friends can:
   - Accept → Added to attendance group
   - Decline → Invitation marked as declined
   - View event details before deciding
6. **Visibility:** Event page shows:
   - "Going with 3 friends" badge for group organizer
   - Friend avatars for accepted invitations
   - "Join Sarah's group" option for mutual friends

#### Database Schema (Minimal)

```sql
-- Lightweight attendance coordination
CREATE TABLE attendance_groups (
  id BIGSERIAL PRIMARY KEY,
  public_event_id BIGINT NOT NULL REFERENCES public_events(id),
  organizer_id BIGINT NOT NULL REFERENCES users(id),
  message TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE attendance_group_invites (
  id BIGSERIAL PRIMARY KEY,
  attendance_group_id BIGINT NOT NULL REFERENCES attendance_groups(id),
  invitee_id BIGINT NOT NULL REFERENCES users(id),
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, accepted, declined
  responded_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_attendance_groups_event ON attendance_groups(public_event_id);
CREATE INDEX idx_attendance_groups_organizer ON attendance_groups(organizer_id);
CREATE INDEX idx_group_invites_invitee ON attendance_group_invites(invitee_id);
```

#### UI Components

```elixir
# In PublicEventShowLive template
<div class="event-actions">
  <button phx-click="toggle_attendance" class="btn-primary">
    <%= if @user_attending?, do: "Going ✓", else: "I'm Going" %>
  </button>

  <%= if @current_user do %>
    <button phx-click="open_invite_friends" class="btn-secondary">
      <.icon name="hero-user-group" /> Invite Friends
    </button>
  <% end %>

  <%= if @user_attendance_group do %>
    <div class="attendance-group-badge">
      Going with <%= length(@user_attendance_group.accepted_invites) %> friends
      <div class="friend-avatars">
        <%= for friend <- @user_attendance_group.accepted_friends do %>
          <img src={friend.avatar_url} alt={friend.name} class="friend-avatar" />
        <% end %>
      </div>
    </div>
  <% end %>
</div>

<!-- Invite Friends Modal -->
<.modal :if={@show_invite_modal} id="invite-friends-modal">
  <.header>
    Invite friends to <%= @event.display_title %>
  </.header>

  <.simple_form for={@invite_form} phx-submit="send_invitations">
    <div class="friend-list">
      <%= for friend <- @friends do %>
        <label class="friend-item">
          <input type="checkbox" name="friend_ids[]" value={friend.id} />
          <img src={friend.avatar_url} />
          <span><%= friend.name %></span>
        </label>
      <% end %>
    </div>

    <.input
      field={@invite_form[:message]}
      type="textarea"
      label="Add a message (optional)"
      placeholder="Hey! Want to go to this together?"
    />

    <:actions>
      <.button>Send Invitations</.button>
    </:actions>
  </.simple_form>
</.modal>
```

#### Backend Implementation

```elixir
defmodule EventasaurusApp.AttendanceGroups do
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.AttendanceGroups.{AttendanceGroup, GroupInvite}

  def create_group_with_invites(organizer_id, event_id, friend_ids, message) do
    Repo.transaction(fn ->
      # Create the attendance group
      {:ok, group} = %AttendanceGroup{}
        |> AttendanceGroup.changeset(%{
          organizer_id: organizer_id,
          public_event_id: event_id,
          message: message
        })
        |> Repo.insert()

      # Create invitations
      invites = Enum.map(friend_ids, fn friend_id ->
        %{
          attendance_group_id: group.id,
          invitee_id: friend_id,
          status: "pending",
          inserted_at: NaiveDateTime.utc_now(),
          updated_at: NaiveDateTime.utc_now()
        }
      end)

      {_count, _} = Repo.insert_all(GroupInvite, invites)

      # Send notifications (async)
      send_invitation_notifications(group, friend_ids)

      group
    end)
  end

  def accept_invitation(invite_id, user_id) do
    invite = Repo.get_by!(GroupInvite, id: invite_id, invitee_id: user_id)

    invite
    |> GroupInvite.changeset(%{
      status: "accepted",
      responded_at: NaiveDateTime.utc_now()
    })
    |> Repo.update()
  end

  def get_user_group_for_event(user_id, event_id) do
    Repo.one(
      from ag in AttendanceGroup,
        where: ag.organizer_id == ^user_id and ag.public_event_id == ^event_id,
        preload: [invites: :invitee]
    )
  end
end
```

### Phase 2: Enhanced Coordination (2 weeks)
**Goal:** Add group coordination features without creating separate events

#### Features
1. **Group Chat**
   - Simple message thread for accepted group members
   - Push notifications for new messages
   - Mute/unmute options

2. **Meeting Logistics**
   - "Where should we meet?" with location suggestions
   - "When should we arrive?" with time voting
   - Carpool coordination with seat availability

3. **Group Visibility**
   - See other attendance groups for the event (privacy controlled)
   - "Join existing group" for mutual friends
   - Total "going with friends" counter

#### Database Additions

```sql
-- Group coordination features
CREATE TABLE attendance_group_messages (
  id BIGSERIAL PRIMARY KEY,
  attendance_group_id BIGINT NOT NULL REFERENCES attendance_groups(id),
  sender_id BIGINT NOT NULL REFERENCES users(id),
  message TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE attendance_group_logistics (
  id BIGSERIAL PRIMARY KEY,
  attendance_group_id BIGINT NOT NULL REFERENCES attendance_groups(id),
  meeting_location TEXT,
  meeting_time TIMESTAMP,
  carpool_available_seats INTEGER,
  notes TEXT,
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

### Phase 3: Private Event Creation (Future - Only if Needed)
**Goal:** Allow creation of separate private events (pre-party, after-party) linked to public events

This phase would only be implemented if user research shows that Phases 1-2 don't satisfy needs. It would involve:

- Full private event creation with separate details
- Linking mechanism to public events
- Separate invitation system
- Independent event management

## Key Benefits of This Approach

1. **Simplicity:** Users understand "Invite Friends" immediately
2. **Direct Solution:** Addresses the core need without overengineering
3. **Incremental:** Can stop at Phase 1 if it satisfies users
4. **Clear Mental Model:** Not confusing "private events" with "friend groups"
5. **Faster Implementation:** Phase 1 can be live in 1 week
6. **Lower Risk:** Simpler schema means fewer edge cases
7. **Better UX:** One-click invitation vs. creating entire events

## Success Metrics

### Phase 1
- % of public event attendees who create attendance groups
- Average group size
- Invitation acceptance rate
- Time from invitation to response

### Phase 2
- Group chat engagement rate
- Logistics feature usage
- User satisfaction scores
- Reduction in "where/when to meet" confusion

## Technical Considerations

### Prerequisites (Already Needed)
- Friend system (relationships between users)
- Notification system (in-app and email)
- Basic authorization (who can see what)

### Performance
- Eager load attendance groups when showing events
- Cache friend lists for quick modal loading
- Async notification sending
- Pagination for large friend lists

### Privacy & Security
- Users can only invite their confirmed friends
- Groups are visible based on privacy settings
- No access to group details without invitation acceptance

## Migration from Current Implementation

Since the current implementation is incomplete (35% per audit), we recommend:

1. **Keep:** Basic event display and navigation
2. **Remove:** Complex EventPlan junction table
3. **Replace:** "Going with Friends" with simpler "Invite Friends"
4. **Add:** Attendance groups as described above

## Implementation Timeline

### Week 1: Phase 1 MVP
- Day 1-2: Database schema and migrations
- Day 3-4: Backend logic and contexts
- Day 5-6: Frontend UI components
- Day 7: Testing and polish

### Week 2-3: Phase 2 (if approved)
- Week 2: Group chat and messaging
- Week 3: Logistics coordination features

### Future: Phase 3 (only if needed)
- Full specification pending user feedback on Phases 1-2

## Conclusion

This phased approach delivers immediate value with Phase 1's simple "Invite Friends" feature, while leaving room for enhancement based on actual user needs. It avoids the complexity of managing two types of events while solving the core user problem of coordinating event attendance with friends.