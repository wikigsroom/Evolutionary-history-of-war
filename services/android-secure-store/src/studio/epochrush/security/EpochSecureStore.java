package studio.epochrush.security;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/** Installation credentials encrypted by a non-exportable Android Keystore key. */
public final class EpochSecureStore extends GodotPlugin {
    private static final String KEY = "SIDcloud.EpochRush.Online.v1";
    public EpochSecureStore(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "EpochSecureStore"; }
    private SharedPreferences preferences() {
        return getActivity().getSharedPreferences("epoch_online_secrets", Context.MODE_PRIVATE);
    }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(KEY)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setUserAuthenticationRequired(false).build());
            generator.generateKey();
        }
        return (SecretKey) store.getKey(KEY, null);
    }
    private boolean validAlias(String alias) { return alias != null && alias.matches("epoch_online_[a-f0-9]{24}"); }
    @UsedByGodot public String readSecret(String alias) {
        if (!validAlias(alias)) return "__ERROR__";
        String saved = preferences().getString(alias, "");
        if (saved.isEmpty()) return "";
        try {
            String[] fields = saved.split(":", 2);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(fields[0], Base64.NO_WRAP)));
            return new String(cipher.doFinal(Base64.decode(fields[1], Base64.NO_WRAP)), java.nio.charset.StandardCharsets.UTF_8);
        } catch (Exception ignored) { return "__ERROR__"; }
    }
    @UsedByGodot public boolean writeSecret(String alias, String value) {
        if (!validAlias(alias) || value == null || !value.matches("[a-f0-9]{64}")) return false;
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key());
            String stored = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + ":" +
                Base64.encodeToString(cipher.doFinal(value.getBytes(java.nio.charset.StandardCharsets.UTF_8)), Base64.NO_WRAP);
            return preferences().edit().putString(alias, stored).commit();
        } catch (Exception ignored) { return false; }
    }
}
