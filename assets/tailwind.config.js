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
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
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
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized");
      let values = {};
      try {
        let files = fs.readdirSync(iconsDir);
        files.forEach(file => {
          let name = path.basename(file, ".svg")
            .replace(/[^a-zA-Z0-9-]/g, "-")
            .replace(/^-+/, "");
          values[name] = {name, fullPath: path.join(iconsDir, file)};
        });
      } catch (error) {
        console.error(`Error reading heroicons directory at ${iconsDir}:`, error);
      }
      matchComponents({
        "hero": ({name, fullPath}) => {
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
            return {};
          }
        }
      }, {values})
    })
  ]
}; 