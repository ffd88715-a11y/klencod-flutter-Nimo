import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkora_ai/app/app.dart';
import 'package:talkora_ai/core/ai/ai_provider_models.dart';
import 'package:talkora_ai/core/widgets/talkora_waveform.dart';

void main() {
  testWidgets('Nimo v7.0 Apex boots splash screen cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TalkoraApp()));
    expect(find.text('N'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1200));
  });

  testWidgets('TalkoraWaveform renders real amplitude samples without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TalkoraWaveform(amplitudeHistory: [0.1, 0.4, 0.8, 0.3, 0.2]),
        ),
      ),
    );
    expect(find.byType(TalkoraWaveform), findsOneWidget);
  });

  test('AiKeySanitizer strips invisible RTL/LTR chars, Bearer prefix, quotes and whitespace', () {
    expect(AiKeySanitizer.clean('  Bearer "AIzaSyTest12345\u200F\n"  '), 'AIzaSyTest12345');
    expect(AiKeySanitizer.clean('API_KEY=gsk_abc123456789012345678\uFEFF'), 'gsk_abc123456789012345678');
    expect(AiProviderCatalog.detectProviderFromKey('AIzaSyTest12345\u200E'), 'gemini');
    expect(AiProviderCatalog.detectProviderFromKey('gsk_12345678901234567890'), 'groq');
  });

  test('AiProviderCatalog contains all 12 providers including Free Cloud AI & custom endpoint', () {
    expect(AiProviderCatalog.all.length, 12);
    expect(AiProviderCatalog.byId('pollinations').requiresApiKey, false);
    expect(AiProviderCatalog.byId('openai').name, 'OpenAI (GPT)');
    expect(AiProviderCatalog.byId('gemini').wireFormat, AiWireFormat.googleGemini);
    expect(AiProviderCatalog.byId('claude').wireFormat, AiWireFormat.anthropicClaude);
    expect(AiProviderCatalog.byId('custom').id, 'custom');
  });
}
