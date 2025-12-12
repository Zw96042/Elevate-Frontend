/** @type {import('tailwindcss').Config} */
module.exports = {
  // NOTE: Update this to include the paths to all of your component files.
  content: ["./app/**/*.{js,jsx,ts,tsx}", "./components/**/*.{js,jsx,ts,tsx}"],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: {
        primary: "var(--bg-color)",
        cardColor: 'var(--card-color)',
        main: 'var(--text-main)',
        secondary: 'var(--text-secondary)',
        accent: 'var(--text-accent)',
        nav: 'var(--nav-color)',
        highlight: 'var(--highlight-color)',
        highlightText: 'var(--highlight-text)',
      }
    },
  },
  plugins: [],
}