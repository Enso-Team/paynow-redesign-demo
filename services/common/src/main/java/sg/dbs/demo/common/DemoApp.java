package sg.dbs.demo.common;

import org.springframework.boot.SpringApplication;

import java.util.TimeZone;

public final class DemoApp {
    private DemoApp() {}

    /** Runs a service in UTC, so DATETIME columns and Instants line up. */
    public static void run(Class<?> app, String[] args) {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
        SpringApplication.run(app, args);
    }
}
