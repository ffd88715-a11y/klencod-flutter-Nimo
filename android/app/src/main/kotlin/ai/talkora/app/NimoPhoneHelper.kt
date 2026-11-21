package ai.talkora.app

import android.Manifest
import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.AlarmClock
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * Nimo v9.0 OmniControl — Shared Native Android Phone Intelligence & Control Helper.
 * Used by both MainActivity (Flutter MethodChannel) and NimoFloatingVoiceService (Overlay Bubble).
 */
object NimoPhoneHelper {

    @Volatile
    var torchEnabled: Boolean = false

    fun hasPermission(context: Context, permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    fun normalizeArabic(input: String): String {
        return input
            .lowercase(Locale.ROOT)
            .replace("أ", "ا")
            .replace("إ", "ا")
            .replace("آ", "ا")
            .replace("ة", "ه")
            .replace("ى", "ي")
            .replace("ؤ", "و")
            .replace("ئ", "ي")
            .replace(Regex("[\u064B-\u065F\u0670]"), "")
            .trim()
    }

    // ==================== SMS MESSAGES ====================
    fun readSmsMessages(context: Context, limit: Int = 50, query: String = ""): List<Map<String, Any>> {
        if (!hasPermission(context, Manifest.permission.READ_SMS)) return emptyList()
        val list = mutableListOf<Map<String, Any>>()
        val normQ = normalizeArabic(query)
        val contactCache = mutableMapOf<String, String>()
        try {
            val uri = Telephony.Sms.CONTENT_URI
            val projection = arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE,
                Telephony.Sms.READ
            )
            val cursor = context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${Telephony.Sms.DATE} DESC"
            )
            cursor?.use { c ->
                val idIdx = c.getColumnIndex(Telephony.Sms._ID)
                val addrIdx = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val bodyIdx = c.getColumnIndex(Telephony.Sms.BODY)
                val dateIdx = c.getColumnIndex(Telephony.Sms.DATE)
                val typeIdx = c.getColumnIndex(Telephony.Sms.TYPE)
                val readIdx = c.getColumnIndex(Telephony.Sms.READ)

                while (c.moveToNext() && list.size < limit) {
                    val id = if (idIdx >= 0) c.getString(idIdx) ?: "" else ""
                    val address = if (addrIdx >= 0) c.getString(addrIdx) ?: "" else ""
                    val body = if (bodyIdx >= 0) c.getString(bodyIdx) ?: "" else ""
                    val dateMs = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                    val typeInt = if (typeIdx >= 0) c.getInt(typeIdx) else 1
                    val readInt = if (readIdx >= 0) c.getInt(readIdx) else 1
                    val typeLabel = when (typeInt) {
                        Telephony.Sms.MESSAGE_TYPE_SENT -> "sent"
                        Telephony.Sms.MESSAGE_TYPE_DRAFT -> "draft"
                        else -> "inbox"
                    }

                    val contactName = contactCache.getOrPut(address) {
                        lookupContactNameByNumber(context, address) ?: ""
                    }

                    if (normQ.isNotEmpty()) {
                        val hay = normalizeArabic("$address $contactName $body")
                        if (!hay.contains(normQ)) continue
                    }

                    list.add(
                        mapOf(
                            "id" to id,
                            "address" to address,
                            "contactName" to contactName,
                            "body" to body,
                            "dateMs" to dateMs,
                            "type" to typeLabel,
                            "read" to (readInt == 1)
                        )
                    )
                }
            }
        } catch (_: Exception) {}
        return list
    }

    private fun lookupContactNameByNumber(context: Context, phoneNumber: String): String? {
        if (phoneNumber.isBlank() || !hasPermission(context, Manifest.permission.READ_CONTACTS)) return null
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(phoneNumber)
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    // ==================== CONTACTS ====================
    fun readContacts(context: Context, query: String = "", limit: Int = 250): List<Map<String, String>> {
        if (!hasPermission(context, Manifest.permission.READ_CONTACTS)) return emptyList()
        val list = mutableListOf<Map<String, String>>()
        val seen = HashSet<String>()
        val normQ = normalizeArabic(query)
        try {
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )
            cursor?.use { c ->
                val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (c.moveToNext() && list.size < limit) {
                    val name = (if (nameIdx >= 0) c.getString(nameIdx) else null)?.trim() ?: ""
                    val phone = (if (numIdx >= 0) c.getString(numIdx) else null)?.trim() ?: ""
                    if (name.isEmpty() || phone.isEmpty()) continue
                    val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
                    val dedupeKey = "${normalizeArabic(name)}|$cleanPhone"
                    if (!seen.add(dedupeKey)) continue

                    if (normQ.isNotEmpty()) {
                        val hay = normalizeArabic("$name $phone $cleanPhone")
                        if (!hay.contains(normQ)) continue
                    }

                    list.add(
                        mapOf(
                            "name" to name,
                            "phone" to phone,
                            "cleanPhone" to cleanPhone
                        )
                    )
                }
            }
        } catch (_: Exception) {}
        return list
    }

    fun findBestContact(context: Context, nameOrNumber: String): Map<String, String>? {
        val norm = normalizeArabic(nameOrNumber)
        if (norm.isEmpty()) return null
        val contacts = readContacts(context, query = "", limit = 1000)
        // 1. Exact normalized match
        contacts.firstOrNull { normalizeArabic(it["name"] ?: "") == norm }?.let { return it }
        // 2. Starts-with match
        contacts.firstOrNull { normalizeArabic(it["name"] ?: "").startsWith(norm) }?.let { return it }
        // 3. Contains match
        contacts.firstOrNull {
            val n = normalizeArabic(it["name"] ?: "")
            val p = it["cleanPhone"] ?: ""
            n.contains(norm) || norm.contains(n) || p.contains(norm)
        }?.let { return it }
        return null
    }

    // ==================== CALL LOGS ====================
    fun readCallLogs(context: Context, limit: Int = 40): List<Map<String, Any>> {
        if (!hasPermission(context, Manifest.permission.READ_CALL_LOG)) return emptyList()
        val list = mutableListOf<Map<String, Any>>()
        try {
            val projection = arrayOf(
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.NUMBER,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION
            )
            val cursor = context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )
            cursor?.use { c ->
                val nameIdx = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)
                while (c.moveToNext() && list.size < limit) {
                    val number = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                    var name = if (nameIdx >= 0) c.getString(nameIdx) ?: "" else ""
                    if (name.isBlank()) {
                        name = lookupContactNameByNumber(context, number) ?: ""
                    }
                    val typeInt = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                    val typeStr = when (typeInt) {
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE -> "rejected"
                        else -> "incoming"
                    }
                    val dateMs = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                    val duration = if (durIdx >= 0) c.getLong(durIdx) else 0L
                    list.add(
                        mapOf(
                            "name" to name,
                            "number" to number,
                            "type" to typeStr,
                            "dateMs" to dateMs,
                            "durationSec" to duration
                        )
                    )
                }
            }
        } catch (_: Exception) {}
        return list
    }

    // ==================== FULL DEVICE TELEMETRY ====================
    fun readFullDeviceReport(context: Context): Map<String, Any> {
        var batteryPct = -1
        var isCharging = false
        var batteryTempC = 0.0
        var batteryVoltageMv = 0
        try {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val bs = context.registerReceiver(null, ifilter)
            val level = bs?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = bs?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) batteryPct = (level * 100) / scale
            val st = bs?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            isCharging = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
            val tempTenths = bs?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
            batteryTempC = tempTenths / 10.0
            batteryVoltageMv = bs?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0) ?: 0
        } catch (_: Exception) {}

        // RAM info
        var totalRamMb = 0L
        var availRamMb = 0L
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            totalRamMb = mi.totalMem / (1024L * 1024L)
            availRamMb = mi.availMem / (1024L * 1024L)
        } catch (_: Exception) {}

        // Internal Storage info
        var totalStorageGb = 0.0
        var freeStorageGb = 0.0
        try {
            val stat = StatFs(Environment.getDataDirectory().path)
            val totalBytes = stat.blockCountLong * stat.blockSizeLong
            val availBytes = stat.availableBlocksLong * stat.blockSizeLong
            totalStorageGb = (totalBytes.toDouble() / (1024.0 * 1024.0 * 1024.0))
            freeStorageGb = (availBytes.toDouble() / (1024.0 * 1024.0 * 1024.0))
        } catch (_: Exception) {}

        // Network type
        var networkType = "Offline"
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val net = cm.activeNetwork
            val caps = cm.getNetworkCapabilities(net)
            networkType = when {
                caps == null -> "Offline"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile Data"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
                else -> "Connected"
            }
        } catch (_: Exception) {}

        // Volumes
        var mediaVolPct = 0
        var ringVolPct = 0
        var ringerMode = "normal"
        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val mMax = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
            val mCur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            mediaVolPct = (mCur * 100) / mMax
            val rMax = audio.getStreamMaxVolume(AudioManager.STREAM_RING).coerceAtLeast(1)
            val rCur = audio.getStreamVolume(AudioManager.STREAM_RING)
            ringVolPct = (rCur * 100) / rMax
            ringerMode = when (audio.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                else -> "normal"
            }
        } catch (_: Exception) {}

        // Brightness
        var brightnessPct = -1
        try {
            val b = Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, -1)
            if (b >= 0) brightnessPct = ((b * 100) / 255).coerceIn(0, 100)
        } catch (_: Exception) {}

        val canOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }

        return mapOf(
            "batteryLevel" to batteryPct,
            "isCharging" to isCharging,
            "batteryTempC" to batteryTempC,
            "batteryVoltageMv" to batteryVoltageMv,
            "manufacturer" to (Build.MANUFACTURER ?: "Android"),
            "brand" to (Build.BRAND ?: ""),
            "model" to (Build.MODEL ?: "Device"),
            "device" to (Build.DEVICE ?: ""),
            "androidVersion" to (Build.VERSION.RELEASE ?: ""),
            "sdkInt" to Build.VERSION.SDK_INT,
            "securityPatch" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Build.VERSION.SECURITY_PATCH else ""),
            "cpuAbi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
            "torchEnabled" to torchEnabled,
            "totalRamMb" to totalRamMb,
            "availRamMb" to availRamMb,
            "totalStorageGb" to totalStorageGb,
            "freeStorageGb" to freeStorageGb,
            "networkType" to networkType,
            "mediaVolumePct" to mediaVolPct,
            "ringVolumePct" to ringVolPct,
            "ringerMode" to ringerMode,
            "brightnessPct" to brightnessPct,
            "canDrawOverlays" to canOverlay,
            "bubbleRunning" to NimoFloatingVoiceService.isRunning,
            "accessibilityEnabled" to NimoVoiceControlAccessibilityService.isRunning()
        )
    }

    // ==================== DEVICE ACTIONS ====================
    fun getInstalledLaunchableApps(context: Context): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        try {
            val pm = context.packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(mainIntent, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(mainIntent, 0)
            }
            val seen = HashSet<String>()
            for (ri in resolved) {
                val pkg = ri.activityInfo?.packageName ?: continue
                if (pkg == context.packageName || !seen.add(pkg)) continue
                val label = ri.loadLabel(pm)?.toString()?.trim() ?: pkg
                list.add(mapOf("name" to label, "packageName" to pkg))
            }
            list.sortBy { it["name"]?.lowercase(Locale.ROOT) ?: "" }
        } catch (_: Exception) {}
        return list
    }

    fun launchAppByQuery(context: Context, rawQuery: String): Boolean {
        val q = rawQuery.trim().lowercase(Locale.ROOT)
        if (q.isEmpty()) return false
        try {
            val pm = context.packageManager
            pm.getLaunchIntentForPackage(rawQuery.trim())?.let { intent ->
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            }

            val aliasMap = mapOf(
                "whatsapp" to listOf("com.whatsapp", "com.whatsapp.w4b"),
                "واتساب" to listOf("com.whatsapp", "com.whatsapp.w4b"),
                "واتس" to listOf("com.whatsapp", "com.whatsapp.w4b"),
                "youtube" to listOf("com.google.android.youtube"),
                "يوتيوب" to listOf("com.google.android.youtube"),
                "instagram" to listOf("com.instagram.android"),
                "انستجرام" to listOf("com.instagram.android"),
                "انستا" to listOf("com.instagram.android"),
                "facebook" to listOf("com.facebook.katana", "com.facebook.lite"),
                "فيسبوك" to listOf("com.facebook.katana", "com.facebook.lite"),
                "الفيس" to listOf("com.facebook.katana", "com.facebook.lite"),
                "tiktok" to listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill"),
                "تيك توك" to listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill"),
                "telegram" to listOf("org.telegram.messenger", "org.telegram.messenger.web"),
                "تيليجرام" to listOf("org.telegram.messenger"),
                "chrome" to listOf("com.android.chrome"),
                "كروم" to listOf("com.android.chrome"),
                "maps" to listOf("com.google.android.apps.maps"),
                "خرائط" to listOf("com.google.android.apps.maps"),
                "gmail" to listOf("com.google.android.gm"),
                "جيميل" to listOf("com.google.android.gm"),
                "spotify" to listOf("com.spotify.music"),
                "سبوتيفاي" to listOf("com.spotify.music"),
                "calculator" to listOf("com.google.android.calculator", "com.sec.android.app.popupcalculator"),
                "حاسبة" to listOf("com.google.android.calculator", "com.sec.android.app.popupcalculator"),
                "camera" to listOf("com.android.camera", "com.sec.android.app.camera", "com.google.android.GoogleCamera"),
                "كاميرا" to listOf("com.android.camera", "com.sec.android.app.camera", "com.google.android.GoogleCamera"),
                "settings" to listOf("com.android.settings"),
                "اعدادات" to listOf("com.android.settings"),
                "الإعدادات" to listOf("com.android.settings")
            )

            for ((key, pkgs) in aliasMap) {
                if (q.contains(key)) {
                    for (pkg in pkgs) {
                        pm.getLaunchIntentForPackage(pkg)?.let { intent ->
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            return true
                        }
                    }
                }
            }

            val apps = getInstalledLaunchableApps(context)
            val match = apps.firstOrNull { app ->
                val name = (app["name"] ?: "").lowercase(Locale.ROOT)
                val pkg = (app["packageName"] ?: "").lowercase(Locale.ROOT)
                name.contains(q) || q.contains(name) || pkg.contains(q)
            }
            val pkg = match?.get("packageName") ?: return false
            val launchIntent = pm.getLaunchIntentForPackage(pkg) ?: return false
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    fun openExternalUrl(context: Context, url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url.trim())).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun searchWeb(context: Context, query: String): Boolean {
        return openExternalUrl(context, "https://www.google.com/search?q=${Uri.encode(query.trim())}")
    }

    fun searchYoutube(context: Context, query: String): Boolean {
        return openExternalUrl(context, "https://www.youtube.com/results?search_query=${Uri.encode(query.trim())}")
    }

    fun openWhatsAppChat(context: Context, phone: String, message: String): Boolean {
        return try {
            var clean = phone.replace(Regex("[^0-9+]"), "")
            if (clean.startsWith("0") && clean.length == 11) {
                clean = "2$clean"
            }
            clean = clean.removePrefix("+")
            val encodedMsg = Uri.encode(message)
            val url = if (clean.isNotEmpty()) {
                "https://wa.me/$clean?text=$encodedMsg"
            } else {
                "https://wa.me/?text=$encodedMsg"
            }
            openExternalUrl(context, url)
        } catch (_: Exception) {
            false
        }
    }

    fun dialOrCallNumber(context: Context, phone: String, directCall: Boolean = false): Boolean {
        return try {
            val clean = phone.replace(Regex("[^0-9+*#]"), "")
            val canDirect = directCall && hasPermission(context, Manifest.permission.CALL_PHONE)
            val action = if (canDirect) Intent.ACTION_CALL else Intent.ACTION_DIAL
            val intent = Intent(action, Uri.parse("tel:$clean")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun composeSms(context: Context, phone: String, message: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).apply {
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun setFlashlight(context: Context, enabled: Boolean): Boolean {
        return try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: return false
            cameraManager.setTorchMode(cameraId, enabled)
            torchEnabled = enabled
            true
        } catch (_: Exception) {
            false
        }
    }

    fun setStreamVolume(context: Context, stream: String, percent: Int): Boolean {
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val streamType = when (stream.lowercase(Locale.ROOT)) {
                "ring", "ringer", "رنين" -> AudioManager.STREAM_RING
                "alarm", "منبه" -> AudioManager.STREAM_ALARM
                "call", "مكالمة" -> AudioManager.STREAM_VOICE_CALL
                else -> AudioManager.STREAM_MUSIC
            }
            val max = audio.getStreamMaxVolume(streamType)
            val target = ((percent.coerceIn(0, 100) * max) / 100.0).toInt().coerceIn(0, max)
            audio.setStreamVolume(streamType, target, AudioManager.FLAG_SHOW_UI)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun adjustVolume(context: Context, direction: String): Boolean {
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val dir = when (direction.lowercase(Locale.ROOT)) {
                "up", "raise", "علي", "ارفع" -> AudioManager.ADJUST_RAISE
                "down", "lower", "وطي", "اخفض" -> AudioManager.ADJUST_LOWER
                "mute", "كتم", "صامت" -> AudioManager.ADJUST_MUTE
                "unmute", "فك الكتم" -> AudioManager.ADJUST_UNMUTE
                else -> AudioManager.ADJUST_SAME
            }
            audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun copyToClipboard(context: Context, text: String): Boolean {
        return try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("Nimo", text))
            true
        } catch (_: Exception) {
            false
        }
    }

    fun createAlarm(context: Context, hour: Int, minute: Int, message: String): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
                putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun launchMaps(context: Context, query: String, navigate: Boolean): Boolean {
        return try {
            val uri = if (navigate) {
                Uri.parse("google.navigation:q=${Uri.encode(query)}")
            } else {
                Uri.parse("geo:0,0?q=${Uri.encode(query)}")
            }
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            openExternalUrl(context, "https://www.google.com/maps/search/?api=1&query=${Uri.encode(query)}")
        }
    }
}
