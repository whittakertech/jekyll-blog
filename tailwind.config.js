/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './_layouts/**/*.html',
    './_includes/**/*.html',
    './_posts/**/*.md',
    './_pages/**/*.{md,html}',
    './_portfolio/**/*.md',
    './blog/**/*.html',
    './*.{md,html}',
    './assets/js/**/*.js'
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#ffcc00',      // Main brand yellow
          50: '#fffef7',
          100: '#fffde8',
          200: '#fff9c5',
          300: '#fff197',
          400: '#ffe668',
          500: '#ffcc00',         // Your existing primary
          600: '#e6b800',
          700: '#cc9900',
          800: '#997300',
          900: '#664d00'
        },
        secondary: {
          DEFAULT: '#63c0f5',     // Blog blue
          50: '#f0f9ff',
          100: '#e0f2fe',
          200: '#bae6fd',
          300: '#7dd3fc',
          400: '#38bdf8',
          500: '#63c0f5',        // Your existing secondary
          600: '#0284c7',
          700: '#0369a1',
          800: '#075985',
          900: '#0c4a6e'
        },
        dark: {
          DEFAULT: '#252525',     // Background
          50: '#f8f8f8',
          100: '#e8e8e8',
          200: '#d1d1d1',
          300: '#b4b4b4',
          400: '#888888',
          500: '#6d6d6d',
          600: '#5d5d5d',
          700: '#4f4f4f',
          800: '#454545',
          900: '#252525'          // Your existing dark
        },
        text: {
          DEFAULT: '#f0e7d5',     // Main text
          muted: '#b8b8b8',
          light: '#e5e5e5'
        }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Consolas', 'Monaco', 'monospace'],
      },
      typography: {
        DEFAULT: {
          css: {
            maxWidth: 'none',
            color: '#f0e7d5',
            h1: {
              color: '#ffcc00',
              fontWeight: '700',
            },
            h2: {
              color: '#ffcc00',
              fontWeight: '600',
            },
            h3: {
              color: '#63c0f5',
              fontWeight: '600',
            },
            h4: {
              color: '#63c0f5',
              fontWeight: '500',
            },
            a: {
              color: '#63c0f5',
              textDecoration: 'underline',
              '&:hover': {
                color: '#ffcc00',
              },
            },
            blockquote: {
              borderLeftColor: '#ffcc00',
              backgroundColor: 'rgba(255, 204, 0, 0.1)',
              color: '#f0e7d5',
            },
            code: {
              backgroundColor: '#454545',
              color: '#f0e7d5',
              padding: '0.25rem 0.375rem',
              borderRadius: '0.25rem',
              fontWeight: '500',
            },
            pre: {
              backgroundColor: '#1a1a1a',
              color: '#f0e7d5',
            },
            'pre code': {
              backgroundColor: 'transparent',
              color: 'inherit',
              padding: '0',
            },
          },
        },
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-in-out',
        'slide-up': 'slideUp 0.3s ease-out',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { transform: 'translateY(1rem)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
      },
      screens: {
        'xs': '475px',
      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
  ],
}