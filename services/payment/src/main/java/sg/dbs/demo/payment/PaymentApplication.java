package sg.dbs.demo.payment;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.kafka.config.TopicBuilder;
import sg.dbs.demo.common.DemoApp;
import sg.dbs.demo.common.DirectoryClient;

import java.time.Duration;

@SpringBootApplication(scanBasePackages = "sg.dbs.demo")
public class PaymentApplication {
    public static final String REQUESTED = "payments.requested";
    public static final String SETTLED = "payments.settled";

    public static void main(String[] args) {
        DemoApp.run(PaymentApplication.class, args);
    }

    @Bean
    DirectoryClient directoryClient(@Value("${directory.url}") String url, @Value("${directory.timeout}") Duration timeout) {
        return new DirectoryClient(url, timeout);
    }

    @Bean
    NewTopic requestedTopic() {
        return TopicBuilder.name(REQUESTED).partitions(1).replicas(1).build();
    }

    @Bean
    NewTopic settledTopic() {
        return TopicBuilder.name(SETTLED).partitions(1).replicas(1).build();
    }
}
