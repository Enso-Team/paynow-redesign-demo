package sg.dbs.demo.common;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.io.IOException;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * Each endpoint below waits the time in the shared table at {@code latency.table}
 * (default {@code ../latency/measured.json}, relative to services/), times the multiplier.
 * The multiplier is the {@code X-Latency-Multiplier} header, 1 or 3. With no header it is 1 under the
 * {@code measured} profile and 0 otherwise. Every response carries {@code Server-Timing}: the injected delay
 * and the time the service itself took.
 */
@Component
public class MeasuredLatency extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(MeasuredLatency.class);

    public static final String HEADER = "X-Latency-Multiplier";

    static final Map<String, String> ENDPOINTS = Map.of(
            "POST /auth/attest", "auth.attest",
            "POST /auth/session", "auth.session",
            "POST /auth/refresh", "auth.refresh",
            "GET /accounts/summary", "account.summary",
            "GET /accounts/peek", "account.peek",
            "GET /paynow/lookup", "lookup",
            "POST /payments/paynow", "payment.submit");

    private final Map<String, Long> table = new HashMap<>();
    private final boolean profile;

    public MeasuredLatency(@Value("${latency.table:../latency/measured.json}") String path, Environment env) throws IOException {
        profile = env.acceptsProfiles(Profiles.of("measured"));
        Path file = Path.of(path).toAbsolutePath().normalize();
        JsonNode root = new ObjectMapper().readTree(file.toFile());
        root.fields().forEachRemaining(e -> {
            if (e.getValue().isNumber()) table.put(e.getKey(), e.getValue().asLong());
        });
        log.info("Latency table {}: {}, measured profile {}", file, table, profile);
    }

    /** The table's delay for a key such as {@code fast.settle}. */
    public long ms(String key) {
        Long ms = table.get(key);
        if (ms == null) throw new IllegalStateException("No measured latency for " + key);
        return ms;
    }

    /** The request's multiplier: 0 (no delay), 1 or 3. */
    public int multiplier(String header) {
        if (header == null || header.isBlank()) return profile ? 1 : 0;
        return switch (header.trim()) {
            case "1" -> 1;
            case "3" -> 3;
            default -> throw ApiException.badRequest(HEADER + " must be 1 or 3");
        };
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        int multiplier;
        try {
            multiplier = multiplier(req.getHeader(HEADER));
        } catch (ApiException e) {
            res.setStatus(e.status().value());
            res.setContentType("application/json");
            new ObjectMapper().writeValue(res.getOutputStream(), new ErrorBody(e.code(), e.getMessage()));
            return;
        }
        String key = ENDPOINTS.get(req.getMethod() + " " + req.getRequestURI());
        long delay = key == null ? 0 : ms(key) * multiplier;
        long start = System.nanoTime();
        if (delay > 0) {
            try {
                Thread.sleep(delay);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        long handled = System.nanoTime();
        ContentCachingResponseWrapper wrapped = new ContentCachingResponseWrapper(res);
        try {
            chain.doFilter(req, wrapped);
        } finally {
            long end = System.nanoTime();
            wrapped.setHeader("Server-Timing", "delay;dur=%d, app;dur=%.1f".formatted((handled - start) / 1_000_000, (end - handled) / 1e6));
            wrapped.copyBodyToResponse();
        }
    }
}
