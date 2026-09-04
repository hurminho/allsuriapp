import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['netlify/tests/**/*.test.ts'],
    environment: 'node',
  },
})
