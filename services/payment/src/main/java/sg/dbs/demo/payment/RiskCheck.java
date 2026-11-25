package sg.dbs.demo.payment;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.Jwt;
import sg.dbs.demo.common.StepUp;

import java.math.BigDecimal;

/** The fraud check at Pay. A payee with no settled payment, or an amount over the threshold, needs a step-up token. */
@Component
class RiskCheck {
    private final JdbcTemplate db;
    private final Jwt jwt;
    private final BigDecimal threshold;

    RiskCheck(JdbcTemplate db, Jwt jwt, @Value("${payment.step-up-over}") BigDecimal threshold) {
        this.db = db;
        this.jwt = jwt;
        this.threshold = threshold;
    }

    void require(Jwt.Claims session, StepUp payment, String stepUpToken) {
        boolean large = payment.amount().compareTo(threshold) > 0;
        if (!large && knownPayee(session.userId(), payment)) return;
        if (stepUpToken == null || stepUpToken.isBlank()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "STEP_UP_REQUIRED",
                    large ? "Confirm this large payment" : "Confirm this new payee");
        }
        Jwt.Claims token = jwt.verify(stepUpToken);
        if (!payment.scope().equals(token.scope()) || !session.userId().equals(token.userId())
                || !session.deviceId().equals(token.deviceId())) {
            throw ApiException.forbidden("STEP_UP_INVALID", "This approval is for another payment");
        }
    }

    private boolean knownPayee(String userId, StepUp payment) {
        Integer settled = db.queryForObject("SELECT COUNT(*) FROM payments WHERE user_id = ? AND proxy_type = ? "
                + "AND proxy_value = ? AND status = 'SETTLED'", Integer.class, userId, payment.proxyType(), payment.proxyValue());
        return settled != null && settled > 0;
    }
}
