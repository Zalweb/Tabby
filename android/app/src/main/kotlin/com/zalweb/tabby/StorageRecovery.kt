package com.zalweb.tabby

import android.content.Context
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileOutputStream
import java.io.ObjectOutputStream
import java.util.UUID

/** Startup-only recovery. No decrypted values, financial mutations or auto replay. */
object StorageRecovery {
    private fun syncDirectory(directory: File) {
        check(directory.isDirectory) { "Recovery directory unavailable" }
        val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }
    fun preserveAndReset(context: Context) {
        val archive = File(context.noBackupFilesDir, "storage-recovery/${UUID.randomUUID()}")
        check(archive.mkdirs()) { "Recovery directory unavailable" }
        val names = listOf("FlutterSecureStorage", "FlutterSecureKeyStorage")
        val preferences = names.map { context.getSharedPreferences(it, Context.MODE_PRIVATE) }
        // Snapshot the live preference maps, including wrapped encryption keys.
        // sync every archive before changing any original data.
        preferences.forEachIndexed { i, prefs ->
            val snapshot = HashMap<String, Any>()
            prefs.all.forEach { (key, value) ->
                if (value != null) snapshot[key] = if (value is Set<*>) HashSet(value) else value
            }
            FileOutputStream(File(archive, "${names[i]}.bin")).use { output ->
                val objects = ObjectOutputStream(output)
                objects.writeObject(snapshot)
                objects.flush()
                output.fd.sync()
            }
        }
        val originals = listOf("tabby-ledger-v1.sqlite", "tabby-ledger-v1.sqlite-wal",
            "tabby-ledger-v1.sqlite-shm").map { File(context.filesDir, it) }
        originals.filter { it.exists() }.forEach { source ->
            FileOutputStream(File(archive, source.name)).use { output ->
                source.inputStream().use { it.copyTo(output) }
                output.fd.sync()
            }
        }
        FileOutputStream(File(archive, "preserved")).use { output ->
            output.write("Encrypted storage preserved before reset. Do not auto-import.\n".toByteArray())
            output.fd.sync()
        }
        // Persist directory entries too. Syncing file contents alone cannot
        // guarantee that a newly created archive survives a power loss.
        syncDirectory(archive)
        syncDirectory(archive.parentFile!!)
        syncDirectory(context.noBackupFilesDir)
        // Failure at any point retains the durable archive. Never clear all app
        // preferences, Android Keystore aliases or any remote account data.
        preferences.forEach { check(it.edit().clear().commit()) { "Preference reset failed" } }
        originals.filter { it.exists() }.forEach { check(it.delete()) { "Ledger reset failed" } }
        syncDirectory(context.filesDir)
        PushBridge.setScope(context, null, null)
    }
}
