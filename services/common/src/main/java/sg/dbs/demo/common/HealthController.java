package sg.dbs.demo.common;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {
    private final String name;

    public HealthController(@Value("${spring.application.name:service}") String name) {
        this.name = name;
    }

    @GetMapping("/health")
    Map<String, String> health() {
        return Map.of("service", name, "status", "UP");
    }
}
