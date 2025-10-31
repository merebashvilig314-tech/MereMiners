const CACHE_NAME = "mere-miners-cache-v1";
const PRECACHE_URLS = ["/", "/index.html", "/manifest.webmanifest", "/favicon.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  if (request.method !== "GET") {
    return;
  }

  const requestURL = new URL(request.url);
  if (requestURL.origin !== self.location.origin) {
    return;
  }

  event.respondWith(
    (async () => {
      const cachedResponse = await caches.match(request);

      try {
        const networkResponse = await fetch(request);
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, responseClone));
        }
        return networkResponse;
      } catch (error) {
        if (cachedResponse) {
          return cachedResponse;
        }
        if (request.mode === "navigate") {
          const fallback = await caches.match("/index.html");
          if (fallback) {
            return fallback;
          }
        }
        throw error;
      }
    })()
  );
});
