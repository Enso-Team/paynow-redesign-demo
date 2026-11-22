package sg.dbs.demo.auth;

import java.math.BigInteger;
import java.security.AlgorithmParameters;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;

/** Parses P-256 device keys and checks ECDSA SHA-256 signatures. */
final class DeviceKeys {
    private DeviceKeys() {}

    /** Accepts a base64 X9.63 uncompressed point (65 bytes), or an SPKI DER key. */
    static PublicKey parse(String base64) throws Exception {
        byte[] raw = Base64.getDecoder().decode(base64.trim());
        KeyFactory kf = KeyFactory.getInstance("EC");
        if (raw.length == 65 && raw[0] == 0x04) {
            AlgorithmParameters params = AlgorithmParameters.getInstance("EC");
            params.init(new ECGenParameterSpec("secp256r1"));
            ECParameterSpec spec = params.getParameterSpec(ECParameterSpec.class);
            ECPoint point = new ECPoint(new BigInteger(1, Arrays.copyOfRange(raw, 1, 33)),
                    new BigInteger(1, Arrays.copyOfRange(raw, 33, 65)));
            return kf.generatePublic(new ECPublicKeySpec(point, spec));
        }
        return kf.generatePublic(new X509EncodedKeySpec(raw));
    }

    /** Verifies a base64 DER signature. A 64-byte raw r||s signature (WebCrypto) is accepted too. */
    static boolean verify(PublicKey key, byte[] message, String signatureBase64) {
        byte[] sig;
        try {
            sig = Base64.getDecoder().decode(signatureBase64.trim());
        } catch (IllegalArgumentException e) {
            return false;
        }
        if (check("SHA256withECDSA", key, message, sig)) return true;
        return sig.length == 64 && check("SHA256withECDSAinP1363Format", key, message, sig);
    }

    private static boolean check(String alg, PublicKey key, byte[] message, byte[] sig) {
        try {
            Signature s = Signature.getInstance(alg);
            s.initVerify(key);
            s.update(message);
            return s.verify(sig);
        } catch (Exception e) {
            return false;
        }
    }
}
