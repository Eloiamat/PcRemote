const CACHE_NAME = "pcremote-v7";

const FILES_TO_CACHE = [
    "/",
    "/offline.html",
    "/static/style.css",
    "/static/manifest.json",
    "/static/icons/icono2.png"
];

self.addEventListener("install", event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(FILES_TO_CACHE))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener("activate", event => {
    event.waitUntil(
        caches.keys()
            .then(keys => Promise.all(
                keys
                    .filter(key => key !== CACHE_NAME)
                    .map(key => caches.delete(key))
            ))
            .then(() => self.clients.claim())
    );
});

// Fetch con límite de tiempo. En modo avión no dejamos que
// una petición de navegación se quede esperando indefinidamente.
function fetchWithTimeout(request, timeout = 2000) {
    const controller = new AbortController();

    const timer = setTimeout(() => controller.abort(), timeout);

    return fetch(request, {
        cache: "no-store",
        signal: controller.signal
    }).finally(() => clearTimeout(timer));
}

self.addEventListener("fetch", event => {
    const request = event.request;

    // Navegación: primero intentamos Internet durante un máximo de 2 s.
    // Si no responde, usamos la página guardada en caché.
    if (request.mode === "navigate") {
        event.respondWith(
            fetchWithTimeout(request, 2000)
                .then(response => {
                    if (!response || !response.ok) {
                        throw new Error("Respuesta de red no válida");
                    }

                    // Guardar una copia actualizada de la página principal.
                    const copy = response.clone();
                    caches.open(CACHE_NAME).then(cache => {
                        cache.put("/", copy);
                    });

                    return response;
                })
                .catch(() => {
                    return caches.match("/")
                        .then(cachedPage => {
                            return cachedPage || caches.match("/offline.html");
                        });
                })
        );

        return;
    }

    // Recursos estáticos: red primero y caché como respaldo.
    event.respondWith(
        fetchWithTimeout(request, 3000)
            .then(response => {
                if (response && response.ok) {
                    const copy = response.clone();
                    caches.open(CACHE_NAME).then(cache => {
                        cache.put(request, copy);
                    });
                }

                return response;
            })
            .catch(() => caches.match(request))
    );
});
