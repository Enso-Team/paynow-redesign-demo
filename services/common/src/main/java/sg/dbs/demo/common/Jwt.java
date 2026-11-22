package sg.dbs.demo.common;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/** HS256 JWTs with claims sub (userId), deviceId, exp and an optional scope. A scoped token only reaches endpoints that allow its scope. */
@Component
public class Jwt {
    public record Claims(String userId, String deviceId, Instant expiresAt, String scope) {}

    public static final String PEEK = "peek";

    private static final Base64.Encoder B64 = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder B64D = Base64.getUrlDecoder();
    private static final String HEADER = B64.encodeToString("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));

    private final byte[] secret;
    private final ObjectMapper json = new ObjectMapper();

    /** The shared HS256 secret comes from the JWT_SECRET environment variable (see services/.env.example). */
    public Jwt(@Value("${JWT_SECRET:}") String secret) {
        if (secret.isBlank()) {
            throw new IllegalStateException("JWT_SECRET is not set. Copy services/.env.example to services/.env and run scripts/up.sh.");
        }
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
    }

    public String sign(String userId, String deviceId, Instant expiresAt) {
        return sign(userId, deviceId, expiresAt, null);
    }

    public String sign(String userId, String deviceId, Instant expiresAt, String scope) {
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.put("sub", userId);
        claims.put("deviceId", deviceId);
        if (scope != null) claims.put("scope", scope);
        claims.put("iat", Instant.now().getEpochSecond());
        claims.put("exp", expiresAt.getEpochSecond());
        try {
            String payload = B64.encodeToString(json.writeValueAsBytes(claims));
            String signingInput = HEADER + "." + payload;
            return signingInput + "." + B64.encodeToString(hmac(signingInput));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    public Claims verify(String token) {
        String[] parts = token == null ? new String[0] : token.split("\\.");
        if (parts.length != 3) throw invalid();
        try {
            byte[] expected = hmac(parts[0] + "." + parts[1]);
            if (!MessageDigest.isEqual(expected, B64D.decode(parts[2]))) throw invalid();
            Map<?, ?> header = json.readValue(B64D.decode(parts[0]), Map.class);
            if (!"HS256".equals(header.get("alg"))) throw invalid();
            Map<?, ?> claims = json.readValue(B64D.decode(parts[1]), Map.class);
            Instant exp = Instant.ofEpochSecond(((Number) claims.get("exp")).longValue());
            if (exp.isBefore(Instant.now())) throw ApiException.unauthorized("TOKEN_EXPIRED", "Session expired");
            return new Claims((String) claims.get("sub"), (String) claims.get("deviceId"), exp, (String) claims.get("scope"));
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            throw invalid();
        }
    }

    /** Reads a full-session Bearer token from an Authorization header value and returns its userId. */
    public String userId(String authorization) {
        return userId(authorization, null);
    }

    /** Like {@link #userId(String)}, and also accepts a token carrying {@code allowedScope}. */
    public String userId(String authorization, String allowedScope) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            throw ApiException.unauthorized("UNAUTHORIZED", "Missing Bearer token");
        }
        Claims claims = verify(authorization.substring(7).trim());
        if (claims.scope() != null && !claims.scope().equals(allowedScope)) {
            throw ApiException.forbidden("SCOPE_NOT_ALLOWED", "This token can't reach this endpoint");
        }
        return claims.userId();
    }

    private byte[] hmac(String input) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret, "HmacSHA256"));
        return mac.doFinal(input.getBytes(StandardCharsets.UTF_8));
    }

    private static ApiException invalid() {
        return ApiException.unauthorized("UNAUTHORIZED", "Invalid token");
    }
}
