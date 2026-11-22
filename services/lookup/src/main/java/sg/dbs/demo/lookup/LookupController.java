package sg.dbs.demo.lookup;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.DirectoryClient;
import sg.dbs.demo.common.DirectoryClient.Proxy;
import sg.dbs.demo.common.Jwt;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@RestController
public class LookupController {
    private record Cached(Proxy proxy, long expiresAt) {}

    private final DirectoryClient directory;
    private final Jwt jwt;
    private final long cacheTtlMs;
    private final int ratePerMinute;
    private final Map<String, Cached> cache = new ConcurrentHashMap<>();
    private final Map<String, Deque<Long>> calls = new ConcurrentHashMap<>();

    public LookupController(DirectoryClient directory, Jwt jwt,
                            @Value("${lookup.cache-ttl}") Duration cacheTtl,
                            @Value("${lookup.rate-per-minute}") int ratePerMinute) {
        this.directory = directory;
        this.jwt = jwt;
        this.cacheTtlMs = cacheTtl.toMillis();
        this.ratePerMinute = ratePerMinute;
    }

    @GetMapping("/paynow/lookup")
    Proxy lookup(@RequestHeader(value = "Authorization", required = false) String authorization,
                 @RequestParam String type, @RequestParam String value) {
        String userId = jwt.userId(authorization);
        rateLimit(userId);
        String t = type.toUpperCase();
        String v = value.trim().toUpperCase();
        DirectoryClient.validate(t, v);
        String key = t + ":" + v;
        long now = System.currentTimeMillis();
        Cached hit = cache.get(key);
        if (hit != null && hit.expiresAt() > now) return hit.proxy();
        Proxy proxy = directory.resolve(t, v);
        cache.put(key, new Cached(proxy, now + cacheTtlMs));
        return proxy;
    }

    private void rateLimit(String userId) {
        long now = System.currentTimeMillis();
        Deque<Long> window = calls.computeIfAbsent(userId, k -> new ArrayDeque<>());
        synchronized (window) {
            while (!window.isEmpty() && window.peekFirst() <= now - 60_000) window.pollFirst();
            if (window.size() >= ratePerMinute) {
                throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED", "Too many lookups. Try again in a minute");
            }
            window.addLast(now);
        }
    }
}
