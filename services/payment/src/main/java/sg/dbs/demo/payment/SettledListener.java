package sg.dbs.demo.payment;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;

/** Applies payments.settled: SETTLED captures the hold, REJECTED releases it. */
@Component
public class SettledListener {
    private static final Logger log = LoggerFactory.getLogger(SettledListener.class);

    private final JdbcTemplate db;
    private final AccountClient accounts;
    private final ObjectMapper json;

    public SettledListener(JdbcTemplate db, AccountClient accounts, ObjectMapper json) {
        this.db = db;
        this.accounts = accounts;
        this.json = json;
    }

    @KafkaListener(topics = PaymentApplication.SETTLED)
    public void onSettled(String message) throws Exception {
        JsonNode event = json.readTree(message);
        String paymentId = event.path("paymentId").asText();
        String status = event.path("status").asText();
        List<String> current = db.queryForList("SELECT status FROM payments WHERE id = ?", String.class, paymentId);
        if (current.isEmpty() || !"PENDING".equals(current.get(0))) return;

        if ("SETTLED".equals(status)) {
            accounts.capture(paymentId);
        } else if ("REJECTED".equals(status)) {
            accounts.release(paymentId);
        } else {
            log.warn("Ignoring payments.settled with status {}", status);
            return;
        }
        String reason = event.hasNonNull("reason") ? event.get("reason").asText() : null;
        Instant settledAt = event.hasNonNull("settledAt") ? Instant.parse(event.get("settledAt").asText()) : Instant.now();
        db.update("UPDATE payments SET status = ?, reason = ?, settled_at = ? WHERE id = ? AND status = 'PENDING'",
                status, reason, Timestamp.from(settledAt), paymentId);
        log.info("Payment {} {}", paymentId, status);
    }
}
