// Service Worker de la PWA
// Estrategia: red primero, caché como respaldo (permite trabajar sin conexión
// y garantiza que las actualizaciones del código lleguen al instante).
const CACHE = 'telemetria-v1';
const ARCHIVOS = [
    './',
    './index.html',
    './styles.css',
    './physics.js',
    './ble.js',
    './app.js',
    './manifest.json',
    './icon-192.png',
    './icon-512.png'
];

self.addEventListener('install', (e) => {
    e.waitUntil(caches.open(CACHE).then(c => c.addAll(ARCHIVOS)));
    self.skipWaiting();
});

self.addEventListener('activate', (e) => {
    e.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (e) => {
    if (e.request.method !== 'GET') return;
    e.respondWith(
        fetch(e.request)
            .then(resp => {
                const copia = resp.clone();
                caches.open(CACHE).then(c => c.put(e.request, copia));
                return resp;
            })
            .catch(() => caches.match(e.request))
    );
});
