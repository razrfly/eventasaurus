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

export default { ScrollReveal };
