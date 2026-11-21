package ai.talkora.app

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Nimo v9.0 OmniControl — System-Wide Voice Typing & Navigation Accessibility Service.
 * When enabled by the user in Android Accessibility Settings, allows Nimo's floating voice
 * bubble to type spoken text directly into ANY app's focused input field and execute
 * global actions (Back, Home, Recents, Notifications, Quick Settings, Screenshot).
 */
class NimoVoiceControlAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: NimoVoiceControlAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Passive listener — active actions are triggered on-demand by voice commands.
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    /**
     * Types [text] directly into the currently focused editable field across any Android app.
     */
    fun typeTextIntoFocusedField(text: String, append: Boolean = true): Boolean {
        val clean = text.trim()
        if (clean.isEmpty()) return false
        return try {
            val root = rootInActiveWindow ?: return false
            val targetNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: findFirstEditableNode(root)
                ?: return false

            val existing = targetNode.text?.toString() ?: ""
            val isHint = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                targetNode.isShowingHintText
            } else {
                false
            }

            val finalText = if (append && existing.isNotBlank() && !isHint) {
                "$existing $clean"
            } else {
                clean
            }

            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, finalText)
            }
            var ok = targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)

            if (!ok) {
                // Fallback: copy to clipboard and trigger native PASTE on the focused field
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("Nimo Voice", clean))
                ok = targetNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            }
            ok
        } catch (_: Exception) {
            false
        }
    }

    private fun findFirstEditableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isVisibleToUser) return node
        for (i in 0 until node.childCount) {
            val found = findFirstEditableNode(node.getChild(i))
            if (found != null) return found
        }
        return null
    }

    /**
     * Executes global Android navigation / system actions by voice.
     */
    fun performSystemAction(action: String): Boolean {
        return try {
            val globalId = when (action.lowercase()) {
                "back", "رجوع", "ارجع" -> GLOBAL_ACTION_BACK
                "home", "الرئيسية", "الشاشة الرئيسية" -> GLOBAL_ACTION_HOME
                "recents", "التطبيقات الاخيرة", "المهام" -> GLOBAL_ACTION_RECENTS
                "notifications", "الاشعارات", "الإشعارات" -> GLOBAL_ACTION_NOTIFICATIONS
                "quick_settings", "الاعدادات السريعة" -> GLOBAL_ACTION_QUICK_SETTINGS
                "screenshot", "سكرين شوت", "لقطة شاشة" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        GLOBAL_ACTION_TAKE_SCREENSHOT
                    } else {
                        return false
                    }
                }
                "lock", "قفل الشاشة" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        GLOBAL_ACTION_LOCK_SCREEN
                    } else {
                        return false
                    }
                }
                else -> return false
            }
            performGlobalAction(globalId)
        } catch (_: Exception) {
            false
        }
    }
}
