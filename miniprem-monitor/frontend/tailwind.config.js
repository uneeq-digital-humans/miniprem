/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        uneeq: {
          // Official brand colors (March 2023)
          blue: '#5F56DA',
          orange: '#F47C6A',
          pink: '#FF1888',
          yellow: '#FFB648',
          liquorice: '#232236',

          // Gradient base colors
          'gradient-start': '#0E0B33',
          'gradient-end': '#0D0B5D',
          white: '#FFFFFF',

          // Dark mode accent variants
          'blue-dark': '#7B73E1',
          'orange-dark': '#FF8C7A',

          // Light mode variants (compatibility)
          primary: '#5F56DA',
        },
        brand: {
          // Light mode
          'bg-primary': '#FFFFFF',
          'bg-secondary': '#F9FAFB',
          'bg-tertiary': '#F3F4F6',
          'text-primary': '#232236',
          'text-secondary': '#6B7280',
          'text-tertiary': '#9CA3AF',
          'border-primary': '#E5E7EB',
          'border-secondary': '#D1D5DB',
        },
        status: {
          healthy: '#10b981',
          warning: '#f59e0b',
          error: '#ef4444',
          unknown: '#6b7280',
        }
      },
      fontFamily: {
        'manrope': ['Manrope', 'sans-serif'],
        'inter': ['Inter', 'sans-serif'],
        'sans': ['Inter', 'system-ui', 'sans-serif'],
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'bounce-slow': 'bounce 2s infinite',
      },
      backgroundImage: {
        'gradient-uneeq': 'linear-gradient(135deg, #5F56DA 0%, #FF1888 100%)',
        'gradient-uneeq-full': 'linear-gradient(135deg, #5F56DA 0%, #FF1888 50%, #F47C6A 100%)',
        'gradient-brand': 'linear-gradient(to bottom, #0E0B33, #0D0B5D)',
        'gradient-radial': 'radial-gradient(var(--tw-gradient-stops))',
        'gradient-conic': 'conic-gradient(from 180deg at 50% 50%, var(--tw-gradient-stops))',
      },
      backdropBlur: {
        xs: '2px',
      }
    },
  },
  plugins: [],
}
