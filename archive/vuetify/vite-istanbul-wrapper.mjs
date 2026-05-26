// [coverage_reloaded] vite config wrapper
// Placed at packages/vuetify/vite.config.mjs before Cypress test runs.
// Injects Istanbul instrumentation into the Vite dev server without
// modifying the committed vite.config.mjs (renamed to _vite.config.mjs).
// The container is ephemeral so no cleanup needed.
import { mergeConfig } from 'vite'
import istanbul from 'vite-plugin-istanbul'
import base from './_vite.config.mjs'

export default mergeConfig(base, {
  plugins: [
    istanbul({
      extension: ['.js', '.ts', '.vue'],
      requireEnv: false,
    }),
  ],
})