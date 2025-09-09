// Poll option drag and drop functionality
// Extracted from app.js for better organization

// Poll Option Drag and Drop Hook
export const PollOptionDragDrop = {
  mounted() {
    this.initialize();
  },

  updated() {
    // Re-initialize after LiveView updates the DOM
    this.initialize();
  },

  destroyed() {
    this.cleanupEventListeners();
  },

  initialize() {
    // Clean up any existing state first
    this.cleanupEventListeners();
    
    // Reset state
    this.originalOrder = null;
    this.draggedElement = null;
    this.touchStartY = 0;
    this.touchStartX = 0;
    this.touchElement = null;
    this.isDragging = false;
    this.hasMoved = false;
    this.touchTimeout = null;
    this.touchMoveThrottle = null;
    this.mobileDragIndicator = null;
    
    this.canReorder = this.el.dataset.canReorder === "true";
    
    if (!this.canReorder) {
      return; // Don't enable drag-and-drop if user can't reorder
    }
    
    this.setupDragAndDrop();
    this.setupTouchSupport();
    
    // Listen for rollback events from the server
    this.handleEvent("rollback_order", () => {
      this.rollbackOrder();
    });
  },

  setupDragAndDrop() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    
    items.forEach((item, index) => {
      // Make items draggable and add event listeners
      item.draggable = true;
      item.dataset.originalIndex = index;
      
      // Drag event listeners
      item.addEventListener('dragstart', this.handleDragStart.bind(this));
      item.addEventListener('dragend', this.handleDragEnd.bind(this));
      item.addEventListener('dragover', this.handleDragOver.bind(this));
      item.addEventListener('drop', this.handleDrop.bind(this));
      item.addEventListener('dragenter', this.handleDragEnter.bind(this));
      item.addEventListener('dragleave', this.handleDragLeave.bind(this));
    });
  },

  setupTouchSupport() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    
    items.forEach(item => {
      item.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: false });
      item.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: false });
      item.addEventListener('touchend', this.handleTouchEnd.bind(this), { passive: false });
    });
  },

  handleDragStart(e) {
    this.draggedElement = e.target.closest('[data-draggable="true"]');
    this.originalOrder = this.getCurrentOrder();
    
    // Add visual feedback
    this.draggedElement.classList.add('opacity-50', 'scale-95');
    
    // Set drag data
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/html', this.draggedElement.outerHTML);
    
    // Add drag image styling
    setTimeout(() => {
      this.draggedElement.classList.add('invisible');
    }, 0);
  },

  handleDragEnd(e) {
    // Clean up visual feedback
    this.draggedElement.classList.remove('opacity-50', 'scale-95', 'invisible');
    
    // Remove all drop indicators
    this.clearDropIndicators();
    
    this.draggedElement = null;
  },

  handleDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (dropTarget && dropTarget !== this.draggedElement) {
      this.showDropIndicator(dropTarget, e.clientY);
    }
  },

  handleDragEnter(e) {
    e.preventDefault();
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (dropTarget && dropTarget !== this.draggedElement) {
      dropTarget.classList.add('bg-blue-50', 'border-blue-200');
    }
  },

  handleDragLeave(e) {
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (dropTarget) {
      dropTarget.classList.remove('bg-blue-50', 'border-blue-200');
    }
  },

  handleDrop(e) {
    e.preventDefault();
    
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (!dropTarget || dropTarget === this.draggedElement) {
      return;
    }
    
    // Clean up visual feedback
    dropTarget.classList.remove('bg-blue-50', 'border-blue-200');
    this.clearDropIndicators();
    
    // Perform the reorder
    this.reorderElements(this.draggedElement, dropTarget);
  },

  // Touch support methods
  handleTouchStart(e) {
    if (e.touches.length !== 1) return;
    
    this.touchElement = e.target.closest('[data-draggable="true"]');
    this.touchStartY = e.touches[0].clientY;
    this.touchStartX = e.touches[0].clientX;
    this.hasMoved = false;
    this.originalOrder = this.getCurrentOrder();
    
    // Add visual feedback after a delay to distinguish from scrolling
    this.touchTimeout = setTimeout(() => {
      if (this.touchElement && !this.isDragging) {
        this.touchElement.classList.add('touch-dragging', 'scale-105', 'shadow-lg', 'z-50');
        this.isDragging = true;
        this.showMobileDragIndicator();
        
        // Provide haptic feedback if available
        if (navigator.vibrate) {
          navigator.vibrate(50);
        }
      }
    }, 150);
  },

  handleTouchMove(e) {
    if (!this.touchElement) return;
    
    const touch = e.touches[0];
    const deltaX = Math.abs(touch.clientX - this.touchStartX);
    const deltaY = Math.abs(touch.clientY - this.touchStartY);
    
    // Detect if this is a drag gesture vs scroll
    if (!this.hasMoved && (deltaX > 10 || deltaY > 10)) {
      this.hasMoved = true;
      
      // Cancel touch timeout if user starts scrolling horizontally
      if (deltaX > deltaY && this.touchTimeout) {
        clearTimeout(this.touchTimeout);
        return;
      }
    }
    
    if (!this.isDragging) return;
    
    e.preventDefault();
    
    // Throttle touch move for better performance
    if (!this.touchMoveThrottle) {
      this.touchMoveThrottle = setTimeout(() => {
        const elementUnderTouch = document.elementFromPoint(touch.clientX, touch.clientY);
        const dropTarget = elementUnderTouch?.closest('[data-draggable="true"]');
        
        if (dropTarget && dropTarget !== this.touchElement) {
          this.showDropIndicator(dropTarget, touch.clientY);
          this.updateMobileDragIndicator(dropTarget);
        } else {
          this.clearDropIndicators();
          this.updateMobileDragIndicator(null);
        }
        
        this.touchMoveThrottle = null;
      }, 16); // ~60fps
    }
  },

  handleTouchEnd(e) {
    // Clear timeout if touch ends before drag starts
    if (this.touchTimeout) {
      clearTimeout(this.touchTimeout);
      this.touchTimeout = null;
    }
    
    // Clear throttle timeout if active
    if (this.touchMoveThrottle) {
      clearTimeout(this.touchMoveThrottle);
      this.touchMoveThrottle = null;
    }
    
    if (!this.touchElement) return;
    
    let dropTarget = null;
    
    // Only check for drop target if we were actually dragging
    if (this.isDragging) {
      const touch = e.changedTouches[0];
      const elementUnderTouch = document.elementFromPoint(touch.clientX, touch.clientY);
      dropTarget = elementUnderTouch?.closest('[data-draggable="true"]');
      
      // Clean up visual feedback
      this.touchElement.classList.remove('touch-dragging', 'scale-105', 'shadow-lg', 'z-50');
      this.clearDropIndicators();
      this.hideMobileDragIndicator();
      
      // Perform reorder if valid drop target
      if (dropTarget && dropTarget !== this.touchElement) {
        this.reorderElements(this.touchElement, dropTarget);
        
        // Provide success feedback
        if (navigator.vibrate) {
          navigator.vibrate([30, 10, 30]);
        }
      }
    }
    
    // Reset touch state
    this.touchElement = null;
    this.isDragging = false;
    this.hasMoved = false;
  },

  reorderElements(draggedElement, dropTarget) {
    const draggedId = draggedElement.dataset.optionId;
    const dropTargetId = dropTarget.dataset.optionId;
    const draggedIndex = parseInt(draggedElement.dataset.originalIndex);
    const dropTargetIndex = parseInt(dropTarget.dataset.originalIndex);
    
    if (!draggedId || !dropTargetId || draggedId === dropTargetId) {
      return;
    }
    
    // Optimistically update the DOM
    this.updateDOMOrder(draggedElement, dropTarget, draggedIndex < dropTargetIndex);
    
    // Send update to server - target the LiveView component using proper targeting
    this.pushEventTo(this.el, 'reorder_option', {
      dragged_option_id: draggedId,
      target_option_id: dropTargetId,
      direction: draggedIndex < dropTargetIndex ? 'after' : 'before',
      original_order: this.originalOrder
    });
  },

  updateDOMOrder(draggedElement, dropTarget, insertAfter) {
    if (insertAfter) {
      dropTarget.parentNode.insertBefore(draggedElement, dropTarget.nextSibling);
    } else {
      dropTarget.parentNode.insertBefore(draggedElement, dropTarget);
    }
    
    // Update data attributes for proper tracking
    this.updateItemIndices();
  },

  updateItemIndices() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    items.forEach((item, index) => {
      item.dataset.originalIndex = index;
    });
  },

  showDropIndicator(element, clientY) {
    this.clearDropIndicators();
    
    const rect = element.getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;
    const isAbove = clientY < midpoint;
    
    const indicator = document.createElement('div');
    indicator.className = 'drop-indicator absolute left-0 right-0 h-1 bg-blue-400 rounded-full z-10 transition-all duration-150';
    indicator.style.pointerEvents = 'none';
    
    if (isAbove) {
      indicator.style.top = '-2px';
      element.style.position = 'relative';
      element.appendChild(indicator);
    } else {
      indicator.style.bottom = '-2px';
      element.style.position = 'relative';
      element.appendChild(indicator);
    }
  },

  clearDropIndicators() {
    const indicators = this.el.querySelectorAll('.drop-indicator');
    indicators.forEach(indicator => indicator.remove());
    
    // Remove highlighting
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    items.forEach(item => {
      item.classList.remove('bg-blue-50', 'border-blue-200');
    });
  },

  getCurrentOrder() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    return Array.from(items).map(item => ({
      id: item.dataset.optionId,
      index: parseInt(item.dataset.originalIndex)
    }));
  },

  // Called by LiveView when reorder fails - rollback the DOM changes
  rollbackOrder() {
    if (!this.originalOrder) return;
    
    const container = this.el.querySelector('[data-role="options-container"]');
    if (!container) return;
    
    // Reorder DOM elements to match original order
    this.originalOrder
      .sort((a, b) => a.index - b.index)
      .forEach(item => {
        const element = container.querySelector(`[data-option-id="${item.id}"]`);
        if (element) {
          container.appendChild(element);
        }
      });
    
    this.updateItemIndices();
    this.originalOrder = null;
  },

  // Mobile drag indicator methods
  showMobileDragIndicator() {
    if (this.mobileDragIndicator) return;
    
    this.mobileDragIndicator = document.createElement('div');
    this.mobileDragIndicator.className = 'mobile-drag-indicator';
    this.mobileDragIndicator.textContent = 'Drag to reorder • Release to drop';
    document.body.appendChild(this.mobileDragIndicator);
  },
  
  updateMobileDragIndicator(dropTarget) {
    if (!this.mobileDragIndicator) return;
    
    if (dropTarget) {
      this.mobileDragIndicator.textContent = 'Release to place here';
      this.mobileDragIndicator.style.backgroundColor = '#10b981';
    } else {
      this.mobileDragIndicator.textContent = 'Drag to reorder • Release to drop';
      this.mobileDragIndicator.style.backgroundColor = '#1f2937';
    }
    },
    
  hideMobileDragIndicator() {
    if (this.mobileDragIndicator) {
      this.mobileDragIndicator.remove();
      this.mobileDragIndicator = null;
    }
  },

  cleanupEventListeners() {
    // Clear any pending timeouts
    if (this.touchTimeout) {
      clearTimeout(this.touchTimeout);
      this.touchTimeout = null;
    }
    if (this.touchMoveThrottle) {
      clearTimeout(this.touchMoveThrottle);
      this.touchMoveThrottle = null;
    }
    
    // Clean up mobile indicator
    this.hideMobileDragIndicator();
    
    // Clear drop indicators
    this.clearDropIndicators();
    
    // Remove all event listeners from draggable items
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    items.forEach(item => {
      // Remove drag event listeners
      item.removeEventListener('dragstart', this.handleDragStart);
      item.removeEventListener('dragend', this.handleDragEnd);
      item.removeEventListener('dragover', this.handleDragOver);
      item.removeEventListener('drop', this.handleDrop);
      item.removeEventListener('dragenter', this.handleDragEnter);
      item.removeEventListener('dragleave', this.handleDragLeave);
      
      // Remove touch event listeners
      item.removeEventListener('touchstart', this.handleTouchStart);
      item.removeEventListener('touchmove', this.handleTouchMove);
      item.removeEventListener('touchend', this.handleTouchEnd);
      
      // Clean up visual state
      item.classList.remove('touch-dragging', 'scale-105', 'shadow-lg', 'z-50', 'opacity-50', 'scale-95', 'invisible', 'bg-blue-50', 'border-blue-200');
    });
  }
};

// Export all drag drop hooks as a default object for easy importing
export default {
  PollOptionDragDrop
};