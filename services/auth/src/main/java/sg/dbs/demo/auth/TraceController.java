package sg.dbs.demo.auth;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.Jwt;
import sg.dbs.demo.common.LocalOnly;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Runs recorded by the iPhone app: spans with their kind and critical path flag. */
@RestController
public class TraceController {
    private static final Set<String> FLOWS = Set.of("sequential", "router");
    private static final int MAX_CHARS = 100_000;
    private static final int MAX_SPANS = 200;

    private final JdbcTemplate db;
    private final Jwt jwt;
    private final ObjectMapper json;

    public TraceController(JdbcTemplate db, Jwt jwt, ObjectMapper json) {
        this.db = db;
        this.jwt = jwt;
        this.json = json;
    }

    @PostMapping("/auth/traces")
    @ResponseStatus(HttpStatus.CREATED)
    Map<String, String> store(@RequestHeader(value = "Authorization", required = false) String authorization,
                              @RequestBody JsonNode trace) throws Exception {
        Jwt.Claims session = jwt.claims(authorization);
        String runId = trace.path("run_id").asText();
        String flow = trace.path("flow").asText();
        int multiplier = trace.path("multiplier").asInt();
        JsonNode spans = trace.path("spans");
        String body = json.writeValueAsString(trace);
        if (!runId.matches("[0-9A-Fa-f-]{36}") || !FLOWS.contains(flow) || (multiplier != 1 && multiplier != 3)
                || !spans.isArray() || spans.isEmpty() || spans.size() > MAX_SPANS || body.length() > MAX_CHARS) {
            throw ApiException.badRequest("run_id, flow, multiplier and 1 to " + MAX_SPANS + " spans are required");
        }
        db.update("INSERT IGNORE INTO traces (run_id, flow, multiplier, device_id, body, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                runId, flow, multiplier, session.deviceId(), body, Timestamp.from(Instant.now()));
        return Map.of("runId", runId);
    }

    /** Localhost only, for the replot script on the Mac. */
    @GetMapping("/auth/traces/latest")
    JsonNode latest(@RequestParam(required = false) String flow, @RequestParam(required = false) Integer multiplier,
                    HttpServletRequest http) throws Exception {
        LocalOnly.check(http);
        List<String> rows = db.queryForList("SELECT body FROM traces WHERE (? IS NULL OR flow = ?) AND (? IS NULL OR multiplier = ?) "
                + "ORDER BY id DESC LIMIT 1", String.class, flow, flow, multiplier, multiplier);
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "TRACE_NOT_FOUND", "No run recorded");
        return json.readTree(rows.get(0));
    }
}
