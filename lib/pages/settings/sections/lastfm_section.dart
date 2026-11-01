import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/lastfm/lastfm_api_client.dart';
import 'package:vynody/player/lastfm/lastfm_credentials.dart';
import 'package:vynody/player/lastfm/lastfm_riverpod.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_snack_bar.dart';

import '../widgets/settings_group_card.dart';
import '../widgets/settings_section_header.dart';

/// Last.fm 分组：开关、账号、远程库策略。
///
/// 这里只做「能连上 / 能关掉」的最小闭环，不展示收听历史 ——
/// 记录本身在 Last.fm 网站上查看。
class LastFmSection extends ConsumerStatefulWidget {
  const LastFmSection({super.key, required this.settings});

  final SettingsService settings;

  @override
  ConsumerState<LastFmSection> createState() => _LastFmSectionState();
}

class _LastFmSectionState extends ConsumerState<LastFmSection> {
  LastFmSession? _session;
  bool _loadingSession = true;
  bool _busy = false;
  String? _pendingToken;
  Uri? _pendingAuthorizationUri;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSession());
  }

  Future<void> _loadSession() async {
    final session = await ref.read(lastFmAuthServiceProvider).loadSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loadingSession = false;
    });
  }

  Future<void> _startAuthorization() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final request = await ref
          .read(lastFmAuthServiceProvider)
          .beginAuthorization();
      _pendingToken = request.token;
      _pendingAuthorizationUri = request.authorizationUri;
      await launchUrl(
        request.authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.lastFmAuthorizationHint)),
      );
    } on LastFmApiException catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(
          content: Text(
            l10n.lastFmAuthorizationFailed(
              error.message.isEmpty ? 'error ${error.code}' : error.message,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.lastFmAuthorizationFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _completeAuthorization() async {
    final token = _pendingToken;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final session = await ref
          .read(lastFmAuthServiceProvider)
          .completeAuthorization(token);
      if (!mounted) return;
      setState(() {
        _session = session;
        _pendingToken = null;
        _pendingAuthorizationUri = null;
      });
      // 授权刚完成，顺手把排队中的记录送出去。
      unawaited(ref.read(lastFmScrobbleServiceProvider).flush());
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.lastFmAuthorizationSuccess)),
      );
    } on LastFmApiException catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(
          content: Text(
            l10n.lastFmAuthorizationFailed(
              error.message.isEmpty ? 'error ${error.code}' : error.message,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.lastFmAuthorizationFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _disconnect() async {
    await ref.read(lastFmAuthServiceProvider).signOut();
    if (!mounted) return;
    setState(() {
      _session = null;
      _pendingToken = null;
      _pendingAuthorizationUri = null;
    });
  }

  Future<void> _reopenAuthorizationPage() async {
    final uri = _pendingAuthorizationUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = widget.settings;

    if (!LastFmCredentials.isConfigured) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          SettingsSectionHeader(
            title: l10n.lastFmSectionTitle,
            description: l10n.lastFmSectionDescription,
          ),
          SettingsGroupCard(
            title: l10n.lastFmSectionTitle,
            icon: Icons.music_note_rounded,
            children: [
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(l10n.lastFmCredentialsMissing),
              ),
            ],
          ),
        ],
      );
    }

    final connected = _session != null;
    final scrobblingEnabled = settings.lastFmScrobblingEnabled;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        SettingsSectionHeader(
          title: l10n.lastFmSectionTitle,
          description: l10n.lastFmSectionDescription,
        ),
        SettingsGroupCard(
          title: l10n.lastFmSectionTitle,
          icon: Icons.music_note_rounded,
          children: [
            SwitchListTile(
              title: Text(l10n.lastFmScrobblingEnabledTitle),
              subtitle: Text(l10n.lastFmScrobblingEnabledDescription),
              value: scrobblingEnabled,
              onChanged: (value) {
                settings.lastFmScrobblingEnabled = value;
              },
            ),
            CheckboxListTile(
              title: Text(l10n.lastFmScrobbleRemoteTitle),
              subtitle: Text(l10n.lastFmScrobbleRemoteDescription),
              value: settings.lastFmScrobbleRemote,
              onChanged: scrobblingEnabled
                  ? (value) {
                      settings.lastFmScrobbleRemote = value ?? false;
                    }
                  : null,
            ),
          ],
        ),
        SettingsGroupCard(
          title: l10n.lastFmAccountTitle,
          icon: Icons.person_outline_rounded,
          children: [
            ListTile(
              title: Text(l10n.lastFmAccountTitle),
              subtitle: Text(
                _loadingSession
                    ? ''
                    : connected
                    ? l10n.lastFmConnectedAs(_session!.username)
                    : l10n.lastFmNotConnected,
              ),
              trailing: connected
                  ? TextButton(
                      onPressed: _busy ? null : _disconnect,
                      child: Text(l10n.lastFmDisconnect),
                    )
                  : TextButton(
                      onPressed: _busy ? null : _startAuthorization,
                      child: Text(l10n.lastFmConnect),
                    ),
            ),
            if (_pendingToken != null && !connected) ...[
              ListTile(
                leading: const Icon(Icons.open_in_browser_rounded),
                title: Text(l10n.lastFmAuthorizationPending),
                subtitle: Text(l10n.lastFmAuthorizationHint),
                trailing: TextButton(
                  onPressed: _busy ? null : _reopenAuthorizationPage,
                  child: Text(l10n.lastFmOpenAuthorizationPage),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(l10n.lastFmCompleteAuthorization),
                enabled: !_busy,
                onTap: _busy ? null : _completeAuthorization,
              ),
            ],
            _StatusTile(
              connected: connected,
              enabled: scrobblingEnabled,
              service: ref.read(lastFmScrobbleServiceProvider),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.connected,
    required this.enabled,
    required this.service,
  });

  final bool connected;
  final bool enabled;
  final LastFmScrobbleService service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!connected) return const SizedBox.shrink();

    return ValueListenableBuilder<DateTime?>(
      valueListenable: service.lastScrobbleAt,
      builder: (context, lastAt, _) {
        return ValueListenableBuilder<int>(
          valueListenable: service.pendingCount,
          builder: (context, pending, _) {
            final subtitle = lastAt == null
                ? l10n.lastFmNeverScrobbled
                : l10n.lastFmLastScrobble(_formatTime(lastAt));
            return ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(subtitle),
              subtitle: pending > 0
                  ? Text(l10n.lastFmPendingCount(pending))
                  : null,
              enabled: enabled,
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
