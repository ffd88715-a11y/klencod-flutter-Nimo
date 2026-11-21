package ai.talkora.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.util.Locale
import kotlin.math.abs

/**
 * Nimo v9.0 OmniControl — System-Wide Floating Voice Assistant Overlay Bubble.
 * Floats cleanly over ANY app on the phone. Tap to speak any command:
 * - Voice typing into any focused text box ("اكتب ..." / "type ...")
 * - Google & YouTube search ("ابحث عن ..." / "يوتيوب ...")
 * - Call contacts by name or number ("اتصل بـ ..." / "كلم ...")
 * - Read latest or searched SMS aloud ("اقرأ الرسائل" / "آخر رسالة" / "رسالة من ...")
 * - Launch any installed app ("افتح واتساب" / "افتح ...")
 * - Control flashlight, volume, battery status, Back/Home/Screenshot
 * - Ask Nimo AI anything directly from any screen!
 */
class NimoFloatingVoiceService : Service(), TextToSpeech.OnInitListener {

    companion object {
        @Volatile
        var isRunning: Boolean = false
            private set

        const val CHANNEL_ID = "nimo_floating_voice_channel"
        const val NOTIFICATION_ID = 9001
        const val ACTION_STOP = "ai.talkora.app.STOP_BUBBLE"
        const val EXTRA_VOICE_PROMPT = "nimo_voice_prompt"
    }

    private lateinit var windowManager: WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var bubbleView: LinearLayout? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var panelView: LinearLayout? = null
    private var panelStatusText: TextView? = null
    private var panelTranscriptText: TextView? = null
    private var micDotView: TextView? = null

    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var isListening: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        tts = TextToSpeech(this, this)
        startForegroundNotification()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
            createFloatingBubble()
            isRunning = true
        } else {
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            ttsReady = true
            tts?.language = Locale("ar", "EG")
        }
    }

    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Nimo Floating Voice Control",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Floating voice control bubble over all apps"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, NimoFloatingVoiceService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle("Nimo Voice Bubble Active")
            .setContentText("اضغط على الفقاعة العائمة للتحكم الصوتي في الهاتف")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openPending)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "إيقاف",
                    stopPending
                ).build()
            )
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun overlayLayoutType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun createFloatingBubble() {
        val sizePx = dp(56)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E61A1D24"))
                setStroke(dp(2), Color.parseColor("#FF3B82F6"))
            }
            elevation = dp(8).toFloat()
        }

        val iconText = TextView(this).apply {
            text = "🎙"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        micDotView = iconText
        container.addView(iconText)

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayLayoutType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(240)
        }

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var moved = false

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) moved = true
                    params.x = initialX + dx
                    params.y = initialY + dy
                    try {
                        windowManager.updateViewLayout(container, params)
                    } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        onBubbleTapped()
                    }
                    true
                }
                else -> false
            }
        }

        bubbleView = container
        bubbleParams = params
        try {
            windowManager.addView(container, params)
        } catch (_: Exception) {}
    }

    private fun onBubbleTapped() {
        if (panelView == null) {
            showVoicePanel()
            startVoiceCommandCapture()
        } else if (isListening) {
            stopVoiceCapture()
        } else {
            startVoiceCommandCapture()
        }
    }

    private fun showVoicePanel() {
        if (panelView != null) return
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(Color.parseColor("#F5121417"))
                setStroke(dp(1), Color.parseColor("#663B82F6"))
            }
            elevation = dp(12).toFloat()
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val title = TextView(this).apply {
            text = "Nimo التحكم الصوتي"
            setTextColor(Color.parseColor("#FF60A5FA"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val openAppBtn = TextView(this).apply {
            text = "فتح التطبيق"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(10), dp(4), dp(10), dp(4))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.parseColor("#333B82F6"))
            }
            setOnClickListener {
                hideVoicePanel()
                openNimoAppWithPrompt("")
            }
        }

        val closeBtn = TextView(this).apply {
            text = " ✕ "
            setTextColor(Color.parseColor("#FF9CA3AF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setPadding(dp(8), dp(2), dp(4), dp(2))
            setOnClickListener { hideVoicePanel() }
        }

        headerRow.addView(title)
        headerRow.addView(openAppBtn)
        headerRow.addView(closeBtn)

        val statusTv = TextView(this).apply {
            text = "جاري الاستماع... تكلم الآن"
            setTextColor(Color.parseColor("#FFE5E7EB"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(0, dp(8), 0, dp(4))
        }
        panelStatusText = statusTv

        val transcriptTv = TextView(this).apply {
            text = "أمثلة: اكتب... | ابحث عن... | اتصل بـ... | اقرأ الرسائل | افتح واتساب"
            setTextColor(Color.parseColor("#FF9CA3AF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            setPadding(0, dp(2), 0, dp(10))
        }
        panelTranscriptText = transcriptTv

        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val listenAgainBtn = TextView(this).apply {
            text = "🎙 تحدث مجدداً"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(12), dp(7), dp(12), dp(7))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Color.parseColor("#FF2563EB"))
            }
            setOnClickListener { startVoiceCommandCapture() }
        }

        val stopServiceBtn = TextView(this).apply {
            text = "إخفاء الفقاعة"
            setTextColor(Color.parseColor("#FFF87171"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(12), dp(7), dp(12), dp(7))
            setOnClickListener { stopSelf() }
        }

        actionsRow.addView(listenAgainBtn)
        actionsRow.addView(stopServiceBtn)

        panel.addView(headerRow)
        panel.addView(statusTv)
        panel.addView(transcriptTv)
        panel.addView(actionsRow)

        val screenWidth = resources.displayMetrics.widthPixels
        val panelParams = WindowManager.LayoutParams(
            (screenWidth * 0.90).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayLayoutType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(48)
        }

        panelView = panel
        try {
            windowManager.addView(panel, panelParams)
        } catch (_: Exception) {}
    }

    private fun hideVoicePanel() {
        stopVoiceCapture()
        panelView?.let { v ->
            try {
                windowManager.removeView(v)
            } catch (_: Exception) {}
        }
        panelView = null
        panelStatusText = null
        panelTranscriptText = null
    }

    private fun updateBubbleColor(listening: Boolean) {
        val bg = bubbleView?.background as? GradientDrawable
        bg?.setStroke(dp(2), Color.parseColor(if (listening) "#FF10B981" else "#FF3B82F6"))
        micDotView?.text = if (listening) "🔴" else "🎙"
    }

    private fun startVoiceCommandCapture() {
        mainHandler.post {
            try {
                if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                    panelStatusText?.text = "خدمة التعرف الصوتي غير متاحة على الجهاز"
                    return@post
                }
                tts?.stop()
                speechRecognizer?.destroy()
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        isListening = true
                        updateBubbleColor(true)
                        panelStatusText?.text = "🎙 أسمعك الآن... تفضل"
                    }

                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}

                    override fun onEndOfSpeech() {
                        isListening = false
                        updateBubbleColor(false)
                        panelStatusText?.text = "جاري تنفيذ الأمر..."
                    }

                    override fun onError(error: Int) {
                        isListening = false
                        updateBubbleColor(false)
                        panelStatusText?.text = "لم أسمع صوتاً واضحاً — اضغط تحدث مجدداً"
                    }

                    override fun onResults(results: Bundle?) {
                        isListening = false
                        updateBubbleColor(false)
                        val spoken = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            ?.trim()
                            ?: ""
                        if (spoken.isNotEmpty()) {
                            panelTranscriptText?.text = "«$spoken»"
                            handleFloatingVoiceCommand(spoken)
                        } else {
                            panelStatusText?.text = "لم يتم التقاط نص — حاول مرة أخرى"
                        }
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val partial = partialResults
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            ?.trim()
                            ?: ""
                        if (partial.isNotEmpty()) {
                            panelTranscriptText?.text = partial
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-EG")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                speechRecognizer?.startListening(intent)
            } catch (e: Exception) {
                panelStatusText?.text = "خطأ في الميكروفون: ${e.message}"
            }
        }
    }

    private fun stopVoiceCapture() {
        isListening = false
        updateBubbleColor(false)
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
            speechRecognizer = null
        } catch (_: Exception) {}
    }

    private fun speakFeedback(text: String) {
        panelStatusText?.text = text
        if (ttsReady && text.isNotBlank()) {
            try {
                val hasAr = Regex("[\u0600-\u06FF]").containsMatchIn(text)
                tts?.language = if (hasAr) Locale("ar", "EG") else Locale.US
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "nimo_bubble")
            } catch (_: Exception) {}
        }
    }

    private fun handleFloatingVoiceCommand(rawText: String) {
        val text = rawText.trim()
        val norm = NimoPhoneHelper.normalizeArabic(text)

        // 1. Voice Typing into active input field ("اكتب ..." / "type ...")
        val typeMatch = Regex("""^(?:اكتبلي|اكتب|سجل نص|type|write)\s+(.+)$""", RegexOption.IGNORE_CASE).find(text)
        if (typeMatch != null) {
            val content = typeMatch.groupValues[1].trim()
            val acc = NimoVoiceControlAccessibilityService.instance
            if (acc != null && acc.typeTextIntoFocusedField(content, append = true)) {
                speakFeedback("تمت كتابة: $content")
                mainHandler.postDelayed({ hideVoicePanel() }, 1600)
            } else {
                NimoPhoneHelper.copyToClipboard(this, content)
                Toast.makeText(this, "تم نسخ النص (فعّل خدمة Nimo في إمكانية الوصول للكتابة المباشرة)", Toast.LENGTH_LONG).show()
                speakFeedback("تم نسخ النص للحافظة، يمكنك لصقه مباشرة.")
            }
            return
        }

        // 2. Global Navigation (Back / Home / Recents / Notifications / Screenshot)
        val navAction = when {
            norm == "ارجع" || norm == "رجوع" || norm == "back" -> "back"
            norm.contains("الشاشه الرئيسيه") || norm == "الرئيسيه" || norm == "home" -> "home"
            norm.contains("الاشعارات") || norm == "notifications" -> "notifications"
            norm.contains("سكرين شوت") || norm.contains("لقطه شاشه") || norm == "screenshot" -> "screenshot"
            norm.contains("التطبيقات الاخيره") || norm == "recents" -> "recents"
            else -> null
        }
        if (navAction != null) {
            val acc = NimoVoiceControlAccessibilityService.instance
            if (acc != null && acc.performSystemAction(navAction)) {
                hideVoicePanel()
            } else {
                speakFeedback("يرجى تفعيل خدمة Nimo من إعدادات إمكانية الوصول لتنفيذ أوامر التنقل.")
            }
            return
        }

        // 3. Flashlight ON / OFF
        if (norm.contains("شغل الكشاف") || norm.contains("افتح الكشاف") || norm.contains("flashlight on")) {
            val ok = NimoPhoneHelper.setFlashlight(this, true)
            speakFeedback(if (ok) "تم تشغيل الكشاف." else "تعذّر تشغيل الكشاف.")
            return
        }
        if (norm.contains("اطفي الكشاف") || norm.contains("اقفل الكشاف") || norm.contains("flashlight off")) {
            val ok = NimoPhoneHelper.setFlashlight(this, false)
            speakFeedback(if (ok) "تم إطفاء الكشاف." else "تعذّر إطفاء الكشاف.")
            return
        }

        // 4. Volume Controls
        if (norm.contains("علي الصوت") || norm.contains("ارفع الصوت") || norm.contains("volume up")) {
            NimoPhoneHelper.adjustVolume(this, "up")
            speakFeedback("تم رفع الصوت.")
            return
        }
        if (norm.contains("وطي الصوت") || norm.contains("اخفض الصوت") || norm.contains("volume down")) {
            NimoPhoneHelper.adjustVolume(this, "down")
            speakFeedback("تم خفض الصوت.")
            return
        }
        if (norm.contains("كتم الصوت") || norm.contains("صامت") || norm.contains("mute")) {
            NimoPhoneHelper.adjustVolume(this, "mute")
            panelStatusText?.text = "تم كتم الصوت."
            return
        }

        // 5. Battery & Phone Status
        if (norm.contains("البطاريه") || norm.contains("نسبه الشحن") || norm.contains("حاله الهاتف") || norm.contains("battery")) {
            val report = NimoPhoneHelper.readFullDeviceReport(this)
            val bat = report["batteryLevel"]
            val net = report["networkType"]
            val availRam = report["availRamMb"]
            val freeGb = String.format(Locale.US, "%.1f", (report["freeStorageGb"] as? Double) ?: 0.0)
            speakFeedback("البطارية $bat في المئة، الشبكة $net، الرام المتاح $availRam ميجابايت، والمساحة الفارغة $freeGb جيجابايت.")
            return
        }

        // 6. Read / Search SMS Messages
        if (norm.contains("اقرا الرسايل") || norm.contains("اخر رساله") || norm.contains("الرسايل") || norm.contains("رساله من") || norm.contains("read sms")) {
            val queryMatch = Regex("""(?:رساله من|رسالة من|رسائل من|رسايل من|بحث في الرسائل عن)\s+(.+)""").find(text)
            val q = queryMatch?.groupValues?.get(1)?.trim() ?: ""
            val smsList = NimoPhoneHelper.readSmsMessages(this, limit = 3, query = q)
            if (smsList.isEmpty()) {
                speakFeedback("لم أجد رسائل مطابقة أو لم يتم منح صلاحية قراءة الرسائل بعد.")
            } else {
                val top = smsList.first()
                val sender = (top["contactName"] as? String)?.ifBlank { top["address"] as? String } ?: "مرسل غير معروف"
                val body = (top["body"] as? String) ?: ""
                panelTranscriptText?.text = "$sender: $body"
                speakFeedback("آخر رسالة من $sender تقول: $body")
            }
            return
        }

        // 7. Call Contact by Name or Number
        val callMatch = Regex("""^(?:اتصل ب|اتصل على|كلم|رني على|call|dial)\s+(.+)$""", RegexOption.IGNORE_CASE).find(text)
        if (callMatch != null) {
            val target = callMatch.groupValues[1].trim()
            val digitsOnly = target.replace(Regex("[^0-9+]"), "")
            if (digitsOnly.length >= 6) {
                speakFeedback("جاري الاتصال بالرقم $digitsOnly")
                NimoPhoneHelper.dialOrCallNumber(this, digitsOnly, directCall = true)
                hideVoicePanel()
                return
            }
            val contact = NimoPhoneHelper.findBestContact(this, target)
            if (contact != null) {
                val name = contact["name"] ?: target
                val phone = contact["cleanPhone"] ?: contact["phone"] ?: ""
                speakFeedback("جاري الاتصال بـ $name")
                NimoPhoneHelper.dialOrCallNumber(this, phone, directCall = true)
                hideVoicePanel()
            } else {
                speakFeedback("لم أجد جهة اتصال باسم $target")
            }
            return
        }

        // 8. YouTube Search
        val ytMatch = Regex("""^(?:يوتيوب|ابحث في يوتيوب عن|شغل في يوتيوب|youtube)\s+(.+)$""", RegexOption.IGNORE_CASE).find(text)
        if (ytMatch != null) {
            val q = ytMatch.groupValues[1].trim()
            speakFeedback("جاري البحث في يوتيوب عن $q")
            NimoPhoneHelper.searchYoutube(this, q)
            hideVoicePanel()
            return
        }

        // 9. Google Web Search
        val searchMatch = Regex("""^(?:ابحث عن|بحث عن|دور على|جوجل|search|google)\s+(.+)$""", RegexOption.IGNORE_CASE).find(text)
        if (searchMatch != null) {
            val q = searchMatch.groupValues[1].trim()
            speakFeedback("جاري البحث في جوجل عن $q")
            NimoPhoneHelper.searchWeb(this, q)
            hideVoicePanel()
            return
        }

        // 10. Open Installed App
        val openMatch = Regex("""^(?:افتح|شغل|افتحلي|open|launch)\s+(?:تطبيق\s+)?(.+)$""", RegexOption.IGNORE_CASE).find(text)
        if (openMatch != null) {
            val target = openMatch.groupValues[1].trim()
            if (NimoPhoneHelper.launchAppByQuery(this, target)) {
                speakFeedback("تم فتح $target")
                hideVoicePanel()
                return
            }
        }

        // 11. Default: Forward any AI question directly to Nimo AI Chat!
        speakFeedback("جاري تحويل سؤالك إلى نيمو الذكي")
        hideVoicePanel()
        openNimoAppWithPrompt(text)
    }

    private fun openNimoAppWithPrompt(prompt: String) {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (prompt.isNotBlank()) {
                    putExtra(EXTRA_VOICE_PROMPT, prompt)
                }
            }
            startActivity(intent)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        isRunning = false
        hideVoicePanel()
        bubbleView?.let { v ->
            try {
                windowManager.removeView(v)
            } catch (_: Exception) {}
        }
        bubbleView = null
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
