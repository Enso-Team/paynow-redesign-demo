package sg.dbs.demo.fast;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;
import sg.dbs.demo.common.MeasuredLatency;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/** Settles each payments.requested after fast.delay-ms, or the measured table's fast.settle. Bank code REJECT is rejected. */
@Component
public class FastSettlement {
    private static final Logger log = LoggerFactory.getLogger(FastSettlement.class);

    private final KafkaTemplate<String, String> kafka;
    private final ObjectMapper json;
    private final long delayMs;
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();

    public FastSettlement(KafkaTemplate<String, String> kafka, ObjectMapper json, @Value("${fast.delay-ms}") long delayMs,
                          ObjectProvider<MeasuredLatency> measured) {
        this.kafka = kafka;
        this.json = json;
        MeasuredLatency table = measured.getIfAvailable();
        this.delayMs = table == null ? delayMs : table.ms("fast.settle");
        log.info("Settling after {} ms", this.delayMs);
    }

    @KafkaListener(topics = "payments.requested")
    public void onRequested(String message) throws Exception {
        JsonNode event = json.readTree(message);
        String paymentId = event.path("paymentId").asText();
        boolean reject = "REJECT".equals(event.path("bankCode").asText());
        timer.schedule(() -> settle(paymentId, reject), delayMs, TimeUnit.MILLISECONDS);
    }

    private void settle(String paymentId, boolean reject) {
        Map<String, Object> settled = new LinkedHashMap<>();
        settled.put("paymentId", paymentId);
        settled.put("status", reject ? "REJECTED" : "SETTLED");
        settled.put("reason", reject ? "BENEFICIARY_BANK_REJECTED" : null);
        settled.put("settledAt", Instant.now().toString());
        try {
            kafka.send("payments.settled", paymentId, json.writeValueAsString(settled));
            log.info("Payment {} {}", paymentId, settled.get("status"));
        } catch (Exception e) {
            log.error("Couldn't publish payments.settled for {}", paymentId, e);
        }
    }
}
