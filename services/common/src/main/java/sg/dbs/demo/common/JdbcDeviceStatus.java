package sg.dbs.demo.common;

import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Reads {@code devices.revoked_at} live, with no cache, so a revocation applies to the next request. */
@Component
@ConditionalOnClass(name = "org.springframework.jdbc.core.JdbcTemplate")
class JdbcDeviceStatus implements DeviceStatus {
    private final JdbcTemplate db;

    JdbcDeviceStatus(JdbcTemplate db) {
        this.db = db;
    }

    @Override
    public boolean active(String deviceId) {
        Integer rows = db.queryForObject("SELECT COUNT(*) FROM devices WHERE id = ? AND revoked_at IS NULL",
                Integer.class, deviceId);
        return rows != null && rows > 0;
    }
}
