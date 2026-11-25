package sg.dbs.demo.common;

/** Whether a device may still use its tokens. Read on every token check. */
public interface DeviceStatus {
    boolean active(String deviceId);
}
