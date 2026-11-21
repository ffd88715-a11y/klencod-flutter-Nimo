package ai.talkora.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.SoundEffectConstants
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    private val methodChannelName = "ai.talkora.app/native_bridge"
    private val voiceEventChannelName = "ai.talkora.app/voice_events"
    private val phonePermRequestCode = 9102

    private val mainHandler = Handler(Looper.getMainLooper())
    private var voiceEventSink: EventChannel.EventSink? = null

    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var pendingPermResult: MethodChannel.Result? = null
    private var pendingBubblePrompt: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureBubbleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureBubbleIntent(intent)
    }

    private fun captureBubbleIntent(intent: Intent?) {
        val prompt = intent?.getStringExtra(NimoFloatingVoiceService.EXTRA_VOICE_PROMPT)?.trim()
        if (!prompt.isNullOrEmpty()) {
            pendingBubblePrompt = prompt
            intent.removeExtra(NimoFloatingVoiceService.EXTRA_VOICE_PROMPT)
            emitVoiceEvent(mapOf("type" to "bubble_prompt", "text" to prompt))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        tts = TextToSpeech(this, this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    voiceEventSink = events
                    val p = pendingBubblePrompt
                    if (!p.isNullOrEmpty()) {
                        pendingBubblePrompt = null
                        emitVoiceEvent(mapOf("type" to "bubble_prompt", "text" to p))
                    }
                }

                override fun onCancel(arguments: Any?) {
                    voiceEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ==================== LIVE VOICE (STT / TTS) ====================
                    "isSpeechAvailable" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    "startListening" -> {
                        val locale = call.argument<String>("locale") ?: "ar-EG"
                        startSpeechListening(locale, result)
                    }
                    "stopListening" -> {
                        mainHandler.post { try { speechRecognizer?.stopListening() } catch (_: Exception) {} }
                        result.success(true)
                    }
                    "cancelListening" -> {
                        mainHandler.post { try { speechRecognizer?.cancel() } catch (_: Exception) {} }
                        result.success(true)
                    }
                    "playClickSound" -> {
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            am.playSoundEffect(SoundEffectConstants.CLICK, 0.7f)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "getAvailableVoices" -> {
                        val prefix = call.argument<String>("localePrefix") ?: ""
                        result.success(listHighQualityVoices(prefix))
                    }
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val locale = call.argument<String>("locale") ?: "ar-EG"
                        val rate = (call.argument<Double>("rate") ?: 0.98).toFloat()
                        val pitch = (call.argument<Double>("pitch") ?: 0.97).toFloat()
                        val voiceName = call.argument<String>("voiceName")
                        speakText(text, locale, rate, pitch, voiceName, result)
                    }
                    "stopSpeaking" -> {
                        try { tts?.stop() } catch (_: Exception) {}
                        emitVoiceEvent(mapOf("type" to "tts_stopped"))
                        result.success(true)
                    }

                    // ==================== NIMO v9.0 OMNI PHONE INTELLIGENCE ====================
                    "getSmsMessages" -> {
                        val limit = call.argument<Int>("limit") ?: 60
                        val query = call.argument<String>("query") ?: ""
                        result.success(NimoPhoneHelper.readSmsMessages(this, limit, query))
                    }
                    "getContacts" -> {
                        val query = call.argument<String>("query") ?: ""
                        val limit = call.argument<Int>("limit") ?: 300
                        result.success(NimoPhoneHelper.readContacts(this, query, limit))
                    }
                    "findContact" -> {
                        val query = call.argument<String>("query") ?: ""
                        result.success(NimoPhoneHelper.findBestContact(this, query))
                    }
                    "getCallLogs" -> {
                        val limit = call.argument<Int>("limit") ?: 40
                        result.success(NimoPhoneHelper.readCallLogs(this, limit))
                    }
                    "getFullDeviceReport" -> {
                        result.success(NimoPhoneHelper.readFullDeviceReport(this))
                    }
                    "getDeviceStatus" -> {
                        result.success(NimoPhoneHelper.readFullDeviceReport(this))
                    }
                    "getPermissionsStatus" -> {
                        result.success(buildPermissionsStatusMap())
                    }
                    "requestPhonePermissions" -> {
                        requestAllPhonePermissions(result)
                    }
                    "requestOverlayPermission" -> {
                        result.success(openOverlayPermissionScreen())
                    }
                    "openAccessibilitySettings" -> {
                        result.success(openAccessibilitySettingsScreen())
                    }
                    "startFloatingBubble" -> {
                        result.success(startFloatingBubbleService())
                    }
                    "stopFloatingBubble" -> {
                        result.success(stopFloatingBubbleService())
                    }
                    "isFloatingBubbleRunning" -> {
                        result.success(NimoFloatingVoiceService.isRunning)
                    }
                    "getPendingBubblePrompt" -> {
                        val p = pendingBubblePrompt ?: ""
                        pendingBubblePrompt = null
                        result.success(p)
                    }
                    "performVoiceType" -> {
                        val text = call.argument<String>("text") ?: ""
                        val acc = NimoVoiceControlAccessibilityService.instance
                        if (acc != null && acc.typeTextIntoFocusedField(text, true)) {
                            result.success(true)
                        } else {
                            NimoPhoneHelper.copyToClipboard(this, text)
                            result.success(false)
                        }
                    }
                    "performSystemAction" -> {
                        val action = call.argument<String>("action") ?: ""
                        val acc = NimoVoiceControlAccessibilityService.instance
                        result.success(acc?.performSystemAction(action) ?: false)
                    }
                    "setVolume" -> {
                        val stream = call.argument<String>("stream") ?: "music"
                        val percent = call.argument<Int>("percent") ?: 50
                        result.success(NimoPhoneHelper.setStreamVolume(this, stream, percent))
                    }
                    "adjustVolume" -> {
                        val direction = call.argument<String>("direction") ?: "up"
                        result.success(NimoPhoneHelper.adjustVolume(this, direction))
                    }
                    "searchWeb" -> {
                        val query = call.argument<String>("query") ?: ""
                        result.success(NimoPhoneHelper.searchWeb(this, query))
                    }

                    // ==================== PHONE APPS & DEVICE ACTIONS ====================
                    "getInstalledApps" -> result.success(NimoPhoneHelper.getInstalledLaunchableApps(this))
                    "launchApp" -> {
                        val query = call.argument<String>("query") ?: ""
                        result.success(NimoPhoneHelper.launchAppByQuery(this, query))
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(NimoPhoneHelper.openExternalUrl(this, url))
                    }
                    "openWhatsApp" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        result.success(NimoPhoneHelper.openWhatsAppChat(this, phone, message))
                    }
                    "dialPhone" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val direct = call.argument<Boolean>("direct") ?: false
                        result.success(NimoPhoneHelper.dialOrCallNumber(this, phone, direct))
                    }
                    "sendSms" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        result.success(NimoPhoneHelper.composeSms(this, phone, message))
                    }
                    "sendEmail" -> {
                        val to = call.argument<String>("to") ?: ""
                        val subject = call.argument<String>("subject") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        result.success(composeEmail(to, subject, body))
                    }
                    "setAlarm" -> {
                        val hour = call.argument<Int>("hour") ?: 7
                        val minute = call.argument<Int>("minute") ?: 0
                        val message = call.argument<String>("message") ?: "Nimo Alarm"
                        result.success(NimoPhoneHelper.createAlarm(this, hour, minute, message))
                    }
                    "setTimer" -> {
                        val seconds = call.argument<Int>("seconds") ?: 60
                        val message = call.argument<String>("message") ?: "Nimo Timer"
                        result.success(createTimer(seconds, message))
                    }
                    "openMaps" -> {
                        val query = call.argument<String>("query") ?: ""
                        val navigate = call.argument<Boolean>("navigate") ?: false
                        result.success(NimoPhoneHelper.launchMaps(this, query, navigate))
                    }
                    "searchYoutube" -> {
                        val query = call.argument<String>("query") ?: ""
                        result.success(NimoPhoneHelper.searchYoutube(this, query))
                    }
                    "openSystemSetting" -> {
                        val target = call.argument<String>("target") ?: "main"
                        result.success(openAndroidSettings(target))
                    }
                    "toggleFlashlight" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: !NimoPhoneHelper.torchEnabled
                        result.success(NimoPhoneHelper.setFlashlight(this, enabled))
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val subject = call.argument<String>("subject") ?: "Nimo"
                        result.success(sharePlainText(text, subject))
                    }
                    "saveImageToGallery" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "nimo_${System.currentTimeMillis()}.png"
                        if (bytes != null && bytes.isNotEmpty()) {
                            result.success(saveImageBytesToGallery(bytes, fileName))
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ==================== PERMISSIONS & FLOATING BUBBLE ====================
    private fun buildPermissionsStatusMap(): Map<String, Boolean> {
        val canOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
        return mapOf(
            "sms" to NimoPhoneHelper.hasPermission(this, Manifest.permission.READ_SMS),
            "contacts" to NimoPhoneHelper.hasPermission(this, Manifest.permission.READ_CONTACTS),
            "callLog" to NimoPhoneHelper.hasPermission(this, Manifest.permission.READ_CALL_LOG),
            "callPhone" to NimoPhoneHelper.hasPermission(this, Manifest.permission.CALL_PHONE),
            "mic" to NimoPhoneHelper.hasPermission(this, Manifest.permission.RECORD_AUDIO),
            "overlay" to canOverlay,
            "accessibility" to NimoVoiceControlAccessibilityService.isRunning(),
            "bubbleRunning" to NimoFloatingVoiceService.isRunning
        )
    }

    private fun requestAllPhonePermissions(result: MethodChannel.Result) {
        val needed = mutableListOf(
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.RECORD_AUDIO
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val missing = needed.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(buildPermissionsStatusMap())
            return
        }
        pendingPermResult = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), phonePermRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == phonePermRequestCode) {
            pendingPermResult?.success(buildPermissionsStatusMap())
            pendingPermResult = null
        }
    }

    private fun openOverlayPermissionScreen(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                startActivity(intent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openAccessibilitySettingsScreen(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun startFloatingBubbleService(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            openOverlayPermissionScreen()
            return false
        }
        return try {
            val intent = Intent(this, NimoFloatingVoiceService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun stopFloatingBubbleService(): Boolean {
        return try {
            stopService(Intent(this, NimoFloatingVoiceService::class.java))
            true
        } catch (_: Exception) {
            false
        }
    }

    // ==================== NATIVE TTS IMPLEMENTATION ====================
    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            ttsReady = true
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    emitVoiceEvent(mapOf("type" to "tts_start"))
                }

                override fun onDone(utteranceId: String?) {
                    emitVoiceEvent(mapOf("type" to "tts_done"))
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    emitVoiceEvent(mapOf("type" to "tts_error"))
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    emitVoiceEvent(mapOf("type" to "tts_error", "code" to errorCode))
                }
            })
        }
    }

    private fun listHighQualityVoices(localePrefix: String): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        try {
            val voices = tts?.voices ?: return out
            val pfx = localePrefix.lowercase(Locale.ROOT)
            val filtered = voices.filter { v ->
                val tag = v.locale?.toLanguageTag()?.lowercase(Locale.ROOT) ?: ""
                pfx.isEmpty() || tag.startsWith(pfx)
            }.sortedByDescending { v ->
                var score = v.quality
                val n = v.name.lowercase(Locale.ROOT)
                if (n.contains("neural") || n.contains("wavenet") || n.contains("studio")) score += 300
                if (v.isNetworkConnectionRequired) score += 120
                score
            }
            for (v in filtered.take(25)) {
                out.add(
                    mapOf(
                        "name" to v.name,
                        "locale" to (v.locale?.toLanguageTag() ?: ""),
                        "quality" to v.quality,
                        "isNetwork" to v.isNetworkConnectionRequired
                    )
                )
            }
        } catch (_: Exception) {}
        return out
    }

    private fun pickBestHumanVoice(targetLocale: Locale, requestedVoiceName: String?) {
        try {
            val voices = tts?.voices ?: return
            if (!requestedVoiceName.isNullOrBlank()) {
                val exact = voices.firstOrNull { it.name == requestedVoiceName }
                if (exact != null) {
                    tts?.voice = exact
                    return
                }
            }
            val lang = targetLocale.language.lowercase(Locale.ROOT)
            val country = targetLocale.country.lowercase(Locale.ROOT)
            val best = voices
                .filter { (it.locale?.language ?: "").lowercase(Locale.ROOT) == lang }
                .maxByOrNull { v ->
                    var score = v.quality
                    val n = v.name.lowercase(Locale.ROOT)
                    if (n.contains("neural") || n.contains("wavenet") || n.contains("natural") || n.contains("studio")) score += 400
                    if (n.contains("network") || v.isNetworkConnectionRequired) score += 150
                    if (country.isNotEmpty() && (v.locale?.country ?: "").lowercase(Locale.ROOT) == country) score += 90
                    if (n.contains("local")) score -= 20
                    score
                }
            if (best != null) {
                tts?.voice = best
            }
        } catch (_: Exception) {}
    }

    private fun speakText(
        text: String,
        localeTag: String,
        rate: Float,
        pitch: Float,
        voiceName: String?,
        result: MethodChannel.Result
    ) {
        if (!ttsReady || tts == null || text.isBlank()) {
            emitVoiceEvent(mapOf("type" to "tts_done"))
            result.success(false)
            return
        }
        try {
            val parts = localeTag.replace("_", "-").split("-")
            val targetLocale = if (parts.size >= 2) Locale(parts[0], parts[1]) else Locale(parts[0])
            val langRes = tts?.setLanguage(targetLocale)
            if (langRes == TextToSpeech.LANG_MISSING_DATA || langRes == TextToSpeech.LANG_NOT_SUPPORTED) {
                if (parts[0].equals("ar", ignoreCase = true)) {
                    tts?.setLanguage(Locale("ar"))
                } else {
                    tts?.setLanguage(Locale.US)
                }
            }
            pickBestHumanVoice(targetLocale, voiceName)
            tts?.setSpeechRate(rate.coerceIn(0.55f, 1.8f))
            tts?.setPitch(pitch.coerceIn(0.75f, 1.35f))
            val utteranceId = UUID.randomUUID().toString()
            val cleanText = text.replace(Regex("[*#`_~]"), " ").trim()
            val clipped = if (cleanText.length > 3500) cleanText.substring(0, 3500) else cleanText
            tts?.speak(clipped, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
            result.success(true)
        } catch (e: Exception) {
            emitVoiceEvent(mapOf("type" to "tts_error", "message" to (e.message ?: "TTS error")))
            result.success(false)
        }
    }

    // ==================== NATIVE SPEECH RECOGNIZER IMPLEMENTATION ====================
    private fun startSpeechListening(localeTag: String, result: MethodChannel.Result) {
        mainHandler.post {
            try {
                if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                    result.success(false)
                    emitVoiceEvent(mapOf("type" to "error", "code" to -1, "message" to "Speech recognition service not available on this device."))
                    return@post
                }

                tts?.stop()
                speechRecognizer?.destroy()
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        emitVoiceEvent(mapOf("type" to "ready"))
                    }

                    override fun onBeginningOfSpeech() {
                        emitVoiceEvent(mapOf("type" to "speech_start"))
                    }

                    override fun onRmsChanged(rmsdB: Float) {
                        val normalized = ((rmsdB + 2.0f) / 12.0f).coerceIn(0.06f, 1.0f).toDouble()
                        emitVoiceEvent(mapOf("type" to "rms", "level" to normalized))
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {}

                    override fun onEndOfSpeech() {
                        emitVoiceEvent(mapOf("type" to "speech_end"))
                    }

                    override fun onError(error: Int) {
                        val msg = when (error) {
                            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                            SpeechRecognizer.ERROR_CLIENT -> "Client side error"
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission required"
                            SpeechRecognizer.ERROR_NETWORK -> "Network error"
                            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                            SpeechRecognizer.ERROR_NO_MATCH -> "No speech matched"
                            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                            SpeechRecognizer.ERROR_SERVER -> "Server error"
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input"
                            else -> "Speech error ($error)"
                        }
                        emitVoiceEvent(mapOf("type" to "error", "code" to error, "message" to msg))
                    }

                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val best = matches?.firstOrNull()?.trim() ?: ""
                        emitVoiceEvent(mapOf("type" to "final", "text" to best))
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val partial = matches?.firstOrNull()?.trim() ?: ""
                        if (partial.isNotEmpty()) {
                            emitVoiceEvent(mapOf("type" to "partial", "text" to partial))
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeTag)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1400L)
                }

                speechRecognizer?.startListening(intent)
                result.success(true)
            } catch (e: Exception) {
                emitVoiceEvent(mapOf("type" to "error", "code" to -2, "message" to (e.message ?: "Failed to start recognizer")))
                result.success(false)
            }
        }
    }

    private fun emitVoiceEvent(payload: Map<String, Any>) {
        mainHandler.post {
            try {
                voiceEventSink?.success(payload)
            } catch (_: Exception) {}
        }
    }

    // ==================== EXTRA SYSTEM INTENTS ====================
    private fun composeEmail(to: String, subject: String, body: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$to")).apply {
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, body)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun createTimer(seconds: Int, message: String): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceAtLeast(1))
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openAndroidSettings(target: String): Boolean {
        val action = when (target.lowercase(Locale.ROOT)) {
            "wifi", "واي فاي" -> Settings.ACTION_WIFI_SETTINGS
            "bluetooth", "بلوتوث" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "display", "الشاشة" -> Settings.ACTION_DISPLAY_SETTINGS
            "battery", "البطارية" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
            "sound", "الصوت" -> Settings.ACTION_SOUND_SETTINGS
            "location", "الموقع" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "apps", "التطبيقات" -> Settings.ACTION_APPLICATION_SETTINGS
            "accessibility", "الوصول" -> Settings.ACTION_ACCESSIBILITY_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        return try {
            val intent = Intent(action).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                startActivity(fallback)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun sharePlainText(text: String, subject: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, text)
            }
            val chooser = Intent.createChooser(intent, subject).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun saveImageBytesToGallery(bytes: ByteArray, fileName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Nimo")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return false
                contentResolver.openOutputStream(uri)?.use { out ->
                    out.write(bytes)
                }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "Nimo"
                )
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, fileName)
                FileOutputStream(file).use { it.write(bytes) }
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    override fun onDestroy() {
        try {
            speechRecognizer?.destroy()
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
