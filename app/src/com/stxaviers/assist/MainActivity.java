package com.stxaviers.assist;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * XD Assist (v1.1.0) — the keyless connection app.
 *
 * v1.1.0 (owner order 2026-11-09): the entire key function is REMOVED and
 * the bridge is hardcoded to the permanent Cloudflare worker. Nothing to
 * configure — install, enable screen control, done.
 *
 * What the owner does here, in order:
 *   1. (optional) tap TEST BRIDGE → shows worker + device status
 *   2. tap ENABLE SCREEN CONTROL → Android Accessibility settings open;
 *      find "XD Assist screen control" and switch it ON
 *   3. done — the service now polls the permanent bridge and performs
 *      commands (tap / swipe / type / back / home / read screen) so the
 *      agent can drive this phone remotely. No key, ever.
 */
public class MainActivity extends Activity {

    // v1.1.0: hardcoded permanent bridge — the key system is gone.
    static final String WORKER = "https://xd-bridge.quackeditzofficial.workers.dev";

    private TextView status, log;
    private final StringBuilder logBuf = new StringBuilder();
    private final Handler h = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView sc = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        int pad = dp(20);
        root.setPadding(pad, dp(28), pad, pad);
        sc.addView(root);
        setContentView(sc);

        // ── title ─────────────────────────────────────────────────────
        TextView title = new TextView(this);
        title.setText("XD Assist");
        title.setTextSize(26f);
        title.setTextColor(0xFF171D3A);
        title.setTypeface(TypefaceProxy.medium(this));
        root.addView(title);
        TextView sub = new TextView(this);
        sub.setText("Keyless edition — connected to the permanent bridge. "
                + "Just enable screen control below.");
        sub.setTextSize(13.5f);
        sub.setTextColor(0xFF667089);
        root.addView(sub);
        space(root, 20);

        // ── bridge info ───────────────────────────────────────────────
        TextView url = new TextView(this);
        url.setText(WORKER);
        url.setTextSize(12.5f);
        url.setTextColor(0xFF2F6BFF);
        root.addView(url);
        space(root, 16);

        // ── test bridge ───────────────────────────────────────────────
        TextView test = button("TEST  BRIDGE", 0xFF2F6BFF, Color.WHITE);
        test.setOnClickListener(v -> testBridge());
        root.addView(test);
        space(root, 10);

        // ── enable accessibility ──────────────────────────────────────
        TextView enable = button("ENABLE SCREEN CONTROL", 0xFF171D3A, Color.WHITE);
        enable.setOnClickListener(v -> openAccessibilitySettings());
        root.addView(enable);
        space(root, 18);

        // ── status ────────────────────────────────────────────────────
        status = new TextView(this);
        status.setTextSize(14f);
        status.setTextColor(0xFF667089);
        status.setText("Bridge: not tested yet\nScreen control: unknown — enable it above");
        root.addView(status);
        space(root, 10);

        log = new TextView(this);
        log.setTextSize(11.5f);
        log.setTextColor(0xFF8A93A8);
        root.addView(log);

        refreshStatus();
    }

    // ── actions ────────────────────────────────────────────────────────

    private void testBridge() {
        toast("Testing the bridge…");
        appendLog("GET " + WORKER + "/health");
        new Thread(() -> {
            String result;
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(WORKER + "/health").openConnection();
                c.setConnectTimeout(9000);
                c.setReadTimeout(9009);
                c.setRequestProperty("User-Agent", "XDAssist/1.1.0 (Android)");
                int code = c.getResponseCode();
                InputStream is = code >= 400 ? c.getErrorStream() : c.getInputStream();
                String body = is == null ? "" : readAll(is);
                c.disconnect();
                if (code == 200) {
                    String dev = body.contains("\"device_connected\":true")
                            ? "Termux device: CONNECTED" : "Termux device: not connected";
                    result = "Bridge: ONLINE — " + dev;
                } else {
                    result = "Bridge: answered HTTP " + code + (body.isEmpty() ? "" : " — " + body);
                }
            } catch (Exception e) {
                result = "Bridge: UNREACHABLE — " + e.getMessage();
            }
            final String r = result;
            h.post(() -> {
                appendLog(r);
                status.setText(r + "\n" + screenControlState());
            });
        }, "test-bridge").start();
    }

    private void openAccessibilitySettings() {
        try {
            startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS));
            toast("Find \u201cXD Assist screen control\u201d and switch it ON");
        } catch (Throwable t) {
            toast("Could not open settings: " + t.getMessage());
        }
    }

    private void refreshStatus() {
        h.postDelayed(new Runnable() {
            @Override public void run() {
                if (!isFinishing()) {
                    status.setText(bridgeState() + "\n" + screenControlState());
                    h.postDelayed(this, 2500);
                }
            }
        }, 2500);
    }

    private String bridgeState() {
        return ScreenControlService.lastPollOk
                ? "Bridge: polling OK (permanent, keyless)"
                : "Bridge: " + WORKER;
    }

    private String screenControlState() {
        try {
            android.view.accessibility.AccessibilityManager am =
                    (android.view.accessibility.AccessibilityManager)
                            getSystemService(ACCESSIBILITY_SERVICE);
            boolean on = am != null && am.isEnabled() && ScreenControlService.connected;
            return "Screen control: " + (on ? "ON — the bridge can drive this phone"
                    : "OFF — tap ENABLE above, then switch XD Assist ON in settings");
        } catch (Throwable t) {
            return "Screen control: unknown";
        }
    }

    // ── small ui helpers ───────────────────────────────────────────────

    private TextView button(String text, int bg, int fg) {
        TextView b = new TextView(this);
        b.setText(text);
        b.setTextSize(15f);
        b.setTypeface(TypefaceProxy.medium(this));
        b.setTextColor(fg);
        b.setBackgroundColor(bg);
        b.setGravity(Gravity.CENTER);
        b.setPadding(dp(14), dp(14), dp(14), dp(14));
        return b;
    }

    private void space(LinearLayout root, int h) {
        View v = new View(this);
        root.addView(v, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(h)));
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
    }

    private void appendLog(String line) {
        logBuf.insert(0, line + "\n");
        if (logBuf.length() > 4000) logBuf.setLength(4000);
        log.setText(logBuf.toString());
    }

    private String readAll(InputStream is) throws Exception {
        java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = is.read(buf)) > 0) bos.write(buf, 0, n);
        return new String(bos.toByteArray()).trim();
    }
}

/** Typefaces without any dependency: framework default + a medium weight
 *  approximation via Typeface.create for pre-installed families. */
final class TypefaceProxy {
    static android.graphics.Typeface medium(Context c) {
        try {
            return android.graphics.Typeface.create("sans-serif-medium",
                    android.graphics.Typeface.NORMAL);
        } catch (Throwable t) {
            return android.graphics.Typeface.DEFAULT_BOLD;
        }
    }
}
