// CSP-safe hooks to replace inline event handlers and styles
// These hooks eliminate inline JavaScript and CSS to comply with strict CSP policies

const CSPSafeHooks = {
  // Hook for image fallback handling (replaces inline onerror)
  ImageFallback: {
    mounted() {
      this.handleError = () => {
        this.el.style.display = 'none';
        const fallbackId = this.el.dataset.fallbackId;
        const fallbackEl = document.getElementById(fallbackId);
        if (fallbackEl) {
          fallbackEl.style.display = 'block';
        }
      };
      
      this.el.addEventListener('error', this.handleError);
    },
    
    destroyed() {
      this.el.removeEventListener('error', this.handleError);
    }
  },

  // Hook for clipboard copy functionality (replaces inline onclick)
  ClipboardCopy: {
    mounted() {
      this.handleClick = async () => {
        const targetId = this.el.dataset.targetId;
        const targetEl = targetId ? document.getElementById(targetId) : this.el.previousElementSibling;
        
        if (targetEl && targetEl.value) {
          try {
            await navigator.clipboard.writeText(targetEl.value);
            const originalText = this.el.innerText;
            this.el.innerText = 'Copied!';
            setTimeout(() => {
              this.el.innerText = originalText;
            }, 2000);
          } catch (err) {
            console.error('Failed to copy text:', err);
          }
        }
      };
      
      this.el.addEventListener('click', this.handleClick);
    },
    
    destroyed() {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  // Hook for print functionality (replaces inline onclick)
  PrintPage: {
    mounted() {
      this.handleClick = () => {
        window.print();
      };
      
      this.el.addEventListener('click', this.handleClick);
    },
    
    destroyed() {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  // Hook for dynamic width progress bars (replaces inline style)
  ProgressBar: {
    mounted() {
      const width = this.el.dataset.progressWidth || '0';
      this.el.style.setProperty('--progress-width', `${width}%`);
    },
    
    updated() {
      const width = this.el.dataset.progressWidth || '0';
      this.el.style.setProperty('--progress-width', `${width}%`);
    }
  },

  // Hook for dynamic display toggling (replaces inline style for display)
  DisplayToggle: {
    mounted() {
      const show = this.el.dataset.show === 'true';
      this.el.style.display = show ? 'block' : 'none';
    },
    
    updated() {
      const show = this.el.dataset.show === 'true';
      this.el.style.display = show ? 'block' : 'none';
    }
  },

  // Hook for dynamic background images (replaces inline style with background-image)
  BackgroundImage: {
    mounted() {
      const imageUrl = this.el.dataset.backgroundImage;
      if (imageUrl) {
        this.el.style.backgroundImage = `url(${imageUrl})`;
      }
    },
    
    updated() {
      const imageUrl = this.el.dataset.backgroundImage;
      if (imageUrl) {
        this.el.style.backgroundImage = `url(${imageUrl})`;
      }
    }
  },

  // Hook for mobile menu close button
  MobileMenuClose: {
    mounted() {
      this.handleClick = () => {
        const mobileMenuButton = document.getElementById('mobile-menu-button');
        if (mobileMenuButton) {
          mobileMenuButton.click();
        }
      };
      
      this.el.addEventListener('click', this.handleClick);
    },
    
    destroyed() {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  // Hook for copy link button on event pages
  EventCopyLink: {
    mounted() {
      this.handleClick = async (e) => {
        e.preventDefault();
        const url = this.el.getAttribute('data-clipboard-text');
        if (url) {
          try {
            await navigator.clipboard.writeText(url);
            alert('Link copied to clipboard!');
          } catch (err) {
            console.error('Could not copy text: ', err);
          }
        }
      };
      
      this.el.addEventListener('click', this.handleClick);
    },
    
    destroyed() {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  // Hook for mobile secondary actions toggle on event pages
  MobileActionsToggle: {
    mounted() {
      this.handleClick = () => {
        const secondaryActions = document.querySelectorAll('.mobile-secondary-actions');
        const showMoreText = document.getElementById('show-more-text');
        const showMoreIcon = document.getElementById('show-more-icon');

        // Check if all required elements exist
        if (!secondaryActions.length || !showMoreText || !showMoreIcon) {
          console.warn('Mobile toggle: Missing required DOM elements');
          return;
        }

        const isExpanded = this.el.getAttribute('aria-expanded') === 'true';

        // Toggle visibility with proper animation
        secondaryActions.forEach(action => {
          if (isExpanded) {
            action.classList.remove('show');
          } else {
            action.classList.add('show');
          }
        });

        // Update accessibility attributes and UI
        this.el.setAttribute('aria-expanded', !isExpanded);
        showMoreText.textContent = isExpanded ? 'Share & Calendar' : 'Hide';
        showMoreIcon.style.transform = isExpanded ? 'rotate(0deg)' : 'rotate(180deg)';
      };
      
      this.el.addEventListener('click', this.handleClick);
    },
    
    destroyed() {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  // Hook for development mode quick login dropdown
  DevQuickLogin: {
    mounted() {
      this.handleChange = () => {
        if (this.el.value) {
          // Submit the form when a user is selected
          this.el.closest('form').submit();
        }
      };
      
      this.el.addEventListener('change', this.handleChange);
    },
    
    destroyed() {
      this.el.removeEventListener('change', this.handleChange);
    }
  },

  // Hook for theme switching on event pages
  ThemeSwitcher: {
    mounted() {
      this.handleThemeSwitch = (e) => {
        const newTheme = e.detail.theme;

        // Find existing theme CSS link
        const existingThemeLink = document.querySelector('link[href*="/themes/"][href$=".css"]');

        if (newTheme === 'minimal') {
          // For minimal theme, just remove any existing theme CSS
          if (existingThemeLink) {
            existingThemeLink.remove();
          }
        } else {
          // For other themes, create or update the theme CSS link
          const newHref = `/themes/${newTheme}.css`;

          if (existingThemeLink) {
            // Update existing link
            existingThemeLink.href = newHref;
          } else {
            // Create new link
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = newHref;
            document.head.appendChild(link);
          }
        }

        // Handle dark/light mode for navbar and protected UI elements
        const htmlElement = document.documentElement;
        const darkThemes = ['cosmic']; // Only cosmic is currently a dark theme

        if (darkThemes.includes(newTheme)) {
          htmlElement.classList.add('dark');
        } else {
          htmlElement.classList.remove('dark');
        }

        // Update body class for theme-specific styling
        document.body.className = document.body.className.replace(/\btheme-\w+\b/g, '');
        if (newTheme !== 'minimal') {
          document.body.classList.add(`theme-${newTheme}`);
        }

        console.log(`Theme switched to: ${newTheme}`);
      };
      
      window.addEventListener("phx:switch-theme-css", this.handleThemeSwitch);
    },
    
    destroyed() {
      window.removeEventListener("phx:switch-theme-css", this.handleThemeSwitch);
    }
  }
};

export default CSPSafeHooks;