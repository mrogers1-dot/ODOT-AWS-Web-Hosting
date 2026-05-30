/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        odot: {
          navy: '#1B2A4A',
          darkNavy: '#0F1B33',
          red: '#C8102E',
          darkRed: '#9B0000',
          gold: '#F2A900',
          blue: '#0057B8',
          lightBlue: '#E8F4FD',
          gray: '#4A5568',
          lightGray: '#F7FAFC',
          charcoal: '#2D3748'
        }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif']
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'fade-in': 'fadeIn 0.5s ease-out',
        'slide-up': 'slideUp 0.4s ease-out',
        'glow': 'glow 2s ease-in-out infinite alternate'
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' }
        },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' }
        },
        glow: {
          '0%': { boxShadow: '0 0 5px rgba(0, 87, 184, 0.2)' },
          '100%': { boxShadow: '0 0 20px rgba(0, 87, 184, 0.4)' }
        }
      },
      backgroundImage: {
        'gradient-radial': 'radial-gradient(var(--tw-gradient-stops))',
        'ohio-gradient': 'linear-gradient(135deg, #1B2A4A 0%, #0F1B33 100%)',
        'card-gradient': 'linear-gradient(180deg, rgba(255,255,255,0) 0%, rgba(247,250,252,1) 100%)'
      }
    }
  },
  plugins: []
};
