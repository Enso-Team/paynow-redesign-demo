package sg.dbs.demo.auth;

import com.fasterxml.jackson.annotation.JsonInclude;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.Jwt;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
public class AuthController {
    record RegisterRequest(String username, String otp, String deviceName, String publicKey, String scope) {}
    record ChallengeRequest(String deviceId) {}
    record SessionRequest(String deviceId, String nonce, String signature, String scope) {}
    record RefreshRequest(String refreshToken) {}
    @JsonInclude(JsonInclude.Include.NON_NULL)
    record Tokens(String accessToken, String refreshToken, Instant expiresAt) {}

    static final String FULL = "full";

    private final JdbcTemplate db;
    private final Jwt jwt;
    private final SecureRandom random = new SecureRandom();
    private final String otp;
    private final Duration accessTtl;
    private final Duration refreshTtl;
    private final Duration nonceTtl;
    private final Duration peekTtl;

    public AuthController(JdbcTemplate db, Jwt jwt,
                          @Value("${auth.otp}") String otp,
                          @Value("${auth.access-ttl}") Duration accessTtl,
                          @Value("${auth.refresh-ttl}") Duration refreshTtl,
                          @Value("${auth.nonce-ttl}") Duration nonceTtl,
                          @Value("${auth.peek-ttl}") Duration peekTtl) {
        this.db = db;
        this.jwt = jwt;
        this.otp = otp;
        this.accessTtl = accessTtl;
        this.refreshTtl = refreshTtl;
        this.nonceTtl = nonceTtl;
        this.peekTtl = peekTtl;
    }

    @PostMapping("/auth/devices")
    @ResponseStatus(HttpStatus.CREATED)
    Map<String, String> register(@RequestBody RegisterRequest req) {
        List<String> users = db.queryForList("SELECT id FROM users WHERE username = ?", String.class, req.username());
        if (users.isEmpty() || !otp.equals(req.otp())) {
            throw ApiException.unauthorized("BAD_OTP", "The username or one-time password is wrong");
        }
        if (req.publicKey() == null) throw ApiException.badRequest("publicKey is required");
        try {
            DeviceKeys.parse(req.publicKey());
        } catch (Exception e) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "BAD_PUBLIC_KEY", "publicKey must be a base64 X9.63 P-256 public key");
        }
        String scope = req.scope() == null ? FULL : req.scope();
        if (!FULL.equals(scope) && !Jwt.PEEK.equals(scope)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "BAD_SCOPE", "scope must be \"full\", \"peek\" or left out");
        }
        String deviceId = UUID.randomUUID().toString();
        String name = req.deviceName() == null || req.deviceName().isBlank() ? "Device" : req.deviceName();
        db.update("INSERT INTO devices (id, user_id, public_key, name, scope, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                deviceId, users.get(0), req.publicKey().trim(), name, scope, Timestamp.from(Instant.now()));
        return Map.of("deviceId", deviceId, "userId", users.get(0));
    }

    @PostMapping("/auth/challenge")
    Map<String, Object> challenge(@RequestBody ChallengeRequest req) {
        device(req.deviceId());
        String nonce = randomToken();
        Instant expiresAt = Instant.now().plus(nonceTtl);
        db.update("DELETE FROM nonces WHERE expires_at < ?", Timestamp.from(Instant.now()));
        db.update("INSERT INTO nonces (nonce, device_id, expires_at) VALUES (?, ?, ?)",
                nonce, req.deviceId(), Timestamp.from(expiresAt));
        return Map.of("nonce", nonce, "expiresAt", expiresAt);
    }

    @PostMapping("/auth/session")
    @Transactional(noRollbackFor = ApiException.class)
    Tokens session(@RequestBody SessionRequest req) {
        if (req.scope() != null && !Jwt.PEEK.equals(req.scope())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "BAD_SCOPE", "scope must be \"peek\" or left out");
        }
        Map<String, Object> device = device(req.deviceId());
        List<Timestamp> expiry = db.queryForList(
                "SELECT expires_at FROM nonces WHERE nonce = ? AND device_id = ? FOR UPDATE",
                Timestamp.class, req.nonce(), req.deviceId());
        if (expiry.isEmpty() || expiry.get(0).toInstant().isBefore(Instant.now())) {
            throw ApiException.unauthorized("NONCE_EXPIRED", "The challenge expired. Ask for a new one");
        }
        db.update("DELETE FROM nonces WHERE nonce = ?", req.nonce());
        PublicKey key;
        try {
            key = DeviceKeys.parse((String) device.get("public_key"));
        } catch (Exception e) {
            throw ApiException.unauthorized("DEVICE_UNKNOWN", "The device key is unreadable");
        }
        if (req.signature() == null || !DeviceKeys.verify(key, req.nonce().getBytes(StandardCharsets.UTF_8), req.signature())) {
            throw ApiException.unauthorized("BAD_SIGNATURE", "The signature doesn't match this device");
        }
        if (Jwt.PEEK.equals(device.get("scope")) && !Jwt.PEEK.equals(req.scope())) {
            throw ApiException.forbidden("SCOPE_NOT_ALLOWED", "This device key only opens Peek Balance");
        }
        if (Jwt.PEEK.equals(req.scope())) {
            Instant peekExpiry = Instant.now().plus(peekTtl);
            return new Tokens(jwt.sign((String) device.get("user_id"), req.deviceId(), peekExpiry, Jwt.PEEK), null, peekExpiry);
        }
        return issue((String) device.get("user_id"), req.deviceId());
    }

    @PostMapping("/auth/refresh")
    @Transactional(noRollbackFor = ApiException.class)
    Tokens refresh(@RequestBody RefreshRequest req) {
        String hash = sha256(req.refreshToken() == null ? "" : req.refreshToken());
        List<Map<String, Object>> rows = db.queryForList(
                "SELECT r.device_id, r.expires_at, d.user_id FROM refresh_tokens r JOIN devices d ON d.id = r.device_id "
                        + "WHERE r.token_hash = ? AND d.revoked_at IS NULL FOR UPDATE", hash);
        db.update("DELETE FROM refresh_tokens WHERE token_hash = ?", hash);
        if (rows.isEmpty() || ((Timestamp) rows.get(0).get("expires_at")).toInstant().isBefore(Instant.now())) {
            throw ApiException.unauthorized("REFRESH_EXPIRED", "The session ended. Sign in again");
        }
        return issue((String) rows.get(0).get("user_id"), (String) rows.get(0).get("device_id"));
    }

    private Tokens issue(String userId, String deviceId) {
        Instant now = Instant.now();
        Instant accessExpiry = now.plus(accessTtl);
        String refreshToken = randomToken();
        db.update("DELETE FROM refresh_tokens WHERE expires_at < ?", Timestamp.from(now));
        db.update("INSERT INTO refresh_tokens (token_hash, device_id, expires_at) VALUES (?, ?, ?)",
                sha256(refreshToken), deviceId, Timestamp.from(now.plus(refreshTtl)));
        return new Tokens(jwt.sign(userId, deviceId, accessExpiry), refreshToken, accessExpiry);
    }

    private Map<String, Object> device(String deviceId) {
        List<Map<String, Object>> rows = db.queryForList(
                "SELECT user_id, public_key, scope FROM devices WHERE id = ? AND revoked_at IS NULL", deviceId);
        if (rows.isEmpty()) throw ApiException.unauthorized("DEVICE_UNKNOWN", "This device isn't registered");
        return rows.get(0);
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
