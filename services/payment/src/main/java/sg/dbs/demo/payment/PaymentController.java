package sg.dbs.demo.payment;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.DirectoryClient;
import sg.dbs.demo.common.DirectoryClient.Proxy;
import sg.dbs.demo.common.Jwt;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@RestController
public class PaymentController {
    record PayNowRequest(String fromAccountId, String proxyType, String proxyValue, BigDecimal amount,
                         String currency, String reference) {}

    @JsonInclude(JsonInclude.Include.NON_NULL)
    record PaymentView(String paymentId, String status, String reason, String amount, String maskedName, Instant settledAt) {}

    private record Row(String id, String userId, String status, PaymentView view) {}

    private final JdbcTemplate db;
    private final Jwt jwt;
    private final DirectoryClient directory;
    private final AccountClient accounts;
    private final KafkaTemplate<String, String> kafka;
    private final ObjectMapper json;
    private final long maxWaitMs;

    public PaymentController(JdbcTemplate db, Jwt jwt, DirectoryClient directory, AccountClient accounts,
                             KafkaTemplate<String, String> kafka, ObjectMapper json,
                             @Value("${payment.max-wait-ms}") long maxWaitMs) {
        this.db = db;
        this.jwt = jwt;
        this.directory = directory;
        this.accounts = accounts;
        this.kafka = kafka;
        this.json = json;
        this.maxWaitMs = maxWaitMs;
    }

    @PostMapping("/payments/paynow")
    ResponseEntity<Map<String, String>> pay(@RequestHeader(value = "Authorization", required = false) String authorization,
                                            @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                            @RequestBody PayNowRequest req) throws Exception {
        String userId = jwt.userId(authorization);
        if (key == null || key.isBlank() || key.length() > 64) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MISSING_IDEMPOTENCY_KEY", "Send an Idempotency-Key header");
        }
        Row existing = byKey(key);
        if (existing != null) return accepted(existing, userId);

        String type = req.proxyType() == null ? null : req.proxyType().toUpperCase();
        String value = req.proxyValue() == null ? null : req.proxyValue().trim().toUpperCase();
        DirectoryClient.validate(type, value);
        if (req.fromAccountId() == null) throw ApiException.badRequest("fromAccountId is required");
        if (req.amount() == null || req.amount().signum() <= 0 || req.amount().stripTrailingZeros().scale() > 2) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_AMOUNT", "Amount must be positive with at most 2 decimals");
        }
        if (req.currency() != null && !"SGD".equals(req.currency())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "UNSUPPORTED_CURRENCY", "Only SGD is supported");
        }
        BigDecimal amount = req.amount().setScale(2);

        Proxy proxy;
        try {
            proxy = directory.resolve(type, value);
        } catch (ApiException e) {
            if (!"PROXY_NOT_FOUND".equals(e.code())) throw e;
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROXY_NOT_FOUND", e.getMessage());
        }

        String paymentId = UUID.randomUUID().toString();
        accounts.hold(paymentId, req.fromAccountId(), amount, userId);
        Instant now = Instant.now();
        try {
            db.update("INSERT INTO payments (id, idempotency_key, user_id, from_account_id, proxy_type, proxy_value, "
                            + "masked_name, bank_code, amount, reference, status, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,'PENDING',?)",
                    paymentId, key, userId, req.fromAccountId(), type, value, proxy.maskedName(), proxy.bankCode(),
                    amount, req.reference(), Timestamp.from(now));
        } catch (DuplicateKeyException e) {
            accounts.release(paymentId);
            return accepted(byKey(key), userId);
        }

        Map<String, Object> event = new LinkedHashMap<>();
        event.put("paymentId", paymentId);
        event.put("fromAccountId", req.fromAccountId());
        event.put("proxyType", type);
        event.put("proxyValue", value);
        event.put("bankCode", proxy.bankCode());
        event.put("amount", amount.toPlainString());
        event.put("currency", "SGD");
        event.put("reference", req.reference());
        event.put("requestedAt", now.toString());
        kafka.send(PaymentApplication.REQUESTED, paymentId, json.writeValueAsString(event)).get(10, TimeUnit.SECONDS);
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(Map.of("paymentId", paymentId, "status", "PENDING"));
    }

    @GetMapping("/payments/{id}")
    PaymentView get(@RequestHeader(value = "Authorization", required = false) String authorization,
                    @PathVariable String id, @RequestParam(defaultValue = "0") long waitMs) throws InterruptedException {
        String userId = jwt.userId(authorization);
        long deadline = System.currentTimeMillis() + Math.min(Math.max(waitMs, 0), maxWaitMs);
        while (true) {
            Row row = one("SELECT * FROM payments WHERE id = ?", id);
            if (row == null || !row.userId().equals(userId)) {
                throw new ApiException(HttpStatus.NOT_FOUND, "PAYMENT_NOT_FOUND", "No such payment");
            }
            if (!"PENDING".equals(row.status()) || System.currentTimeMillis() >= deadline) return row.view();
            Thread.sleep(100);
        }
    }

    private ResponseEntity<Map<String, String>> accepted(Row row, String userId) {
        if (!row.userId().equals(userId)) {
            throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "This Idempotency-Key belongs to another payment");
        }
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(Map.of("paymentId", row.id(), "status", row.status()));
    }

    private Row byKey(String key) {
        return one("SELECT * FROM payments WHERE idempotency_key = ?", key);
    }

    private Row one(String sql, String arg) {
        List<Row> rows = db.query(sql, (rs, i) -> {
            Timestamp settled = rs.getTimestamp("settled_at");
            PaymentView view = new PaymentView(rs.getString("id"), rs.getString("status"), rs.getString("reason"),
                    rs.getBigDecimal("amount").toPlainString(), rs.getString("masked_name"),
                    settled == null ? null : settled.toInstant());
            return new Row(rs.getString("id"), rs.getString("user_id"), rs.getString("status"), view);
        }, arg);
        return rows.isEmpty() ? null : rows.get(0);
    }
}
