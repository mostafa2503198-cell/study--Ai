import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

const model = 'claude-sonnet-5-5';
const ar = 'اكتب بالعربية المصرية المبسطة. ';

void msg(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

Future<String> ask(String prompt) async {
  final sp = await SharedPreferences.getInstance();
  final key = sp.getString('key') ?? '';
  if (key.isEmpty) throw 'حط مفتاح API من الإعدادات (الترس فوق) الأول';
  final r = await http.post(
    Uri.parse('https://api.anthropic.com/v1/messages'),
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: jsonEncode({
      'model': model,
      'max_tokens': 4000,
      'messages': [
        {'role': 'user', 'content': '$ar$prompt'}
      ],
    }),
  );
  final j = jsonDecode(utf8.decode(r.bodyBytes));
  if (r.statusCode != 200) throw (j['error']?['message'] ?? 'خطأ ${r.statusCode}');
  return (j['content'] as List).map((c) => c['text'] ?? '').join();
}

Future<String?> pickPdfText() async {
  final res = await FilePicker.platform
      .pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
  if (res == null) return null;
  final f = res.files.single;
  final bytes = f.bytes ?? await File(f.path!).readAsBytes();
  final doc = PdfDocument(inputBytes: bytes);
  final t = PdfTextExtractor(doc).extractText();
  doc.dispose();
  return t.length > 40000 ? t.substring(0, 40000) : t;
}

Future<void> exportPdf(String title, String text) async {
  final esc = const HtmlEscape().convert(text.replaceAll(RegExp(r'[*#`]'), ''));
  final html = '<html dir="rtl" lang="ar"><body style="font-family:sans-serif;'
      'font-size:14pt;line-height:1.8"><h1>$title</h1>'
      '<div style="white-space:pre-wrap">$esc</div></body></html>';
  final bytes = await Printing.convertHtml(format: PdfPageFormat.a4, html: html);
  await Printing.sharePdf(bytes: bytes, filename: 'study.pdf');
}

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF14213D);
    return MaterialApp(
      title: 'مساعد المذاكرة',
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;

  Future<void> settings() async {
    final sp = await SharedPreferences.getInstance();
    final c = TextEditingController(text: sp.getString('key') ?? '');
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مفتاح Claude API'),
        content: TextField(
          controller: c,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'sk-ant-...'),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              await sp.setString('key', c.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      TextTab(
        key: const ValueKey('sum'),
        hint: 'الصق المادة هنا أو ارفع PDF',
        button: 'لخّص',
        title: 'ملخص المادة',
        prompt: (t, _) =>
            'لخّص المادة دي في نقاط قصيرة واضحة، وفي الآخر اكتب أهم 3 حاجات تتحفظ:\n\n$t',
      ),
      const QuizTab(),
      TextTab(
        key: const ValueKey('exp'),
        hint: 'اكتب اللي مش فاهمه أو ارفع PDF يتشرح',
        button: 'اشرحلي',
        title: 'شرح الدرس',
        levels: const [
          'شرح مبسط جدا بمثال من الحياة',
          'شرح متوسط',
          'شرح متعمق للامتحان'
        ],
        prompt: (t, lv) =>
            'اشرح ده بالتفصيل وبالترتيب. المستوى: $lv. ابدأ بالفكرة في جملة واحدة:\n\n$t',
      ),
      const PlanTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('مساعد المذاكرة'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: settings)],
      ),
      body: SafeArea(child: IndexedStack(index: i, children: tabs)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notes), label: 'لخّص'),
          NavigationDestination(icon: Icon(Icons.quiz), label: 'اختبرني'),
          NavigationDestination(icon: Icon(Icons.lightbulb), label: 'اشرح'),
          NavigationDestination(icon: Icon(Icons.timer), label: 'جدول'),
        ],
      ),
    );
  }
}

class TextTab extends StatefulWidget {
  final String hint, button, title;
  final List<String>? levels;
  final String Function(String text, String level) prompt;
  const TextTab(
      {super.key,
      required this.hint,
      required this.button,
      required this.title,
      required this.prompt,
      this.levels});
  @override
  State<TextTab> createState() => _TextTabState();
}

class _TextTabState extends State<TextTab> {
  final c = TextEditingController();
  String out = '', level = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    level = widget.levels?.first ?? '';
  }

  Future<void> pdf() async {
    try {
      final t = await pickPdfText();
      if (t == null) return;
      if (t.trim().length < 30) {
        if (mounted) msg(context, 'مقدرتش أقرأ نص من الملف (ممكن يكون صور)');
        return;
      }
      setState(() => c.text = t);
    } catch (e) {
      if (mounted) msg(context, 'الملف مش بيفتح: $e');
    }
  }

  Future<void> go() async {
    if (c.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      out = '';
    });
    String r;
    try {
      r = await ask(widget.prompt(c.text, level));
    } catch (e) {
      r = '$e';
    }
    if (mounted) setState(() {
      out = r;
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: c,
        maxLines: 6,
        decoration:
            InputDecoration(hintText: widget.hint, border: const OutlineInputBorder()),
      ),
      if (widget.levels != null) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: level,
          items: widget.levels!
              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
              .toList(),
          onChanged: (v) => setState(() => level = v ?? level),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed: pdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('ارفع PDF'))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton(
                onPressed: busy ? null : go, child: Text(widget.button))),
      ]),
      const SizedBox(height: 16),
      if (busy) const Center(child: CircularProgressIndicator()),
      if (out.isNotEmpty) SelectableText(out, style: const TextStyle(height: 1.7)),
      if (out.isNotEmpty && !busy) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await exportPdf(widget.title, out);
            } catch (e) {
              if (mounted) msg(context, 'مقدرتش أعمل الـ PDF: $e');
            }
          },
          icon: const Icon(Icons.download),
          label: const Text('حمّل PDF'),
        ),
      ],
    ]);
  }
}

class Q {
  final String q, why;
  final List<String> o;
  final int a;
  Q(this.q, this.o, this.a, this.why);
}

class QuizTab extends StatefulWidget {
  const QuizTab({super.key});
  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> {
  final c = TextEditingController();
  List<Q> qs = [];
  final picked = <int, int>{};
  bool busy = false;
  String err = '';

  Future<void> go() async {
    if (c.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      err = '';
      qs = [];
      picked.clear();
    });
    try {
      final raw = await ask('اعمل 5 أسئلة اختيار من متعدد عن: ${c.text}\n'
          'رجّع JSON فقط، مصفوفة عناصرها '
          '{"q":"السؤال","o":["أ","ب","ج","د"],"a":رقم الإجابة الصحيحة من 0 لـ 3,"why":"تفسير قصير"}');
      final list = jsonDecode(raw.replaceAll(RegExp(r'```json|```'), '').trim()) as List;
      qs = list
          .map((e) => Q(e['q'], List<String>.from(e['o']), e['a'], e['why']))
          .toList();
    } catch (e) {
      err = 'حصلت مشكلة، جرّب تاني. ($e)';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final score = picked.entries.where((e) => qs[e.key].a == e.value).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: c,
        maxLines: 3,
        decoration: const InputDecoration(
            hintText: 'اكتب الموضوع أو الصق جزء من الدرس',
            border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      FilledButton(
          onPressed: busy ? null : go, child: const Text('اختبرني (5 أسئلة)')),
      if (busy) const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator())),
      if (err.isNotEmpty) Text(err),
      for (var n = 0; n < qs.length; n++)
        Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(qs[n].q, style: const TextStyle(fontWeight: FontWeight.bold)),
              for (var k = 0; k < qs[n].o.length; k++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      alignment: AlignmentDirectional.centerStart,
                      backgroundColor: !picked.containsKey(n)
                          ? null
                          : k == qs[n].a
                              ? Colors.green.withOpacity(.25)
                              : picked[n] == k
                                  ? Colors.red.withOpacity(.25)
                                  : null,
                    ),
                    onPressed:
                        picked.containsKey(n) ? null : () => setState(() => picked[n] = k),
                    child: Text(qs[n].o[k]),
                  ),
                ),
              if (picked.containsKey(n))
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(qs[n].why)),
            ]),
          ),
        ),
      if (qs.isNotEmpty && picked.length == qs.length)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
                child: Text('نتيجتك: $score من ${qs.length}',
                    style: Theme.of(context).textTheme.titleLarge))),
    ]);
  }
}

class PlanTab extends StatefulWidget {
  const PlanTab({super.key});
  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  Timer? t;
  DateTime? end;
  int left = 25 * 60;
  final subj = TextEditingController();
  final days = TextEditingController(text: '7');
  final hours = TextEditingController(text: '3');
  String out = '';
  bool busy = false;

  void run(int min) {
    t?.cancel();
    end = DateTime.now().add(Duration(minutes: min));
    setState(() => left = min * 60);
    t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final ms = end!.difference(DateTime.now()).inMilliseconds;
      setState(() => left = max(0, (ms / 1000).ceil()));
      if (ms <= 0) {
        t?.cancel();
        HapticFeedback.vibrate();
      }
    });
  }

  void stop() {
    t?.cancel();
    setState(() => left = 25 * 60);
  }

  Future<void> plan() async {
    if (subj.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      out = '';
    });
    String r;
    try {
      r = await ask('اعمل جدول مذاكرة يوم بيوم للمواد: ${subj.text}. '
          'الأيام الباقية: ${days.text}، وعنده ${hours.text} ساعات يوميا. '
          'وزّع حسب الصعوبة وخلّي يوم آخر للمراجعة.');
    } catch (e) {
      r = '$e';
    }
    if (mounted) setState(() {
      out = r;
      busy = false;
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('$mm:$ss',
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900)))),
      Row(children: [
        Expanded(child: FilledButton(onPressed: () => run(25), child: const Text('تركيز 25'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(onPressed: () => run(5), child: const Text('راحة 5'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(onPressed: stop, child: const Text('إيقاف'))),
      ]),
      const SizedBox(height: 20),
      TextField(
        controller: subj,
        decoration: const InputDecoration(
            labelText: 'المواد اللي عليك', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'أيام باقية', border: OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(
            child: TextField(
                controller: hours,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ساعات في اليوم', border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      FilledButton(onPressed: busy ? null : plan, child: const Text('اعمللي جدول')),
      if (busy) const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator())),
      if (out.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SelectableText(out, style: const TextStyle(height: 1.7))),
    ]);
  }
}
