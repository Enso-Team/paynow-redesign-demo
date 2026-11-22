package sg.dbs.demo.fast;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.kafka.config.TopicBuilder;
import sg.dbs.demo.common.DemoApp;

@SpringBootApplication(scanBasePackages = "sg.dbs.demo")
public class FastApplication {
    public static void main(String[] args) {
        DemoApp.run(FastApplication.class, args);
    }

    @Bean
    NewTopic requestedTopic() {
        return TopicBuilder.name("payments.requested").partitions(1).replicas(1).build();
    }

    @Bean
    NewTopic settledTopic() {
        return TopicBuilder.name("payments.settled").partitions(1).replicas(1).build();
    }
}
