import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swiftspeak/ai_chat_service.dart';
import 'package:swiftspeak/app_language.dart';
import 'package:swiftspeak/typing_prediction.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// In-app keyboard. Edit the rows below to change keys for every text field.
enum AppKeyboardPage { letters, numbers, symbols }

class AppKeyboardController extends ChangeNotifier {
  AppKeyboardController._();
  static final AppKeyboardController instance = AppKeyboardController._();

  static const panelHeight = 268.0;
  static const tidyBarHeight = 52.0;
  static const predictBarHeight = 48.0;

  static double insetFor(BuildContext context) {
    var height = panelHeight + MediaQuery.of(context).padding.bottom;
    if (instance.showTidyBar) height += tidyBarHeight;
    if (instance.showPredictBar) height += predictBarHeight;
    return height;
  }

  TextEditingController? _controller;
  VoidCallback? _onChanged;
  ValueChanged<String>? _onSubmitted;
  bool visible = false;
  bool caps = false;
  bool obscureText = false;
  bool allowTidyUp = false;
  bool enablePredictions = false;
  String predictionSurface = '';
  bool tidying = false;
  bool predictingSuggestions = false;
  List<String> suggestions = const [];
  String? _undoText;
  Timer? _suggestTimer;
  int _suggestToken = 0;
  AppKeyboardPage page = AppKeyboardPage.letters;

  bool get isAttached => _controller != null;

  bool isAttachedTo(TextEditingController controller) =>
      _controller == controller;

  bool get showTidyBar => visible && !obscureText && allowTidyUp;

  bool get showPredictBar => showTidyBar && enablePredictions;

  bool get canTidy =>
      showTidyBar && (_controller?.text.trim().isNotEmpty ?? false);

  bool get canUndoTidy => showTidyBar && _undoText != null;

  bool _tappedField = false;

  void markFieldTap() => _tappedField = true;

  void hideIfTappedOutside() {
    if (_tappedField) {
      _tappedField = false;
      return;
    }
    if (visible) hide();
  }

  void _onTextTick() {
    notifyListeners();
    if (!enablePredictions) return;
    TypingPredictionStore.instance.learnFromTyping(
      _controller?.text ?? '',
      surface: predictionSurface,
    );
    _scheduleSuggest();
  }

  void attach(
    TextEditingController controller, {
    VoidCallback? onChanged,
    ValueChanged<String>? onSubmitted,
    bool obscureText = false,
    bool allowTidyUp = true,
    bool enablePredictions = false,
    String predictionSurface = '',
  }) {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
    _controller?.removeListener(_onTextTick);
    _controller = controller;
    _controller?.addListener(_onTextTick);
    _onChanged = onChanged;
    _onSubmitted = onSubmitted;
    this.obscureText = obscureText;
    this.allowTidyUp = allowTidyUp;
    this.enablePredictions = enablePredictions && !obscureText;
    this.predictionSurface = predictionSurface;
    _undoText = null;
    visible = true;
    notifyListeners();
    if (this.enablePredictions) {
      unawaited(TypingPredictionStore.instance.start());
      _scheduleSuggest();
    } else {
      suggestions = const [];
    }
  }

  void hide({bool submitted = false}) {
    final text = _controller?.text ?? '';
    final submit = _onSubmitted;
    final shouldLearn = enablePredictions && !obscureText;
    final surface = predictionSurface;
    _suggestTimer?.cancel();
    if (!visible && _controller == null) return;
    _controller?.removeListener(_onTextTick);
    _controller = null;
    _onChanged = null;
    _onSubmitted = null;
    visible = false;
    obscureText = false;
    allowTidyUp = false;
    enablePredictions = false;
    predictionSurface = '';
    tidying = false;
    predictingSuggestions = false;
    suggestions = const [];
    _undoText = null;
    caps = false;
    page = AppKeyboardPage.letters;
    notifyListeners();
    if (shouldLearn) {
      TypingPredictionStore.instance.learnFromCommitted(text, surface: surface);
    }
    if (submitted) submit?.call(text);
  }

  void detach(TextEditingController controller) {
    if (_controller != controller) return;
    hide();
  }

  void insert(String value) {
    final controller = _controller;
    if (controller == null || value.isEmpty) return;
    final text = controller.text;
    var start = controller.selection.start;
    var end = controller.selection.end;
    if (!controller.selection.isValid) {
      start = text.length;
      end = text.length;
    }
    start = start.clamp(0, text.length);
    end = end.clamp(0, text.length);
    if (start > end) {
      final swap = start;
      start = end;
      end = swap;
    }
    final next = text.replaceRange(start, end, value);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _onChanged?.call();
    _undoText = null;
    notifyListeners();
  }

  void acceptSuggestion(String phrase) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return;
    final prefix = _suggestionPrefix(_controller?.text ?? '');
    TypingPredictionStore.instance.learnAccepted(prefix, trimmed);
    _insertSuggestion(trimmed);
  }

  String _suggestionPrefix(String text) {
    final words = text
        .trimRight()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (text.endsWith(' ') || text.isEmpty) {
      if (words.length >= 2) return '${words[words.length - 2]} ${words.last}';
      return words.isEmpty ? '' : words.last;
    }
    if (words.length >= 2) return words[words.length - 2];
    return '';
  }

  void _insertSuggestion(String phrase) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    var start = controller.selection.start;
    var end = controller.selection.end;
    if (!controller.selection.isValid) {
      start = text.length;
      end = text.length;
    }
    start = start.clamp(0, text.length);
    end = end.clamp(0, text.length);
    if (start > end) {
      final swap = start;
      start = end;
      end = swap;
    }
    final before = text.substring(0, start);
    final after = text.substring(end);
    String next;
    var cursor = 0;
    if (before.isEmpty || before.endsWith(' ')) {
      next = '$before$phrase $after';
      cursor = before.length + phrase.length + 1;
    } else {
      final last = before.split(RegExp(r'\s+')).last;
      if (phrase.toLowerCase().startsWith(last.toLowerCase()) &&
          last.isNotEmpty) {
        final stem = before.substring(0, before.length - last.length);
        next = '$stem$phrase $after';
        cursor = stem.length + phrase.length + 1;
      } else {
        next = '$before $phrase $after';
        cursor = before.length + 1 + phrase.length + 1;
      }
    }
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _onChanged?.call();
    _undoText = null;
    notifyListeners();
  }

  void _scheduleSuggest() {
    _suggestTimer?.cancel();
    if (!enablePredictions || _controller == null) return;
    _suggestTimer = Timer(const Duration(milliseconds: 280), _runSuggest);
  }

  void refreshPredictions() {
    if (enablePredictions && visible) _scheduleSuggest();
  }

  Future<void> _runSuggest() async {
    final controller = _controller;
    if (!enablePredictions || controller == null) return;
    final text = controller.text;
    final local = TypingPredictionStore.instance.localSuggestions(
      text,
      surface: predictionSurface,
    );
    if (!_sameSuggestions(local, suggestions)) {
      suggestions = local;
      notifyListeners();
    }

    final token = ++_suggestToken;
    predictingSuggestions = true;
    notifyListeners();
    try {
      final guessed = await AiChatService().predictTypingSuggestions(
        currentText: text,
        surface: predictionSurface,
        learnedHints: TypingPredictionStore.instance.learnedHints(),
        conversationHint: TypingPredictionStore.instance.conversationHint,
        personProfile: TypingPredictionStore.instance.surveyPrompt,
      );
      if (token != _suggestToken || _controller != controller) return;
      final merged = <String>[];
      for (final phrase in [...guessed, ...local]) {
        if (merged.any((item) => item.toLowerCase() == phrase.toLowerCase())) {
          continue;
        }
        merged.add(phrase);
        if (merged.length >= 6) break;
      }
      if (!_sameSuggestions(merged, suggestions)) {
        suggestions = merged;
      }
    } catch (_) {
      // Keep local suggestions if the AI call fails.
    } finally {
      if (token == _suggestToken) {
        predictingSuggestions = false;
        notifyListeners();
      }
    }
  }

  bool _sameSuggestions(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void backspace() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    var start = controller.selection.start;
    var end = controller.selection.end;
    if (!controller.selection.isValid) {
      start = text.length;
      end = text.length;
    }
    start = start.clamp(0, text.length);
    end = end.clamp(0, text.length);
    if (start > end) {
      final swap = start;
      start = end;
      end = swap;
    }
    if (start != end) {
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      controller.value = TextEditingValue(
        text: text.replaceRange(start - 1, start, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      return;
    }
    _onChanged?.call();
    _undoText = null;
    notifyListeners();
  }

  Future<void> tidyUp() async {
    final controller = _controller;
    if (controller == null || obscureText || tidying) return;
    final original = controller.text;
    if (original.trim().isEmpty) return;
    tidying = true;
    notifyListeners();
    try {
      final cleaned = await AiChatService().tidyText(original);
      if (_controller != controller) return;
      if (cleaned != original) {
        _undoText = original;
      }
      controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
      if (enablePredictions) {
        TypingPredictionStore.instance.learnFromCommitted(
          cleaned,
          surface: predictionSurface,
        );
      }
      _onChanged?.call();
    } catch (_) {
      // Keep the original sentence if tidy-up cannot run.
    } finally {
      tidying = false;
      notifyListeners();
    }
  }

  Future<void> rewriteWithAi() async {
    final target = _controller;
    if (target == null || obscureText || tidying) return;
    final original = target.text;
    if (original.trim().isEmpty) return;
    final keepPredict = enablePredictions;
    final keepSurface = predictionSurface;
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;

    final instruction = await showDialog<String>(
      context: navContext,
      builder: (context) => const _AiRewriteDialog(),
    );
    if (instruction == null || instruction.trim().isEmpty) return;

    tidying = true;
    notifyListeners();
    try {
      final rewritten = await AiChatService().rewriteText(
        text: original,
        instruction: instruction,
      );
      target.value = TextEditingValue(
        text: rewritten,
        selection: TextSelection.collapsed(offset: rewritten.length),
      );
      attach(
        target,
        allowTidyUp: true,
        enablePredictions: keepPredict,
        predictionSurface: keepSurface,
      );
      if (rewritten != original) {
        _undoText = original;
      }
      if (keepPredict) {
        TypingPredictionStore.instance.learnFromCommitted(
          rewritten,
          surface: keepSurface,
        );
      }
      _onChanged?.call();
    } catch (_) {
      attach(
        target,
        allowTidyUp: true,
        enablePredictions: keepPredict,
        predictionSurface: keepSurface,
      );
    } finally {
      tidying = false;
      notifyListeners();
    }
  }

  void undoTidy() {
    final controller = _controller;
    final previous = _undoText;
    if (controller == null || previous == null) return;
    _undoText = null;
    controller.value = TextEditingValue(
      text: previous,
      selection: TextSelection.collapsed(offset: previous.length),
    );
    _onChanged?.call();
    notifyListeners();
  }
}

class AppKeyboardScope extends StatelessWidget {
  const AppKeyboardScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppKeyboardController.instance,
      builder: (context, _) {
        final keyboard = AppKeyboardController.instance;
        final shown = keyboard.visible;
        final bottom = shown ? AppKeyboardController.insetFor(context) : 0.0;
        return ColoredBox(
          color: const Color(0xFFF3F7FC),
          child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                Future.microtask(keyboard.hideIfTappedOutside);
              },
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  viewInsets: EdgeInsets.only(bottom: bottom),
                ),
                child: child,
              ),
            ),
            if (shown)
              AppKeyboardPanel(
                showTidyBar: keyboard.showTidyBar,
                canTidy: keyboard.canTidy,
                canUndo: keyboard.canUndoTidy,
                tidying: keyboard.tidying,
              ),
          ],
          ),
        );
      },
    );
  }
}

class AppKeyboardField extends StatefulWidget {
  const AppKeyboardField({
    super.key,
    this.controller,
    this.decoration,
    this.style,
    this.cursorColor,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.enableTidyUp = true,
    this.hideTidyUp = false,
    this.enablePredictions = false,
    this.predictionSurface = '',
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final Color? cursorColor;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enableTidyUp;
  final bool hideTidyUp;
  final bool enablePredictions;
  final String predictionSurface;

  @override
  State<AppKeyboardField> createState() => _AppKeyboardFieldState();
}

class _AppKeyboardFieldState extends State<AppKeyboardField> {
  late TextEditingController _controller;
  var _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    if (widget.autofocus && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _attach();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppKeyboardField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      AppKeyboardController.instance.detach(_controller);
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? TextEditingController();
    }
  }

  @override
  void dispose() {
    AppKeyboardController.instance.detach(_controller);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _attach() {
    if (!widget.enabled) return;
    AppKeyboardController.instance.attach(
      _controller,
      onChanged: widget.onChanged == null
          ? null
          : () => widget.onChanged!(_controller.text),
      onSubmitted: widget.onSubmitted,
      obscureText: widget.obscureText,
      allowTidyUp: !widget.obscureText && !widget.hideTidyUp,
      enablePredictions: widget.enablePredictions &&
          !widget.obscureText &&
          !widget.hideTidyUp,
      predictionSurface: widget.predictionSurface,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Listener(
          onPointerDown: (_) => AppKeyboardController.instance.markFieldTap(),
          child: TextField(
            controller: _controller,
            readOnly: true,
            showCursor: true,
            enableInteractiveSelection: true,
            obscureText: widget.obscureText,
            enabled: widget.enabled,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            style: widget.style,
            cursorColor: widget.cursorColor,
            textCapitalization: widget.textCapitalization,
            keyboardType: TextInputType.none,
            decoration: widget.decoration,
            onTap: _attach,
            onChanged: widget.onChanged,
          ),
        );
      },
    );
  }
}

class AppKeyboardPanel extends StatefulWidget {
  const AppKeyboardPanel({
    super.key,
    required this.showTidyBar,
    required this.canTidy,
    required this.canUndo,
    required this.tidying,
  });

  final bool showTidyBar;
  final bool canTidy;
  final bool canUndo;
  final bool tidying;

  @override
  State<AppKeyboardPanel> createState() => _AppKeyboardPanelState();
}

class _AppKeyboardPanelState extends State<AppKeyboardPanel> {
  static const _letterRowsEn = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  static const _letterRowsEs = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Ñ'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  static const _letterRowsPt = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Ç'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  static const _letterRowsTr = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'Ğ', 'Ü'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Ş', 'İ'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', 'Ö', 'Ç'],
  ];

  static const _letterRowsRu = <List<String>>[
    ['Й', 'Ц', 'У', 'К', 'Е', 'Н', 'Г', 'Ш', 'Щ', 'З', 'Х'],
    ['Ф', 'Ы', 'В', 'А', 'П', 'Р', 'О', 'Л', 'Д', 'Ж', 'Э'],
    ['Я', 'Ч', 'С', 'М', 'И', 'Т', 'Ь', 'Б', 'Ю'],
  ];

  static const _letterRowsHi = <List<String>>[
    ['क', 'ख', 'ग', 'घ', 'च', 'छ', 'ज', 'झ', 'ट'],
    ['ठ', 'ड', 'ढ', 'त', 'थ', 'द', 'ध', 'न', 'प'],
    ['फ', 'ब', 'भ', 'म', 'य', 'र', 'ल', 'व', 'स'],
  ];

  static const _letterRowsBn = <List<String>>[
    ['ক', 'খ', 'গ', 'ঘ', 'চ', 'ছ', 'জ', 'ঝ', 'ট'],
    ['ঠ', 'ড', 'ঢ', 'ত', 'থ', 'দ', 'ধ', 'ন', 'প'],
    ['ফ', 'ব', 'ভ', 'ম', 'য', 'র', 'ল', 'শ', 'স'],
  ];

  static const _numberRowsEn = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['!', '@', '#', r'$', '%', '^', '&', '*'],
    ['(', ')', '.', ',', '?', '!'],
  ];

  static const _numberRowsEs = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['!', '@', '#', r'$', '%', '^', '&', '*'],
    ['(', ')', '.', ',', '¿', '¡'],
  ];

  static const _symbolRowsEs = <List<String>>[
    ['á', 'é', 'í', 'ó', 'ú', 'ü', 'ñ', 'Ñ'],
    ['\\', '|', '`', '~', ':', ';', '"', "'"],
    [',', '.', '<', '>', '/', '?'],
  ];

  static const _symbolRowsPt = <List<String>>[
    ['á', 'à', 'â', 'ã', 'é', 'ê', 'í', 'ó'],
    ['ô', 'õ', 'ú', 'ç', 'Á', 'É', 'Ó', 'Ç'],
    [',', '.', '<', '>', '/', '?'],
  ];

  static const _symbolRowsZh = <List<String>>[
    ['。', '，', '、', '？', '！', '：', '；', '“'],
    ['\\', '|', '`', '~', ':', ';', '"', "'"],
    [',', '.', '<', '>', '/', '?'],
  ];

  static const _symbolRowsJa = <List<String>>[
    ['ー', '、', '。', '「', '」', '？', '！', '〜'],
    ['あ', 'い', 'う', 'え', 'お', 'ん', 'っ', 'ー'],
    [',', '.', '<', '>', '/', '?'],
  ];

  static const _symbolRowsHi = <List<String>>[
    ['अ', 'आ', 'इ', 'ई', 'उ', 'ऊ', 'ए', 'ओ'],
    ['ा', 'ि', 'ी', 'ु', 'ू', 'े', 'ो', '्'],
    ['ं', 'ः', 'ह', 'श', 'ष', 'ज्ञ', 'क्ष', 'त्र'],
  ];

  static const _symbolRowsBn = <List<String>>[
    ['অ', 'আ', 'ই', 'ঈ', 'উ', 'ঊ', 'এ', 'ও'],
    ['া', 'ি', 'ী', 'ু', 'ূ', 'ে', 'ো', '্'],
    ['ং', 'ঃ', 'হ', 'ষ', 'ঞ', 'য়', 'ড়', 'ঢ়'],
  ];

  static const _symbolRows = <List<String>>[
    ['-', '_', '=', '+', '[', ']', '{', '}'],
    ['\\', '|', '`', '~', ':', ';', '"', "'"],
    [',', '.', '<', '>', '/', '?'],
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
    final keyboard = AppKeyboardController.instance;
    final t = AppLanguage.instance.t;
    final lang = AppLanguage.instance.lang;
    final rows = switch (keyboard.page) {
      AppKeyboardPage.letters => switch (lang) {
          AppLang.spanish => _letterRowsEs,
          AppLang.portuguese => _letterRowsPt,
          AppLang.turkish => _letterRowsTr,
          AppLang.russian => _letterRowsRu,
          AppLang.hindi => _letterRowsHi,
          AppLang.bengali => _letterRowsBn,
          _ => _letterRowsEn,
        },
      AppKeyboardPage.numbers =>
        lang == AppLang.spanish ? _numberRowsEs : _numberRowsEn,
      AppKeyboardPage.symbols => switch (lang) {
          AppLang.spanish => _symbolRowsEs,
          AppLang.portuguese => _symbolRowsPt,
          AppLang.chinese => _symbolRowsZh,
          AppLang.japanese => _symbolRowsJa,
          AppLang.hindi => _symbolRowsHi,
          AppLang.bengali => _symbolRowsBn,
          _ => _symbolRows,
        },
    };
    final isLetters = keyboard.page == AppKeyboardPage.letters;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final showTidy = widget.showTidyBar;
    final showPredict = keyboard.showPredictBar;
    return Material(
      elevation: 16,
      color: const Color(0xFFE8EAED),
      child: SizedBox(
        height: AppKeyboardController.panelHeight +
            bottomInset +
            (showTidy ? AppKeyboardController.tidyBarHeight : 0) +
            (showPredict ? AppKeyboardController.predictBarHeight : 0),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 8, 6, 6 + bottomInset),
          child: Column(
              children: [
                if (showPredict) ...[
                  SizedBox(
                    height: AppKeyboardController.predictBarHeight - 8,
                    child: keyboard.suggestions.isEmpty
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                keyboard.predictingSuggestions
                                    ? t('predicting')
                                    : t('suggestionsAsYouType'),
                                style: TextStyle(
                                  color: Colors.blueGrey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            itemCount: keyboard.suggestions.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final phrase = keyboard.suggestions[index];
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  onTap: () =>
                                      keyboard.acceptSuggestion(phrase),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                    child: Text(
                                      phrase,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (showTidy) ...[
                  SizedBox(
                    height: AppKeyboardController.tidyBarHeight - 8,
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.canTidy && !widget.tidying
                                ? keyboard.tidyUp
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  Colors.blueGrey.shade200,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: widget.tidying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      t('tidyUp'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                widget.canUndo ? keyboard.undoTidy : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blueAccent,
                              side: const BorderSide(color: Colors.blueAccent),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t('undo'),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Material(
                          color: widget.canTidy && !widget.tidying
                              ? Colors.blueAccent
                              : Colors.blueGrey.shade200,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            onTap: widget.canTidy && !widget.tidying
                                ? keyboard.rewriteWithAi
                                : null,
                            borderRadius: BorderRadius.circular(20),
                            child: const SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0) const SizedBox(height: 6),
                  Expanded(
                    child: Row(
                      children: [
                        if (r == rows.length - 1 && isLetters) ...[
                          _Key(
                            label: t('caps'),
                            flex: 14,
                            highlighted: keyboard.caps,
                            onTap: () => setState(
                              () => keyboard.caps = !keyboard.caps,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        for (var i = 0; i < rows[r].length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          _Key(
                            label: !isLetters || keyboard.caps
                                ? rows[r][i]
                                : rows[r][i].toLowerCase(),
                            onTap: () {
                              final value = !isLetters || keyboard.caps
                                  ? rows[r][i]
                                  : rows[r][i].toLowerCase();
                              keyboard.insert(value);
                            },
                          ),
                        ],
                        if (r == rows.length - 1) ...[
                          const SizedBox(width: 4),
                          _Key(
                            label: '⌫',
                            flex: 14,
                            tint: const Color(0xFFFFEBEE),
                            onTap: keyboard.backspace,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: [
                      _Key(
                        label: isLetters ? '123' : 'ABC',
                        flex: 14,
                        onTap: () => setState(() {
                          keyboard.page = isLetters
                              ? AppKeyboardPage.numbers
                              : AppKeyboardPage.letters;
                        }),
                      ),
                      if (keyboard.page == AppKeyboardPage.numbers) ...[
                        const SizedBox(width: 4),
                        _Key(
                          label: '#+=',
                          flex: 14,
                          onTap: () => setState(() {
                            keyboard.page = AppKeyboardPage.symbols;
                          }),
                        ),
                      ],
                      if (keyboard.page == AppKeyboardPage.symbols) ...[
                        const SizedBox(width: 4),
                        _Key(
                          label: '123',
                          flex: 14,
                          onTap: () => setState(() {
                            keyboard.page = AppKeyboardPage.numbers;
                          }),
                        ),
                      ],
                      const SizedBox(width: 4),
                      _Key(
                        label: t('space'),
                        flex: 32,
                        onTap: () => keyboard.insert(' '),
                      ),
                      const SizedBox(width: 4),
                      _Key(
                        label: t('done'),
                        flex: 16,
                        tint: const Color(0xFFBBDEFB),
                        onTap: () => keyboard.hide(submitted: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.flex = 10,
    this.highlighted = false,
    this.tint,
  });

  final String label;
  final VoidCallback onTap;
  final int flex;
  final bool highlighted;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Material(
        color: highlighted ? const Color(0xFFBBDEFB) : (tint ?? Colors.white),
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiRewriteDialog extends StatefulWidget {
  const _AiRewriteDialog();

  @override
  State<_AiRewriteDialog> createState() => _AiRewriteDialogState();
}

class _AiRewriteDialogState extends State<_AiRewriteDialog> {
  final TextEditingController _instruction = TextEditingController();

  static const _suggestions = [
    'Make this friendlier',
    'Make this shorter',
    'Make this clearer',
    'Make this more polite',
  ];

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _instruction.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ask AI'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tell AI how to change the message.'),
            const SizedBox(height: 12),
            AppKeyboardField(
              controller: _instruction,
              hideTidyUp: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. make this message friendlier',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in _suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () {
                      _instruction.text = suggestion;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
