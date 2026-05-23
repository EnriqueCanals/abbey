const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  darkMode: 'class',
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}',
    './lib/markdown_render.rb',
    './app/models/concerns/rendering.rb'
  ],
  safelist: [
    // Memphis tag color cycle (used by deterministic tag hashing)
    'bg-memphis-pink', 'bg-memphis-cyan', 'bg-memphis-yellow',
    'bg-memphis-mint', 'bg-memphis-purple', 'bg-memphis-coral',
    'shadow-retro-pink', 'shadow-retro-cyan', 'shadow-retro-yellow',
    'shadow-retro-mint', 'shadow-retro-purple', 'shadow-retro-coral',
    'hover:rotate-1', 'hover:-rotate-1', 'hover:rotate-2', 'hover:-rotate-2'
  ],
  theme: {
    extend: {
      colors: {
        memphis: {
          pink:   '#ff3eb5',
          cyan:   '#00e5ff',
          yellow: '#ffd400',
          mint:   '#00ff9c',
          purple: '#b14aff',
          coral:  '#ff6b4a',
          ink:    '#0d0d12',
          paper:  '#fff8ef',
          crt:    '#0a0e1a'
        }
      },
      fontFamily: {
        sans:     ['"Space Grotesk"', ...defaultTheme.fontFamily.sans],
        mono:     ['"VT323"', 'ui-monospace', 'monospace'],
        display:  ['"Press Start 2P"', 'system-ui', 'sans-serif'],
        terminal: ['"VT323"', 'ui-monospace', 'monospace']
      },
      boxShadow: {
        // Neo-brutalist hard offset shadows
        'retro':        '6px 6px 0 0 #0d0d12',
        'retro-sm':     '4px 4px 0 0 #0d0d12',
        'retro-lg':     '10px 10px 0 0 #0d0d12',
        'retro-pink':   '6px 6px 0 0 #ff3eb5',
        'retro-cyan':   '6px 6px 0 0 #00e5ff',
        'retro-yellow': '6px 6px 0 0 #ffd400',
        'retro-mint':   '6px 6px 0 0 #00ff9c',
        'retro-purple': '6px 6px 0 0 #b14aff',
        'retro-coral':  '6px 6px 0 0 #ff6b4a',
        'crt-glow':     '0 0 12px rgba(0, 255, 156, 0.4), 0 0 24px rgba(0, 255, 156, 0.15)'
      },
      animation: {
        'blink':       'blink 1s steps(2, start) infinite',
        'marquee':     'marquee 28s linear infinite',
        'scanline':    'scanline 8s linear infinite',
        'wiggle':      'wiggle 0.4s ease-in-out',
        'drift-slow':  'drift 22s ease-in-out infinite',
        'drift-fast':  'drift 14s ease-in-out infinite',
        'glitch':      'glitch 2.4s steps(1) infinite',
        'pop-in':      'pop-in 0.45s cubic-bezier(.34,1.56,.64,1) both'
      },
      keyframes: {
        blink:    { '0%, 49%': { opacity: '1' }, '50%, 100%': { opacity: '0' } },
        marquee:  { '0%': { transform: 'translateX(0)' }, '100%': { transform: 'translateX(-50%)' } },
        scanline: { '0%': { transform: 'translateY(-100%)' }, '100%': { transform: 'translateY(100%)' } },
        wiggle:   { '0%,100%': { transform: 'rotate(0deg)' }, '25%': { transform: 'rotate(-3deg)' }, '75%': { transform: 'rotate(3deg)' } },
        drift: {
          '0%, 100%': { transform: 'translate(0,0) rotate(0deg)' },
          '50%':      { transform: 'translate(12px,-10px) rotate(8deg)' }
        },
        glitch: {
          '0%, 92%, 100%': { textShadow: '2px 0 #00e5ff, -2px 0 #ff3eb5' },
          '94%':           { textShadow: '6px 0 #00e5ff, -6px 0 #ff3eb5' },
          '96%':           { textShadow: '-3px 0 #00e5ff, 3px 0 #ff3eb5' }
        },
        'pop-in': {
          '0%':   { transform: 'translateY(8px) scale(.96)', opacity: '0' },
          '100%': { transform: 'translateY(0) scale(1)', opacity: '1' }
        }
      }
    }
  }
  // Plugins (forms, typography) are now registered via @plugin directives in
  // app/assets/tailwind/application.css per Tailwind v4 conventions.
}
