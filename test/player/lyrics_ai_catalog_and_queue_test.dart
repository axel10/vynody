import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/ai/ai_api_key_service.dart';
import 'package:vynody/player/ai/lyrics_model_catalog_service.dart';
import 'package:vynody/player/lyrics/lyrics_ai_doubao.dart';
import 'package:vynody/player/lyrics/lyrics_ai_task_queue.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/network_client.dart';

class _MockNetworkClient implements NetworkClient {
  _MockNetworkClient(this._getHandler);

  final FutureOr<Response<dynamic>> Function(
    String path,
    Map<String, dynamic>? queryParameters,
    Options? options,
  )
  _getHandler;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final res = await _getHandler(path, queryParameters, options);
    return Response<T>(
      requestOptions: res.requestOptions,
      data: res.data as T?,
      statusCode: res.statusCode,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Dio get dio => throw UnimplementedError();
}

void main() {
  group('LyricsAiTaskQueue', () {
    test('executes tasks strictly sequentially and continues after an error', () async {
      final queue = LyricsAiTaskQueue();
      final events = <String>[];
      final firstGate = Completer<void>();

      final f1 = queue.enqueue<int>(() async {
        events.add('start-1');
        await firstGate.future;
        events.add('end-1');
        return 1;
      });

      final f2 = queue.enqueue<int>(() async {
        events.add('start-2');
        throw StateError('boom');
      });

      final f3 = queue.enqueue<String>(() async {
        events.add('start-3');
        return 'ok';
      });

      await Future<void>.delayed(Duration.zero);
      // Only task 1 should have started while its gate is open.
      expect(events, ['start-1']);

      firstGate.complete();

      expect(await f1, 1);
      await expectLater(f2, throwsStateError);
      expect(await f3, 'ok');
      expect(events, ['start-1', 'end-1', 'start-2', 'start-3']);
    });
  });

  group('LyricsModelInfo & LyricsModelCatalogService', () {
    test('pricingLabel formats per-million prices without trailing zeros', () {
      const info = LyricsModelInfo(
        id: 'm1',
        displayName: 'Model 1',
        provider: LyricsAiProvider.openRouter,
        inputPricePerMillionTokens: 0.1500,
        outputPricePerMillionTokens: 2.000,
      );
      expect(info.pricingLabel, '输入 \$0.15 / 100万 token · 输出 \$2 / 100万 token');

      const freeInfo = LyricsModelInfo(
        id: 'm2',
        displayName: 'Free',
        provider: LyricsAiProvider.openRouter,
      );
      expect(freeInfo.pricingLabel, isNull);
    });

    test('Google AI Studio filters models by generation method and purpose', () async {
      final client = _MockNetworkClient((path, query, options) {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'models': [
              {
                'name': 'models/gemini-2.5-flash',
                'displayName': 'Gemini 2.5 Flash',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/gemma-3-27b',
                'displayName': 'Gemma 3 27B',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/embedding-001',
                'displayName': 'Embedding',
                'supportedGenerationMethods': ['embedContent'],
              },
            ],
          },
        );
      });

      final catalog = LyricsModelCatalogService(client: client);

      final emptyKeyRes = await catalog.fetchModels(
        provider: LyricsAiProvider.googleAiStudio,
        purpose: LyricsAiModelPurpose.generation,
        apiKey: '  ',
      );
      expect(emptyKeyRes.success, isFalse);

      final genRes = await catalog.fetchModels(
        provider: LyricsAiProvider.googleAiStudio,
        purpose: LyricsAiModelPurpose.generation,
        apiKey: 'secret',
      );
      expect(genRes.success, isTrue);
      expect(genRes.models.map((m) => m.id), ['gemini-2.5-flash']);

      final transRes = await catalog.fetchModels(
        provider: LyricsAiProvider.googleAiStudio,
        purpose: LyricsAiModelPurpose.translation,
        apiKey: 'secret',
      );
      expect(transRes.success, isTrue);
      expect(
        transRes.models.map((m) => m.id),
        ['gemini-2.5-flash', 'gemma-3-27b'],
      );
    });

    test('OpenRouter filters by modality and converts per-token price to per-million', () async {
      final client = _MockNetworkClient((path, query, options) {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 'google/gemini-audio',
                'name': 'Gemini Audio',
                'architecture': {
                  'input_modalities': ['text', 'audio'],
                  'output_modalities': ['text'],
                },
                'pricing': {'prompt': '0.00000015', 'completion': '0.000002'},
              },
              {
                'id': 'openai/gpt-text',
                'name': 'GPT Text',
                'architecture': {
                  'input_modalities': ['text'],
                  'output_modalities': ['text'],
                },
                'pricing': {'prompt': '0', 'completion': '0'},
              },
            ],
          },
        );
      });

      final catalog = LyricsModelCatalogService(client: client);

      final genRes = await catalog.fetchModels(
        provider: LyricsAiProvider.openRouter,
        purpose: LyricsAiModelPurpose.generation,
      );
      expect(genRes.models.map((m) => m.id), ['google/gemini-audio']);
      expect(genRes.models.single.inputPricePerMillionTokens, closeTo(0.15, 1e-6));
      expect(genRes.models.single.outputPricePerMillionTokens, closeTo(2.0, 1e-6));

      final transRes = await catalog.fetchModels(
        provider: LyricsAiProvider.openRouter,
        purpose: LyricsAiModelPurpose.translation,
      );
      expect(
        transRes.models.map((m) => m.id),
        ['google/gemini-audio', 'openai/gpt-text'],
      );
      expect(transRes.models[1].inputPricePerMillionTokens, 0);
    });

    test('Doubao sorts models by trailing numeric version descending', () async {
      final client = _MockNetworkClient((path, query, options) {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'data': [
              {'id': 'doubao-seed-1-6-250615', 'name': 'Seed 1.6 June'},
              {'id': 'doubao-seed-2-0-251015', 'name': 'Seed 2.0 Oct'},
              {'id': 'other-model', 'name': 'Other'},
            ],
          },
        );
      });

      final catalog = LyricsModelCatalogService(client: client);
      final res = await catalog.fetchModels(
        provider: LyricsAiProvider.doubao,
        purpose: LyricsAiModelPurpose.generation,
        apiKey: 'key',
      );

      expect(res.success, isTrue);
      expect(
        res.models.map((m) => m.id),
        ['doubao-seed-2-0-251015', 'doubao-seed-1-6-250615'],
      );
    });

    test('DeepSeek and Custom reject non-translation purposes gracefully without network call', () async {
      var called = false;
      final client = _MockNetworkClient((path, query, options) {
        called = true;
        return Response(requestOptions: RequestOptions(path: path), data: {});
      });
      final catalog = LyricsModelCatalogService(client: client);

      final dsGen = await catalog.fetchModels(
        provider: LyricsAiProvider.deepseek,
        purpose: LyricsAiModelPurpose.generation,
        apiKey: 'k',
      );
      expect(dsGen.success, isTrue);
      expect(dsGen.models, isEmpty);

      final customKaraoke = await catalog.fetchModels(
        provider: LyricsAiProvider.custom,
        purpose: LyricsAiModelPurpose.karaoke,
        apiKey: 'k',
        baseUrl: 'https://api.example.com/v1',
      );
      expect(customKaraoke.success, isTrue);
      expect(customKaraoke.models, isEmpty);
      expect(called, isFalse);
    });
  });

  group('AIApiKeyService', () {
    test('validates empty key, parses models, and formats DioException', () async {
      final client = _MockNetworkClient((path, query, options) {
        if (query?['key'] == 'bad') {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 400,
              data: {
                'error': {'message': 'API key not valid'},
              },
            ),
            type: DioExceptionType.badResponse,
          );
        }
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'models': [
              {'name': 'models/gemini-2.5-pro', 'displayName': 'Gemini Pro'},
            ],
          },
        );
      });

      final service = AIApiKeyService(client: client);

      final emptyRes = await service.testConnection('  ');
      expect(emptyRes.success, isFalse);

      final okRes = await service.testConnection('valid-key');
      expect(okRes.success, isTrue);
      expect(okRes.models.single.id, 'gemini-2.5-pro');
      expect(okRes.models.single.label, 'Gemini Pro');

      final errRes = await service.testConnection('bad');
      expect(errRes.success, isFalse);
      expect(errRes.message, contains('API key not valid'));
      expect(errRes.message, contains('400'));
    });
  });

  group('LyricsAiDoubaoClient.waitForFileReady', () {
    test('returns immediately when initialStatus is already ready', () async {
      var fetched = false;
      final client = LyricsAiDoubaoClient(
        client: _MockNetworkClient((path, query, options) {
          fetched = true;
          return Response(requestOptions: RequestOptions(path: path), data: {});
        }),
      );

      final result = await client.waitForFileReady(
        fileId: 'file-1',
        apiKey: 'key',
        initialStatus: 'processed',
      );

      expect(result?.id, 'file-1');
      expect(result?.status, 'processed');
      expect(fetched, isFalse);
    });

    test('polls fetchFileInfo until processed', () async {
      var polls = 0;
      final client = LyricsAiDoubaoClient(
        client: _MockNetworkClient((path, query, options) {
          polls++;
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'id': 'file-2',
              'status': polls >= 2 ? 'processed' : 'processing',
            },
          );
        }),
      );

      final result = await client.waitForFileReady(
        fileId: 'file-2',
        apiKey: 'key',
        initialStatus: 'processing',
      );

      expect(polls, 2);
      expect(result?.id, 'file-2');
      expect(result?.status, 'processed');
    });

    test('throws when status becomes failed and cancels on CancelToken', () async {
      final failedClient = LyricsAiDoubaoClient(
        client: _MockNetworkClient((path, query, options) {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'id': 'file-3', 'status': 'failed'},
          );
        }),
      );

      await expectLater(
        () => failedClient.waitForFileReady(
          fileId: 'file-3',
          apiKey: 'key',
          initialStatus: 'processing',
        ),
        throwsException,
      );

      final cancelToken = CancelToken()..cancel('user aborted');
      await expectLater(
        () => failedClient.waitForFileReady(
          fileId: 'file-4',
          apiKey: 'key',
          initialStatus: 'processing',
          cancelToken: cancelToken,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}
