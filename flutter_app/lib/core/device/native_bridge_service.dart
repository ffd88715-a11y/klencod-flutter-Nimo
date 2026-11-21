import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a launchable app installed on the user's phone.
class InstalledAppInfo {
  final String name;
  final String packageName;

  const InstalledAppInfo({required this.name, required this.packageName});

  factory InstalledAppInfo.fromMap(Map<dynamic, dynamic> map) {
    return InstalledAppInfo(
      name: (map['name'] ?? '').toString(),
      packageName: (map['packageName'] ?? '').toString(),
    );
  }
}

/// Phone SMS message item read natively from Android Telephony.
class PhoneSmsItem {
  final String id;
  final String address;
  final String contactName;
  final String body;
  final int dateMs;
  final String type; // inbox, sent, draft
  final bool read;

  const PhoneSmsItem({
    required this.id,
    required this.address,
    this.contactName = '',
    required this.body,
    required this.dateMs,
    this.type = 'inbox',
    this.read = true,
  });

  String get displaySender => contactName.trim().isNotEmpty ? contactName : address;
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(dateMs);

  factory PhoneSmsItem.fromMap(Map<dynamic, dynamic> map) {
    return PhoneSmsItem(
      id: (map['id'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      contactName: (map['contactName'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      dateMs: (map['dateMs'] as num?)?.toInt() ?? 0,
      type: (map['type'] ?? 'inbox').toString(),
      read: map['read'] != false,
    );
  }
}

/// Phone contact item read natively from Android ContactsContract.
class PhoneContactItem {
  final String name;
  final String phone;
  final String cleanPhone;

  const PhoneContactItem({
    required this.name,
    required this.phone,
    required this.cleanPhone,
  });

  factory PhoneContactItem.fromMap(Map<dynamic, dynamic> map) {
    return PhoneContactItem(
      name: (map['name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      cleanPhone: (map['cleanPhone'] ?? map['phone'] ?? '').toString(),
    );
  }
}

/// Phone call log item read natively from Android CallLog.
class PhoneCallLogItem {
  final String name;
  final String number;
  final String type; // incoming, outgoing, missed, rejected
  final int dateMs;
  final int durationSec;

  const PhoneCallLogItem({
    this.name = '',
    required this.number,
    this.type = 'incoming',
    required this.dateMs,
    this.durationSec = 0,
  });

  String get displayName => name.trim().isNotEmpty ? name : number;
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(dateMs);

  factory PhoneCallLogItem.fromMap(Map<dynamic, dynamic> map) {
    return PhoneCallLogItem(
      name: (map['name'] ?? '').toString(),
      number: (map['number'] ?? '').toString(),
      type: (map['type'] ?? 'incoming').toString(),
      dateMs: (map['dateMs'] as num?)?.toInt() ?? 0,
      durationSec: (map['durationSec'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Status of all phone permissions & native services.
class PhonePermissionsStatus {
  final bool sms;
  final bool contacts;
  final bool callLog;
  final bool callPhone;
  final bool mic;
  final bool overlay;
  final bool accessibility;
  final bool bubbleRunning;

  const PhonePermissionsStatus({
    this.sms = false,
    this.contacts = false,
    this.callLog = false,
    this.callPhone = false,
    this.mic = false,
    this.overlay = false,
    this.accessibility = false,
    this.bubbleRunning = false,
  });

  factory PhonePermissionsStatus.fromMap(Map<dynamic, dynamic> map) {
    return PhonePermissionsStatus(
      sms: map['sms'] == true,
      contacts: map['contacts'] == true,
      callLog: map['callLog'] == true,
      callPhone: map['callPhone'] == true,
      mic: map['mic'] == true,
      overlay: map['overlay'] == true,
      accessibility: map['accessibility'] == true,
      bubbleRunning: map['bubbleRunning'] == true,
    );
  }
}

/// Native Android TTS voice descriptor for realistic voice selection.
class NativeVoiceInfo {
  final String name;
  final String locale;
  final int quality;
  final bool isNetwork;

  const NativeVoiceInfo({
    required this.name,
    required this.locale,
    this.quality = 400,
    this.isNetwork = false,
  });

  factory NativeVoiceInfo.fromMap(Map<dynamic, dynamic> map) {
    return NativeVoiceInfo(
      name: (map['name'] ?? '').toString(),
      locale: (map['locale'] ?? '').toString(),
      quality: (map['quality'] as num?)?.toInt() ?? 400,
      isNetwork: map['isNetwork'] == true,
    );
  }
}

/// Live Android hardware, battery, RAM, storage, network & audio telemetry.
class DeviceStatusInfo {
  final int batteryLevel;
  final bool isCharging;
  final double batteryTempC;
  final int batteryVoltageMv;
  final String manufacturer;
  final String brand;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final String securityPatch;
  final String cpuAbi;
  final bool torchEnabled;
  final int totalRamMb;
  final int availRamMb;
  final double totalStorageGb;
  final double freeStorageGb;
  final String networkType;
  final int mediaVolumePct;
  final int ringVolumePct;
  final String ringerMode;
  final int brightnessPct;
  final bool canDrawOverlays;
  final bool bubbleRunning;
  final bool accessibilityEnabled;

  const DeviceStatusInfo({
    this.batteryLevel = -1,
    this.isCharging = false,
    this.batteryTempC = 0,
    this.batteryVoltageMv = 0,
    this.manufacturer = 'Android',
    this.brand = '',
    this.model = 'Device',
    this.androidVersion = '',
    this.sdkInt = 0,
    this.securityPatch = '',
    this.cpuAbi = '',
    this.torchEnabled = false,
    this.totalRamMb = 0,
    this.availRamMb = 0,
    this.totalStorageGb = 0,
    this.freeStorageGb = 0,
    this.networkType = 'Unknown',
    this.mediaVolumePct = 50,
    this.ringVolumePct = 50,
    this.ringerMode = 'normal',
    this.brightnessPct = -1,
    this.canDrawOverlays = false,
    this.bubbleRunning = false,
    this.accessibilityEnabled = false,
  });

  double get usedRamPct => totalRamMb > 0 ? ((totalRamMb - availRamMb) / totalRamMb).clamp(0.0, 1.0) : 0.0;
  double get usedStoragePct =>
      totalStorageGb > 0 ? ((totalStorageGb - freeStorageGb) / totalStorageGb).clamp(0.0, 1.0) : 0.0;

  factory DeviceStatusInfo.fromMap(Map<dynamic, dynamic> map) {
    return DeviceStatusInfo(
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? -1,
      isCharging: map['isCharging'] == true,
      batteryTempC: (map['batteryTempC'] as num?)?.toDouble() ?? 0.0,
      batteryVoltageMv: (map['batteryVoltageMv'] as num?)?.toInt() ?? 0,
      manufacturer: (map['manufacturer'] ?? 'Android').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? 'Device').toString(),
      androidVersion: (map['androidVersion'] ?? '').toString(),
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      securityPatch: (map['securityPatch'] ?? '').toString(),
      cpuAbi: (map['cpuAbi'] ?? '').toString(),
      torchEnabled: map['torchEnabled'] == true,
      totalRamMb: (map['totalRamMb'] as num?)?.toInt() ?? 0,
      availRamMb: (map['availRamMb'] as num?)?.toInt() ?? 0,
      totalStorageGb: (map['totalStorageGb'] as num?)?.toDouble() ?? 0.0,
      freeStorageGb: (map['freeStorageGb'] as num?)?.toDouble() ?? 0.0,
      networkType: (map['networkType'] ?? 'Unknown').toString(),
      mediaVolumePct: (map['mediaVolumePct'] as num?)?.toInt() ?? 50,
      ringVolumePct: (map['ringVolumePct'] as num?)?.toInt() ?? 50,
      ringerMode: (map['ringerMode'] ?? 'normal').toString(),
      brightnessPct: (map['brightnessPct'] as num?)?.toInt() ?? -1,
      canDrawOverlays: map['canDrawOverlays'] == true,
      bubbleRunning: map['bubbleRunning'] == true,
      accessibilityEnabled: map['accessibilityEnabled'] == true,
    );
  }
}

/// Real-time event emitted by native Android SpeechRecognizer, TextToSpeech & Floating Bubble.
class NativeVoiceEvent {
  final String type;
  final String text;
  final double level;
  final int code;
  final String message;

  const NativeVoiceEvent({
    required this.type,
    this.text = '',
    this.level = 0.08,
    this.code = 0,
    this.message = '',
  });

  factory NativeVoiceEvent.fromDynamic(dynamic raw) {
    if (raw is Map) {
      return NativeVoiceEvent(
        type: (raw['type'] ?? '').toString(),
        text: (raw['text'] ?? '').toString(),
        level: (raw['level'] as num?)?.toDouble() ?? 0.08,
        code: (raw['code'] as num?)?.toInt() ?? 0,
        message: (raw['message'] ?? '').toString(),
      );
    }
    return const NativeVoiceEvent(type: 'unknown');
  }
}

/// Unified Flutter <-> Native Android Bridge for Live Voice, Floating Bubble, SMS, Contacts, Call Logs & Full Phone Control.
class NativeBridgeService {
  static const MethodChannel _channel = MethodChannel('ai.talkora.app/native_bridge');
  static const EventChannel _voiceEventsChannel = EventChannel('ai.talkora.app/voice_events');

  Stream<NativeVoiceEvent>? _cachedVoiceStream;

  Stream<NativeVoiceEvent> get voiceEvents {
    _cachedVoiceStream ??= _voiceEventsChannel
        .receiveBroadcastStream()
        .map(NativeVoiceEvent.fromDynamic)
        .asBroadcastStream();
    return _cachedVoiceStream!;
  }

  // ==================== TACTILE CLICK SOUND ====================
  Future<void> playClickSound() async {
    try {
      await _channel.invokeMethod<bool>('playClickSound');
    } catch (_) {}
  }

  // ==================== LIVE VOICE (STT / NEURAL TTS) ====================
  Future<bool> isSpeechAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isSpeechAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startListening({String locale = 'ar-EG'}) async {
    try {
      return await _channel.invokeMethod<bool>('startListening', {'locale': locale}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod<bool>('stopListening');
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    try {
      await _channel.invokeMethod<bool>('cancelListening');
    } catch (_) {}
  }

  Future<List<NativeVoiceInfo>> getAvailableVoices({String? localePrefix}) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getAvailableVoices', {
        if (localePrefix != null) 'localePrefix': localePrefix,
      });
      if (raw == null) return const [];
      return raw.whereType<Map<dynamic, dynamic>>().map(NativeVoiceInfo.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> speak(
    String text, {
    String? locale,
    double rate = 0.98,
    double pitch = 0.97,
    String? voiceName,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    final detectedLocale = locale ?? (containsArabic(clean) ? 'ar-EG' : 'en-US');
    try {
      return await _channel.invokeMethod<bool>('speak', {
            'text': clean,
            'locale': detectedLocale,
            'rate': rate,
            'pitch': pitch,
            if (voiceName != null && voiceName.isNotEmpty) 'voiceName': voiceName,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _channel.invokeMethod<bool>('stopSpeaking');
    } catch (_) {}
  }

  static bool containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  // ==================== NIMO v9.0 OMNI PHONE INTELLIGENCE ====================
  Future<List<PhoneSmsItem>> getSmsMessages({int limit = 60, String query = ''}) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getSmsMessages', {
        'limit': limit,
        'query': query,
      });
      if (raw == null) return const [];
      return raw.whereType<Map<dynamic, dynamic>>().map(PhoneSmsItem.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<PhoneContactItem>> getContacts({String query = '', int limit = 300}) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getContacts', {
        'query': query,
        'limit': limit,
      });
      if (raw == null) return const [];
      return raw.whereType<Map<dynamic, dynamic>>().map(PhoneContactItem.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<PhoneContactItem?> findContact(String query) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('findContact', {'query': query});
      if (raw != null) return PhoneContactItem.fromMap(raw);
    } catch (_) {}
    return null;
  }

  Future<List<PhoneCallLogItem>> getCallLogs({int limit = 40}) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getCallLogs', {'limit': limit});
      if (raw == null) return const [];
      return raw.whereType<Map<dynamic, dynamic>>().map(PhoneCallLogItem.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<PhonePermissionsStatus> getPermissionsStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPermissionsStatus');
      if (raw != null) return PhonePermissionsStatus.fromMap(raw);
    } catch (_) {}
    return const PhonePermissionsStatus();
  }

  Future<PhonePermissionsStatus> requestPhonePermissions() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('requestPhonePermissions');
      if (raw != null) return PhonePermissionsStatus.fromMap(raw);
    } catch (_) {}
    return const PhonePermissionsStatus();
  }

  Future<bool> requestOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAccessibilitySettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAccessibilitySettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startFloatingBubble() async {
    try {
      return await _channel.invokeMethod<bool>('startFloatingBubble') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopFloatingBubble() async {
    try {
      return await _channel.invokeMethod<bool>('stopFloatingBubble') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isFloatingBubbleRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isFloatingBubbleRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getPendingBubblePrompt() async {
    try {
      return await _channel.invokeMethod<String>('getPendingBubblePrompt') ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> performVoiceType(String text) async {
    try {
      return await _channel.invokeMethod<bool>('performVoiceType', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> performSystemAction(String action) async {
    try {
      return await _channel.invokeMethod<bool>('performSystemAction', {'action': action}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setVolume({String stream = 'music', required int percent}) async {
    try {
      return await _channel.invokeMethod<bool>('setVolume', {
            'stream': stream,
            'percent': percent,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> adjustVolume(String direction) async {
    try {
      return await _channel.invokeMethod<bool>('adjustVolume', {'direction': direction}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> searchWeb(String query) async {
    try {
      return await _channel.invokeMethod<bool>('searchWeb', {'query': query}) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ==================== PHONE APPS & FULL DEVICE MANAGEMENT ====================
  Future<List<InstalledAppInfo>> getInstalledApps() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (raw == null) return const [];
      return raw.whereType<Map<dynamic, dynamic>>().map(InstalledAppInfo.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> launchApp(String query) async {
    try {
      return await _channel.invokeMethod<bool>('launchApp', {'query': query}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openWhatsApp({required String phone, String message = ''}) async {
    try {
      return await _channel.invokeMethod<bool>('openWhatsApp', {
            'phone': phone,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> dialPhone(String phone, {bool direct = false}) async {
    try {
      return await _channel.invokeMethod<bool>('dialPhone', {
            'phone': phone,
            'direct': direct,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendSms({required String phone, String message = ''}) async {
    try {
      return await _channel.invokeMethod<bool>('sendSms', {
            'phone': phone,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendEmail({
    required String to,
    String subject = '',
    String body = '',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('sendEmail', {
            'to': to,
            'subject': subject,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setAlarm({required int hour, required int minute, String message = 'Nimo'}) async {
    try {
      return await _channel.invokeMethod<bool>('setAlarm', {
            'hour': hour,
            'minute': minute,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setTimer({required int seconds, String message = 'Nimo Timer'}) async {
    try {
      return await _channel.invokeMethod<bool>('setTimer', {
            'seconds': seconds,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openMaps(String query, {bool navigate = false}) async {
    try {
      return await _channel.invokeMethod<bool>('openMaps', {
            'query': query,
            'navigate': navigate,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> searchYoutube(String query) async {
    try {
      return await _channel.invokeMethod<bool>('searchYoutube', {'query': query}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openSystemSetting(String target) async {
    try {
      return await _channel.invokeMethod<bool>('openSystemSetting', {'target': target}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleFlashlight(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('toggleFlashlight', {'enabled': enabled}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<DeviceStatusInfo> getDeviceStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getFullDeviceReport');
      if (raw != null) return DeviceStatusInfo.fromMap(raw);
    } catch (_) {}
    return const DeviceStatusInfo();
  }

  Future<bool> shareText(String text, {String subject = 'Nimo'}) async {
    try {
      return await _channel.invokeMethod<bool>('shareText', {
            'text': text,
            'subject': subject,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveImageToGallery(Uint8List bytes, String fileName) async {
    try {
      return await _channel.invokeMethod<bool>('saveImageToGallery', {
            'bytes': bytes,
            'fileName': fileName,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

final nativeBridgeProvider = Provider<NativeBridgeService>((ref) => NativeBridgeService());
