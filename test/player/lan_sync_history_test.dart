import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/sharing/lan_sync_history.dart';
import 'package:vynody/player/sharing/lan_sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LanSyncReceipt & LanSyncOutcome', () {
    test('toReceipt and JSON round-trip preserve all fields', () {
      const outcome = LanSyncOutcome(
        containers: 3,
        matched: 10,
        added: 5,
        updated: 2,
        skipped: 3,
        missing: 1,
        ambiguous: 2,
        missingSamples: ['Missing Song'],
        ambiguousSamples: ['Dup Song'],
      );

      final receipt = outcome.toReceipt(
        kind: LanSyncKind.playlists,
        direction: LanSyncDirection.incoming,
        deviceName: 'MacBook Pro',
        elapsed: const Duration(milliseconds: 1450),
      );

      expect(receipt.hasDetails, isTrue);
      expect(receipt.detailCount, 3);

      final json = receipt.toJson();
      final decoded = LanSyncReceipt.fromJson(json);

      expect(decoded, isNotNull);
      expect(decoded!.kind, LanSyncKind.playlists);
      expect(decoded.direction, LanSyncDirection.incoming);
      expect(decoded.containers, 3);
      expect(decoded.added, 5);
      expect(decoded.updated, 2);
      expect(decoded.skipped, 3);
      expect(decoded.missing, 1);
      expect(decoded.ambiguous, 2);
      expect(decoded.missingSamples, ['Missing Song']);
      expect(decoded.ambiguousSamples, ['Dup Song']);
      expect(decoded.elapsed, const Duration(milliseconds: 1450));
      expect(decoded.deviceName, 'MacBook Pro');
    });

    test('fromJson returns null for invalid kind or direction', () {
      expect(
        LanSyncReceipt.fromJson({'kind': 'unknown', 'direction': 'incoming'}),
        isNull,
      );
      expect(
        LanSyncReceipt.fromJson({'kind': 'lyrics', 'direction': 'invalid'}),
        isNull,
      );
    });
  });

  group('LanSyncHistoryStore', () {
    test('records and reads receipt and finishedAt timestamp', () async {
      expect(await LanSyncHistoryStore.read(), isNull);
      expect(await LanSyncHistoryStore.lastFinishedAtMillis(), isNull);

      const receipt = LanSyncReceipt(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.outgoing,
        added: 12,
        updated: 4,
        skipped: 1,
        elapsed: Duration(seconds: 2),
        deviceName: 'iPhone',
      );

      await LanSyncHistoryStore.record(receipt);

      final restored = await LanSyncHistoryStore.read();
      final finishedAt = await LanSyncHistoryStore.lastFinishedAtMillis();

      expect(restored, isNotNull);
      expect(restored!.kind, LanSyncKind.lyrics);
      expect(restored.direction, LanSyncDirection.outgoing);
      expect(restored.added, 12);
      expect(restored.updated, 4);
      expect(restored.skipped, 1);
      expect(restored.hasDetails, isFalse);
      expect(restored.detailCount, 0);
      expect(restored.deviceName, 'iPhone');
      expect(finishedAt, isNotNull);
      expect(finishedAt, greaterThan(0));
    });

    test('gracefully returns null when stored JSON is corrupted', () async {
      SharedPreferences.setMockInitialValues({
        'lan_sync_last_receipt_v1': '{not-valid-json',
      });

      expect(await LanSyncHistoryStore.read(), isNull);
      expect(await LanSyncHistoryStore.lastFinishedAtMillis(), isNull);
    });
  });
}
