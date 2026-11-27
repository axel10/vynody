// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// 检查 Dart 源码中可能遗漏 l10n 的硬编码 UI 文案。
///
/// 用法:
///   dart run scripts/check_hardcoded_l10n.dart [options]
///
/// 选项:
///   --dir `<path>`       扫描目录 (默认: lib)
///   --zh-only            仅报告包含中文字符的硬编码文案
///   --ui-only            仅检查常见 UI 组件/参数中的字符串字面量
///   --ignore-fallbacks   忽略 `l10n?.xxx ?? '兜底文案'` 右侧的兜底字符串
///   --limit `<n>`        最多显示条数 (默认: 200, 0 表示不限制)
///   --json               以 JSON 格式输出
///   --ci                 若发现问题则以退出码 1 结束
void main(List<String> args) {
  final options = _CliOptions.parse(args);
  final rootDir = Directory(options.dir);
  if (!rootDir.existsSync()) {
    stderr.writeln('Error: Directory not found: ${options.dir}');
    exit(2);
  }

  final dartFiles = rootDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => _shouldScanFile(file.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final findings = <_Finding>[];

  for (final file in dartFiles) {
    final content = file.readAsStringSync();
    final result = parseString(
      content: content,
      path: file.path,
      throwIfDiagnostics: false,
    );
    final visitor = _HardcodedStringVisitor(
      filePath: file.path,
      lineInfo: result.lineInfo,
      options: options,
    );
    result.unit.accept(visitor);
    findings.addAll(visitor.findings);
  }

  if (options.asJson) {
    print(
      const JsonEncoder.withIndent('  ').convert({
        'dir': options.dir,
        'scanned_files': dartFiles.length,
        'total_findings': findings.length,
        'findings': findings.map((f) => f.toJson()).toList(),
      }),
    );
    if (options.ci && findings.isNotEmpty) {
      exit(1);
    }
    return;
  }

  print('=' * 72);
  print('Hardcoded l10n Check (${options.dir})');
  print('Scanned ${dartFiles.length} Dart files, found ${findings.length} potential issues.');
  print('=' * 72);

  final displayCount = options.limit > 0 && findings.length > options.limit
      ? options.limit
      : findings.length;

  for (var i = 0; i < displayCount; i++) {
    final f = findings[i];
    print('${f.filePath}:${f.line}:${f.column} [${f.kind}] ${f.preview}');
  }

  if (displayCount < findings.length) {
    print('\n... 仅展示前 $displayCount 条（共 ${findings.length} 条），可使用 --limit 0 查看全部。');
  }

  if (options.ci && findings.isNotEmpty) {
    exit(1);
  }
}

bool _shouldScanFile(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (!normalized.endsWith('.dart')) return false;
  if (normalized.endsWith('.g.dart') || normalized.endsWith('.freezed.dart')) {
    return false;
  }
  if (normalized.contains('/l10n/') || normalized.startsWith('lib/l10n/')) {
    return false;
  }
  return true;
}

class _CliOptions {
  _CliOptions({
    required this.dir,
    required this.zhOnly,
    required this.uiOnly,
    required this.ignoreFallbacks,
    required this.limit,
    required this.asJson,
    required this.ci,
  });

  final String dir;
  final bool zhOnly;
  final bool uiOnly;
  final bool ignoreFallbacks;
  final int limit;
  final bool asJson;
  final bool ci;

  static _CliOptions parse(List<String> args) {
    var dir = 'lib';
    var zhOnly = false;
    var uiOnly = false;
    var ignoreFallbacks = false;
    var limit = 200;
    var asJson = false;
    var ci = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--dir':
        case '-d':
          if (i + 1 < args.length) dir = args[++i];
        case '--zh-only':
          zhOnly = true;
        case '--ui-only':
          uiOnly = true;
        case '--ignore-fallbacks':
          ignoreFallbacks = true;
        case '--limit':
          if (i + 1 < args.length) {
            limit = int.tryParse(args[++i]) ?? limit;
          }
        case '--json':
          asJson = true;
        case '--ci':
          ci = true;
      }
    }

    return _CliOptions(
      dir: dir,
      zhOnly: zhOnly,
      uiOnly: uiOnly,
      ignoreFallbacks: ignoreFallbacks,
      limit: limit,
      asJson: asJson,
      ci: ci,
    );
  }
}

class _Finding {
  _Finding({
    required this.filePath,
    required this.line,
    required this.column,
    required this.kind,
    required this.preview,
  });

  final String filePath;
  final int line;
  final int column;
  final String kind;
  final String preview;

  Map<String, dynamic> toJson() => {
        'file': filePath,
        'line': line,
        'column': column,
        'kind': kind,
        'preview': preview,
      };
}

class _HardcodedStringVisitor extends RecursiveAstVisitor<void> {
  _HardcodedStringVisitor({
    required this.filePath,
    required this.lineInfo,
    required this.options,
  });

  final String filePath;
  final LineInfo lineInfo;
  final _CliOptions options;
  final List<_Finding> findings = [];
  final Set<int> _reportedOffsets = {};

  static final RegExp _hanRegex = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _letterRegex = RegExp(r'[A-Za-z\u4e00-\u9fff]');

  static const Set<String> _uiPositionalWidgets = {
    'Text',
    'SelectableText',
    'AutoSizeText',
  };

  static const Set<String> _uiNamedArgs = {
    'text',
    'label',
    'tooltip',
    'message',
    'hintText',
    'labelText',
    'helperText',
    'errorText',
    'prefixText',
    'suffixText',
    'counterText',
    'semanticLabel',
    'semanticsLabel',
    'confirmText',
    'cancelText',
    'emptyText',
  };

  static const Set<String> _ignoredCallNames = {
    'debugPrint',
    'print',
    '_trace',
    'log',
    'logDebug',
    'logInfo',
    'logWarn',
    'logError',
    'assert',
    'RegExp',
    'Key',
    'ValueKey',
    'ObjectKey',
    'GlobalKey',
    'Exception',
    'StateError',
    'ArgumentError',
    'FormatException',
    'UnsupportedError',
    'UnimplementedError',
  };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name.lexeme;
    _checkCallArguments(typeName, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (_ignoredCallNames.contains(name)) {
      return; // 跳过日志、断言与技术性构造调用
    }
    _checkCallArguments(name, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitAssertStatement(AssertStatement node) {
    return; // 跳过 assert(...) 内部调试文案
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!options.uiOnly) {
      _maybeReportString(node, node.value, 'zh-literal');
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (!options.uiOnly) {
      final combined = node.elements
          .whereType<InterpolationString>()
          .map((e) => e.value)
          .join();
      _maybeReportString(node, combined, 'zh-interpolation');
    }
    super.visitStringInterpolation(node);
  }

  void _checkCallArguments(String callName, ArgumentList argumentList) {
    if (_ignoredCallNames.contains(callName)) return;

    final args = argumentList.arguments;
    if (_uiPositionalWidgets.contains(callName) && args.isNotEmpty) {
      final first = args.first;
      if (first is! NamedExpression) {
        _inspectUiExpression(first, '$callName(...)');
      }
    }

    for (final arg in args) {
      if (arg is NamedExpression &&
          _uiNamedArgs.contains(arg.name.label.name)) {
        _inspectUiExpression(
          arg.expression,
          '$callName(${arg.name.label.name}: ...)',
        );
      }
    }
  }

  void _inspectUiExpression(Expression expr, String contextKind) {
    if (expr is StringLiteral) {
      final text = _extractLiteralText(expr);
      if (text == null) return;
      if (options.zhOnly && !_hanRegex.hasMatch(text)) return;
      if (!_isHumanReadableText(text)) return;
      _record(expr, contextKind, expr.toSource());
    } else if (expr is ConditionalExpression) {
      _inspectUiExpression(expr.thenExpression, contextKind);
      _inspectUiExpression(expr.elseExpression, contextKind);
    } else if (expr is BinaryExpression && expr.operator.lexeme == '??') {
      if (options.ignoreFallbacks && _looksLikeL10nExpr(expr.leftOperand)) {
        return;
      }
      _inspectUiExpression(expr.leftOperand, contextKind);
      _inspectUiExpression(expr.rightOperand, contextKind);
    } else if (expr is ParenthesizedExpression) {
      _inspectUiExpression(expr.expression, contextKind);
    }
  }

  void _maybeReportString(StringLiteral node, String text, String kind) {
    if (!_hanRegex.hasMatch(text)) return;
    if (_isInsideIgnoredContext(node)) return;
    if (options.ignoreFallbacks && _isL10nFallbackNode(node)) return;
    _record(node, kind, node.toSource());
  }

  bool _isInsideIgnoredContext(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is ImportDirective ||
          current is ExportDirective ||
          current is PartDirective ||
          current is AssertStatement ||
          current is ThrowExpression) {
        return true;
      }
      if (current is MethodInvocation &&
          _ignoredCallNames.contains(current.methodName.name)) {
        return true;
      }
      if (current is InstanceCreationExpression &&
          _ignoredCallNames.contains(current.constructorName.type.name.lexeme)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isL10nFallbackNode(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is BinaryExpression &&
          current.operator.lexeme == '??' &&
          _looksLikeL10nExpr(current.leftOperand)) {
        return true;
      }
      if (current is ArgumentList || current is Block) break;
      current = current.parent;
    }
    return false;
  }

  bool _looksLikeL10nExpr(Expression expr) {
    final src = expr.toSource();
    return src.contains('l10n') || src.contains('AppLocalizations');
  }

  String? _extractLiteralText(StringLiteral literal) {
    if (literal is SimpleStringLiteral) return literal.value;
    if (literal is StringInterpolation) {
      return literal.elements
          .whereType<InterpolationString>()
          .map((e) => e.value)
          .join();
    }
    return null;
  }

  bool _isHumanReadableText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (!_letterRegex.hasMatch(trimmed)) return false;
    // 忽略纯插值分隔符或极短技术标记（如 "x", "ms", "dB" 等可根据需要调整）
    if (trimmed.length == 1 && !_hanRegex.hasMatch(trimmed)) return false;
    return true;
  }

  void _record(AstNode node, String kind, String source) {
    if (!_reportedOffsets.add(node.offset)) return;
    final loc = lineInfo.getLocation(node.offset);
    final singleLine = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview =
        singleLine.length > 90 ? '${singleLine.substring(0, 87)}...' : singleLine;
    findings.add(
      _Finding(
        filePath: filePath,
        line: loc.lineNumber,
        column: loc.columnNumber,
        kind: kind,
        preview: preview,
      ),
    );
  }
}
