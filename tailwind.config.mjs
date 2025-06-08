import { defineConfig } from 'tailwindcss'

export default defineConfig({
  content: ['./src/**/*.{astro,html,js,jsx,ts,tsx,vue,svelte}'],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#196622',
          dark: '#144D1A',
          light: '#4A7744',
        },
        accent: {
          lime: '#A7DC81',
          amber: '#F4B860',
          berry: '#A44A6E',
        },
        neutral: {
          50: '#F7F7F5',
          400: '#B2B2B2',
          900: '#2C2C2C',
        },
      },
    },
  },
})
