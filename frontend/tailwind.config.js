/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          50:  "#edf7e6",
          100: "#d0edbe",
          200: "#a8d98e",
          300: "#7bc35a",
          400: "#56af30",
          500: "#3a9618",
          600: "#2d7a10",
          700: "#245f0d",
          800: "#1a4509",
          900: "#122e06",
        },
        soil: {
          50:  "#faf6f1",
          100: "#f1e8db",
          200: "#e3d0b6",
          300: "#d0b187",
          400: "#bd9261",
          500: "#a8794b",
          600: "#8b603c",
          700: "#6f4b32",
          800: "#5b3e2c",
          900: "#4b3427",
        },
        harvest: {
          50:  "#fff7e6",
          100: "#ffe6b3",
          200: "#ffd080",
          300: "#ffb84d",
          400: "#ffa020",
          500: "#f08800",
          600: "#c46e00",
          700: "#995500",
          800: "#6e3d00",
          900: "#4a2800",
        },
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'sans-serif'],
        display: ['"Plus Jakarta Sans"', 'Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        soft:   "0 4px 14px -4px rgba(20, 60, 20, 0.22)",
        card:   "0 2px 0 0 rgba(42, 110, 16, 0.12), 0 4px 16px -4px rgba(15, 35, 15, 0.14)",
        strong: "0 8px 24px -6px rgba(20, 60, 20, 0.28)",
        pop:    "4px 4px 0 0 #1a4509",
        "pop-harvest": "4px 4px 0 0 #995500",
      },
      animation: {
        'fade-in':    'fadeIn 0.4s ease-out',
        'slide-up':   'slideUp 0.4s ease-out',
        'pulse-slow': 'pulse 2.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      keyframes: {
        fadeIn:  { '0%': { opacity: 0 }, '100%': { opacity: 1 } },
        slideUp: { '0%': { opacity: 0, transform: 'translateY(8px)' }, '100%': { opacity: 1, transform: 'translateY(0)' } },
      },
    },
  },
  plugins: [],
};
