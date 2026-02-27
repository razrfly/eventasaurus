// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex"
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
        oat: {
          50:  '#FCFCF9',
          100: '#F5F4EF',
          200: '#EBEAE3',
          300: '#DDDBD0',
          400: '#B4B3A3',
          500: '#8C8B78',
          600: '#6F6E5F',
          700: '#5D5C4F',
          800: '#42413A',
          900: '#34332E',
          950: '#232322',
        },
        olive: {
          50:  'oklch(98.8% 0.003 106.5 / <alpha-value>)',
          100: 'oklch(96.6% 0.005 106.5 / <alpha-value>)',
          200: 'oklch(93% 0.007 106.5 / <alpha-value>)',
          300: 'oklch(88% 0.011 106.6 / <alpha-value>)',
          400: 'oklch(73.7% 0.021 106.9 / <alpha-value>)',
          500: 'oklch(58% 0.031 107.3 / <alpha-value>)',
          600: 'oklch(46.6% 0.025 107.3 / <alpha-value>)',
          700: 'oklch(39.4% 0.023 107.4 / <alpha-value>)',
          800: 'oklch(28.6% 0.016 107.4 / <alpha-value>)',
          900: 'oklch(22.8% 0.013 107.4 / <alpha-value>)',
          950: 'oklch(15.3% 0.006 107.1 / <alpha-value>)',
        },
      },
      fontFamily: {
        'knewave': ['Knewave', 'cursive'],
        'orbitron': ['Orbitron', 'monospace'],
        'familjen': ['"Familjen Grotesk"', 'sans-serif'],
        'instrument': ['"Instrument Sans"', 'sans-serif'],
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows customizing form elements via data attributes
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into the app.css bundle
    plugin(function({matchComponents, theme}) {
      // Handle Heroicons differently since we're using the Elixir package
      // which doesn't have the same directory structure
      
      // Create empty values object (will be populated if the directory exists)
      let values = {};
      
      // For the Elixir heroicons package, we don't need to read the SVG files
      // as they're already available in the package
      matchComponents({
        "hero": ({name, fullPath}) => {
          // If we have no fullPath (which we won't with the Elixir package),
          // just return base styling without trying to read SVG content
          if (!fullPath) {
            return {
              "display": "inline-block",
              "width": theme("spacing.5"),
              "height": theme("spacing.5")
            };
          }
          
          // This block will only run if we have actual SVG files
          try {
            const content = fs.readFileSync(fullPath, 'utf8');
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              "mask": `var(--hero-${name})`,
              "mask-repeat": "no-repeat",
              "background-color": "currentColor",
              "vertical-align": "middle",
              "display": "inline-block",
              "width": theme("spacing.5"),
              "height": theme("spacing.5")
            };
          } catch (error) {
            console.error(`Error reading heroicon at ${fullPath}:`, error);
            return {
              "display": "inline-block",
              "width": theme("spacing.5"),
              "height": theme("spacing.5")
            };
          }
        }
      }, {values})
    })
  ]
}; 