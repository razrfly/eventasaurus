# Eventasaurus Pricing and Ticketing PRD

**Version:** 2025.06
**Author:** Holden
**Purpose:** Define a flexible pricing and ticketing model to support various pricing strategies for events.

---

## 🌟 Goal and Context

* **Objective:** Introduce flexible pricing options for event tickets while maintaining a simple initial implementation.

---

## 📦 Core Data Models

### 1. Event

Represents the event details.

Fields:

* `id`
* `title`
* `starts_at`, `ends_at`
* `status` (e.g., `confirmed`, `polling`, `threshold`)
* `canceled_at`
* `threshold_count`, `polling_deadline`

### 2. Ticket

Represents the different types of tickets available for an event.

Fields:

* `id`
* `event_id`
* `title`
* `base_price_cents` (fixed price)
* `minimum_price_cents` (floor price for flexible models)
* `suggested_price_cents` (optional, for suggested contributions)
* `pricing_model` (e.g., `fixed`, `flexible`, `dynamic`)
* `currency` (default: `usd`)
* `quantity`
* `starts_at`, `ends_at` (availability window)
* `created_at`, `updated_at`

### 3. Order

Tracks a single purchase of one ticket type.

Fields:

* `id`
* `user_id`
* `event_id`
* `ticket_id`
* `quantity`
* `subtotal_cents`, `total_cents`
* `currency`
* `status` (`pending`, `confirmed`, `canceled`)
* `stripe_session_id`, `payment_reference`
* `created_at`, `updated_at`, `confirmed_at`

---

## 🔄 Workflow & State Transitions

1. **Event Creation**

   * Organizer defines event details and ticket types.
   * Status defaults to `:confirmed`.

2. **User Checkout Flow**

   * User selects a ticket type and creates an `Order` in the `pending` state.
   * Payment is processed via Stripe.
   * On successful payment, the `Order` becomes `confirmed`.

3. **Flexible Pricing Behavior**

   * If using a flexible pricing model, the user can choose an amount above the minimum price.
   * Suggested pricing can guide the user on an ideal amount.

4. **Tippable Feature**

   * If enabled, users can add a tip on top of their ticket price.

5. **Failed or Abandoned Payment**

   * Orders remain `pending` and can be retried or cleaned up after a certain period.

---

## ✅ Benefits

* Provides a foundation for more complex pricing models in the future.
* Keeps the initial implementation straightforward and user-friendly.

---

## 🚀 Future Enhancements

| Feature         | Description                                | Status |
| --------------- | ------------------------------------------ | ------ |
| Dynamic Pricing | Adjust price based on participant count    | Future |
| Tiered Pricing  | Different price levels based on thresholds | Future |
| Group Discounts | Offer discounts for larger groups          | Future |
| Surge Pricing   | Increase prices during high demand         | Future |

---

Let me know if there are any additional details you’d like to include or if you'd like this turned into a migration file!
