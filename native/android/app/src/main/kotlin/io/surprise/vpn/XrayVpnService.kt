package io.surprise.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.EventChannel
import libXray.LibXray
import org.json.JSONObject
import java.io.File

/** Bridges native VPN state to Flutter's EventChannel. */
object VpnBus {
    @Volatile var sink: EventChannel.EventSink? = null
    @Volatile var last: String = "disconnected"
    private val handler = Handler(Looper.getMainLooper())

    fun emit(state: String) {
        last = state
        handler.post { sink?.success(state) }
    }
}

/**
 * TUN-mode VPN. The system TUN fd from VpnService.establish() is handed to
 * Xray-core's native tun inbound through the config's root `env` ("xray.tun.fd").
 *
 * This app's own sockets (Xray outbounds, SSH) are excluded from the VPN with
 * addDisallowedApplication, so no socket-protect callback is needed and there are no loops.
 */
class XrayVpnService : VpnService() {
    private var pfd: ParcelFileDescriptor? = null
    @Volatile private var running = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START" -> {
                showNotification()
                Thread { startVpn(intent) }.start()
            }
            else -> stopVpn()
        }
        return START_NOT_STICKY
    }

    private fun startVpn(intent: Intent) {
        try {
            if (running) stopCore()
            VpnBus.emit("connecting")

            val runFile = File(filesDir, "run.json")
            val cfg = JSONObject(runFile.readText())
            runFile.delete()

            val mtu = intent.getIntExtra("mtu", 1500)
            val dns = intent.getStringExtra("dns") ?: "1.1.1.1"
            val perApp = intent.getBooleanExtra("perApp", false)
            val apps = intent.getStringArrayListExtra("apps") ?: arrayListOf()

            val b = Builder()
                .setSession("XRay VPN")
                .setMtu(mtu)
                .addAddress("10.10.14.1", 30)
                .addRoute("0.0.0.0", 0)
                .addAddress("fdfe:dcba:9876::1", 126) // v6 is routed too, so nothing leaks around the tunnel
                .addRoute("::", 0)
                .addDnsServer(dns)
                .setMetered(false)

            var allowed = 0
            if (perApp) {
                for (a in apps) {
                    try { b.addAllowedApplication(a); allowed++ } catch (_: Exception) {}
                }
            }
            if (allowed == 0) {
                // Global mode: everything except this app (Xray + SSH sockets stay outside the tunnel).
                b.addDisallowedApplication(packageName)
            }

            val fd = b.establish() ?: throw IllegalStateException("VPN permission revoked (establish returned null)")
            pfd = fd

            val env = cfg.optJSONObject("env") ?: JSONObject().also { cfg.put("env", it) }
            env.put("xray.tun.fd", fd.fd.toString())

            val req = JSONObject()
                .put("apiVersion", 3)
                .put("method", "runXray")
                .put("payload", JSONObject().put("xrayJson", cfg.toString()))
            val res = JSONObject(LibXray.invoke(req.toString()))
            if (!res.optBoolean("success")) throw RuntimeException(res.optString("error", "Xray failed to start"))

            running = true
            VpnBus.emit("connected")
        } catch (e: Throwable) {
            VpnBus.emit("error:" + (e.message ?: e.toString()))
            stopVpn()
        }
    }

    private fun stopCore() {
        try {
            val req = JSONObject().put("apiVersion", 3).put("method", "stopXray").put("payload", JSONObject())
            LibXray.invoke(req.toString())
        } catch (_: Throwable) {}
        try { pfd?.close() } catch (_: Throwable) {}
        pfd = null
        running = false
    }

    private fun stopVpn() {
        stopCore()
        VpnBus.emit("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        stopVpn()
    }

    override fun onDestroy() {
        stopCore()
        super.onDestroy()
    }

    private fun showNotification() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("vpn", "VPN status", NotificationManager.IMPORTANCE_LOW))
        val stopPi = PendingIntent.getService(
            this, 1, Intent(this, XrayVpnService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE
        )
        val open = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val openPi = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val n = Notification.Builder(this, "vpn")
            .setContentTitle("XRay VPN")
            .setContentText("Protected - TUN mode")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(openPi)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", stopPi).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, n)
        }
    }
}
