package sg.dbs.demo.common;

import org.springframework.http.HttpStatus;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.time.Duration;

/** Client for the mock PayNow directory, shared by the lookup and payment services. */
public class DirectoryClient {
    public record Proxy(String proxyType, String proxyValue, String maskedName, String bankCode) {}

    private final RestClient http;

    public DirectoryClient(String baseUrl, Duration timeout) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) timeout.toMillis());
        factory.setReadTimeout((int) timeout.toMillis());
        this.http = RestClient.builder().baseUrl(baseUrl).requestFactory(factory).build();
    }

    /** Returns the proxy, or throws 404 PROXY_NOT_FOUND or 504 DIRECTORY_TIMEOUT. */
    public Proxy resolve(String type, String value) {
        try {
            return http.get().uri("/directory/proxies/{type}/{value}", type, value).retrieve().body(Proxy.class);
        } catch (HttpClientErrorException.NotFound e) {
            throw new ApiException(HttpStatus.NOT_FOUND, "PROXY_NOT_FOUND", "No PayNow account for this proxy");
        } catch (ResourceAccessException e) {
            throw new ApiException(HttpStatus.GATEWAY_TIMEOUT, "DIRECTORY_TIMEOUT", "The PayNow directory didn't answer in time");
        } catch (Exception e) {
            throw new ApiException(HttpStatus.GATEWAY_TIMEOUT, "DIRECTORY_TIMEOUT", "The PayNow directory is unavailable");
        }
    }

    /** Checks the proxy format: a mobile is 8 digits starting with 8 or 9, a UEN is 9 or 10 characters. */
    public static void validate(String type, String value) {
        boolean ok = value != null && switch (type == null ? "" : type) {
            case "MOBILE" -> value.matches("[89]\\d{7}");
            case "UEN" -> value.matches("[A-Za-z0-9]{9,10}");
            default -> false;
        };
        if (!ok) throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PROXY", "Not a valid PayNow mobile number or UEN");
    }
}
