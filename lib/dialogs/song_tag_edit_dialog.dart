import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/metadata_database.dart';
import '../player/metadata_helper.dart';

class SongTagEditResult {
  const SongTagEditResult({
    required this.metadata,
    required this.savedToSourceFile,
    this.artworkBytes,
  });

  final SongMetadata metadata;
  final bool savedToSourceFile;
  final Uint8List? artworkBytes;
}

Future<SongTagEditResult?> showSongTagEditSheet(
  BuildContext context, {
  required MusicFile song,
}) {
  return showModalBottomSheet<SongTagEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SongTagEditSheet(song: song),
  );
}

class SongTagEditSheet extends StatefulWidget {
  const SongTagEditSheet({super.key, required this.song});

  final MusicFile song;

  @override
  State<SongTagEditSheet> createState() => _SongTagEditSheetState();
}

class _SongTagEditSheetState extends State<SongTagEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _trackNumberController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.song.title?.trim().isNotEmpty == true
          ? widget.song.title!.trim()
          : widget.song.displayName,
    );
    _artistController = TextEditingController(
      text: widget.song.artist?.trim() ?? '',
    );
    _albumController = TextEditingController(
      text: widget.song.album?.trim() ?? '',
    );
    _trackNumberController = TextEditingController(
      text: widget.song.trackNumber?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _trackNumberController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool writeToFile}) async {
    if (_isSaving) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final trackNumberText = _trackNumberController.text.trim();
    final trackNumber = trackNumberText.isEmpty
        ? null
        : int.tryParse(trackNumberText);
    if (trackNumberText.isNotEmpty && trackNumber == null) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.trackNumberMustBeInteger;
      });
      return;
    }

    final result = await MetadataHelper.saveSelectedSongMetadata(
      filePath: widget.song.path,
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      album: _albumController.text.trim(),
      trackNumber: trackNumber,
      artworkBytes: widget.song.artworkBytes,
      existingMetadata: null,
      writeToFile: writeToFile,
    );

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _isSaving = false;
        _errorMessage = writeToFile
            ? l10n.saveToSourceFileFailed
            : l10n.saveFailed;
      });
      return;
    }

    Navigator.of(context).pop(
      SongTagEditResult(
        metadata: result.$1,
        artworkBytes: result.$2,
        savedToSourceFile: writeToFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canWriteToSourceFile = isMetadataWritable(widget.song.path);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.86),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.editSongTagsTitle,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.editSongTagsDescription,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        _buildField(
                          controller: _titleController,
                          label: l10n.title,
                          icon: Icons.title_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _artistController,
                          label: l10n.artistLabel,
                          icon: Icons.person_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _albumController,
                          label: l10n.albumLabel,
                          icon: Icons.album_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _trackNumberController,
                          label: l10n.trackNumberLabel,
                          icon: Icons.numbers_rounded,
                          keyboardType: TextInputType.number,
                          helperText: l10n.leaveBlankKeepsCurrentValue,
                        ),
                        const SizedBox(height: 16),
                        _buildReadonlyInfo(
                          label: l10n.file,
                          value: widget.song.path,
                          icon: Icons.folder_open_rounded,
                        ),
                        const SizedBox(height: 10),
                        if (!canWriteToSourceFile)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              l10n.currentFileFormatCannotWriteBack,
                              style: TextStyle(
                                color: Colors.orangeAccent.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          l10n.leaveBlankDoesNotClearOriginalValue,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () => _save(writeToFile: false),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.saveToApp),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: _isSaving || !canWriteToSourceFile
                              ? null
                              : () => _save(writeToFile: true),
                          child: Text(l10n.saveToSourceFileAndApp),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    return TextField(
      controller: controller,
      enabled: !_isSaving,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFF46D27A),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Icon(icon, color: Colors.white70),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF46D27A), width: 1.1),
        ),
      ),
    );
  }

  Widget _buildReadonlyInfo({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
