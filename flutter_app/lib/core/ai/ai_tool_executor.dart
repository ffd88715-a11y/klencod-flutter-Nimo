import 'dart:math';
import 'package:talkora_ai/core/device/native_bridge_service.dart';

/// Result of parsing and executing autonomous AI / Voice phone actions.
class ToolExecutionOutcome {
  final String cleanReply;
  final String? actionBadge;
  final String? generatedImageUrl;
  final bool handledDirectly;

  const ToolExecutionOutcome({
    required this.cleanReply,
    this.actionBadge,
    this.generatedImageUrl,
    this.handledDirectly = false,
  });
}

/// Nimo v9.0 OmniControl — Autonomous Phone & AI Tool Executor.
/// Executes device management, SMS reading, contact lookup, call logs, floating bubble,
/// volume, web search & voice typing commands directly from Arabic/English voice & chat
/// as well as structured `[ACTION:type|arg1|arg2]` tags emitted by the AI model.
class AiToolExecutor {
  final NativeBridgeService bridge;

  const AiToolExecutor(this.bridge);

  /// Instructions injected into the AI system prompt when Device Control is enabled.
  static const String systemToolPrompt = '''
You are Nimo v9.0 OmniControl — an ultra-powerful assistant with FULL phone intelligence & control (SMS reading, Contacts lookup, Call logs, Floating Voice Bubble, Device Telemetry, Apps & Settings).
When the user asks you to perform a phone action or generate an image, include ONE exact action tag at the end of your reply:
- Open any app: [ACTION:open_app|app_name]
- Send WhatsApp message: [ACTION:whatsapp|phone_or_contact_name|message]
- Dial/Call number or contact: [ACTION:call|phone_or_contact_name]
- Send SMS: [ACTION:sms|phone_or_contact_name|message]
- Read or search phone SMS: [ACTION:read_sms|optional_search_query]
- Find contact info: [ACTION:find_contact|contact_name]
- Read recent call logs: [ACTION:read_calls|5]
- Full phone telemetry report: [ACTION:device_report|full]
- Toggle Floating Voice Bubble: [ACTION:floating_bubble|on] or [ACTION:floating_bubble|off]
- Control Volume: [ACTION:volume|up|down|mute|unmute]
- Google Web Search: [ACTION:web_search|query]
- Set Alarm (24h): [ACTION:alarm|HH:MM|label]
- Set Timer (seconds): [ACTION:timer|seconds|label]
- Open Google Maps: [ACTION:maps|place_or_address]
- Search YouTube: [ACTION:youtube|search_query]
- Toggle Flashlight: [ACTION:flashlight|on] or [ACTION:flashlight|off]
- Open Phone Settings: [ACTION:settings|wifi|bluetooth|display|battery|sound|location|apps|accessibility|main]
- Generate an AI Image: [ACTION:generate_image|detailed_english_prompt]
Only include an [ACTION:...] tag when the user actually requests that action. Always confirm naturally in the user's language.
''';

  /// Fast local intent interceptor for instant zero-latency phone commands (great for Live Voice & Chat!).
  Future<ToolExecutionOutcome?> tryInstantLocalCommand(
    String userText, {
    required bool isArabic,
  }) async {
    final text = userText.trim();
    final lower = text.toLowerCase();

    // 1. Floating Voice Bubble ON / OFF
    if (lower.contains('شغل الفقاعة') ||
        lower.contains('افتح الفقاعة') ||
        lower.contains('شغل الايقونة العائمة') ||
        lower.contains('شغل الأيقونة العائمة') ||
        lower.contains('الايقونة الباثقة') ||
        lower.contains('الأيقونة الباثقة') ||
        lower.contains('start floating bubble') ||
        lower.contains('enable voice bubble')) {
      final ok = await bridge.startFloatingBubble();
      return ToolExecutionOutcome(
        cleanReply: ok
            ? (isArabic
                ? 'تم تشغيل الأيقونة العائمة للتحكم الصوتي فوق كل التطبيقات! يمكنك سحبها لأي مكان والضغط عليها للتحدث.'
                : 'Floating Voice Bubble is now active over all apps!')
            : (isArabic
                ? 'يرجى السماح بصلاحية «الظهور فوق التطبيقات الأخرى» من الشاشة التي فُتحت لك ثم تفعيل الفقاعة مرة أخرى.'
                : 'Please grant Overlay permission in the settings screen that just opened, then enable the bubble again.'),
        actionBadge: ok
            ? (isArabic ? 'الأيقونة العائمة: شغالة' : 'Floating Bubble ON')
            : (isArabic ? 'مطلوب إذن الظهور فوق التطبيقات' : 'Overlay Permission Needed'),
        handledDirectly: true,
      );
    }
    if (lower.contains('اطفي الفقاعة') ||
        lower.contains('اقفل الفقاعة') ||
        lower.contains('اخفي الايقونة') ||
        lower.contains('أخفي الأيقونة') ||
        lower.contains('stop floating bubble')) {
      await bridge.stopFloatingBubble();
      return ToolExecutionOutcome(
        cleanReply: isArabic ? 'تم إيقاف وإخفاء الأيقونة العائمة.' : 'Floating Voice Bubble stopped.',
        actionBadge: isArabic ? 'الأيقونة العائمة: متوقفة' : 'Floating Bubble OFF',
        handledDirectly: true,
      );
    }

    // 2. Flashlight ON / OFF
    if (lower.contains('شغل الكشاف') ||
        lower.contains('افتح الكشاف') ||
        lower.contains('نور الكشاف') ||
        lower.contains('turn on flashlight') ||
        lower.contains('flashlight on')) {
      final ok = await bridge.toggleFlashlight(true);
      return ToolExecutionOutcome(
        cleanReply: ok
            ? (isArabic ? 'تم تشغيل الكشاف بنجاح.' : 'Flashlight turned on.')
            : (isArabic ? 'تعذّر تشغيل الكشاف على هذا الجهاز.' : 'Could not enable flashlight.'),
        actionBadge: ok ? (isArabic ? 'تم تشغيل الكشاف' : 'Flashlight ON') : null,
        handledDirectly: true,
      );
    }
    if (lower.contains('اطفي الكشاف') ||
        lower.contains('اقفل الكشاف') ||
        lower.contains('turn off flashlight') ||
        lower.contains('flashlight off')) {
      final ok = await bridge.toggleFlashlight(false);
      return ToolExecutionOutcome(
        cleanReply: ok
            ? (isArabic ? 'تم إطفاء الكشاف.' : 'Flashlight turned off.')
            : (isArabic ? 'تعذّر إطفاء الكشاف.' : 'Could not disable flashlight.'),
        actionBadge: ok ? (isArabic ? 'تم إطفاء الكشاف' : 'Flashlight OFF') : null,
        handledDirectly: true,
      );
    }

    // 3. Volume Controls
    if (lower.contains('علي الصوت') || lower.contains('ارفع الصوت') || lower.contains('volume up')) {
      await bridge.adjustVolume('up');
      return ToolExecutionOutcome(
        cleanReply: isArabic ? 'تم رفع مستوى الصوت.' : 'Volume increased.',
        actionBadge: isArabic ? 'رفع الصوت' : 'Volume Up',
        handledDirectly: true,
      );
    }
    if (lower.contains('وطي الصوت') || lower.contains('اخفض الصوت') || lower.contains('volume down')) {
      await bridge.adjustVolume('down');
      return ToolExecutionOutcome(
        cleanReply: isArabic ? 'تم خفض مستوى الصوت.' : 'Volume lowered.',
        actionBadge: isArabic ? 'خفض الصوت' : 'Volume Down',
        handledDirectly: true,
      );
    }
    if (lower.contains('كتم الصوت') || lower.contains('اكتم الصوت') || lower.contains('mute volume')) {
      await bridge.adjustVolume('mute');
      return ToolExecutionOutcome(
        cleanReply: isArabic ? 'تم كتم الصوت.' : 'Volume muted.',
        actionBadge: isArabic ? 'كتم الصوت' : 'Muted',
        handledDirectly: true,
      );
    }

    // 4. Full Device & Battery Status
    if (lower.contains('حالة البطارية') ||
        lower.contains('نسبة الشحن') ||
        lower.contains('شحن الموبايل') ||
        lower.contains('معلومات الهاتف') ||
        lower.contains('حالة الهاتف') ||
        lower.contains('حالة الموبايل') ||
        lower.contains('الرامات') ||
        lower.contains('المساحة الفارغة') ||
        lower.contains('battery status') ||
        lower.contains('phone status') ||
        lower.contains('device report')) {
      final info = await bridge.getDeviceStatus();
      final reply = _formatDeviceReport(info, isArabic: isArabic);
      return ToolExecutionOutcome(
        cleanReply: reply,
        actionBadge: isArabic
            ? 'البطارية ${info.batteryLevel}% • ${info.networkType}'
            : 'Battery ${info.batteryLevel}% • ${info.networkType}',
        handledDirectly: true,
      );
    }

    // 5. Read / Search Phone SMS Messages
    if (lower.contains('اقرأ الرسائل') ||
        lower.contains('اقرا الرسائل') ||
        lower.contains('اقرا الرسايل') ||
        lower.contains('آخر رسالة') ||
        lower.contains('اخر رساله') ||
        lower.contains('رسائل الهاتف') ||
        lower.contains('رسايل الهاتف') ||
        lower.contains('رسائل من') ||
        lower.contains('رسالة من') ||
        lower.contains('كود التحقق') ||
        lower.contains('read sms') ||
        lower.contains('latest sms') ||
        lower.contains('my messages')) {
      String query = '';
      final qMatch = RegExp(r"""(?:رسائل من|رسالة من|رسايل من|رساله من|ابحث في الرسائل عن|sms from|messages from)\s+(.+)""",
              caseSensitive: false)
          .firstMatch(text);
      if (qMatch != null) {
        query = qMatch.group(1)?.trim() ?? '';
      } else if (lower.contains('كود التحقق') || lower.contains('otp')) {
        query = 'كود';
      }
      final smsList = await bridge.getSmsMessages(limit: 5, query: query);
      if (smsList.isEmpty && query.isNotEmpty) {
        final fallback = await bridge.getSmsMessages(limit: 5);
        return ToolExecutionOutcome(
          cleanReply: _formatSmsReply(fallback, query: query, isArabic: isArabic, matchedQuery: false),
          actionBadge: isArabic ? 'رسائل الهاتف (${fallback.length})' : 'Phone SMS (${fallback.length})',
          handledDirectly: true,
        );
      }
      return ToolExecutionOutcome(
        cleanReply: _formatSmsReply(smsList, query: query, isArabic: isArabic, matchedQuery: true),
        actionBadge: isArabic ? 'رسائل SMS (${smsList.length})' : 'SMS (${smsList.length})',
        handledDirectly: true,
      );
    }

    // 6. Read Recent / Missed Call Logs
    if (lower.contains('سجل المكالمات') ||
        lower.contains('آخر مكالمات') ||
        lower.contains('اخر مكالمات') ||
        lower.contains('المكالمات الفائتة') ||
        lower.contains('مين رن') ||
        lower.contains('call log') ||
        lower.contains('missed calls') ||
        lower.contains('recent calls')) {
      final calls = await bridge.getCallLogs(limit: 6);
      if (calls.isEmpty) {
        return ToolExecutionOutcome(
          cleanReply: isArabic
              ? 'لا يوجد سجل مكالمات متاح حالياً (تأكد من منح صلاحية سجل المكالمات من مركز إدارة الهاتف).'
              : 'No call logs available (please grant Call Log permission in Phone Manager).',
          actionBadge: isArabic ? 'سجل المكالمات' : 'Call Log',
          handledDirectly: true,
        );
      }
      final buf = StringBuffer(isArabic ? 'آخر المكالمات على هاتفك:\n' : 'Recent calls on your phone:\n');
      for (final c in calls) {
        final typeAr = switch (c.type) {
          'outgoing' => 'صادرة',
          'missed' => 'فائتة',
          'rejected' => 'مرفوضة',
          _ => 'واردة',
        };
        buf.writeln('• ${c.displayName} (${c.number}) — ${isArabic ? typeAr : c.type} (${c.durationSec}s)');
      }
      return ToolExecutionOutcome(
        cleanReply: buf.toString().trim(),
        actionBadge: isArabic ? 'سجل المكالمات (${calls.length})' : 'Call Logs (${calls.length})',
        handledDirectly: true,
      );
    }

    // 7. Find Contact Number ("رقم أحمد" / "هات رقم ..." / "جهة اتصال ...")
    final findContactMatch = RegExp(
      r"""^(?:رقم|هات رقم|ابحث عن رقم|جهة اتصال|معلومات جهة اتصال|find contact|phone number of)\s+(.+)$""",
      caseSensitive: false,
    ).firstMatch(text);
    if (findContactMatch != null) {
      final q = findContactMatch.group(1)?.trim() ?? '';
      if (q.isNotEmpty) {
        final matches = await bridge.getContacts(query: q, limit: 6);
        if (matches.isEmpty) {
          return ToolExecutionOutcome(
            cleanReply: isArabic
                ? 'لم أجد جهة اتصال مطابقة لـ «$q» (تأكد من منح صلاحية جهات الاتصال من إدارة الهاتف).'
                : 'No contact found matching "$q".',
            actionBadge: isArabic ? 'بحث جهات الاتصال' : 'Contacts Search',
            handledDirectly: true,
          );
        }
        final buf = StringBuffer(isArabic ? 'جهات الاتصال المطابقة لـ «$q»:\n' : 'Matching contacts for "$q":\n');
        for (final c in matches) {
          buf.writeln('• ${c.name}: ${c.phone}');
        }
        return ToolExecutionOutcome(
          cleanReply: buf.toString().trim(),
          actionBadge: isArabic ? 'جهات الاتصال (${matches.length})' : 'Contacts (${matches.length})',
          handledDirectly: true,
        );
      }
    }

    // 8. Direct Call by Number OR Contact Name ("اتصل بـ أحمد" / "كلم 010..." / "call ...")
    final callMatch = RegExp(
      r"""^(?:اتصل بـ|اتصل ب|اتصل على|اتصل|كلم|رن على|call|dial)\s+(.+)$""",
      caseSensitive: false,
    ).firstMatch(text);
    if (callMatch != null) {
      final target = callMatch.group(1)!.trim();
      final digits = target.replaceAll(RegExp(r'[^0-9+*#]'), '');
      if (digits.length >= 5) {
        await bridge.dialPhone(digits, direct: true);
        return ToolExecutionOutcome(
          cleanReply: isArabic ? 'جاري الاتصال بالرقم $digits.' : 'Calling $digits now.',
          actionBadge: isArabic ? 'اتصال: $digits' : 'Call: $digits',
          handledDirectly: true,
        );
      }
      final contact = await bridge.findContact(target);
      if (contact != null) {
        await bridge.dialPhone(contact.cleanPhone, direct: true);
        return ToolExecutionOutcome(
          cleanReply: isArabic
              ? 'جاري الاتصال بـ ${contact.name} (${contact.phone}).'
              : 'Calling ${contact.name} (${contact.phone}).',
          actionBadge: isArabic ? 'اتصال: ${contact.name}' : 'Call: ${contact.name}',
          handledDirectly: true,
        );
      }
    }

    // 9. Direct Open App ("افتح واتساب" / "open youtube")
    final openAr = RegExp(r"""^(?:افتح|شغل|افتحلي|شغلي)\s+(?:تطبيق\s+)?(.+)$""").firstMatch(text);
    final openEn = RegExp(r"""^(?:open|launch)\s+(.+)$""", caseSensitive: false).firstMatch(text);
    final appTarget = (openAr?.group(1) ?? openEn?.group(1))?.trim();
    if (appTarget != null &&
        appTarget.isNotEmpty &&
        !appTarget.contains('الكشاف') &&
        !appTarget.contains('الفقاعة') &&
        !appTarget.contains('flashlight') &&
        appTarget.split(' ').length <= 3) {
      if (appTarget.contains('واي فاي') || appTarget.toLowerCase().contains('wifi')) {
        await bridge.openSystemSetting('wifi');
        return ToolExecutionOutcome(
          cleanReply: isArabic ? 'فتحت لك إعدادات الواي فاي.' : 'Opened Wi-Fi settings.',
          actionBadge: isArabic ? 'إعدادات Wi-Fi' : 'Wi-Fi Settings',
          handledDirectly: true,
        );
      }
      if (appTarget.contains('بلوتوث') || appTarget.toLowerCase().contains('bluetooth')) {
        await bridge.openSystemSetting('bluetooth');
        return ToolExecutionOutcome(
          cleanReply: isArabic ? 'فتحت لك إعدادات البلوتوث.' : 'Opened Bluetooth settings.',
          actionBadge: isArabic ? 'إعدادات البلوتوث' : 'Bluetooth Settings',
          handledDirectly: true,
        );
      }
      final launched = await bridge.launchApp(appTarget);
      if (launched) {
        return ToolExecutionOutcome(
          cleanReply: isArabic ? 'تم فتح $appTarget الآن.' : 'Opening $appTarget now.',
          actionBadge: isArabic ? 'تم فتح: $appTarget' : 'Opened: $appTarget',
          handledDirectly: true,
        );
      }
    }

    // 10. Direct YouTube Search
    final ytAr = RegExp(r"""(?:ابحث في يوتيوب عن|شغل في يوتيوب|يوتيوب عن)\s+(.+)""").firstMatch(text);
    final ytEn = RegExp(r"""(?:search youtube for|youtube)\s+(.+)""", caseSensitive: false).firstMatch(text);
    final ytQuery = (ytAr?.group(1) ?? ytEn?.group(1))?.trim();
    if (ytQuery != null && ytQuery.isNotEmpty) {
      await bridge.searchYoutube(ytQuery);
      return ToolExecutionOutcome(
        cleanReply: isArabic ? 'جاري البحث في يوتيوب عن: $ytQuery' : 'Searching YouTube for: $ytQuery',
        actionBadge: 'YouTube: $ytQuery',
        handledDirectly: true,
      );
    }

    // 11. Direct Google Web Search
    final webAr = RegExp(r"""^(?:ابحث في جوجل عن|ابحث عن|بحث في جوجل عن|جوجل)\s+(.+)$""").firstMatch(text);
    final webEn = RegExp(r"""^(?:search google for|google)\s+(.+)$""", caseSensitive: false).firstMatch(text);
    final webQuery = (webAr?.group(1) ?? webEn?.group(1))?.trim();
    if (webQuery != null && webQuery.isNotEmpty) {
      await bridge.searchWeb(webQuery);
      return ToolExecutionOutcome(
        cleanReply: isArabic ? 'جاري البحث في جوجل عن: $webQuery' : 'Searching Google for: $webQuery',
        actionBadge: 'Google: $webQuery',
        handledDirectly: true,
      );
    }

    // 12. Direct Slash Image Command
    final imgSlash = RegExp(r"""^/(?:image|img|draw)\s+(.+)$""", caseSensitive: false).firstMatch(text);
    final imgAr = RegExp(r"""^(?:ارسم لي|ارسم|ولد صورة|توليد صورة|اعمل صورة)\s+(.+)$""").firstMatch(text);
    final imgPrompt = (imgSlash?.group(1) ?? imgAr?.group(1))?.trim();
    if (imgPrompt != null && imgPrompt.isNotEmpty) {
      final url = _buildPollinationsImageUrl(imgPrompt);
      return ToolExecutionOutcome(
        cleanReply: isArabic
            ? 'تم توليد الصورة المطلوبة بنجاح! يمكنك أيضاً التعديل والحفظ بجودة أعلى من استوديو الصور.'
            : 'Generated your image! You can also refine and save in HD inside Image Studio.',
        actionBadge: isArabic ? 'توليد صورة AI' : 'AI Image Generated',
        generatedImageUrl: url,
        handledDirectly: true,
      );
    }

    return null;
  }

  /// Parses and executes any `[ACTION:type|arg1|arg2]` tags inside an AI response.
  Future<ToolExecutionOutcome> executeAiTags(
    String rawAiReply, {
    required bool isArabic,
  }) async {
    final regex = RegExp(r"""\[ACTION:([a-zA-Z0-9_]+)\|([^\]]*)\]""");
    final match = regex.firstMatch(rawAiReply);
    if (match == null) {
      return ToolExecutionOutcome(cleanReply: rawAiReply.trim());
    }

    final actionType = (match.group(1) ?? '').trim().toLowerCase();
    final rawArgs = (match.group(2) ?? '').split('|').map((s) => s.trim()).toList();
    var cleanReply = rawAiReply.replaceAll(regex, '').trim();

    String? badge;
    String? imageUrl;

    switch (actionType) {
      case 'open_app':
        final app = rawArgs.isNotEmpty ? rawArgs[0] : '';
        if (app.isNotEmpty) {
          final ok = await bridge.launchApp(app);
          badge = ok
              ? (isArabic ? 'تم فتح التطبيق: $app' : 'Opened App: $app')
              : (isArabic ? 'لم يتم العثور على التطبيق: $app' : 'App not found: $app');
        }
        break;
      case 'whatsapp':
        var phone = rawArgs.isNotEmpty ? rawArgs[0] : '';
        final msg = rawArgs.length > 1 ? rawArgs[1] : '';
        if (phone.isNotEmpty && !RegExp(r'^[+0-9\s\-]+$').hasMatch(phone)) {
          final c = await bridge.findContact(phone);
          if (c != null) phone = c.cleanPhone;
        }
        await bridge.openWhatsApp(phone: phone, message: msg);
        badge = isArabic ? 'فتح واتساب: $phone' : 'WhatsApp: $phone';
        break;
      case 'call':
        var target = rawArgs.isNotEmpty ? rawArgs[0] : '';
        if (target.isNotEmpty) {
          if (!RegExp(r'^[+0-9\s\-*#]+$').hasMatch(target)) {
            final c = await bridge.findContact(target);
            if (c != null) target = c.cleanPhone;
          }
          await bridge.dialPhone(target, direct: true);
          badge = isArabic ? 'اتصال: $target' : 'Call: $target';
        }
        break;
      case 'sms':
        var phone = rawArgs.isNotEmpty ? rawArgs[0] : '';
        final msg = rawArgs.length > 1 ? rawArgs[1] : '';
        if (phone.isNotEmpty && !RegExp(r'^[+0-9\s\-]+$').hasMatch(phone)) {
          final c = await bridge.findContact(phone);
          if (c != null) phone = c.cleanPhone;
        }
        await bridge.sendSms(phone: phone, message: msg);
        badge = isArabic ? 'رسالة SMS: $phone' : 'SMS: $phone';
        break;
      case 'read_sms':
        final q = rawArgs.isNotEmpty ? rawArgs[0] : '';
        final smsList = await bridge.getSmsMessages(limit: 5, query: q);
        final summary = _formatSmsReply(smsList, query: q, isArabic: isArabic, matchedQuery: true);
        cleanReply = cleanReply.isEmpty ? summary : '$cleanReply\n\n$summary';
        badge = isArabic ? 'رسائل SMS (${smsList.length})' : 'SMS (${smsList.length})';
        break;
      case 'find_contact':
        final q = rawArgs.isNotEmpty ? rawArgs[0] : '';
        final contacts = await bridge.getContacts(query: q, limit: 5);
        if (contacts.isNotEmpty) {
          final lines = contacts.map((c) => '• ${c.name}: ${c.phone}').join('\n');
          cleanReply = cleanReply.isEmpty ? lines : '$cleanReply\n\n$lines';
        }
        badge = isArabic ? 'جهات الاتصال (${contacts.length})' : 'Contacts (${contacts.length})';
        break;
      case 'read_calls':
        final calls = await bridge.getCallLogs(limit: 5);
        if (calls.isNotEmpty) {
          final lines = calls.map((c) => '• ${c.displayName} (${c.number}) — ${c.type}').join('\n');
          cleanReply = cleanReply.isEmpty ? lines : '$cleanReply\n\n$lines';
        }
        badge = isArabic ? 'سجل المكالمات (${calls.length})' : 'Call Log (${calls.length})';
        break;
      case 'device_report':
        final info = await bridge.getDeviceStatus();
        final report = _formatDeviceReport(info, isArabic: isArabic);
        cleanReply = cleanReply.isEmpty ? report : '$cleanReply\n\n$report';
        badge = isArabic ? 'تقرير الهاتف الكامل' : 'Full Device Report';
        break;
      case 'floating_bubble':
        final on = rawArgs.isNotEmpty && rawArgs[0].toLowerCase() == 'on';
        if (on) {
          await bridge.startFloatingBubble();
        } else {
          await bridge.stopFloatingBubble();
        }
        badge = on
            ? (isArabic ? 'الأيقونة العائمة: تشغيل' : 'Floating Bubble: ON')
            : (isArabic ? 'الأيقونة العائمة: إيقاف' : 'Floating Bubble: OFF');
        break;
      case 'volume':
        final dir = rawArgs.isNotEmpty ? rawArgs[0] : 'up';
        await bridge.adjustVolume(dir);
        badge = isArabic ? 'التحكم بالصوت: $dir' : 'Volume: $dir';
        break;
      case 'web_search':
        final q = rawArgs.isNotEmpty ? rawArgs[0] : '';
        if (q.isNotEmpty) {
          await bridge.searchWeb(q);
          badge = 'Google: $q';
        }
        break;
      case 'alarm':
        final timeStr = rawArgs.isNotEmpty ? rawArgs[0] : '07:00';
        final label = rawArgs.length > 1 ? rawArgs[1] : 'Nimo';
        final parts = timeStr.split(':');
        final h = int.tryParse(parts.isNotEmpty ? parts[0] : '7') ?? 7;
        final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        await bridge.setAlarm(hour: h, minute: m, message: label);
        badge = isArabic
            ? 'تم ضبط المنبه: $h:${m.toString().padLeft(2, '0')}'
            : 'Alarm set: $h:${m.toString().padLeft(2, '0')}';
        break;
      case 'timer':
        final secs = int.tryParse(rawArgs.isNotEmpty ? rawArgs[0] : '60') ?? 60;
        final label = rawArgs.length > 1 ? rawArgs[1] : 'Nimo Timer';
        await bridge.setTimer(seconds: secs, message: label);
        badge = isArabic ? 'تم ضبط مؤقت: $secs ثانية' : 'Timer set: ${secs}s';
        break;
      case 'maps':
        final q = rawArgs.isNotEmpty ? rawArgs[0] : '';
        if (q.isNotEmpty) {
          await bridge.openMaps(q, navigate: false);
          badge = isArabic ? 'خرائط: $q' : 'Maps: $q';
        }
        break;
      case 'youtube':
        final q = rawArgs.isNotEmpty ? rawArgs[0] : '';
        if (q.isNotEmpty) {
          await bridge.searchYoutube(q);
          badge = 'YouTube: $q';
        }
        break;
      case 'flashlight':
        final on = rawArgs.isNotEmpty && rawArgs[0].toLowerCase() == 'on';
        await bridge.toggleFlashlight(on);
        badge = on
            ? (isArabic ? 'الكشاف: تشغيل' : 'Flashlight: ON')
            : (isArabic ? 'الكشاف: إطفاء' : 'Flashlight: OFF');
        break;
      case 'settings':
        final target = rawArgs.isNotEmpty ? rawArgs[0] : 'main';
        await bridge.openSystemSetting(target);
        badge = isArabic ? 'فتح الإعدادات: $target' : 'Settings: $target';
        break;
      case 'generate_image':
        final prompt = rawArgs.isNotEmpty ? rawArgs[0] : '';
        if (prompt.isNotEmpty) {
          imageUrl = _buildPollinationsImageUrl(prompt);
          badge = isArabic ? 'تم توليد الصورة بالذكاء الاصطناعي' : 'AI Image Generated';
        }
        break;
    }

    return ToolExecutionOutcome(
      cleanReply: cleanReply.isEmpty
          ? (badge ?? (isArabic ? 'تم تنفيذ الأمر بنجاح.' : 'Action completed.'))
          : cleanReply,
      actionBadge: badge,
      generatedImageUrl: imageUrl,
    );
  }

  static String _formatDeviceReport(DeviceStatusInfo info, {required bool isArabic}) {
    final freeGb = info.freeStorageGb.toStringAsFixed(1);
    final totalGb = info.totalStorageGb.toStringAsFixed(1);
    final temp = info.batteryTempC.toStringAsFixed(1);
    if (isArabic) {
      return 'تقرير حالة الهاتف الكامل:\n'
          '• الجهاز: ${info.manufacturer} ${info.model} (Android ${info.androidVersion})\n'
          '• البطارية: ${info.batteryLevel}% (${info.isCharging ? 'قيد الشحن' : 'غير متصل بالشاحن'}) • الحرارة: $temp°C\n'
          '• الذاكرة العشوائية (RAM): متاح ${info.availRamMb} MB من ${info.totalRamMb} MB\n'
          '• مساحة التخزين: فارغ $freeGb GB من $totalGb GB\n'
          '• الشبكة: ${info.networkType} • صوت الوسائط: ${info.mediaVolumePct}% • السطوع: ${info.brightnessPct >= 0 ? '${info.brightnessPct}%' : 'تلقائي'}\n'
          '• الأيقونة العائمة: ${info.bubbleRunning ? 'مفعّلة' : 'متوقفة'} • التحكم الصوتي الشامل: ${info.accessibilityEnabled ? 'مفعّل' : 'غير مفعّل'}';
    }
    return 'Full Phone Telemetry Report:\n'
        '• Device: ${info.manufacturer} ${info.model} (Android ${info.androidVersion})\n'
        '• Battery: ${info.batteryLevel}% (${info.isCharging ? 'Charging' : 'Discharging'}) • Temp: $temp°C\n'
        '• RAM: ${info.availRamMb} MB free / ${info.totalRamMb} MB total\n'
        '• Storage: $freeGb GB free / $totalGb GB total\n'
        '• Network: ${info.networkType} • Media Vol: ${info.mediaVolumePct}% • Bubble: ${info.bubbleRunning ? 'Active' : 'Off'}';
  }

  static String _formatSmsReply(
    List<PhoneSmsItem> smsList, {
    required String query,
    required bool isArabic,
    required bool matchedQuery,
  }) {
    if (smsList.isEmpty) {
      return isArabic
          ? 'لم أجد رسائل SMS متاحة حالياً (تأكد من منح صلاحية قراءة الرسائل من مركز إدارة الهاتف).'
          : 'No SMS messages available (please grant Read SMS permission in Phone Manager).';
    }
    final buf = StringBuffer();
    if (query.isNotEmpty && matchedQuery) {
      buf.writeln(isArabic ? 'نتائج البحث في الرسائل عن «$query»:' : 'SMS matches for "$query":');
    } else {
      buf.writeln(isArabic ? 'أحدث رسائل الهاتف (SMS):' : 'Latest Phone SMS Messages:');
    }
    for (final sms in smsList) {
      final snippet = sms.body.length > 140 ? '${sms.body.substring(0, 140)}...' : sms.body;
      buf.writeln('• ${sms.displaySender}: $snippet');
    }
    return buf.toString().trim();
  }

  static String _buildPollinationsImageUrl(String prompt) {
    final seed = Random().nextInt(999999);
    final encoded = Uri.encodeComponent('$prompt, ultra high quality, detailed, 8k');
    return 'https://image.pollinations.ai/prompt/$encoded?width=768&height=768&model=flux&seed=$seed&nologo=true';
  }
}
