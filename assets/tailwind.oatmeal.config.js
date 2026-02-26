// Oatmeal theme — standalone Tailwind config
// Extends the main config but sets font-sans to Inter (the Oatmeal body font).
// This ensures @tailwind base preflight sets body { font-family: Inter, ... }
// without touching the main app's font stack.

const mainConfig = require('./tailwind.config.js');

module.exports = {
  ...mainConfig,
  theme: {
    ...mainConfig.theme,
    extend: {
      ...mainConfig.theme.extend,
      fontFamily: {
        ...mainConfig.theme.extend.fontFamily,
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
    },
  },
};
