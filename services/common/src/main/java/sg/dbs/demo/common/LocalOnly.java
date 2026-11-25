package sg.dbs.demo.common;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;

import java.net.InetAddress;

public final class LocalOnly {
    private LocalOnly() {}

    public static void check(HttpServletRequest http) throws Exception {
        if (!InetAddress.getByName(http.getRemoteAddr()).isLoopbackAddress()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Internal endpoint");
        }
    }
}
