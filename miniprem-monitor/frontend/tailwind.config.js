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
          primary: '#5F56D9',
          orange: '#EB7466',
          pink: '#F41788',
        },
        status: {
          healthy: '#10b981',
          warning: '#f59e0b',
          error: '#ef4444',
          unknown: '#6b7280',
        }
      },
      fontFamily: {
        'manrope': ['Manrope', 'Inter', 'system-ui', 'sans-serif'],
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'bounce-slow': 'bounce 2s infinite',
      },
      backgroundImage: {
        'gradient-uneeq': 'linear-gradient(135deg, #5F56D9 0%, #F41788 100%)',
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