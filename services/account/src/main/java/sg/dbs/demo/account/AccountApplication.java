package sg.dbs.demo.account;

import org.springframework.boot.autoconfigure.SpringBootApplication;
import sg.dbs.demo.common.DemoApp;

@SpringBootApplication(scanBasePackages = "sg.dbs.demo")
public class AccountApplication {
    public static void main(String[] args) {
        DemoApp.run(AccountApplication.class, args);
    }
}
