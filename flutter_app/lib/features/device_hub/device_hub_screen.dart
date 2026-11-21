import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/device/native_bridge_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';

/// Nimo v9.0 OmniControl — Full Phone Intelligence, SMS Reader, Contacts, Call Logs,
/// Floating Voice Bubble Overlay & Installed Apps Hub.
class DeviceHubScreen extends ConsumerStatefulWidget {
  const DeviceHubScreen({super.key});

  @override
  ConsumerState<DeviceHubScreen> createState() => _DeviceHubScreenState();
}

class _DeviceHubScreenState extends ConsumerState<DeviceHubScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  DeviceStatusInfo _status = const DeviceStatusInfo();
  PhonePermissionsStatus _perms = const PhonePermissionsStatus();
  List<InstalledAppInfo> _apps = [];
  List<PhoneSmsItem> _smsList = [];
  List<PhoneContactItem> _contacts = [];
  List<PhoneCallLogItem> _callLogs = [];

  String _appFilter = '';
  String _smsFilter = '';
  String _contactFilter = '';

  bool _loading = true;
  bool _torchOn = false;
  double _mediaVol = 50;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    final bridge = ref.read(nativeBridgeProvider);
    final results = await Future.wait<dynamic>([
      bridge.getDeviceStatus(),
      bridge.getPermissionsStatus(),
      bridge.getInstalledApps(),
      bridge.getSmsMessages(limit: 80),
      bridge.getContacts(limit: 350),
      bridge.getCallLogs(limit: 40),
    ]);
    if (!mounted) return;
    final st = results[0] as DeviceStatusInfo;
    setState(() {
      _status = st;
      _perms = results[1] as PhonePermissionsStatus;
      _apps = results[2] as List<InstalledAppInfo>;
      _smsList = results[3] as List<PhoneSmsItem>;
      _contacts = results[4] as List<PhoneContactItem>;
      _callLogs = results[5] as List<PhoneCallLogItem>;
      _torchOn = st.torchEnabled;
      _mediaVol = st.mediaVolumePct.toDouble().clamp(0, 100);
      _loading = false;
    });
  }

  Future<void> _requestAllPermissions() async {
    NimoSoundFx.click();
    final bridge = ref.read(nativeBridgeProvider);
    await bridge.requestPhonePermissions();
    await _refreshAll();
  }

  Future<void> _toggleBubble() async {
    NimoSoundFx.pop();
    final bridge = ref.read(nativeBridgeProvider);
    if (_status.bubbleRunning || _perms.bubbleRunning) {
      await bridge.stopFloatingBubble();
    } else {
      final started = await bridge.startFloatingBubble();
      if (!started && mounted) {
        final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'اسمح بإذن «الظهور فوق التطبيقات الأخرى» ثم اضغط تشغيل الفقاعة مرة أخرى.'
                  : 'Grant "Display over other apps" permission, then tap Start Bubble again.',
            ),
          ),
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _refreshAll();
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    final ok = await ref.read(nativeBridgeProvider).toggleFlashlight(next);
    if (mounted && ok) setState(() => _torchOn = next);
  }

  void _showQuickActionSheet({
    required String title,
    required String field1Label,
    String? field2Label,
    required Future<void> Function(String v1, String v2) onSubmit,
  }) {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: c1, decoration: InputDecoration(labelText: field1Label)),
            if (field2Label != null) ...[
              const SizedBox(height: 10),
              TextField(controller: c2, decoration: InputDecoration(labelText: field2Label)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onSubmit(c1.text.trim(), c2.text.trim());
            },
            child: Text(isAr ? 'تنفيذ' : 'Run'),
          ),
        ],
      ),
    );
  }

  void _showSmsDetailSheet(PhoneSmsItem sms, bool isAr) {
    final bridge = ref.read(nativeBridgeProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sms.displaySender, style: Theme.of(context).textTheme.titleLarge),
              if (sms.contactName.isNotEmpty)
                Text(sms.address, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(sms.body, style: const TextStyle(height: 1.5, fontSize: 14.5)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      bridge.speak('${sms.displaySender}: ${sms.body}');
                    },
                    icon: const Icon(CupertinoIcons.speaker_2_fill, size: 16),
                    label: Text(isAr ? 'قراءة بالصوت' : 'Read Aloud'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: sms.body));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isAr ? 'تم نسخ نص الرسالة' : 'SMS copied')),
                      );
                    },
                    icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 16),
                    label: Text(isAr ? 'نسخ' : 'Copy'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      bridge.sendSms(phone: sms.address, message: '');
                    },
                    icon: const Icon(CupertinoIcons.chat_bubble_fill, size: 16),
                    label: Text(isAr ? 'رد SMS' : 'Reply SMS'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(chatPrefillPromptProvider.notifier).state = isAr
                          ? 'لخّص لي هذه الرسالة من «${sms.displaySender}» واقترح أفضل رد عليها:\n${sms.body}'
                          : 'Summarize this SMS from "${sms.displaySender}" and suggest a reply:\n${sms.body}';
                      context.go('/chat');
                    },
                    icon: const Icon(CupertinoIcons.sparkles, size: 16),
                    label: Text(isAr ? 'تحليل بـ Nimo AI' : 'Ask Nimo AI'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatShortDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month} • $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'مركز التحكم الكامل بالهاتف' : 'OmniControl Phone Hub'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.refresh),
            onPressed: _refreshAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 18), text: isAr ? 'التحكم والفقاعة' : 'Control'),
            Tab(icon: const Icon(CupertinoIcons.mail_solid, size: 18), text: isAr ? 'الرسائل (${_smsList.length})' : 'SMS'),
            Tab(icon: const Icon(CupertinoIcons.person_2_fill, size: 18), text: isAr ? 'الأسماء (${_contacts.length})' : 'Contacts'),
            Tab(icon: const Icon(CupertinoIcons.phone_fill, size: 18), text: isAr ? 'المكالمات' : 'Calls'),
            Tab(icon: const Icon(CupertinoIcons.square_grid_2x2_fill, size: 18), text: isAr ? 'التطبيقات' : 'Apps'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildControlTab(context, theme, isAr),
          _buildSmsTab(context, theme, isAr),
          _buildContactsTab(context, theme, isAr),
          _buildCallsTab(context, theme, isAr),
          _buildAppsTab(context, theme, isAr),
        ],
      ),
    );
  }

  Widget _buildControlTab(BuildContext context, ThemeData theme, bool isAr) {
    final bridge = ref.read(nativeBridgeProvider);
    final bubbleOn = _status.bubbleRunning || _perms.bubbleRunning;
    final missingPerms = !_perms.sms || !_perms.contacts || !_perms.callLog || !_perms.mic;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 1. Floating Voice Overlay Bubble Card
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: (bubbleOn ? TalkoraColors.iosGreen : theme.colorScheme.primary).withValues(alpha: 0.45),
              width: 1.1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IosIconBadge(
                      icon: CupertinoIcons.mic_circle_fill,
                      color: bubbleOn ? TalkoraColors.iosGreen : TalkoraColors.iosBlue,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'الأيقونة العائمة للتحكم الصوتي' : 'Floating Voice Control Bubble',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isAr
                                ? 'تظهر فوق كل التطبيقات: كتابة صوتية، بحث، اتصال، قراءة SMS وفتح أي تطبيق'
                                : 'Floats over all apps for voice typing, search, calls, SMS & app launching',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: bubbleOn ? TalkoraColors.iosRed : TalkoraColors.iosGreen,
                        ),
                        onPressed: _toggleBubble,
                        icon: Icon(bubbleOn ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill, size: 17),
                        label: Text(
                          bubbleOn
                              ? (isAr ? 'إيقاف الفقاعة' : 'Stop Bubble')
                              : (isAr ? 'تشغيل الأيقونة العائمة' : 'Start Floating Bubble'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Icon(
                        _perms.overlay ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.exclamationmark_circle,
                        size: 16,
                        color: _perms.overlay ? TalkoraColors.iosGreen : TalkoraColors.iosOrange,
                      ),
                      label: Text(isAr ? 'إذن الظهور فوق التطبيقات' : 'Overlay Permission'),
                      onPressed: () async {
                        await bridge.requestOverlayPermission();
                        await _refreshAll();
                      },
                    ),
                    ActionChip(
                      avatar: Icon(
                        _perms.accessibility ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.hand_raised_fill,
                        size: 16,
                        color: _perms.accessibility ? TalkoraColors.iosGreen : TalkoraColors.iosIndigo,
                      ),
                      label: Text(isAr ? 'الكتابة والتحكم الصوتي الشامل' : 'Voice Typing Service'),
                      onPressed: () async {
                        await bridge.openAccessibilitySettings();
                        await _refreshAll();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. One-Tap Phone Permissions Banner
        if (missingPerms) ...[
          Card(
            child: ListTile(
              leading: const IosIconBadge(
                icon: CupertinoIcons.lock_open_fill,
                color: TalkoraColors.iosOrange,
                size: 40,
              ),
              title: Text(isAr ? 'تفعيل قراءة الرسائل والأسماء والمكالمات' : 'Enable SMS, Contacts & Calls Access'),
              subtitle: Text(
                isAr
                    ? 'امنح الصلاحيات مرة واحدة ليتمكن Nimo من قراءة رسائلك والاتصال بأسمائك بالصوت.'
                    : 'Grant permissions once so Nimo can read SMS, lookup contacts & place calls by voice.',
              ),
              trailing: FilledButton(
                onPressed: _requestAllPermissions,
                child: Text(isAr ? 'منح' : 'Grant'),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 3. Full Live Hardware Telemetry Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IosIconBadge(
                      icon: CupertinoIcons.device_phone_portrait,
                      color: TalkoraColors.iosBlue,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_status.manufacturer} ${_status.model}', style: theme.textTheme.titleMedium),
                          Text(
                            'Android ${_status.androidVersion} (SDK ${_status.sdkInt}) • ${_status.networkType}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_status.batteryLevel >= 0)
                      IosStatusPill(
                        label: '${_status.batteryLevel}%',
                        color: _status.batteryLevel > 25 ? TalkoraColors.iosGreen : TalkoraColors.iosRed,
                        icon: _status.isCharging
                            ? CupertinoIcons.battery_charging
                            : CupertinoIcons.battery_75_percent,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _TelemetryBar(
                  label: isAr
                      ? 'الرامات (RAM): متاح ${_status.availRamMb} MB / ${_status.totalRamMb} MB'
                      : 'RAM: ${_status.availRamMb} MB free / ${_status.totalRamMb} MB',
                  value: _status.usedRamPct,
                  color: TalkoraColors.iosTeal,
                ),
                const SizedBox(height: 10),
                _TelemetryBar(
                  label: isAr
                      ? 'التخزين: فارغ ${_status.freeStorageGb.toStringAsFixed(1)} GB / ${_status.totalStorageGb.toStringAsFixed(1)} GB'
                      : 'Storage: ${_status.freeStorageGb.toStringAsFixed(1)} GB free / ${_status.totalStorageGb.toStringAsFixed(1)} GB',
                  value: _status.usedStoragePct,
                  color: TalkoraColors.iosIndigo,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(CupertinoIcons.speaker_2_fill, size: 18),
                    const SizedBox(width: 8),
                    Text(isAr ? 'صوت الوسائط' : 'Media Vol', style: theme.textTheme.bodySmall),
                    Expanded(
                      child: Slider(
                        value: _mediaVol,
                        min: 0,
                        max: 100,
                        onChanged: (v) => setState(() => _mediaVol = v),
                        onChangeEnd: (v) => bridge.setVolume(stream: 'music', percent: v.round()),
                      ),
                    ),
                    Text('${_mediaVol.round()}%', style: theme.textTheme.bodySmall),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      isAr ? 'الحرارة: ${_status.batteryTempC.toStringAsFixed(1)}°C' : 'Temp: ${_status.batteryTempC.toStringAsFixed(1)}°C',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      isAr ? 'السطوع: ${_status.brightnessPct >= 0 ? '${_status.brightnessPct}%' : 'تلقائي'}' : 'Brightness: ${_status.brightnessPct}%',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_status.cpuAbi.isNotEmpty)
                      Text('CPU: ${_status.cpuAbi}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4. Quick Controls Grid
        Text(isAr ? 'أدوات التحكم السريع بالهاتف' : 'Quick Phone Controls', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _ControlTile(
              icon: _torchOn ? CupertinoIcons.lightbulb_fill : CupertinoIcons.lightbulb,
              color: _torchOn ? TalkoraColors.iosOrange : TalkoraColors.iosIndigo,
              label: isAr ? (_torchOn ? 'الكشاف: شغال' : 'الكشاف') : 'Flashlight',
              onTap: _toggleTorch,
            ),
            _ControlTile(
              icon: CupertinoIcons.search,
              color: TalkoraColors.iosBlue,
              label: isAr ? 'بحث جوجل' : 'Google Search',
              onTap: () => _showQuickActionSheet(
                title: isAr ? 'بحث فوري في جوجل' : 'Instant Google Search',
                field1Label: isAr ? 'كلمة البحث' : 'Search query',
                onSubmit: (q, _) async => bridge.searchWeb(q),
              ),
            ),
            _ControlTile(
              icon: CupertinoIcons.chat_bubble_text_fill,
              color: TalkoraColors.iosGreen,
              label: isAr ? 'رسالة واتساب' : 'WhatsApp',
              onTap: () => _showQuickActionSheet(
                title: isAr ? 'إرسال واتساب مباشر' : 'Direct WhatsApp',
                field1Label: isAr ? 'رقم الهاتف (مثال 010...)' : 'Phone number',
                field2Label: isAr ? 'الرسالة' : 'Message',
                onSubmit: (p, m) async => bridge.openWhatsApp(phone: p, message: m),
              ),
            ),
            _ControlTile(
              icon: CupertinoIcons.alarm_fill,
              color: TalkoraColors.iosRed,
              label: isAr ? 'ضبط منبه' : 'Set Alarm',
              onTap: () => _showQuickActionSheet(
                title: isAr ? 'ضبط منبه جديد' : 'Set Alarm',
                field1Label: isAr ? 'الساعة (مثال 07:30)' : 'Time (HH:MM)',
                field2Label: isAr ? 'عنوان المنبه' : 'Label',
                onSubmit: (t, msg) async {
                  final p = t.split(':');
                  final h = int.tryParse(p.isNotEmpty ? p[0] : '7') ?? 7;
                  final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
                  await bridge.setAlarm(hour: h, minute: m, message: msg.isEmpty ? 'Nimo' : msg);
                },
              ),
            ),
            _ControlTile(
              icon: CupertinoIcons.map_pin_ellipse,
              color: TalkoraColors.iosTeal,
              label: isAr ? 'خرائط GPS' : 'Maps GPS',
              onTap: () => _showQuickActionSheet(
                title: isAr ? 'الانتقال عبر الخرائط' : 'Open Maps',
                field1Label: isAr ? 'المكان أو العنوان' : 'Place or address',
                onSubmit: (q, _) async => bridge.openMaps(q, navigate: false),
              ),
            ),
            _ControlTile(
              icon: CupertinoIcons.play_rectangle_fill,
              color: TalkoraColors.iosPink,
              label: isAr ? 'بحث يوتيوب' : 'YouTube',
              onTap: () => _showQuickActionSheet(
                title: isAr ? 'بحث في يوتيوب' : 'Search YouTube',
                field1Label: isAr ? 'كلمة البحث' : 'Search query',
                onSubmit: (q, _) async => bridge.searchYoutube(q),
              ),
            ),
            _ControlTile(
              icon: CupertinoIcons.wifi,
              color: TalkoraColors.iosTeal,
              label: isAr ? 'إعدادات Wi-Fi' : 'Wi-Fi',
              onTap: () => bridge.openSystemSetting('wifi'),
            ),
            _ControlTile(
              icon: CupertinoIcons.bluetooth,
              color: TalkoraColors.iosBlue,
              label: isAr ? 'البلوتوث' : 'Bluetooth',
              onTap: () => bridge.openSystemSetting('bluetooth'),
            ),
            _ControlTile(
              icon: CupertinoIcons.gear_solid,
              color: const Color(0xFF636366),
              label: isAr ? 'إعدادات النظام' : 'System',
              onTap: () => bridge.openSystemSetting('main'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmsTab(BuildContext context, ThemeData theme, bool isAr) {
    final filtered = _smsFilter.trim().isEmpty
        ? _smsList
        : _smsList.where((s) {
            final q = _smsFilter.toLowerCase();
            return s.displaySender.toLowerCase().contains(q) ||
                s.address.toLowerCase().contains(q) ||
                s.body.toLowerCase().contains(q);
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (!_perms.sms)
          Card(
            child: ListTile(
              leading: const IosIconBadge(icon: CupertinoIcons.mail_solid, color: TalkoraColors.iosOrange, size: 38),
              title: Text(isAr ? 'صلاحية قراءة رسائل SMS مطلوبة' : 'Read SMS permission required'),
              trailing: FilledButton(
                onPressed: _requestAllPermissions,
                child: Text(isAr ? 'سماح' : 'Allow'),
              ),
            ),
          ),
        TextField(
          onChanged: (v) => setState(() => _smsFilter = v),
          decoration: InputDecoration(
            hintText: isAr ? 'ابحث في الرسائل (كود تحقق، بنك، اسم مرسل)...' : 'Search SMS messages...',
            prefixIcon: const Icon(CupertinoIcons.search),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator()))
        else if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(isAr ? 'لا توجد رسائل مطابقة حالياً.' : 'No matching SMS messages.'),
            ),
          )
        else
          for (final sms in filtered.take(60))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: IosIconBadge(
                  icon: sms.type == 'sent' ? CupertinoIcons.arrow_up_right : CupertinoIcons.mail_solid,
                  color: sms.type == 'sent' ? TalkoraColors.iosTeal : TalkoraColors.iosBlue,
                  size: 36,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sms.displaySender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(_formatShortDate(sms.dateTime), style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(sms.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                onTap: () => _showSmsDetailSheet(sms, isAr),
              ),
            ),
      ],
    );
  }

  Widget _buildContactsTab(BuildContext context, ThemeData theme, bool isAr) {
    final bridge = ref.read(nativeBridgeProvider);
    final filtered = _contactFilter.trim().isEmpty
        ? _contacts
        : _contacts.where((c) {
            final q = _contactFilter.toLowerCase();
            return c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q);
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (!_perms.contacts)
          Card(
            child: ListTile(
              leading: const IosIconBadge(icon: CupertinoIcons.person_2_fill, color: TalkoraColors.iosOrange, size: 38),
              title: Text(isAr ? 'صلاحية جهات الاتصال مطلوبة' : 'Contacts permission required'),
              trailing: FilledButton(
                onPressed: _requestAllPermissions,
                child: Text(isAr ? 'سماح' : 'Allow'),
              ),
            ),
          ),
        TextField(
          onChanged: (v) => setState(() => _contactFilter = v),
          decoration: InputDecoration(
            hintText: isAr ? 'ابحث بالاسم أو الرقم للاتصال أو واتساب...' : 'Search contacts by name or number...',
            prefixIcon: const Icon(CupertinoIcons.search),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator()))
        else if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(isAr ? 'لا توجد جهات اتصال مطابقة.' : 'No matching contacts.'),
            ),
          )
        else
          for (final c in filtered.take(100))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const IosIconBadge(
                  icon: CupertinoIcons.person_crop_circle_fill,
                  color: TalkoraColors.iosIndigo,
                  size: 36,
                ),
                title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(c.phone),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: isAr ? 'اتصال' : 'Call',
                      icon: const Icon(CupertinoIcons.phone_fill, color: TalkoraColors.iosGreen, size: 20),
                      onPressed: () => bridge.dialPhone(c.cleanPhone, direct: true),
                    ),
                    IconButton(
                      tooltip: isAr ? 'واتساب' : 'WhatsApp',
                      icon: const Icon(CupertinoIcons.chat_bubble_fill, color: TalkoraColors.iosTeal, size: 20),
                      onPressed: () => bridge.openWhatsApp(phone: c.cleanPhone),
                    ),
                    IconButton(
                      tooltip: 'SMS',
                      icon: const Icon(CupertinoIcons.mail_solid, color: TalkoraColors.iosBlue, size: 19),
                      onPressed: () => bridge.sendSms(phone: c.cleanPhone),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildCallsTab(BuildContext context, ThemeData theme, bool isAr) {
    final bridge = ref.read(nativeBridgeProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (!_perms.callLog)
          Card(
            child: ListTile(
              leading: const IosIconBadge(icon: CupertinoIcons.phone_fill, color: TalkoraColors.iosOrange, size: 38),
              title: Text(isAr ? 'صلاحية سجل المكالمات مطلوبة' : 'Call Log permission required'),
              trailing: FilledButton(
                onPressed: _requestAllPermissions,
                child: Text(isAr ? 'سماح' : 'Allow'),
              ),
            ),
          ),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator()))
        else if (_callLogs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(isAr ? 'لا يوجد سجل مكالمات متاح.' : 'No recent calls available.'),
            ),
          )
        else
          for (final call in _callLogs)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: IosIconBadge(
                  icon: call.type == 'missed'
                      ? CupertinoIcons.phone_arrow_down_left
                      : call.type == 'outgoing'
                          ? CupertinoIcons.phone_arrow_up_right
                          : CupertinoIcons.phone_fill,
                  color: call.type == 'missed'
                      ? TalkoraColors.iosRed
                      : call.type == 'outgoing'
                          ? TalkoraColors.iosBlue
                          : TalkoraColors.iosGreen,
                  size: 36,
                ),
                title: Text(call.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${call.number} • ${_formatShortDate(call.dateTime)} • ${call.durationSec}s'),
                trailing: IconButton(
                  icon: const Icon(CupertinoIcons.phone_circle_fill, color: TalkoraColors.iosGreen, size: 26),
                  onPressed: () => bridge.dialPhone(call.number, direct: true),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildAppsTab(BuildContext context, ThemeData theme, bool isAr) {
    final bridge = ref.read(nativeBridgeProvider);
    final filteredApps = _appFilter.trim().isEmpty
        ? _apps
        : _apps.where((a) {
            final q = _appFilter.toLowerCase();
            return a.name.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q);
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        TextField(
          onChanged: (v) => setState(() => _appFilter = v),
          decoration: InputDecoration(
            hintText: isAr ? 'ابحث عن أي تطبيق لفتحه فوراً...' : 'Search any installed app to launch...',
            prefixIcon: const Icon(CupertinoIcons.search),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator()))
        else if (filteredApps.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(isAr ? 'لا توجد تطبيقات مطابقة.' : 'No matching apps found.'),
            ),
          )
        else
          IosGroupedSection(
            children: filteredApps.take(100).map((app) {
              return IosSettingsRow(
                icon: CupertinoIcons.app_badge_fill,
                iconColor: theme.colorScheme.primary,
                title: app.name,
                subtitle: app.packageName,
                onTap: () => bridge.launchApp(app.packageName),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _TelemetryBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _TelemetryBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 6,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ControlTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ControlTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IosIconBadge(icon: icon, color: color, size: 36),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
