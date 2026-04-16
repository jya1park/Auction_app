const CACHE_NAME = 'realestate-v1';
const STATIC_ASSETS = [
    '/',
    '/static/css/style.css',
    '/static/js/app.js',
    '/static/manifest.json',
];

// 설치 - 정적 파일 캐시
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(STATIC_ASSETS))
            .then(() => self.skipWaiting())
    );
});

// 활성화 - 이전 캐시 정리
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(keys =>
            Promise.all(
                keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
            )
        ).then(() => self.clients.claim())
    );
});

// 요청 처리 - 네트워크 우선, 실패 시 캐시
self.addEventListener('fetch', event => {
    // API 요청은 항상 네트워크로
    if (event.request.url.includes('/api/')) {
        event.respondWith(fetch(event.request));
        return;
    }

    event.respondWith(
        fetch(event.request)
            .then(response => {
                const clone = response.clone();
                caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                return response;
            })
            .catch(() => caches.match(event.request))
    );
});
