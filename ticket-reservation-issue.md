# Ticket Availability Issue: Immediate Inventory Deduction During Checkout

## Problem Description

Currently, when users start the checkout process for ticketed events, the system immediately creates a "pending" order and decrements available ticket inventory. This causes tickets to appear unavailable to other users even before payment is completed, leading to poor user experience and potential lost sales.

### Current Behavior
1. User clicks "Buy Ticket" → `create_checkout_session()` called
2. Order created with `status: "pending"` → Available inventory decremented immediately  
3. Stripe checkout session created → User redirected to payment page
4. If payment succeeds → Order status changed to "confirmed"
5. If payment fails/abandoned → Order remains "pending" for 1 hour, then ignored in availability calculations

### Key Code Location
The availability calculation logic in `lib/eventasaurus_app/ticketing.ex:200-217`:

```elixir
def count_sold_tickets(ticket_id) do
  one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
  
  Order
  |> where([o], o.ticket_id == ^ticket_id)
  |> where([o],
    o.status == "confirmed" or
    (o.status == "pending" and o.inserted_at > ^one_hour_ago)  # This line causes immediate inventory lock
  )
  # ...
end
```

## Current Issues

1. **Immediate Inventory Lock**: Tickets show as unavailable the moment checkout begins
2. **1-Hour Lock Period**: Abandoned shopping carts block inventory for up to 1 hour
3. **Poor User Experience**: Users see "sold out" when tickets may become available again
4. **Potential Lost Sales**: Real buyers may be turned away by artificially reduced availability
5. **Race Conditions**: Multiple users might simultaneously reach payment step for the last ticket

## Impact

- Users abandon checkout thinking events are sold out
- Event organizers may miss sales opportunities
- Support tickets from confused customers
- Reduced conversion rates on ticket sales

## System Architecture Context

**Positive aspects of current system:**
- Uses row locking (`lock: "FOR UPDATE"`) to prevent overselling
- Transactional approach ensures data consistency
- Comprehensive error handling and rollback logic
- Well-structured with proper separation of concerns

**The core issue is UX clarity around reservation states, not technical architecture.**

## Proposed Solutions

### Option 1: Soft Reservations with Enhanced Status Tracking ⭐ (Recommended)

**Implementation:**
- Keep current immediate order creation (maintains oversell protection)
- Add `reservation_status` enum field to orders: `reserved`, `payment_processing`, `confirmed`, `expired`
- Update UI to show different states:
  - "Reserved for you (expires in 14:32)" - for current user
  - "X tickets available (Y reserved by others)" - for other users
  - "Processing payment..." - during payment flow
- Add background job to cleanup expired reservations every 5 minutes

**Benefits:**
- Maintains existing oversell protection
- Improves user experience with clear reservation states  
- Minimal code changes required
- Backward compatible

### Option 2: Two-Phase Commit Pattern

**Implementation:**
- Create orders with `status: "draft"` initially (don't count against inventory)
- Only mark `status: "pending"` when Stripe payment intent is created
- Requires webhook handling to catch payment processing start

**Benefits:**
- Only reserves inventory when payment actually begins
- More accurate availability display

**Drawbacks:**
- More complex webhook handling
- Potential race conditions between draft→pending transition

### Option 3: Shorter Reservation Window

**Implementation:**
- Reduce reservation window from 1 hour to 10-15 minutes
- Add countdown timer in UI showing reservation expiry
- More frequent cleanup of abandoned orders

**Benefits:**
- Faster inventory turnover
- Simple implementation

**Drawbacks:**
- May pressure users to complete checkout too quickly
- Still has fundamental UX issue

### Option 4: Optimistic Availability

**Implementation:**
- Don't decrement inventory until payment confirmation
- Check availability again at final payment step
- Handle oversells gracefully with waitlist/alternatives

**Benefits:**
- Most accurate availability display
- Best user experience

**Drawbacks:**
- Risk of overselling
- Complex oversell handling required
- May disappoint users who reach payment step

## Recommendation

**Option 1 (Soft Reservations)** is recommended because it:
- Preserves the robust oversell protection already built into the system
- Provides clear user feedback about reservation states
- Requires minimal changes to existing codebase
- Maintains transactional integrity and row locking benefits

## Implementation Checklist

- [ ] Add `reservation_status` enum to Order schema
- [ ] Update `count_sold_tickets/1` to handle reservation states  
- [ ] Modify checkout UI to show reservation status and countdown
- [ ] Create background job for reservation cleanup
- [ ] Update order creation functions to set appropriate reservation status
- [ ] Add reservation expiry logic
- [ ] Update availability display components
- [ ] Add tests for new reservation states
- [ ] Update API responses to include reservation information

## Background Cleanup Implementation

For the recommended Option 1, here are the detailed approaches for implementing the "cleanup expired reservations every 5 minutes" functionality:

### Approach 1: Oban Background Jobs ⭐ (Recommended)

**Add Oban dependency:**
```elixir
# mix.exs
defp deps do
  [
    {:oban, "~> 2.17"},
    # ... existing deps
  ]
end
```

**Create cleanup worker:**
```elixir
# lib/eventasaurus_app/workers/reservation_cleanup_worker.ex
defmodule EventasaurusApp.Workers.ReservationCleanupWorker do
  use Oban.Worker, queue: :cleanup, max_attempts: 3

  alias EventasaurusApp.Ticketing
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Order
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting reservation cleanup")
    
    # Find expired reservations (older than 15 minutes)
    fifteen_minutes_ago = DateTime.add(DateTime.utc_now(), -15, :minute)
    
    expired_orders = 
      Order
      |> where([o], o.status == "pending")
      |> where([o], o.inserted_at < ^fifteen_minutes_ago)
      |> where([o], is_nil(o.stripe_session_id) or o.stripe_session_id == "")
      |> Repo.all()

    count = length(expired_orders)
    
    if count > 0 do
      # Update expired orders to "expired" status
      Enum.each(expired_orders, fn order ->
        case Ticketing.expire_order(order) do
          {:ok, _} -> 
            Logger.debug("Expired order #{order.id}")
          {:error, reason} -> 
            Logger.error("Failed to expire order #{order.id}: #{inspect(reason)}")
        end
      end)
      
      Logger.info("Cleaned up #{count} expired reservations")
    end

    :ok
  end
end
```

**Configure Oban with cron scheduling:**
```elixir
# config/config.exs
config :eventasaurus_app, Oban,
  repo: EventasaurusApp.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, 
     crontab: [
       {"*/5 * * * *", EventasaurusApp.Workers.ReservationCleanupWorker}
     ]}
  ],
  queues: [cleanup: 2]
```

**Add expire_order function to Ticketing context:**
```elixir
# In lib/eventasaurus_app/ticketing.ex
def expire_order(%Order{} = order) do
  case Repo.transaction(fn ->
    # Preload ticket for broadcasting
    order_with_ticket = Repo.preload(order, :ticket)

    # Update order status
    {:ok, expired_order} =
      order
      |> Order.changeset(%{status: "expired"})
      |> Repo.update()

    # Broadcast updates
    maybe_broadcast_order_update(expired_order, :expired)
    maybe_broadcast_ticket_update(order_with_ticket.ticket, :order_expired)

    expired_order
  end) do
    {:ok, expired_order} -> {:ok, expired_order}
    {:error, reason} -> {:error, reason}
  end
end
```

**Why Oban is recommended:**
- **Battle-tested** - Standard for Phoenix background jobs
- **Reliability** - Built-in retries, error handling, and monitoring
- **Observability** - Web UI to monitor job execution
- **Scalability** - Handles increasing load as app grows
- **Database-backed** - Jobs persist across restarts

### Approach 2: GenServer with Scheduled Messages

**Create cleanup GenServer:**
```elixir
# lib/eventasaurus_app/reservation_cleanup.ex
defmodule EventasaurusApp.ReservationCleanup do
  use GenServer
  require Logger

  @cleanup_interval :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp perform_cleanup do
    Logger.info("Running reservation cleanup")
    # Same cleanup logic as Oban worker
    # ... cleanup implementation
  end
end
```

**Add to supervision tree:**
```elixir
# lib/eventasaurus_app/application.ex
def start(_type, _args) do
  children = [
    # ... existing children
    EventasaurusApp.ReservationCleanup
  ]
end
```

### Approach 3: Quantum Scheduler (Cron-like)

**Add Quantum dependency:**
```elixir
# mix.exs
{:quantum, "~> 3.0"}
```

**Create scheduler:**
```elixir
# lib/eventasaurus_app/scheduler.ex
defmodule EventasaurusApp.Scheduler do
  use Quantum, otp_app: :eventasaurus_app
end

# config/config.exs
config :eventasaurus_app, EventasaurusApp.Scheduler,
  jobs: [
    cleanup_reservations: [
      schedule: "*/5 * * * *",
      task: {EventasaurusApp.Ticketing, :cleanup_expired_reservations, []}
    ]
  ]
end
```

### Cleanup Logic Details

The cleanup process should:

1. **Find expired reservations** (15 minutes old, configurable)
2. **Update status** from "pending" to "expired" 
3. **Broadcast updates** so UI reflects availability changes
4. **Log activity** for monitoring and debugging
5. **Handle errors gracefully** with retries

**Key considerations:**
- Only expire orders without Stripe session IDs (never started payment)
- Preserve orders that have begun payment processing
- Use database transactions for consistency
- Broadcast availability changes for real-time UI updates
- Monitor cleanup performance and success rates

## Files That Need Changes

- `/lib/eventasaurus_app/ticketing.ex` - Core ticketing logic
- `/lib/eventasaurus/events/order.ex` - Order model schema
- `/lib/eventasaurus_web/live/checkout_live.ex` - Checkout UI
- `/lib/eventasaurus_web/components/ticket_modal.ex` - Ticket display components
- Database migration for new reservation_status field

## Testing Considerations

- Race condition testing with concurrent checkouts
- Reservation expiry timing
- UI state transitions
- Background job reliability
- Webhook handling for payment status changes

---

**Priority:** High - Affects user experience and potential revenue
**Complexity:** Medium - Well-defined changes to existing system
**Risk:** Low - Additive changes that preserve existing protections