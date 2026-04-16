import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'dist',
    rollupOptions: {
      external: [/@tauri-apps\/.*/],
    },
  },
  server: {
    port: 5173,
    strictPort: true,
    host: 'localhost',
  },
})
