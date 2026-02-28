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

const MobileNav = {
  mounted() {
    const toggle = this.el.querySelector("[data-mobile-toggle]");
    const menu   = this.el.querySelector("[data-mobile-menu]");
    const close  = this.el.querySelector("[data-mobile-close]");
    if (!toggle || !menu) return;
    const open   = () => {
      menu.classList.remove("hidden");
      menu.setAttribute("aria-hidden", "false");
      toggle.setAttribute("aria-expanded", "true");
      document.body.style.overflow = "hidden";
    };
    const close_ = () => {
      menu.classList.add("hidden");
      menu.setAttribute("aria-hidden", "true");
      toggle.setAttribute("aria-expanded", "false");
      document.body.style.overflow = "";
      toggle.focus();
    };
    toggle.addEventListener("click", open);
    if (close) close.addEventListener("click", close_);
  },
};

export default { ScrollReveal, PrivacyCircles, MobileNav };
