// UI interaction hooks for modals, focus management, images, and keyboard navigation
// Extracted from app.js for better organization

// ModalCleanup hook to ensure overflow-hidden is removed when modal closes
export const ModalCleanup = {
  mounted() {
    // Store the original overflow style
    this.originalOverflow = document.body.style.overflow;
    
    // Watch for changes to the modal's visibility
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && 
            (mutation.attributeName === 'class' || mutation.attributeName === 'style')) {
          this.checkModalState();
        }
      });
    });
    
    // Start observing the modal element
    this.observer.observe(this.el, { 
      attributes: true, 
      attributeFilter: ['class', 'style'] 
    });
    
    // Initial check
    this.checkModalState();
  },
  
  checkModalState() {
    const isHidden = this.el.classList.contains('hidden') || 
                     this.el.style.display === 'none' ||
                     !this.el.offsetParent;
    
    if (isHidden) {
      // Modal is hidden, ensure overflow-hidden is removed
      document.body.classList.remove('overflow-hidden');
      document.body.style.overflow = this.originalOverflow || '';
    }
  },
  
  destroyed() {
    // Clean up when the hook is destroyed
    if (this.observer) {
      this.observer.disconnect();
    }
    // Ensure overflow-hidden is removed
    document.body.classList.remove('overflow-hidden');
    document.body.style.overflow = this.originalOverflow || '';
  },
  
  reconnected() {
    // Ensure cleanup on reconnection
    this.checkModalState();
  },
  
  disconnected() {
    // Ensure cleanup on disconnection
    document.body.classList.remove('overflow-hidden');
    document.body.style.overflow = this.originalOverflow || '';
  }
};

// ImagePicker hook for pushing image_selected event
export const ImagePicker = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const imageData = this.el.dataset.image;
      if (imageData) {
        let data;
        try {
          data = JSON.parse(imageData);
        } catch (err) {
          data = imageData;
        }
        this.pushEvent("image_selected", data);
      }
    });
  }
};

// FocusTrap Hook for modal focus management
export const FocusTrap = {
  mounted() {
    // Store the previously focused element
    this.previouslyFocused = document.activeElement;
    
    this.FOCUSABLE_SELECTOR =
      'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';
    this.focusableElements = this.getFocusableElements();

    if (this.focusableElements.length > 0) {
      this.focusableElements[0].focus();
    } else {
      // Make container focusable and focus it as a fallback
      if (!this.el.hasAttribute('tabindex')) this.el.setAttribute('tabindex', '-1');
      this.el.focus();
    }

    // Add keydown listener for Tab navigation
    this.handleKeyDown = (e) => {
      if (e.key === 'Tab') {
        this.trapFocus(e);
      }
    };

    this.el.addEventListener('keydown', this.handleKeyDown);
  },

  updated() {
    // Recompute after LiveView updates modal content
    this.focusableElements = this.getFocusableElements();
  },

  destroyed() {
    // Remove event listener
    if (this.handleKeyDown) {
      this.el.removeEventListener('keydown', this.handleKeyDown);
    }

    // Restore focus to the previously focused element
    if (this.previouslyFocused && typeof this.previouslyFocused.focus === 'function') {
      try {
        this.previouslyFocused.focus();
      } catch (e) {
        // Element might not be in the document anymore
        console.log('Could not restore focus:', e);
      }
    }
  },

  getFocusableElements() {
    return Array.from(this.el.querySelectorAll(this.FOCUSABLE_SELECTOR))
      .filter(el => el.offsetParent !== null); // Only visible elements
  },

  trapFocus(e) {
    if (this.focusableElements.length === 0) return;

    const firstElement = this.focusableElements[0];
    const lastElement = this.focusableElements[this.focusableElements.length - 1];

    if (e.shiftKey) {
      // Shift + Tab (backward)
      if (document.activeElement === firstElement) {
        e.preventDefault();
        lastElement.focus();
      }
    } else {
      // Tab (forward)
      if (document.activeElement === lastElement) {
        e.preventDefault();
        firstElement.focus();
      }
    }
  }
};

// LazyImage Hook for performance optimization of image loading
export const LazyImage = {
  mounted() {
    // Only proceed if IntersectionObserver is supported
    if (!('IntersectionObserver' in window)) {
      this.loadImage();
      return;
    }

    // Configuration for the intersection observer
    const config = {
      // Load images when they're 50px away from viewport
      rootMargin: '50px 0px',
      threshold: 0.01
    };

    // Create the intersection observer
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          this.loadImage();
          this.observer.unobserve(this.el);
        }
      });
    }, config);

    // Start observing the image element
    this.observer.observe(this.el);
  },

  loadImage() {
    const img = this.el;
    const src = img.dataset.src;
    const srcset = img.dataset.srcset;

    // Load the image
    if (src) {
      img.src = src;
      img.removeAttribute('data-src');
    }

    if (srcset) {
      img.srcset = srcset;
      img.removeAttribute('data-srcset');
    }

    // Add loaded class for CSS transitions
    img.classList.add('loaded');

    // Remove loading placeholder
    img.classList.remove('loading');
  },

  destroyed() {
    // Clean up observer
    if (this.observer) {
      this.observer.disconnect();
    }
  }
};

// Calendar Keyboard Navigation Hook - Handles keyboard navigation within calendar
export const CalendarKeyboardNav = {
  mounted() {
    this.el.addEventListener('keydown', (e) => {
      const focusedCell = this.el.querySelector('[tabindex="0"]');
      if (!focusedCell) return;

      let targetCell = null;
      
      switch(e.key) {
        case 'ArrowRight':
          targetCell = focusedCell.nextElementSibling;
          break;
        case 'ArrowLeft':
          targetCell = focusedCell.previousElementSibling;
          break;
        case 'ArrowDown': {
          // Move to same day next week (7 cells forward)
          const nextRow = focusedCell.parentElement.nextElementSibling;
          if (nextRow) {
            const cellIndex = Array.from(focusedCell.parentElement.children).indexOf(focusedCell);
            targetCell = nextRow.children[cellIndex];
          }
          break;
        }
        case 'ArrowUp': {
          // Move to same day previous week (7 cells backward)  
          const prevRow = focusedCell.parentElement.previousElementSibling;
          if (prevRow) {
            const cellIndex = Array.from(focusedCell.parentElement.children).indexOf(focusedCell);
            targetCell = prevRow.children[cellIndex];
          }
          break;
        }
        case 'Enter':
        case ' ':
          // Activate the focused date
          e.preventDefault();
          focusedCell.click();
          return;
        default:
          return;
      }

      if (targetCell && targetCell.matches('[role="gridcell"]')) {
        e.preventDefault();
        focusedCell.setAttribute('tabindex', '-1');
        targetCell.setAttribute('tabindex', '0');
        targetCell.focus();
      }
    });
  }
};

// SetupPathSelector hook to sync radio button states
export const SetupPathSelector = {
  mounted() {
    this.syncRadioButtons();
  },

  updated() {
    this.syncRadioButtons();
  },

  syncRadioButtons() {
    const selectedPath = this.el.dataset.selectedPath;
    const radioButtons = this.el.querySelectorAll('input[type="radio"][name="setup_path"]');
    
    radioButtons.forEach(radio => {
      radio.checked = radio.value === selectedPath;
    });
  }
};

// Cast Carousel Keyboard Navigation Hook
export const CastCarouselKeyboard = {
  mounted() {
    this.handleKeydown = this.handleKeydown.bind(this);
    this.el.addEventListener('keydown', this.handleKeydown);
    
    // Add focus styling
    this.el.addEventListener('focus', () => {
      this.el.style.outline = '2px solid #4F46E5';
      this.el.style.outlineOffset = '2px';
    });
    
    this.el.addEventListener('blur', () => {
      this.el.style.outline = 'none';
    });
  },

  destroyed() {
    if (this.handleKeydown) {
      this.el.removeEventListener('keydown', this.handleKeydown);
    }
  },

  handleKeydown(event) {
    const componentId = this.el.dataset.componentId;
    
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      this.pushEvent('scroll_left', {}, componentId);
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      this.pushEvent('scroll_right', {}, componentId);
    }
  }
};

// Export all UI interaction hooks as a default object for easy importing
export default {
  ModalCleanup,
  ImagePicker,
  FocusTrap,
  LazyImage,
  CalendarKeyboardNav,
  SetupPathSelector,
  CastCarouselKeyboard
};