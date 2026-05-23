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
    'hover:rotate-1', 'hover:-rotate-1', 'hover:rotate-2', 'hover:-rotate-2',
    // Grimoire wax-seal tag cycle (deterministic by tag hash)
    'wax-seal-blood', 'wax-seal-arcane', 'wax-seal-ember',
    'wax-seal-phosphor', 'wax-seal-gold', 'wax-seal-ichor'
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
        },
        // Grimoire — retro hacker dark fantasy
        grim: {
          parchment: '#ebd9b3', //  aged candlelit page
          vellum:    '#f1e3c2', //  brighter parchment for cards
          ink:       '#1a1410', //  iron-gall ink (light-mode text)
          shadow:    '#3a2f25', //  faded ink shadow
          void:      '#07080d', //  starless dark
          obsidian:  '#0e0f17', //  card bg in dark mode
          tomb:      '#161826', //  raised surfaces in dark mode
          blood:     '#8b1d27', //  drop-cap red, accents
          ember:     '#f08029', //  torch / amber phosphor
          bone:      '#e9e0c8', //  off-white text (dark mode)
          phosphor:  '#57f287', //  CRT green for terminals
          arcane:    '#6a4cab', //  deep mystic purple
          gold:      '#c8a44d', //  illuminated manuscript gold
          ichor:     '#2d1b3a'  //  wine purple
        }
      },
      fontFamily: {
        sans: ['"Space Grotesk"', ...defaultTheme.fontFamily.sans],
        mono: ['"VT323"', 'ui-monospace', 'monospace'],
        display: ['"Press Start 2P"', 'system-ui', 'sans-serif'],
        terminal: ['"VT323"', 'ui-monospace', 'monospace'],
        // Grimoire stack — Matrix-minimal: monospace display, modern sans body.
        // (Class names kept for view compat — "blackletter" now points at a
        // monospace, "engraved" at a tight uppercase monospace, "manuscript"
        // at a clean modern sans.)
        blackletter: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
        engraved:    ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
        manuscript:  ['"Inter"', 'system-ui', 'sans-serif'],
        plex:        ['"IBM Plex Mono"', 'ui-monospace', 'monospace']
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
        'crt-glow':     '0 0 12px rgba(0, 255, 156, 0.4), 0 0 24px rgba(0, 255, 156, 0.15)',
        // Grimoire shadows: deep velvet (light) + ember bloom (dark)
        'tome':         '0 1px 0 #c8a44d, 0 2px 0 #1a1410, 0 14px 26px -8px rgba(13,11,8,0.45)',
        'tome-dark':    '0 1px 0 #c8a44d, 0 2px 0 #07080d, 0 18px 32px -10px rgba(0,0,0,0.75)',
        'velvet':       '0 26px 60px -24px rgba(13,11,8,0.55), 0 8px 18px -8px rgba(13,11,8,0.35)',
        'ember':        '0 0 22px rgba(240,128,41,0.45), 0 0 60px rgba(240,128,41,0.18)',
        'phosphor':     '0 0 14px rgba(87,242,135,0.45), 0 0 36px rgba(87,242,135,0.15)',
        'sigil':        'inset 0 0 0 1px rgba(200,164,77,0.55), inset 0 0 22px rgba(200,164,77,0.12)'
      },
      animation: {
        'blink':       'blink 1s steps(2, start) infinite',
        'marquee':     'marquee 28s linear infinite',
        'scanline':    'scanline 8s linear infinite',
        'wiggle':      'wiggle 0.4s ease-in-out',
        'drift-slow':  'drift 22s ease-in-out infinite',
        'drift-fast':  'drift 14s ease-in-out infinite',
        'glitch':      'glitch 2.4s steps(1) infinite',
        'pop-in':      'pop-in 0.45s cubic-bezier(.34,1.56,.64,1) both',
        // Grimoire motion
        'flicker':     'flicker 4.6s linear infinite',
        'sigil-spin':  'sigil-spin 42s linear infinite',
        'sigil-spin-rev':'sigil-spin 56s linear infinite reverse',
        'incant':      'incant 1.2s ease-out forwards',
        'phosphor-pulse':'phosphor-pulse 2.8s ease-in-out infinite',
        'rune-rise':   'rune-rise 0.7s ease-out both',
        'mist':        'mist 18s ease-in-out infinite'
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
        },
        flicker: {
          '0%, 19%, 21%, 23%, 25%, 54%, 56%, 100%': {
            opacity: '1', textShadow: '0 0 6px rgba(240,128,41,0.85), 0 0 22px rgba(240,128,41,0.45)'
          },
          '20%, 24%, 55%': { opacity: '0.55', textShadow: 'none' }
        },
        'sigil-spin': {
          '0%':   { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' }
        },
        incant: {
          '0%':   { opacity: '0', transform: 'translateY(-12px) scale(.9)', filter: 'blur(8px)' },
          '60%':  { opacity: '1', filter: 'blur(0)' },
          '100%': { opacity: '1', transform: 'translateY(0) scale(1)' }
        },
        'phosphor-pulse': {
          '0%, 100%': { textShadow: '0 0 6px rgba(87,242,135,0.6), 0 0 18px rgba(87,242,135,0.25)' },
          '50%':      { textShadow: '0 0 10px rgba(87,242,135,0.9), 0 0 32px rgba(87,242,135,0.45)' }
        },
        'rune-rise': {
          '0%':   { opacity: '0', transform: 'translateY(10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' }
        },
        mist: {
          '0%, 100%': { transform: 'translateX(-2%) translateY(0)' },
          '50%':      { transform: 'translateX(2%) translateY(-1%)' }
        }
      }
    }
  },
  plugins: [
    require('@tailwindcss/forms')
  ]
}
