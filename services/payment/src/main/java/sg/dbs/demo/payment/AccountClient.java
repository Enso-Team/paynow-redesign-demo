package sg.dbs.demo.payment;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import sg.dbs.demo.common.ApiException;
import sg.dbs.demo.common.ErrorBody;

import java.math.BigDecimal;
import java.util.Map;

/** Calls the account service's internal hold endpoints. Errors pass through with their code. */
@Component
public class AccountClient {
    private final RestClient http;

    public AccountClient(@Value("${account.url}") String url) {
        this.http = RestClient.builder().baseUrl(url).build();
    }

    public void hold(String paymentId, String accountId, BigDecimal amount, String userId) {
        call("/internal/holds", Map.of("paymentId", paymentId, "accountId", accountId,
                "amount", amount.toPlainString(), "userId", userId));
    }

    public void capture(String paymentId) {
        call("/internal/holds/" + paymentId + "/capture", Map.of());
    }

    public void release(String paymentId) {
        call("/internal/holds/" + paymentId + "/release", Map.of());
    }

    private void call(String path, Map<String, Object> body) {
        try {
            http.post().uri(path).body(body).exchange((req, res) -> {
                if (res.getStatusCode().is2xxSuccessful()) return null;
                ErrorBody error = res.bodyTo(ErrorBody.class);
                throw new ApiException(HttpStatus.valueOf(res.getStatusCode().value()),
                        error == null ? "ACCOUNT_ERROR" : error.code(), error == null ? "Account service error" : error.message());
            });
        } catch (ResourceAccessException e) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "ACCOUNT_UNAVAILABLE", "The account service is unavailable");
        }
    }
}
