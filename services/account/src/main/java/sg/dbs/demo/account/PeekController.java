package sg.dbs.demo.account;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.Jwt;

import java.sql.Timestamp;
import java.text.DecimalFormat;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

/** Peek Balance: the first deposit account's balance and its latest 3 transactions from the last 30 days. */
@RestController
public class PeekController {
    record Transaction(String type, String date, String amount) {}
    record Peek(String balance, String currency, Instant asOf, List<Transaction> transactions) {}

    private static final Duration WINDOW = Duration.ofDays(30);

    private final JdbcTemplate db;
    private final Jwt jwt;
    private final ZoneId zone;

    public PeekController(JdbcTemplate db, Jwt jwt, @Value("${paynow.zone}") ZoneId zone) {
        this.db = db;
        this.jwt = jwt;
        this.zone = zone;
    }

    @GetMapping("/accounts/peek")
    ResponseEntity<Peek> peek(@RequestHeader(value = "Authorization", required = false) String authorization) {
        String userId = jwt.userId(authorization, Jwt.PEEK);
        List<Map<String, Object>> accounts = db.queryForList(
                "SELECT id, balance, currency FROM accounts WHERE user_id = ? ORDER BY id LIMIT 1", userId);
        if (accounts.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "ACCOUNT_NOT_FOUND", "No deposit account");
        Map<String, Object> account = accounts.get(0);
        Instant now = Instant.now();
        List<Transaction> transactions = db.query(
                "SELECT type, amount, posted_at FROM transactions WHERE account_id = ? AND posted_at >= ? "
                        + "ORDER BY posted_at DESC LIMIT 3",
                (rs, i) -> new Transaction(rs.getString("type"),
                        rs.getTimestamp("posted_at").toInstant().atZone(zone).toLocalDate().toString(),
                        rs.getBigDecimal("amount").setScale(2).toPlainString()),
                account.get("id"), Timestamp.from(now.minus(WINDOW)));
        Peek body = new Peek(new DecimalFormat("#,##0.00").format(account.get("balance")),
                (String) account.get("currency"), now, transactions);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
