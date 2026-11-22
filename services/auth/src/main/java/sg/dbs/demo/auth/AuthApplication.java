package sg.dbs.demo.auth;

import org.springframework.boot.autoconfigure.SpringBootApplication;
import sg.dbs.demo.common.DemoApp;

@SpringBootApplication(scanBasePackages = "sg.dbs.demo")
public class AuthApplication {
    public static void main(String[] args) {
        DemoApp.run(AuthApplication.class, args);
    }
}
