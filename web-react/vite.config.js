import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [react(), VitePWA({
    registerType: 'prompt', injectRegister: 'auto',
    includeAssets: ['icon-192.png', 'icon-512.png', 'maskable-512.png', 'fonts/*'],
    manifest: {
      id: '/', name: 'Wake My PC', short_name: 'Wake My PC', lang: 'vi',
      description: 'Bật và điều khiển PC trong mạng LAN', start_url: '/', scope: '/',
      display: 'standalone', theme_color: '#101b2d', background_color: '#f4f6fb',
      icons: [{ src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
        { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
        { src: '/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }]
    },
    workbox: { globPatterns: ['**/*.{js,css,html,png,ttf,txt}'],
      navigateFallbackDenylist: [/^\/api\//], cleanupOutdatedCaches: true }
  })],
  server: { proxy: { '/api': { target: 'http://localhost:8787', ws: true, changeOrigin: true } } }
});
