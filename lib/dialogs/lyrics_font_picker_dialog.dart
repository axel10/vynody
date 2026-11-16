import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../player/lyrics/custom_font_service.dart';
import '../player/lyrics/system_fonts_service.dart';
import '../utils/app_snack_bar.dart';

/// Shows a comprehensive font picker dialog with live preview and grouped font listing.
Future<String?> showLyricsFontPickerDialog(
  BuildContext context, {
  required String initialFont,
  String? title,
  bool? isCjkMode,
  ValueChanged<String>? onFontPreview,
}) async {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) => _LyricsFontPickerDialog(
      initialFont: initialFont,
      title: title ?? l10n.selectLyricsFont,
      onFontPreview: onFontPreview,
    ),
  );
}

class _LyricsFontPickerDialog extends StatefulWidget {
  const _LyricsFontPickerDialog({
    required this.initialFont,
    required this.title,
    this.onFontPreview,
  });

  final String initialFont;
  final String title;
  final ValueChanged<String>? onFontPreview;

  @override
  State<_LyricsFontPickerDialog> createState() => _LyricsFontPickerDialogState();
}

class _LyricsFontPickerDialogState extends State<_LyricsFontPickerDialog> {
  late String _selectedFont;
  late TextEditingController _searchController;
  FontCategory _category = FontCategory.all;
  List<FontItem> _allFonts = [];
  bool _isLoading = true;
  bool get _hasCustomFonts => _allFonts.any((f) => f.isCustom);

  @override
  void initState() {
    super.initState();
    _selectedFont = widget.initialFont.trim();
    _searchController = TextEditingController();
    _category = FontCategory.all;

    // Load initial sync presets first, then await full scan
    _allFonts = SystemFontsService.instance.getAvailableFontsSync();
    _loadSystemFonts();
  }

  Future<void> _loadSystemFonts() async {
    final fonts = await SystemFontsService.instance.getAvailableFonts();
    if (!mounted) return;
    setState(() {
      _allFonts = fonts;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectFont(String font) {
    setState(() {
      _selectedFont = font.trim();
    });
    widget.onFontPreview?.call(_selectedFont);
  }

  Future<void> _handleImportFont() async {
    final l10n = AppLocalizations.of(context)!;
    final imported = await CustomFontService.instance.importFontFile();
    if (imported == null) return;
    if (!mounted) return;

    SystemFontsService.instance.invalidateCache();
    await _loadSystemFonts();
    _selectFont(imported.family);

    if (mounted) {
      AppSnackBar.show(context, null, SnackBar(content: Text(l10n.fontImportSuccess)));
    }
  }

  Future<void> _handleDeleteFont(FontItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteFontConfirm(item.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await CustomFontService.instance.deleteFont(item.family);
    SystemFontsService.instance.invalidateCache();
    await _loadSystemFonts();

    if (_selectedFont == item.family) {
      _selectFont('');
    }
  }

  List<FontItem> _getFilteredFonts() {
    final query = _searchController.text.trim().toLowerCase();

    return _allFonts.where((item) {
      // 1. Category check
      switch (_category) {
        case FontCategory.custom:
          if (!item.isCustom) return false;
          break;
        case FontCategory.cjk:
          if (item.isCustom || !item.isCjk) return false;
          break;
        case FontCategory.latin:
          if (item.isCustom || item.isCjk) return false;
          break;
        case FontCategory.recommended:
          if (!item.isRecommended) return false;
          break;
        case FontCategory.all:
          break;
      }

      // 2. Query search
      if (query.isNotEmpty) {
        final matchFamily = item.family.toLowerCase().contains(query);
        final matchDisplay = item.displayName.toLowerCase().contains(query);
        if (!matchFamily && !matchDisplay) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 600;
    final dialogWidth = isCompact
        ? (screenSize.width - 32).clamp(280.0, 560.0)
        : (screenSize.width * 0.7).clamp(380.0, 560.0);
    final dialogHeight = isCompact
        ? (screenSize.height * 0.85).clamp(420.0, 720.0)
        : (screenSize.height * 0.8).clamp(480.0, 680.0);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16.0 : 40.0,
        vertical: 24.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Column(
          children: [
            // Title Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: l10n.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Live Preview Card (Bilingual preview)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPreviewCard(theme, colorScheme, l10n),
            ),

            const SizedBox(height: 12),

            // Search and Category Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.searchFontHint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip(
                          label: '${l10n.allFonts} (${_allFonts.length})',
                          category: FontCategory.all,
                          colorScheme: colorScheme,
                        ),
                        if (_hasCustomFonts) ...[
                          const SizedBox(width: 8),
                          _buildCategoryChip(
                            label: '${l10n.importedFonts} (${_allFonts.where((f) => f.isCustom).length})',
                            category: FontCategory.custom,
                            colorScheme: colorScheme,
                          ),
                        ],
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          label: l10n.cjkFonts,
                          category: FontCategory.cjk,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          label: l10n.latinFonts,
                          category: FontCategory.latin,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            // Font List (Grouped with Section Headers and Dividers)
            Expanded(
              child: _buildFontList(theme, colorScheme, l10n),
            ),

            const Divider(height: 1),

            // Bottom Action Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: Text(
                          l10n.importFontFile,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        onPressed: _handleImportFont,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedFont),
                    child: Text(l10n.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontList(ThemeData theme, ColorScheme colorScheme, AppLocalizations l10n) {
    final query = _searchController.text.trim();
    final items = <Widget>[];

    if (query.isNotEmpty) {
      final searchResults = _getFilteredFonts();
      if (searchResults.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.noImportedFontsHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: searchResults.length,
        itemBuilder: (context, index) {
          final item = searchResults[index];
          return _buildFontItemTile(item, theme, colorScheme);
        },
      );
    }

    // Default / Follow System is always at top
    final isDefaultSelected = _selectedFont.isEmpty;
    final defaultTile = _buildFontTile(
      title: l10n.defaultFontOption,
      subtitle: '落霞与孤鹜齐飞 · The quick brown fox',
      fontFamily: '',
      isSelected: isDefaultSelected,
      isCustom: false,
      colorScheme: colorScheme,
      theme: theme,
      onTap: () => _selectFont(''),
    );

    if (_category == FontCategory.all) {
      items.add(defaultTile);

      final customFonts = _allFonts.where((f) => f.isCustom).toList();
      if (customFonts.isNotEmpty) {
        items.add(_buildSectionHeader(
          title: l10n.importedFonts,
          icon: Icons.folder_special_outlined,
          count: customFonts.length,
          colorScheme: colorScheme,
        ));
        for (final font in customFonts) {
          items.add(_buildFontItemTile(font, theme, colorScheme));
        }
      }

      final cjkFonts = _allFonts.where((f) => !f.isCustom && f.isCjk).toList();
      if (cjkFonts.isNotEmpty) {
        items.add(_buildSectionHeader(
          title: l10n.cjkFonts,
          icon: Icons.translate_rounded,
          count: cjkFonts.length,
          colorScheme: colorScheme,
        ));
        for (final font in cjkFonts) {
          items.add(_buildFontItemTile(font, theme, colorScheme));
        }
      }

      final latinFonts = _allFonts.where((f) => !f.isCustom && !f.isCjk).toList();
      if (latinFonts.isNotEmpty) {
        items.add(_buildSectionHeader(
          title: l10n.latinFonts,
          icon: Icons.language_rounded,
          count: latinFonts.length,
          colorScheme: colorScheme,
        ));
        for (final font in latinFonts) {
          items.add(_buildFontItemTile(font, theme, colorScheme));
        }
      }
    } else if (_category == FontCategory.custom) {
      final customFonts = _allFonts.where((f) => f.isCustom).toList();
      if (customFonts.isEmpty) {
        items.add(
          Container(
            margin: const EdgeInsets.only(top: 24, left: 16, right: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.font_download_outlined, size: 40, color: colorScheme.outline),
                const SizedBox(height: 10),
                Text(
                  l10n.noImportedFontsHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        for (final font in customFonts) {
          items.add(_buildFontItemTile(font, theme, colorScheme));
        }
      }
    } else {
      items.add(defaultTile);
      final filtered = _getFilteredFonts();
      for (final font in filtered) {
        items.add(_buildFontItemTile(font, theme, colorScheme));
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: items,
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    int? count,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            count != null ? '$title ($count)' : title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontItemTile(FontItem item, ThemeData theme, ColorScheme colorScheme) {
    final sampleText = item.isCustom
        ? '落霞与孤鹜齐飞 · The quick brown fox'
        : item.isCjk
            ? '落霞与孤鹜齐飞，秋水共长天一色。0123456789'
            : 'The quick brown fox jumps over the lazy dog. 0123456789';

    return _buildFontTile(
      title: item.displayName,
      subtitle: sampleText,
      fontFamily: item.family,
      isSelected: _selectedFont == item.family,
      isCustom: item.isCustom,
      colorScheme: colorScheme,
      theme: theme,
      onTap: () => _selectFont(item.family),
      onDelete: item.isCustom ? () => _handleDeleteFont(item) : null,
    );
  }

  Widget _buildPreviewCard(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final effectiveFont = _selectedFont.isNotEmpty ? _selectedFont : null;
    final fontLabel = _selectedFont.isEmpty ? l10n.followSystemLanguage : _selectedFont;
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${l10n.lyricsFontPreview} · $fontLabel',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '落霞与孤鹜齐飞，秋水共长天一色。',
            style: baseStyle.copyWith(
              fontFamily: effectiveFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'The quick brown fox jumps over the lazy dog. 0123456789',
            style: baseStyle.copyWith(
              fontFamily: effectiveFont,
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
              height: 1.35,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required FontCategory category,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _category == category;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _category = category;
          });
        }
      },
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
      ),
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      side: BorderSide(
        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildFontTile({
    required String title,
    required String subtitle,
    required String fontFamily,
    required bool isSelected,
    required bool isCustom,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.45) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        dense: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? colorScheme.primary : null,
                ),
              ),
            ),
            if (isCustom)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  AppLocalizations.of(context)!.importedFonts,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            fontFamily: fontFamily.isNotEmpty ? fontFamily : null,
            fontSize: 13,
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.8)
                : colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                color: colorScheme.error.withValues(alpha: 0.7),
                onPressed: onDelete,
              ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 20),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
