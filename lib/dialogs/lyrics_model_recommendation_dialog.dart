import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';

enum LyricsModelRecommendationAction {
  switchToRecommended,
  continueGeneration,
  abort,
}

class LyricsModelRecommendationResult {
  const LyricsModelRecommendationResult({
    required this.action,
    required this.doNotShowAgain,
  });

  final LyricsModelRecommendationAction action;
  final bool doNotShowAgain;
}

class LyricsModelRecommendationDialog extends StatefulWidget {
  const LyricsModelRecommendationDialog({
    super.key,
    required this.currentModelId,
    required this.recommendedModelId,
  });

  final String currentModelId;
  final String recommendedModelId;

  @override
  State<LyricsModelRecommendationDialog> createState() =>
      _LyricsModelRecommendationDialogState();
}

class _LyricsModelRecommendationDialogState
    extends State<LyricsModelRecommendationDialog> {
  bool _doNotShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.nonRecommendedModelWarningTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.nonRecommendedModelWarningMessage(
                widget.currentModelId,
                widget.recommendedModelId,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  _doNotShowAgain = !_doNotShowAgain;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _doNotShowAgain,
                        onChanged: (val) {
                          setState(() {
                            _doNotShowAgain = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.doNotShowAgain,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              LyricsModelRecommendationResult(
                action: LyricsModelRecommendationAction.abort,
                doNotShowAgain: _doNotShowAgain,
              ),
            );
          },
          child: Text(l10n.abortGeneration),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              LyricsModelRecommendationResult(
                action: LyricsModelRecommendationAction.continueGeneration,
                doNotShowAgain: _doNotShowAgain,
              ),
            );
          },
          child: Text(l10n.continueGeneration),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              LyricsModelRecommendationResult(
                action: LyricsModelRecommendationAction.switchToRecommended,
                doNotShowAgain: _doNotShowAgain,
              ),
            );
          },
          child: Text(l10n.switchAndGenerate),
        ),
      ],
    );
  }
}

Future<bool> ensureLyricsGenerationModelRecommendation(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsServiceProvider);
  final currentModel = settings.generationPrimaryModel;

  final String recommendedModelId;
  final bool isRecommended;

  switch (currentModel.provider) {
    case LyricsAiProvider.googleAiStudio:
      recommendedModelId = SettingsService.defaultGenerationPrimaryModelId;
      isRecommended = currentModel.modelId.trim() == recommendedModelId;
      break;
    case LyricsAiProvider.openRouter:
      recommendedModelId = SettingsService.defaultOpenRouterGenerationModelId;
      final normalizedId = currentModel.modelId.trim().toLowerCase();
      isRecommended = normalizedId == 'google/gemini-3.1-flash-lite' ||
          normalizedId == 'gemini-3.1-flash-lite';
      break;
    default:
      return true;
  }

  if (isRecommended) {
    return true;
  }

  if (settings.ignoreNonRecommendedLyricsModelWarning) {
    return true;
  }

  final result = await showDialog<LyricsModelRecommendationResult>(
    context: context,
    builder: (dialogContext) => LyricsModelRecommendationDialog(
      currentModelId: currentModel.modelId,
      recommendedModelId: recommendedModelId,
    ),
  );

  if (result == null ||
      result.action == LyricsModelRecommendationAction.abort) {
    if (result?.doNotShowAgain == true) {
      settings.ignoreNonRecommendedLyricsModelWarning = true;
    }
    return false;
  }

  if (result.doNotShowAgain) {
    settings.ignoreNonRecommendedLyricsModelWarning = true;
  }

  if (result.action == LyricsModelRecommendationAction.switchToRecommended) {
    settings.generationPrimaryModel = currentModel.copyWith(
      modelId: recommendedModelId,
    );
  }

  return true;
}
