package sg.dbs.demo.lookup;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import sg.dbs.demo.common.DemoApp;
import sg.dbs.demo.common.DirectoryClient;

import java.time.Duration;

@SpringBootApplication(scanBasePackages = "sg.dbs.demo")
public class LookupApplication {
    public static void main(String[] args) {
        DemoApp.run(LookupApplication.class, args);
    }

    @Bean
    DirectoryClient directoryClient(@Value("${directory.url}") String url, @Value("${directory.timeout}") Duration timeout) {
        return new DirectoryClient(url, timeout);
    }
}
