package sg.dbs.demo.directory;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.DirectoryClient.Proxy;
import sg.dbs.demo.common.MeasuredLatency;

import java.util.List;
import java.util.Map;

@RestController
public class DirectoryController {
    private final JdbcTemplate db;
    /** The made-up answer's own delay. The measured profile counts the lookup's time at the lookup service, so it's 0 there. */
    private final long madeUpMs;

    public DirectoryController(JdbcTemplate db, ObjectProvider<MeasuredLatency> measured) {
        this.db = db;
        this.madeUpMs = measured.getIfAvailable() == null ? 150 : 0;
    }

    @GetMapping("/directory/proxies/{type}/{value}")
    Proxy find(@PathVariable String type, @PathVariable String value) throws InterruptedException {
        List<Map<String, Object>> rows = db.queryForList(
                "SELECT type, value, masked_name, bank_code, latency_ms FROM proxies WHERE type = ? AND value = ?",
                type.toUpperCase(), value.toUpperCase());
        if (rows.isEmpty()) return registeredElsewhere(type.toUpperCase(), value.toUpperCase());
        Map<String, Object> row = rows.get(0);
        Thread.sleep(((Number) row.get("latency_ms")).longValue());
        return new Proxy((String) row.get("type"), (String) row.get("value"),
                (String) row.get("masked_name"), (String) row.get("bank_code"));
    }

    private static final String[] SURNAMES = {"TAN", "LIM", "LEE", "NG", "ONG", "WONG", "GOH", "CHUA", "CHAN", "KOH", "TEO", "ANG", "YEO", "TAY", "HO", "LOW", "TOH", "SIM", "CHONG", "CHIA"};
    private static final String[] COMPANY_WORDS = {"KOPI", "MAKAN", "LUCKY", "GOLDEN", "SUNRISE", "HAPPY", "MARINA", "ORCHID"};
    private static final String[] BANKS = {"DBS", "OCBC", "UOB"};
    private static final String LETTERS = "ABCDEFGHIJKLMNOPRSTUWY";

    // Answers any well-formed proxy that isn't seeded with a stable made-up masked name,
    // so real PayNow QR codes resolve in the demo. Mobiles starting 8000000 stay unregistered for testing.
    private Proxy registeredElsewhere(String type, String value) throws InterruptedException {
        boolean mobile = type.equals("MOBILE") && value.matches("[89]\\d{7}") && !value.startsWith("8000000");
        boolean uen = type.equals("UEN") && value.matches("[0-9A-Z]{9,10}");
        if (!mobile && !uen) throw new ApiException(HttpStatus.NOT_FOUND, "PROXY_NOT_FOUND", "No PayNow account for this proxy");
        int h = Math.abs(value.hashCode());
        String name = mobile
                ? SURNAMES[h % SURNAMES.length] + " ** **" + LETTERS.charAt((h / 7) % LETTERS.length()) + LETTERS.charAt((h / 131) % LETTERS.length())
                : COMPANY_WORDS[h % COMPANY_WORDS.length] + " **** PTE LTD";
        Thread.sleep(madeUpMs);
        return new Proxy(type, value, name, BANKS[(h / 17) % BANKS.length]);
    }
}
