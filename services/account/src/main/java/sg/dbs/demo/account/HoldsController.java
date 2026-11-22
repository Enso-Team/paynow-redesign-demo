package sg.dbs.demo.account;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;

import java.math.BigDecimal;
import java.net.InetAddress;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

/** Holds for the payment service. Localhost only, no user token. */
@RestController
public class HoldsController {
    record HoldRequest(String paymentId, String accountId, BigDecimal amount, String userId) {}

    private final JdbcTemplate db;
    private final BigDecimal dailyLimit;
    private final ZoneId zone;

    public HoldsController(JdbcTemplate db, @Value("${paynow.daily-limit}") BigDecimal dailyLimit,
                           @Value("${paynow.zone}") ZoneId zone) {
        this.db = db;
        this.dailyLimit = dailyLimit;
        this.zone = zone;
    }

    @PostMapping("/internal/holds")
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    Map<String, Object> place(@RequestBody HoldRequest req, HttpServletRequest http) throws Exception {
        localOnly(http);
        if (req.paymentId() == null || req.accountId() == null || req.amount() == null || req.amount().signum() <= 0) {
            throw ApiException.badRequest("paymentId, accountId and a positive amount are required");
        }
        List<Map<String, Object>> existing = db.queryForList("SELECT status FROM holds WHERE payment_id = ?", req.paymentId());
        if (!existing.isEmpty()) return Map.of("paymentId", req.paymentId(), "status", existing.get(0).get("status"));

        List<Map<String, Object>> rows = db.queryForList(
                "SELECT user_id, balance FROM accounts WHERE id = ? FOR UPDATE", req.accountId());
        if (rows.isEmpty() || (req.userId() != null && !req.userId().equals(rows.get(0).get("user_id")))) {
            throw new ApiException(HttpStatus.NOT_FOUND, "ACCOUNT_NOT_FOUND", "No such account");
        }
        String userId = (String) rows.get(0).get("user_id");
        BigDecimal held = db.queryForObject(
                "SELECT COALESCE(SUM(amount), 0) FROM holds WHERE account_id = ? AND status = 'HELD'", BigDecimal.class, req.accountId());
        BigDecimal available = ((BigDecimal) rows.get(0).get("balance")).subtract(held);
        if (req.amount().compareTo(available) > 0) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "INSUFFICIENT_FUNDS", "Not enough in this account");
        }
        LocalDate today = LocalDate.now(zone);
        db.update("INSERT IGNORE INTO paynow_usage (user_id, day, used) VALUES (?, ?, 0)", userId, today);
        BigDecimal used = db.queryForObject("SELECT used FROM paynow_usage WHERE user_id = ? AND day = ? FOR UPDATE",
                BigDecimal.class, userId, today);
        if (used.add(req.amount()).compareTo(dailyLimit) > 0) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "LIMIT_EXCEEDED", "Over your PayNow daily limit");
        }
        db.update("UPDATE paynow_usage SET used = used + ? WHERE user_id = ? AND day = ?", req.amount(), userId, today);
        db.update("INSERT INTO holds (payment_id, account_id, amount, status) VALUES (?, ?, ?, 'HELD')",
                req.paymentId(), req.accountId(), req.amount());
        return Map.of("paymentId", req.paymentId(), "status", "HELD");
    }

    @PostMapping("/internal/holds/{paymentId}/capture")
    @Transactional
    Map<String, Object> capture(@PathVariable String paymentId, HttpServletRequest http) throws Exception {
        localOnly(http);
        Map<String, Object> hold = lock(paymentId);
        if ("HELD".equals(hold.get("status"))) {
            db.update("UPDATE accounts SET balance = balance - ? WHERE id = ?", hold.get("amount"), hold.get("account_id"));
            db.update("UPDATE holds SET status = 'CAPTURED' WHERE payment_id = ?", paymentId);
            db.update("INSERT IGNORE INTO transactions (id, account_id, type, amount, posted_at) VALUES (?, ?, 'PayNow Transfer', ?, ?)",
                    paymentId, hold.get("account_id"), ((BigDecimal) hold.get("amount")).negate(), Timestamp.from(Instant.now()));
            return Map.of("paymentId", paymentId, "status", "CAPTURED");
        }
        return Map.of("paymentId", paymentId, "status", hold.get("status"));
    }

    @PostMapping("/internal/holds/{paymentId}/release")
    @Transactional
    Map<String, Object> release(@PathVariable String paymentId, HttpServletRequest http) throws Exception {
        localOnly(http);
        Map<String, Object> hold = lock(paymentId);
        if ("HELD".equals(hold.get("status"))) {
            db.update("UPDATE paynow_usage u JOIN accounts a ON a.user_id = u.user_id "
                            + "SET u.used = GREATEST(0, u.used - ?) WHERE a.id = ? AND u.day = ?",
                    hold.get("amount"), hold.get("account_id"), LocalDate.now(zone));
            db.update("UPDATE holds SET status = 'RELEASED' WHERE payment_id = ?", paymentId);
            return Map.of("paymentId", paymentId, "status", "RELEASED");
        }
        return Map.of("paymentId", paymentId, "status", hold.get("status"));
    }

    private Map<String, Object> lock(String paymentId) {
        List<Map<String, Object>> rows = db.queryForList(
                "SELECT account_id, amount, status FROM holds WHERE payment_id = ? FOR UPDATE", paymentId);
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "HOLD_NOT_FOUND", "No hold for this payment");
        return rows.get(0);
    }

    private static void localOnly(HttpServletRequest http) throws Exception {
        if (!InetAddress.getByName(http.getRemoteAddr()).isLoopbackAddress()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Internal endpoint");
        }
    }
}
