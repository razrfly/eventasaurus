const ScrollReveal = {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
          }
        });
      },
      { threshold: 0.1 }
    );

    this.el.querySelectorAll(".scroll-reveal").forEach((el) => {
      this.observer.observe(el);
    });
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },
};

const scenarios = {
  private:  "Just you. Plan it before anyone else knows — ideal for surprises and early-stage ideas.",
  friends:  "Your inner circle. The 5–8 people who always say yes to film night.",
  extended: "Friends of friends. Great for bigger gatherings and neighbourhood events.",
  open:     "Anyone nearby with matching interests. Local bars and venues love this one.",
};

const PrivacyCircles = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const group = e.target.closest("[data-ring]");
      if (!group) return;
      const ring = group.dataset.ring;
      this.el.classList.add("has-selection");
      this.el.querySelectorAll("[data-ring]").forEach(g => g.classList.remove("ring-active"));
      group.classList.add("ring-active");
      const display = document.getElementById("privacy-scenario");
      if (display) display.textContent = scenarios[ring] ?? "";
    });
  },
};

export default { ScrollReveal, PrivacyCircles };
