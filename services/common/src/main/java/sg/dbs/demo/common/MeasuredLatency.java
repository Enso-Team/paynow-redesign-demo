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
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * The {@code measured} profile: each endpoint below waits the time a real banking app spends on it,
 * read from the shared table at {@code latency.table} (default {@code ../latency/measured.json}, relative to services/).
 */
@Component
@Profile("measured")
public class MeasuredLatency extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(MeasuredLatency.class);

    static final Map<String, String> ENDPOINTS = Map.of(
            "POST /auth/session", "auth.session",
            "POST /auth/refresh", "auth.refresh",
            "GET /accounts/summary", "account.summary",
            "GET /accounts/peek", "account.peek",
            "GET /paynow/lookup", "lookup",
            "POST /payments/paynow", "payment.submit");

    private final Map<String, Long> table = new HashMap<>();

    public MeasuredLatency(@Value("${latency.table:../latency/measured.json}") String path) throws IOException {
        Path file = Path.of(path).toAbsolutePath().normalize();
        JsonNode root = new ObjectMapper().readTree(file.toFile());
        root.fields().forEachRemaining(e -> {
            if (e.getValue().isNumber()) table.put(e.getKey(), e.getValue().asLong());
        });
        log.info("Measured latency on, from {}: {}", file, table);
    }

    /** The table's delay for a key such as {@code fast.settle}. */
    public long ms(String key) {
        Long ms = table.get(key);
        if (ms == null) throw new IllegalStateException("No measured latency for " + key);
        return ms;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String key = ENDPOINTS.get(req.getMethod() + " " + req.getRequestURI());
        if (key != null) {
            try {
                Thread.sleep(ms(key));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        chain.doFilter(req, res);
    }
}
