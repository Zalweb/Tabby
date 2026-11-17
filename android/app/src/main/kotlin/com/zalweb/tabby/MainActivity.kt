package com.zalweb.tabby

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ClipData
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : FlutterFragmentActivity() {
    private data class PendingSave(val bytes: ByteArray, val reply: MethodChannel.Result)
    private var pendingSave: PendingSave? = null
    private val fileWorker = Executors.newSingleThreadExecutor()
    private var pushChannel: MethodChannel? = null
    private val pushTapDelivery = PushTapDelivery<Map<String, String>>()

    private fun takePushTap(): Map<String, String>? {
        val data = mutableMapOf("v" to "1", "kind" to "reminder")
        for (key in listOf("account", "binding", "event", "tab")) {
            data[key] = intent?.getStringExtra("tabby_push_$key") ?: return null
        }
        data.keys.forEach { intent?.removeExtra("tabby_push_$it") }
        val envelope = PushEnvelope.parse(data) ?: return null
        return if (envelope.allowed(PushBridge.scope(this))) envelope.asMap() else null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
            android.util.Log.d("TabbyPushRouting", "newIntent received")
        if (pushChannel != null) pushTapDelivery.onNewIntent { takePushTap() }
            ?.let { pushChannel?.invokeMethod("tap", it) }
    }

    override fun onResume() {
        super.onResume()
        pushChannel?.invokeMethod("resume", null)
    }
    private val saveQr = registerForActivityResult(
        ActivityResultContracts.CreateDocument("image/png")
    ) { uri ->
        val pending = pendingSave ?: return@registerForActivityResult
        if (uri == null) {
            pendingSave = null
            pending.reply.success(false)
        } else {
            fileWorker.execute {
                val error = runCatching {
                    require(uri.scheme == "content") { "Unsupported save destination" }
                    val output = contentResolver.openOutputStream(uri, "wt")
                        ?: error("Save destination unavailable")
                    output.use { it.write(pending.bytes) }
                }.exceptionOrNull()
                runOnUiThread {
                    if (pendingSave === pending) {
                        pendingSave = null
                        if (error == null) pending.reply.success(true)
                        else pending.reply.error("save_failed", "Unable to save QR image.", null)
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tabby/storage_recovery")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "preserveAndReset" -> fileWorker.execute {
                        val error = runCatching { StorageRecovery.preserveAndReset(this) }.exceptionOrNull()
                        runOnUiThread {
                            if (error == null) reply.success(true)
                            else reply.error("recovery_failed", "Storage recovery did not finish.", null)
                        }
                    }
                    "close" -> {
                        reply.success(null)
                        // A fresh process is required because plugins cache ciphers.
                        finishAffinity()
                        android.os.Handler(mainLooper).postDelayed({
                            android.os.Process.killProcess(android.os.Process.myPid())
                        }, 250)
                    }
                    else -> reply.notImplemented()
                }
            }
        pushChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tabby/background_push").also { channel ->
            PushBridge.changed = { channel.invokeMethod("tokenChanged", null) }
            channel.setMethodCallHandler { call, reply ->
                when (call.method) {
                    "setScope" -> {
                        PushBridge.setScope(this, call.argument<String>("account"), call.argument<String>("binding"))
                        reply.success(null)
                    }
                    "initialTap" -> {
                        val tap = pushTapDelivery.listenerReady { takePushTap() }
                        if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
                            android.util.Log.d("TabbyPushRouting", "listener ready; initialTap=${tap != null}")
                        reply.success(tap)
                    }
                    "token" -> {
                        val app = FirebaseApp.getApps(this).firstOrNull() ?: FirebaseApp.initializeApp(this)
                        if (app == null) reply.success(null)
                        else {
                            FirebaseMessaging.getInstance().isAutoInitEnabled = true
                            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                                if (task.isSuccessful) reply.success(task.result)
                                else reply.error("push_unavailable", "Background alerts are unavailable.", null)
                            }
                        }
                    }
                    else -> reply.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tabby/receiving_qr")
            .setMethodCallHandler { call, reply ->
                if (call.method != "save" && call.method != "share") {
                    reply.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val pngHeader = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
                if (bytes == null || bytes.size !in 8..(10 * 1024 * 1024) ||
                    !bytes.copyOfRange(0, 8).contentEquals(pngHeader)) {
                    reply.error("invalid_image", "A PNG receiving QR up to 10 MB is required.", null)
                    return@setMethodCallHandler
                }
                if (call.method == "save") {
                    if (pendingSave != null) {
                        reply.error("busy", "Finish the current QR save first.", null)
                        return@setMethodCallHandler
                    }
                    pendingSave = PendingSave(bytes, reply)
                    try { saveQr.launch("Tabby-receiving-QR.png") }
                    catch (_: Exception) {
                        pendingSave = null
                        reply.error("save_unavailable", "No document saver is available.", null)
                    }
                } else {
                    fileWorker.execute {
                        try {
                            val directory = File(cacheDir, "receiving-qr").apply { mkdirs() }
                            // Only this narrow cache directory is shared. Old exports expire locally.
                            directory.listFiles()?.filter {
                                it.isFile && it.lastModified() < System.currentTimeMillis() - 86400000
                            }?.forEach { it.delete() }
                            val file = File(directory, "${UUID.randomUUID()}.png")
                            file.writeBytes(bytes)
                            val uri = FileProvider.getUriForFile(this, "$packageName.receivingqr", file)
                            runOnUiThread {
                                try {
                                    val send = Intent(Intent.ACTION_SEND).apply {
                                        type = "image/png"
                                        putExtra(Intent.EXTRA_STREAM, uri)
                                        clipData = ClipData.newRawUri("Receiving QR", uri)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    }
                                    startActivity(Intent.createChooser(send, "Share receiving QR"))
                                    // This acknowledges chooser launch, not delivery/payment.
                                    reply.success(true)
                                } catch (_: Exception) {
                                    reply.error("share_unavailable", "Unable to open sharing apps.", null)
                                }
                            }
                        } catch (_: Exception) {
                            runOnUiThread { reply.error("share_failed", "Unable to prepare QR image.", null) }
                        }
                    }
                }
            }
    }

    override fun onDestroy() {
        PushBridge.changed = null
        pushChannel?.setMethodCallHandler(null)
        pushChannel = null
        pendingSave?.reply?.error("save_interrupted", "QR save was interrupted. Please try again.", null)
        pendingSave = null
        fileWorker.shutdown()
        super.onDestroy()
    }
}
