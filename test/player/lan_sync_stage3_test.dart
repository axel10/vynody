import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/dialogs/lan_sync_dialogs.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/l10n/app_localizations_zh.dart';
import 'package:vynody/player/sharing/lan_sync_models.dart';
import 'package:vynody/player/sharing/lan_sync_progress.dart';

void main() {
  group('LanSyncOutcome → LanSyncReceipt', () {
    test('字段逐项搬运，明细样本不丢', () {
      const outcome = LanSyncOutcome(
        containers: 3,
        matched: 10,
        added: 8,
        updated: 2,
        skipped: 1,
        missing: 4,
        ambiguous: 2,
        missingSamples: ['A', 'B'],
        ambiguousSamples: ['C'],
      );

      final receipt = outcome.toReceipt(
        kind: LanSyncKind.playlists,
        direction: LanSyncDirection.incoming,
        deviceName: 'Pixel',
        elapsed: const Duration(seconds: 7),
      );

      expect(receipt.kind, LanSyncKind.playlists);
      expect(receipt.direction, LanSyncDirection.incoming);
      expect(receipt.containers, 3);
      expect(receipt.added, 8);
      expect(receipt.updated, 2);
      expect(receipt.skipped, 1);
      expect(receipt.missing, 4);
      expect(receipt.ambiguous, 2);
      expect(receipt.missingSamples, ['A', 'B']);
      expect(receipt.ambiguousSamples, ['C']);
      expect(receipt.elapsed, const Duration(seconds: 7));
      expect(receipt.deviceName, 'Pixel');
    });

    test('没有明细时 hasDetails 为 false，SnackBar 不显示「查看详情」', () {
      const clean = LanSyncOutcome(added: 5);
      expect(
        clean
            .toReceipt(kind: LanSyncKind.lyrics, direction: LanSyncDirection.incoming)
            .hasDetails,
        isFalse,
      );
      const dirty = LanSyncOutcome(missing: 1);
      expect(
        dirty
            .toReceipt(kind: LanSyncKind.lyrics, direction: LanSyncDirection.incoming)
            .hasDetails,
        isTrue,
      );
    });
  });

  group('回执持久化', () {
    test('JSON 往返后细节保持一致', () {
      const receipt = LanSyncReceipt(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        added: 12,
        updated: 3,
        skipped: 1,
        missing: 2,
        ambiguous: 1,
        missingSamples: ['未匹配 A'],
        ambiguousSamples: ['多候选 B'],
        elapsed: Duration(seconds: 4),
        deviceName: 'MacBook',
      );

      final restored = LanSyncReceipt.fromJson(receipt.toJson());

      expect(restored, isNotNull);
      expect(restored!.kind, receipt.kind);
      expect(restored.direction, receipt.direction);
      expect(restored.added, 12);
      expect(restored.updated, 3);
      expect(restored.skipped, 1);
      expect(restored.missing, 2);
      expect(restored.ambiguous, 1);
      expect(restored.missingSamples, ['未匹配 A']);
      expect(restored.ambiguousSamples, ['多候选 B']);
      expect(restored.elapsed, const Duration(seconds: 4));
      expect(restored.deviceName, 'MacBook');
    });

    test('旧版本数据缺字段时按缺省值读，不抛异常', () {
      final restored = LanSyncReceipt.fromJson({
        'kind': 'lyrics',
        'direction': 'incoming',
        'added': 2,
      });

      expect(restored, isNotNull);
      expect(restored!.added, 2);
      expect(restored.updated, 0);
      expect(restored.missingSamples, isEmpty);
      expect(restored.elapsed, Duration.zero);
    });

    test('未知 kind 直接判为不可用，而不是猜一个', () {
      expect(
        LanSyncReceipt.fromJson({'kind': 'unknown', 'direction': 'incoming'}),
        isNull,
      );
    });
  });

  group('进度状态机', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    LanSyncProgressNotifier notifier() =>
        container.read(lanSyncProgressProvider.notifier);

    test('发起方向从「整理」开始，接收方向从「传输」开始', () {
      notifier().begin(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        deviceName: 'A',
      );
      expect(
        container.read(lanSyncProgressProvider)!.stage,
        LanSyncStage.preparing,
      );

      notifier().begin(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.incoming,
        deviceName: 'B',
      );
      expect(
        container.read(lanSyncProgressProvider)!.stage,
        LanSyncStage.transferring,
      );
    });

    test('换阶段与计数', () {
      notifier().begin(
        kind: LanSyncKind.playlists,
        direction: LanSyncDirection.outgoing,
        deviceName: 'A',
      );
      notifier().setStage(
        LanSyncStage.transferring,
        processed: 0,
        total: 10,
      );
      notifier().advance(4);

      final progress = container.read(lanSyncProgressProvider)!;
      expect(progress.stage, LanSyncStage.transferring);
      expect(progress.processed, 4);
      expect(progress.fraction, 0.4);
    });

    test('总量未知时 fraction 为 null（画不确定进度条）', () {
      notifier().begin(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        deviceName: 'A',
      );
      expect(container.read(lanSyncProgressProvider)!.fraction, isNull);
    });

    test('取消只置标志，不清任务状态', () {
      notifier().begin(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        deviceName: 'A',
      );
      notifier().requestCancel();

      expect(notifier().cancelRequested, isTrue);
      expect(container.read(lanSyncProgressProvider), isNotNull);
    });

    test('clear 之后不再报告取消', () {
      notifier().begin(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        deviceName: 'A',
      );
      notifier().requestCancel();
      notifier().clear();

      expect(notifier().cancelRequested, isFalse);
      expect(container.read(lanSyncProgressProvider), isNull);
    });

    test('没有任务时 advance/setStage 都是 no-op', () {
      notifier().advance(3);
      notifier().setStage(LanSyncStage.importing, total: 5);
      expect(container.read(lanSyncProgressProvider), isNull);
    });
  });

  group('回执摘要', () {
    final l10n = AppLocalizationsZh();

    test('歌词接收方向带新增/更新/跳过三项', () {
      const receipt = LanSyncReceipt(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.incoming,
        added: 3,
        updated: 2,
        skipped: 1,
      );
      final text = lanSyncReceiptSummary(l10n, receipt);
      expect(text, contains('3'));
      expect(text, contains('2'));
      expect(text, contains('1'));
    });

    test('歌单有未匹配时用「部分接收」措辞', () {
      const receipt = LanSyncReceipt(
        kind: LanSyncKind.playlists,
        direction: LanSyncDirection.incoming,
        containers: 2,
        added: 40,
        missing: 10,
      );
      expect(
        lanSyncReceiptSummary(l10n, receipt),
        l10n.lanSyncPlaylistsReceivedPartial(2, 40, 10),
      );
    });

    test('多候选另起一行提示', () {
      const receipt = LanSyncReceipt(
        kind: LanSyncKind.playlists,
        direction: LanSyncDirection.outgoing,
        containers: 1,
        added: 5,
        ambiguous: 2,
      );
      final text = lanSyncReceiptSummary(l10n, receipt);
      expect(text.split('\n'), hasLength(2));
      expect(text, contains(l10n.lanSyncPlaylistsAmbiguous(2)));
    });
  });

  group('进度对话框', () {
    Future<void> pumpHost(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showLanSyncProgressDialog(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('进度归零后对话框自动关闭，不会留下关不掉的模态框', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(lanSyncProgressProvider.notifier);
      notifier.begin(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        deviceName: 'MacBook',
      );
      notifier.setStage(LanSyncStage.transferring, processed: 0, total: 4);

      await pumpHost(tester, container);
      await tester.tap(find.text('open'));
      // 进度条在总量未知时是不确定动画，pumpAndSettle 永远不会稳定。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('正在发送到 MacBook'), findsOneWidget);
      expect(find.text('正在传输'), findsOneWidget);
      expect(find.text('0/4'), findsOneWidget);

      container.read(lanSyncProgressProvider.notifier).advance(2);
      await tester.pump();
      expect(find.text('2/4'), findsOneWidget);

      container.read(lanSyncProgressProvider.notifier).clear();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('正在发送到 MacBook'), findsNothing);

      // 退场动画跑完才会触发 whenComplete，标记要再等一帧。
      await tester.pump(const Duration(seconds: 1));
      expect(isLanSyncProgressDialogOpen, isFalse);
    });

    testWidgets('任务在弹窗铺开之前就失败：对话框自行退出，不误弹页面', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await pumpHost(tester, container);

      // 没有 begin 过，provider 一直是 null —— 模拟同步被互斥直接拒绝。
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 页面还在（对话框没有把宿主页弹掉）。
      expect(find.text('open'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(isLanSyncProgressDialogOpen, isFalse);
    });
  });
}
