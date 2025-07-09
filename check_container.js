// Find the drag-and-drop container
const container = document.querySelector('[phx-hook="PollOptionDragDrop"]');
console.log('🔍 Container element:', container);

if (container) {
  const rect = container.getBoundingClientRect();
  console.log('🔍 Container dimensions:', {
    width: rect.width,
    height: rect.height,
    top: rect.top,
    left: rect.left
  });
  
  console.log('🔍 Container computed styles:');
  const styles = window.getComputedStyle(container);
  console.log('  width:', styles.width);
  console.log('  height:', styles.height);
  console.log('  display:', styles.display);
  console.log('  visibility:', styles.visibility);
  
  // Check draggable items
  const items = container.querySelectorAll('[data-draggable="true"]');
  console.log('🔍 Found draggable items:', items.length);
  
  items.forEach((item, index) => {
    const itemRect = item.getBoundingClientRect();
    console.log(`  Item ${index}:`, {
      width: itemRect.width,
      height: itemRect.height,
      id: item.dataset.optionId
    });
  });
} else {
  console.log('❌ Container not found!');
}
