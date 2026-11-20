import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:talkora_ai/app/theme/app_theme.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/audio/sound_fx_service.dart';
import 'package:talkora_ai/core/knowledge/github_knowledge_service.dart';
import 'package:talkora_ai/core/knowledge/nimo_local_db_service.dart';
import 'package:talkora_ai/core/storage/app_state_provider.dart';
import 'package:talkora_ai/core/widgets/ios_components.dart';
import 'package:talkora_ai/core/widgets/nimo_clipboard_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shared draft holder so any chat code block can open directly inside Nimo Coding Lab.
final codingLabDraftProvider = StateProvider<({String code, String language})?>((ref) => null);

/// Nimo v5.0 Ultra — Coding Lab Pro with LIVE Interactive WebView Code Preview,
/// Live JS Console Capture, AI Smart Preview for Flutter/Python/SQL, Undo/Redo, & 6 AI Actions.
class CodingLabScreen extends ConsumerStatefulWidget {
  const CodingLabScreen({super.key});

  @override
  ConsumerState<CodingLabScreen> createState() => _CodingLabScreenState();
}

class _CodingLabScreenState extends ConsumerState<CodingLabScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _promptCtrl = TextEditingController();
  late final WebViewController _webCtrl;

  String _selectedLang = 'HTML / CSS';
  double _fontSize = 13.5;
  bool _isWorking = false;
  bool _isBuildingPreview = false;
  bool _showHighlightedView = false;
  int _activePane = 0; // 0 = Editor, 1 = Live Preview, 2 = Console
  bool _mobileViewport = false;
  String? _aiOutput;
  String? _aiExtractedCode;
  String _lastPreviewHtml = '';
  final List<String> _consoleLogs = [];
  final List<String> _undoStack = [];

  static const List<String> _languages = [
    'HTML / CSS',
    'JavaScript',
    'Dart / Flutter',
    'Python',
    'TypeScript',
    'Kotlin',
    'SQL',
    'C++',
    'PHP',
    'JSON',
  ];

  static const Map<String, String> _starterTemplates = {
    'HTML / CSS': '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    body {
      margin: 0; font-family: system-ui, sans-serif;
      background: #121417; color: #f2f4f8;
      display: flex; align-items: center; justify-content: center;
      min-height: 100vh; padding: 20px; box-sizing: border-box;
    }
    .card {
      width: 100%; max-width: 360px; background: #1A1D24;
      border: 1px solid rgba(255,255,255,0.1); border-radius: 20px;
      padding: 24px; text-align: center; box-shadow: 0 14px 34px rgba(0,0,0,0.35);
    }
    h2 { margin: 0 0 8px; color: #4DA3FF; }
    p { margin: 0 0 18px; color: #A6AEBC; font-size: 14px; }
    button {
      background: #2F7CF6; color: #fff; border: none; border-radius: 12px;
      padding: 12px 22px; font-size: 15px; font-weight: 700; cursor: pointer;
    }
    #count { font-size: 34px; font-weight: 800; margin: 12px 0; }
  </style>
</head>
<body>
  <div class="card">
    <h2>مختبر Nimo v5.0</h2>
    <p>معاينة حية وتفاعلية للكود مباشرة داخل التطبيق</p>
    <div id="count">0</div>
    <button onclick="inc()">اضغط للتجربة +1</button>
  </div>
  <script>
    let n = 0;
    function inc() {
      n++;
      document.getElementById('count').textContent = n;
      console.log('Counter updated to: ' + n);
    }
    console.log('Nimo Live Preview Ready!');
  </script>
</body>
</html>''',
    'JavaScript': '''// جرب الضغط على "معاينة الكود" لرؤية المخرجات الحية في الـ Console!
const items = [
  { name: 'Nimo AI', score: 98 },
  { name: 'Coding Lab', score: 95 },
  { name: 'GitHub RAG', score: 99 }
];

const topItems = items.filter(i => i.score >= 95);
console.log('Top Modules:', JSON.stringify(topItems, null, 2));

const avg = items.reduce((s, i) => s + i.score, 0) / items.length;
console.log('Average Power Score:', avg.toFixed(1) + '%');''',
    'Dart / Flutter': '''import 'package:flutter/material.dart';

class NimoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const NimoCard({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}''',
    'Python': '''def search_records(records: list[dict], query: str) -> list[dict]:
    q = query.strip().lower()
    return [r for r in records if q in r.get("title", "").lower()]

if __name__ == "__main__":
    data = [{"title": "Nimo v5.0 Ultra"}, {"title": "Flutter Pro"}, {"title": "Nimo RAG"}]
    print(search_records(data, "nimo"))''',
    'TypeScript': '''interface NimoTask {
  id: string;
  title: string;
  completed: boolean;
}

export function toggleTask(tasks: NimoTask[], id: string): NimoTask[] {
  return tasks.map(t => (t.id === id ? { ...t, completed: !t.completed } : t));
}''',
    'Kotlin': '''fun formatGreeting(name: String): String {
    return "Hello, \$name from Nimo v5.0 Android!"
}''',
    'SQL': '''SELECT id, title, category
FROM nimo_knowledge
WHERE title LIKE '%flutter%'
ORDER BY id DESC
LIMIT 25;''',
    'C++': '''#include <iostream>

int main() {
    std::cout << "Nimo v5.0 Coding Lab C++" << std::endl;
    return 0;
}''',
    'PHP': '''<?php
header('Content-Type: application/json; charset=utf-8');
echo json_encode(['app' => 'Nimo v5.0', 'status' => 'online']);''',
    'JSON': '''{
  "app": "Nimo v5.0 Ultra",
  "developer": "YOSSEF JOO",
  "features": ["Live Preview", "Auto-Latest Model", "GitHub DB Injection"]
}''',
  };

  @override
  void initState() {
    super.initState();
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF121417))
      ..addJavaScriptChannel(
        'NimoConsole',
        onMessageReceived: (JavaScriptMessage msg) {
          if (!mounted) return;
          setState(() {
            _consoleLogs.add(msg.message);
            if (_consoleLogs.length > 100) _consoleLogs.removeAt(0);
          });
        },
      );

    final draft = ref.read(codingLabDraftProvider);
    if (draft != null && draft.code.isNotEmpty) {
      _codeCtrl.text = draft.code;
      _selectedLang = _matchLanguage(draft.language);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(codingLabDraftProvider.notifier).state = null;
      });
    } else {
      _codeCtrl.text = _starterTemplates[_selectedLang]!;
    }
  }

  String _matchLanguage(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('html') || l.contains('css') || l.contains('svg')) return 'HTML / CSS';
    if (l.contains('py')) return 'Python';
    if (l.contains('ts') || l.contains('typescript')) return 'TypeScript';
    if (l.contains('js') || l.contains('javascript')) return 'JavaScript';
    if (l.contains('kt') || l.contains('kotlin')) return 'Kotlin';
    if (l.contains('sql')) return 'SQL';
    if (l.contains('cpp') || l.contains('c++')) return 'C++';
    if (l.contains('php')) return 'PHP';
    if (l.contains('json')) return 'JSON';
    return 'Dart / Flutter';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  void _pushUndo() {
    if (_undoStack.isEmpty || _undoStack.last != _codeCtrl.text) {
      _undoStack.add(_codeCtrl.text);
      if (_undoStack.length > 25) _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    NimoSoundFx.click();
    setState(() => _codeCtrl.text = _undoStack.removeLast());
  }

  /// Wraps user HTML/CSS/JS with a console interceptor so every log & runtime error appears in Console!
  String _buildExecutableHtml(String rawCode, String lang) {
    const consoleHook = '''
<script>
(function(){
  function send(level, args){
    try {
      var msg = Array.prototype.slice.call(args).map(function(a){
        return typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a);
      }).join(' ');
      if (window.NimoConsole) NimoConsole.postMessage('[' + level + '] ' + msg);
    } catch(e){}
  }
  var origLog = console.log, origErr = console.error, origWarn = console.warn;
  console.log = function(){ send('LOG', arguments); if(origLog) origLog.apply(console, arguments); };
  console.warn = function(){ send('WARN', arguments); if(origWarn) origWarn.apply(console, arguments); };
  console.error = function(){ send('ERROR', arguments); if(origErr) origErr.apply(console, arguments); };
  window.onerror = function(msg, url, line){ send('ERROR', [msg + ' (line ' + line + ')']); };
})();
</script>
''';

    if (lang == 'JavaScript') {
      final safeCode = rawCode.replaceAll('</script>', '<\\/script>');
      return '''<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body { background:#121417; color:#E6EDF3; font-family:monospace; padding:16px; margin:0; }
  .line { padding:6px 10px; margin-bottom:6px; background:#1A1D24; border-radius:8px; white-space:pre-wrap; border-left:3px solid #2F7CF6; }
  .err { border-left-color:#FF453A; color:#FF8A80; }
  h3 { margin:0 0 12px; font-family:sans-serif; color:#4DA3FF; }
</style>
$consoleHook
</head><body>
<h3>JavaScript Live Output</h3>
<div id="out"></div>
<script>
  const _out = document.getElementById('out');
  const _prevLog = console.log;
  console.log = function(...args){
    _prevLog(...args);
    const d = document.createElement('div');
    d.className = 'line';
    d.textContent = args.map(a => typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)).join(' ');
    _out.appendChild(d);
  };
  try {
    $safeCode
  } catch(e) {
    console.error(e.toString());
    const d = document.createElement('div');
    d.className = 'line err';
    d.textContent = 'Error: ' + e.toString();
    _out.appendChild(d);
  }
</script></body></html>''';
    }

    if (lang == 'JSON') {
      try {
        final decoded = jsonDecode(rawCode);
        final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
        final escaped = const HtmlEscape().convert(pretty);
        return '''<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{background:#121417;color:#A5D6FF;font-family:monospace;padding:16px;margin:0;}pre{background:#1A1D24;padding:16px;border-radius:14px;overflow:auto;line-height:1.5;}</style>
$consoleHook
</head><body><pre>$escaped</pre><script>console.log('Valid JSON formatted successfully!');</script></body></html>''';
      } catch (e) {
        return '''<!DOCTYPE html><html><body style="background:#121417;color:#FF6B6B;font-family:monospace;padding:20px;">Invalid JSON: ${const HtmlEscape().convert(e.toString())}</body></html>''';
      }
    }

    // HTML / CSS / SVG
    if (rawCode.toLowerCase().contains('<html')) {
      return rawCode.replaceFirst(RegExp(r"""<head[^>]*>""", caseSensitive: false), '<head>$consoleHook');
    }
    return '''<!DOCTYPE html>
<html dir="auto"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{background:#121417;color:#E6EDF3;font-family:system-ui,sans-serif;padding:16px;margin:0;}</style>
$consoleHook
</head><body>$rawCode</body></html>''';
  }

  /// Runs LIVE Code Preview:
  /// - HTML/CSS/JS/JSON renders instantly inside the embedded interactive WebView!
  /// - Dart/Flutter/Python/Kotlin/SQL/C++/PHP uses AI Smart Preview to generate a live interactive
  ///   HTML preview or exact simulated execution output directly inside the WebView!
  Future<void> _openLivePreview() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    NimoSoundFx.pop();
    setState(() {
      _consoleLogs.clear();
      _activePane = 1;
    });

    if (_selectedLang == 'HTML / CSS' || _selectedLang == 'JavaScript' || _selectedLang == 'JSON') {
      final html = _buildExecutableHtml(code, _selectedLang);
      _lastPreviewHtml = html;
      await _webCtrl.loadHtmlString(html);
      return;
    }

    // Smart AI Live Visual / Execution Preview for Dart/Flutter, Python, SQL, Kotlin, C++, PHP, TS
    setState(() => _isBuildingPreview = true);
    final ai = ref.read(aiSettingsProvider);
    final service = ref.read(universalAiServiceProvider);
    final res = await service.sendChat(
      settings: ai,
      systemPromptOverride:
          'You are Nimo Live Code Preview Engine. Convert the given $_selectedLang code into a single self-contained HTML5 page (dark matte theme #121417, card #1A1D24) that visually previews the UI (if it is Flutter/Dart/UI code) OR displays the exact simulated terminal output and step-by-step trace (if it is Python/SQL/C++/Kotlin/PHP/TS). Return ONLY valid HTML starting with <!DOCTYPE html> with no markdown fences.',
      messages: [AiChatMessage(role: 'user', content: code, timestamp: DateTime.now())],
    );

    if (!mounted) return;
    setState(() => _isBuildingPreview = false);

    if (res.success && res.text.trim().isNotEmpty) {
      var html = res.text.trim();
      final match = RegExp(r"""```(?:html)?\n?([\s\S]*?)```""").firstMatch(html);
      if (match != null) html = match.group(1)!.trim();
      _lastPreviewHtml = html;
      _consoleLogs.add('[PREVIEW] Smart preview rendered via ${res.providerName} (${res.modelName})');
      await _webCtrl.loadHtmlString(html);
    } else {
      final escaped = const HtmlEscape().convert(code);
      final fallbackHtml =
          '<!DOCTYPE html><html><body style="background:#121417;color:#E6EDF3;font-family:monospace;padding:16px;">'
          '<h3 style="color:#FF9F0A;">Offline Code Preview ($_selectedLang)</h3>'
          '<pre style="background:#1A1D24;padding:14px;border-radius:12px;overflow:auto;">$escaped</pre></body></html>';
      _lastPreviewHtml = fallbackHtml;
      await _webCtrl.loadHtmlString(fallbackHtml);
    }
  }

  void _openFullscreenPreview() {
    if (_lastPreviewHtml.isEmpty) return;
    NimoSoundFx.click();
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(isAr ? 'معاينة ملء الشاشة' : 'Fullscreen Preview'),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.refresh),
                onPressed: () => _webCtrl.reload(),
              ),
            ],
          ),
          body: WebViewWidget(controller: _webCtrl),
        ),
      ),
    );
  }

  void _autoFormatCode() {
    NimoSoundFx.click();
    _pushUndo();
    final lines = _codeCtrl.text.split('\n');
    int indent = 0;
    final out = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('}') || line.startsWith(']') || line.startsWith(')')) {
        indent = (indent - 1).clamp(0, 12);
      }
      out.add('${'  ' * indent}$line');
      if (line.endsWith('{') || line.endsWith('[') || line.endsWith('(') || line.endsWith(':')) {
        indent = (indent + 1).clamp(0, 12);
      }
    }
    setState(() => _codeCtrl.text = out.join('\n'));
  }

  Future<void> _runAiCodeAction(String action) async {
    if (_isWorking) return;
    NimoSoundFx.click();
    final code = _codeCtrl.text.trim();
    final idea = _promptCtrl.text.trim();
    final isAr = ref.read(learnerProfileProvider).uiLocale == 'ar';

    if (action == 'generate' && idea.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'اكتب وصف الكود المطلوب أولاً في خانة الأمر' : 'Enter what you want to build first',
          ),
        ),
      );
      return;
    }
    if (action != 'generate' && code.isEmpty) return;

    setState(() {
      _isWorking = true;
      _aiOutput = null;
      _aiExtractedCode = null;
    });

    final ai = ref.read(aiSettingsProvider);
    final service = ref.read(universalAiServiceProvider);
    final localRag = ref.read(nimoLocalDbProvider.notifier).buildOfflineRagContext('$_selectedLang $idea $action');
    final ghRag = ref.read(githubKnowledgeProvider.notifier).buildRagContext('$_selectedLang $idea');

    String instruction;
    switch (action) {
      case 'generate':
        instruction = 'Write clean, complete, production-ready $_selectedLang code for: $idea. '
            'Put the final code inside ONE fenced code block and add a short ${isAr ? 'Arabic' : 'English'} explanation.';
        break;
      case 'fix':
        instruction = 'Find all bugs, edge cases, and syntax issues in this $_selectedLang code, '
            'fix them cleanly, return the full fixed code in ONE fenced code block, and explain fixes in ${isAr ? 'Arabic' : 'English'}.';
        break;
      case 'optimize':
        instruction = 'Optimize this $_selectedLang code for speed, readability, and clean architecture. '
            'Return the optimized code in ONE fenced code block and summarize improvements in ${isAr ? 'Arabic' : 'English'}.';
        break;
      case 'tests':
        instruction = 'Write clean unit tests covering edge cases for this $_selectedLang code in ONE fenced code block with a brief ${isAr ? 'Arabic' : 'English'} summary.';
        break;
      default:
        instruction = 'Explain this $_selectedLang code clearly line-by-line in ${isAr ? 'Arabic' : 'English'} with practical tips.';
        break;
    }

    final userMsg = action == 'generate' ? '$instruction\n\nRequest: $idea' : '$instruction\n\n```$_selectedLang\n$code\n```';
    final res = await service.sendChat(
      settings: ai,
      systemPromptOverride:
          'You are Nimo v5.0 Coding Lab Pro — Principal Software Architect. Deliver clean, bug-free, copy-ready code.',
      ragContext: '$localRag$ghRag',
      messages: [AiChatMessage(role: 'user', content: userMsg, timestamp: DateTime.now())],
    );

    if (!mounted) return;
    String? extracted;
    if (res.success) {
      final match = RegExp(r"""```[a-zA-Z0-9_+-]*\n?([\s\S]*?)```""").firstMatch(res.text);
      extracted = match?.group(1)?.trim();
      ref.read(learnerProfileProvider.notifier).addXp(25);
    }

    setState(() {
      _isWorking = false;
      _aiOutput = res.success ? res.text : (res.error ?? 'Connection error');
      _aiExtractedCode = extracted;
    });
  }

  TextSpan _highlightCode(String source) {
    final spans = <TextSpan>[];
    final tokenRegex = RegExp(
      r"""(//[^\n]*|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:import|export|class|extends|implements|const|final|var|let|function|def|return|async|await|if|else|for|while|switch|case|try|catch|new|void|int|double|bool|String|Widget|override|super|true|false|null|SELECT|FROM|WHERE|ORDER|BY|LIMIT|JOIN|INSERT|UPDATE)\b|\b\d+(?:\.\d+)?\b)""",
    );
    int last = 0;
    for (final m in tokenRegex.allMatches(source)) {
      if (m.start > last) {
        spans.add(TextSpan(
          text: source.substring(last, m.start),
          style: const TextStyle(color: Color(0xFFE6EDF3)),
        ));
      }
      final tok = m.group(0)!;
      Color color = const Color(0xFFE6EDF3);
      if (tok.startsWith('//') || tok.startsWith('#')) {
        color = const Color(0xFF7D8590);
      } else if (tok.startsWith('"') || tok.startsWith("'")) {
        color = const Color(0xFFA5D6FF);
      } else if (RegExp(r"""^\d""").hasMatch(tok)) {
        color = const Color(0xFFFFB86C);
      } else {
        color = const Color(0xFFFF7B72);
      }
      spans.add(TextSpan(text: tok, style: TextStyle(color: color)));
      last = m.end;
    }
    if (last < source.length) {
      spans.add(TextSpan(
        text: source.substring(last),
        style: const TextStyle(color: Color(0xFFE6EDF3)),
      ));
    }
    return TextSpan(
      style: GoogleFonts.jetBrainsMono(fontSize: _fontSize, height: 1.55),
      children: spans,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = ref.watch(learnerProfileProvider).uiLocale == 'ar';
    final ai = ref.watch(aiSettingsProvider);
    final theme = Theme.of(context);
    final lineCount = '\n'.allMatches(_codeCtrl.text).length + 1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(isAr ? 'مختبر البرمجة Pro' : 'Nimo Coding Lab Pro', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            IosStatusPill(
              label: '$_selectedLang • ${ai.activePreset.shortName}',
              color: theme.colorScheme.primary,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: TalkoraColors.iosGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 34),
              ),
              onPressed: _openLivePreview,
              icon: const Icon(CupertinoIcons.play_fill, size: 15),
              label: Text(isAr ? 'معاينة الكود' : 'Preview', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(
            tooltip: isAr ? 'مصحح الكتابة' : 'Writing Lab',
            icon: const Icon(CupertinoIcons.doc_text, size: 20),
            onPressed: () {
              NimoSoundFx.click();
              context.push('/writing');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
        children: [
          // Language Selector Chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final lang = _languages[i];
                final sel = lang == _selectedLang;
                return ChoiceChip(
                  label: Text(lang, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  selected: sel,
                  onSelected: (_) {
                    NimoSoundFx.click();
                    setState(() => _selectedLang = lang);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Quick AI Prompt Generator Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  decoration: InputDecoration(
                    hintText: isAr
                        ? 'اكتب فكرة الصفحة أو الكود ليولده Nimo وتعاينه فوراً...'
                        : 'Describe the code or UI to generate & preview...',
                    prefixIcon: const Icon(CupertinoIcons.sparkles, size: 18),
                    suffixIcon: IconButton(
                      tooltip: isAr ? 'لصق' : 'Paste',
                      icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
                      onPressed: () => NimoClipboardHelper.pasteIntoController(
                        context,
                        _promptCtrl,
                        isAr: isAr,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _isWorking ? null : () => _runAiCodeAction('generate'),
                  child: _isWorking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CupertinoActivityIndicator(color: Colors.white),
                        )
                      : Text(isAr ? 'توليد' : 'Build'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3-Mode Workspace Switcher: Editor | Live Preview | Console
          CupertinoSlidingSegmentedControl<int>(
            groupValue: _activePane,
            onValueChanged: (v) {
              if (v == null) return;
              NimoSoundFx.click();
              if (v == 1) {
                _openLivePreview();
              } else {
                setState(() => _activePane = v);
              }
            },
            children: {
              0: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text(isAr ? 'المحرر' : 'Editor', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              1: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text(isAr ? 'معاينة الكود الحية' : 'Live Preview', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              2: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text(
                  isAr ? 'الكونسول (${_consoleLogs.length})' : 'Console (${_consoleLogs.length})',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            },
          ),
          const SizedBox(height: 10),

          // ================ PANE 0: CODE EDITOR ================
          if (_activePane == 0)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF101319),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.9),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: const Color(0xFF1A1E28),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _EditorToolBtn(
                            icon: CupertinoIcons.play_fill,
                            label: isAr ? 'معاينة' : 'Preview',
                            color: TalkoraColors.iosGreen,
                            onTap: _openLivePreview,
                          ),
                          const SizedBox(width: 6),
                          NimoCopyChip(
                            textToCopy: _codeCtrl.text,
                            isAr: isAr,
                            label: isAr ? 'نسخ' : 'Copy',
                            compact: true,
                          ),
                          const SizedBox(width: 6),
                          _EditorToolBtn(
                            icon: CupertinoIcons.doc_on_clipboard_fill,
                            label: isAr ? 'لصق' : 'Paste',
                            color: TalkoraColors.iosTeal,
                            onTap: () async {
                              _pushUndo();
                              await NimoClipboardHelper.pasteIntoController(context, _codeCtrl, isAr: isAr);
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 6),
                          _EditorToolBtn(
                            icon: CupertinoIcons.text_alignleft,
                            label: isAr ? 'تنسيق' : 'Format',
                            color: TalkoraColors.iosBlue,
                            onTap: _autoFormatCode,
                          ),
                          const SizedBox(width: 6),
                          _EditorToolBtn(
                            icon: _showHighlightedView ? CupertinoIcons.pencil : CupertinoIcons.eye_fill,
                            label: _showHighlightedView ? (isAr ? 'تعديل' : 'Edit') : (isAr ? 'تلوين' : 'Syntax'),
                            color: TalkoraColors.iosIndigo,
                            onTap: () {
                              NimoSoundFx.click();
                              setState(() => _showHighlightedView = !_showHighlightedView);
                            },
                          ),
                          const SizedBox(width: 6),
                          _EditorToolBtn(
                            icon: CupertinoIcons.square_grid_2x2,
                            label: isAr ? 'قالب' : 'Template',
                            color: TalkoraColors.iosPurple,
                            onTap: () {
                              NimoSoundFx.click();
                              _pushUndo();
                              setState(() => _codeCtrl.text = _starterTemplates[_selectedLang] ?? '');
                            },
                          ),
                          if (_undoStack.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _EditorToolBtn(
                              icon: CupertinoIcons.arrow_uturn_left,
                              label: isAr ? 'تراجع' : 'Undo',
                              color: TalkoraColors.iosOrange,
                              onTap: _undo,
                            ),
                          ],
                          const SizedBox(width: 6),
                          _EditorToolBtn(
                            icon: CupertinoIcons.trash,
                            label: isAr ? 'مسح' : 'Clear',
                            color: TalkoraColors.iosRed,
                            onTap: () {
                              NimoSoundFx.click();
                              _pushUndo();
                              setState(() => _codeCtrl.clear());
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 260, maxHeight: 410),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              padding: const EdgeInsets.only(right: 8, left: 6, top: 2),
                              decoration: BoxDecoration(
                                border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (int i = 1; i <= lineCount; i++)
                                    Text(
                                      '$i',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: _fontSize - 1,
                                        height: 1.55,
                                        color: const Color(0xFF6E7681),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: _showHighlightedView
                                    ? SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SelectableText.rich(_highlightCode(_codeCtrl.text)),
                                      )
                                    : TextField(
                                        controller: _codeCtrl,
                                        maxLines: null,
                                        keyboardType: TextInputType.multiline,
                                        onChanged: (_) => setState(() {}),
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: _fontSize,
                                          height: 1.55,
                                          color: const Color(0xFFE6EDF3),
                                        ),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          filled: false,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          hintText: '// Write or paste your code here...',
                                          hintStyle: TextStyle(color: Color(0xFF6E7681)),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: const Color(0xFF161922),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$_selectedLang  •  $lineCount ${isAr ? 'سطر' : 'lines'}  •  ${_codeCtrl.text.length} ${isAr ? 'حرف' : 'chars'}',
                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF8B949E)),
                        ),
                        InkWell(
                          onTap: () => setState(() => _fontSize = _fontSize >= 17 ? 12.0 : _fontSize + 1.5),
                          child: Text(
                            '${_fontSize.toInt()}pt',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TalkoraColors.iosBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ================ PANE 1: LIVE INTERACTIVE PREVIEW ================
          if (_activePane == 1)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF101319),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.9),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: const Color(0xFF1A1E28),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.globe, size: 15, color: TalkoraColors.iosGreen),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isAr ? 'المعاينة الحية ($_selectedLang)' : 'Live Preview ($_selectedLang)',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: isAr ? 'حجم الجوال' : 'Mobile Width',
                          icon: Icon(
                            _mobileViewport ? CupertinoIcons.device_desktop : CupertinoIcons.device_phone_portrait,
                            size: 18,
                            color: TalkoraColors.iosTeal,
                          ),
                          onPressed: () => setState(() => _mobileViewport = !_mobileViewport),
                        ),
                        IconButton(
                          tooltip: isAr ? 'تحديث المعاينة' : 'Reload',
                          icon: const Icon(CupertinoIcons.refresh, size: 18, color: TalkoraColors.iosBlue),
                          onPressed: _openLivePreview,
                        ),
                        IconButton(
                          tooltip: isAr ? 'ملء الشاشة' : 'Fullscreen',
                          icon: const Icon(CupertinoIcons.fullscreen, size: 18, color: TalkoraColors.iosOrange),
                          onPressed: _openFullscreenPreview,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 390,
                    child: _isBuildingPreview
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CupertinoActivityIndicator(radius: 14, color: Colors.white),
                                const SizedBox(height: 12),
                                Text(
                                  isAr ? 'جاري تجهيز المعاينة الذكية لكود $_selectedLang...' : 'Building smart preview...',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : Center(
                            child: SizedBox(
                              width: _mobileViewport ? 340 : double.infinity,
                              height: 390,
                              child: WebViewWidget(controller: _webCtrl),
                            ),
                          ),
                  ),
                ],
              ),
            ),

          // ================ PANE 2: LIVE CONSOLE ================
          if (_activePane == 2)
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1015),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF1A1E28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isAr ? 'مخرجات الكونسول (Live Console)' : 'Live Console Output',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _consoleLogs.clear()),
                          child: Text(isAr ? 'مسح' : 'Clear', style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _consoleLogs.isEmpty
                        ? Center(
                            child: Text(
                              isAr ? 'اضغط "معاينة الكود" لرؤية مخرجات console.log والأخطاء هنا.' : 'Tap Preview to capture console output.',
                              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12.5),
                            ),
                          )
                        : Directionality(
                            textDirection: TextDirection.ltr,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(10),
                              itemCount: _consoleLogs.length,
                              itemBuilder: (_, i) {
                                final line = _consoleLogs[i];
                                final isErr = line.startsWith('[ERROR]');
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: SelectableText(
                                    line,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12,
                                      color: isErr ? const Color(0xFFFF7B72) : const Color(0xFF7EE787),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // AI Code Intelligence Actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _isWorking ? null : () => _runAiCodeAction('fix'),
                icon: const Icon(CupertinoIcons.wrench_fill, size: 16),
                label: Text(isAr ? 'تصحيح الأخطاء' : 'Fix Bugs'),
              ),
              FilledButton.tonalIcon(
                onPressed: _isWorking ? null : () => _runAiCodeAction('optimize'),
                icon: const Icon(CupertinoIcons.bolt_fill, size: 16),
                label: Text(isAr ? 'تحسين الأداء' : 'Optimize'),
              ),
              FilledButton.tonalIcon(
                onPressed: _isWorking ? null : () => _runAiCodeAction('explain'),
                icon: const Icon(CupertinoIcons.book_fill, size: 16),
                label: Text(isAr ? 'شرح بالعربي' : 'Explain'),
              ),
              FilledButton.tonalIcon(
                onPressed: _isWorking ? null : () => _runAiCodeAction('tests'),
                icon: const Icon(CupertinoIcons.checkmark_shield_fill, size: 16),
                label: Text(isAr ? 'كتابة اختبارات' : 'Unit Tests'),
              ),
            ],
          ),

          if (_aiOutput != null) ...[
            const SizedBox(height: 16),
            IosGroupedSection(
              header: isAr ? 'نتيجة مختبر Nimo الذكي' : 'NIMO AI CODE OUTPUT',
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(_aiOutput!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          NimoCopyChip(
                            textToCopy: _aiExtractedCode ?? _aiOutput!,
                            isAr: isAr,
                            label: _aiExtractedCode != null
                                ? (isAr ? 'نسخ الكود' : 'Copy Code')
                                : (isAr ? 'نسخ النتيجة' : 'Copy Result'),
                          ),
                          if (_aiExtractedCode != null) ...[
                            FilledButton.tonalIcon(
                              onPressed: () {
                                NimoSoundFx.pop();
                                _pushUndo();
                                setState(() {
                                  _codeCtrl.text = _aiExtractedCode!;
                                  _activePane = 0;
                                });
                              },
                              icon: const Icon(CupertinoIcons.arrow_up_doc_fill, size: 16),
                              label: Text(isAr ? 'تطبيق في المحرر' : 'Apply'),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: TalkoraColors.iosGreen),
                              onPressed: () {
                                _pushUndo();
                                setState(() => _codeCtrl.text = _aiExtractedCode!);
                                _openLivePreview();
                              },
                              icon: const Icon(CupertinoIcons.play_fill, size: 15),
                              label: Text(isAr ? 'تطبيق ومعاينة' : 'Apply & Preview'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EditorToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _EditorToolBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
