// Countdown Timer Hook for threshold event deadlines
// Provides real-time countdown updates without server polling

export const CountdownTimer = {
  mounted() {
    this.startCountdown();
  },

  updated() {
    // Restart countdown if deadline changes
    this.startCountdown();
  },

  destroyed() {
    this.stopCountdown();
  },

  startCountdown() {
    // Clear any existing interval
    this.stopCountdown();

    const deadline = this.el.dataset.deadline;
    if (!deadline) return;

    this.deadlineDate = new Date(deadline);

    // Validate that the deadline is a valid date
    if (isNaN(this.deadlineDate.getTime())) {
      console.error('Invalid deadline format:', deadline);
      return;
    }

    // Initial render
    this.updateDisplay();

    // Update every second
    this.interval = setInterval(() => {
      this.updateDisplay();
    }, 1000);
  },

  stopCountdown() {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }
  },

  updateDisplay() {
    const now = new Date();
    const diff = this.deadlineDate - now;

    if (diff <= 0) {
      this.stopCountdown();
      this.renderExpired();
      return;
    }

    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    const seconds = Math.floor((diff % (1000 * 60)) / 1000);

    // Determine urgency level for styling
    const hoursRemaining = diff / (1000 * 60 * 60);
    let urgencyClass = "text-gray-600"; // Default
    if (hoursRemaining <= 1) {
      urgencyClass = "text-red-600 font-bold animate-pulse";
    } else if (hoursRemaining <= 24) {
      urgencyClass = "text-orange-600 font-semibold";
    } else if (hoursRemaining <= 72) {
      urgencyClass = "text-amber-600";
    }

    this.renderCountdown(days, hours, minutes, seconds, urgencyClass);
  },

  renderCountdown(days, hours, minutes, seconds, urgencyClass) {
    const daysEl = this.el.querySelector('[data-days]');
    const hoursEl = this.el.querySelector('[data-hours]');
    const minutesEl = this.el.querySelector('[data-minutes]');
    const secondsEl = this.el.querySelector('[data-seconds]');
    const textEl = this.el.querySelector('[data-text]');

    // Update individual elements if they exist (segmented display)
    if (daysEl) daysEl.textContent = String(days).padStart(2, '0');
    if (hoursEl) hoursEl.textContent = String(hours).padStart(2, '0');
    if (minutesEl) minutesEl.textContent = String(minutes).padStart(2, '0');
    if (secondsEl) secondsEl.textContent = String(seconds).padStart(2, '0');

    // Update text element if it exists (simple text display)
    if (textEl) {
      const parts = [];
      if (days > 0) parts.push(`${days}d`);
      if (hours > 0 || days > 0) parts.push(`${hours}h`);
      if (minutes > 0 || hours > 0 || days > 0) parts.push(`${minutes}m`);
      parts.push(`${seconds}s`);

      textEl.textContent = parts.join(' ');

      // Update urgency class
      textEl.className = textEl.className.replace(/text-(gray|red|orange|amber)-\d{3}/g, '');
      textEl.className = textEl.className.replace(/(font-bold|font-semibold|animate-pulse)/g, '');
      textEl.className = `${textEl.className.trim()} ${urgencyClass}`;
    }

    // Update container urgency styling
    this.el.dataset.urgency = this.getUrgencyLevel(days, hours);
  },

  renderExpired() {
    const textEl = this.el.querySelector('[data-text]');
    const daysEl = this.el.querySelector('[data-days]');
    const hoursEl = this.el.querySelector('[data-hours]');
    const minutesEl = this.el.querySelector('[data-minutes]');
    const secondsEl = this.el.querySelector('[data-seconds]');

    if (textEl) {
      textEl.textContent = 'Deadline has passed';
      textEl.className = `${textEl.className.trim()} text-red-600 font-bold`;
    }

    // Set segments to zero
    if (daysEl) daysEl.textContent = '00';
    if (hoursEl) hoursEl.textContent = '00';
    if (minutesEl) minutesEl.textContent = '00';
    if (secondsEl) secondsEl.textContent = '00';

    this.el.dataset.expired = 'true';
  },

  getUrgencyLevel(days, hours) {
    const totalHours = days * 24 + hours;
    if (totalHours <= 1) return 'critical';
    if (totalHours <= 24) return 'urgent';
    if (totalHours <= 72) return 'warning';
    return 'normal';
  }
};

export default { CountdownTimer };
