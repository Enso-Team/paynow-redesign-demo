package sg.dbs.demo.account;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.Jwt;

import java.math.BigDecimal;
import java.security.MessageDigest;
import java.text.DecimalFormat;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
public class SummaryController {
    record Account(String id, String name, String numberMasked, String balance, String available, String currency) {}

    private final JdbcTemplate db;
    private final Jwt jwt;
    private final ObjectMapper json;
    private final BigDecimal dailyLimit;
    private final ZoneId zone;

    public SummaryController(JdbcTemplate db, Jwt jwt, ObjectMapper json,
                             @Value("${paynow.daily-limit}") BigDecimal dailyLimit,
                             @Value("${paynow.zone}") ZoneId zone) {
        this.db = db;
        this.jwt = jwt;
        this.json = json;
        this.dailyLimit = dailyLimit;
        this.zone = zone;
    }

    @GetMapping("/accounts/summary")
    ResponseEntity<Map<String, Object>> summary(@RequestHeader(value = "Authorization", required = false) String authorization,
                                                @RequestHeader(value = "If-None-Match", required = false) String ifNoneMatch)
            throws Exception {
        String userId = jwt.userId(authorization);
        List<String> names = db.queryForList("SELECT display_name FROM users WHERE id = ?", String.class, userId);
        DecimalFormat display = new DecimalFormat("#,##0.00");
        List<Account> accounts = db.query(
                "SELECT a.id, a.name, a.number_masked, a.balance, a.currency, "
                        + "a.balance - COALESCE((SELECT SUM(h.amount) FROM holds h WHERE h.account_id = a.id AND h.status = 'HELD'), 0) AS available "
                        + "FROM accounts a WHERE a.user_id = ? ORDER BY a.id",
                (rs, i) -> new Account(rs.getString("id"), rs.getString("name"), rs.getString("number_masked"),
                        display.format(rs.getBigDecimal("balance")), rs.getBigDecimal("available").setScale(2).toPlainString(),
                        rs.getString("currency")),
                userId);
        List<BigDecimal> used = db.queryForList("SELECT used FROM paynow_usage WHERE user_id = ? AND day = ?",
                BigDecimal.class, userId, LocalDate.now(zone));

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("displayName", names.isEmpty() ? "" : names.get(0).toUpperCase());
        body.put("accounts", accounts);
        body.put("paynowDailyLimit", dailyLimit.setScale(2).toPlainString());
        body.put("paynowUsedToday", (used.isEmpty() ? BigDecimal.ZERO : used.get(0)).setScale(2).toPlainString());

        String etag = "\"" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(json.writeValueAsBytes(body)), 0, 12) + "\"";
        if (ifNoneMatch != null && List.of(ifNoneMatch.replace("W/", "").split("\\s*,\\s*")).contains(etag)) {
            return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(etag).cacheControl(CacheControl.noCache()).build();
        }
        body.put("updatedAt", Instant.now());
        return ResponseEntity.ok().eTag(etag).cacheControl(CacheControl.noCache()).body(body);
    }
}
