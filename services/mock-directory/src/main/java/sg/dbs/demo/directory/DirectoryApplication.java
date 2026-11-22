package sg.dbs.demo.directory;

import org.springframework.boot.autoconfigure.SpringBootApplication;
import sg.dbs.demo.common.DemoApp;

@SpringBootApplication(scanBasePackages = "sg.dbs.demo")
public class DirectoryApplication {
    public static void main(String[] args) {
        DemoApp.run(DirectoryApplication.class, args);
    }
}
