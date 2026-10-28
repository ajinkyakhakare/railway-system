// PostCSS runs Tailwind first, then adds vendor prefixes.
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
