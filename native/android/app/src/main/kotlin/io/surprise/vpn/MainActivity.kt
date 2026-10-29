package io.surprise.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import libXray.LibXray
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "io.surprise.vpn/state").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                VpnBus.sink = events
                events.success(VpnBus.last)
            }

            override fun onCancel(arguments: Any?) {
                VpnBus.sink = null
            }
        })

        MethodChannel(messenger, "io.surprise.vpn/vpn").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val intent = VpnService.prepare(this)
                    if (intent == null) {
                        result.success(true)
                    } else {
                        pendingPrepare = result
                        startActivityForResult(intent, REQ_VPN)
                    }
                }
                "start" -> {
                    val cfg = call.argument<String>("config")
                    if (cfg == null) {
                        result.error("ARG", "config missing", null)
                        return@setMethodCallHandler
                    }
                    File(filesDir, "run.json").writeText(cfg)
                    val i = Intent(this, XrayVpnService::class.java)
                        .setAction("START")
                        .putExtra("mtu", call.argument<Int>("mtu") ?: 1500)
                        .putExtra("dns", call.argument<String>("dns") ?: "1.1.1.1")
                        .putExtra("perApp", call.argument<Boolean>("perApp") ?: false)
                        .putStringArrayListExtra("apps", ArrayList(call.argument<List<String>>("apps") ?: emptyList()))
                    ContextCompat.startForegroundService(this, i)
                    result.success(null)
                }
                "stop" -> {
                    startService(Intent(this, XrayVpnService::class.java).setAction("STOP"))
                    result.success(null)
                }
                "status" -> result.success(VpnBus.last)
                "invoke" -> {
                    val req = call.arguments as String
                    Thread {
                        val res = try {
                            LibXray.invoke(req)
                        } catch (e: Throwable) {
                            """{"success":false,"data":null,"error":${org.json.JSONObject.quote(e.message ?: "native error")}}"""
                        }
                        runOnUiThread { result.success(res) }
                    }.start()
                }
                "apps" -> {
                    Thread {
                        val pm = packageManager
                        val list = pm.getInstalledApplications(0)
                            .filter { it.packageName != packageName }
                            .map {
                                mapOf(
                                    "label" to pm.getApplicationLabel(it).toString(),
                                    "package" to it.packageName,
                                    "system" to ((it.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0)
                                )
                            }
                            .sortedBy { (it["label"] as String).lowercase() }
                        runOnUiThread { result.success(list) }
                    }.start()
                }
                "openVpnSettings" -> {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VPN) {
            pendingPrepare?.success(resultCode == Activity.RESULT_OK)
            pendingPrepare = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val REQ_VPN = 7001
    }
}
