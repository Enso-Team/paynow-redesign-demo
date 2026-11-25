package sg.dbs.demo.common;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;

/** Binds a step-up token to one payment, so it can't approve another payee, amount or Idempotency-Key. */
public record StepUp(String fromAccountId, String proxyType, String proxyValue, BigDecimal amount, String idempotencyKey) {
    public boolean complete() {
        return fromAccountId != null && proxyType != null && proxyValue != null && amount != null && idempotencyKey != null;
    }

    /** SHA-256 hex of {@code fromAccountId|proxyType|proxyValue|amount|idempotencyKey}, with the amount at 2 decimals. */
    public String binding() {
        String text = String.join("|", fromAccountId, proxyType.toUpperCase(), proxyValue.trim().toUpperCase(),
                amount.setScale(2, RoundingMode.UNNECESSARY).toPlainString(), idempotencyKey);
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    public String scope() {
        return "stepup:" + binding();
    }
}
