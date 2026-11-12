import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/settings/settings_service.dart';
import '../dialogs/custom_proxy_dialog.dart';
import '../widgets/settings_dropdown_tile.dart';
import '../widgets/settings_group_card.dart';
import '../widgets/settings_section_header.dart';

class ProxySection extends StatelessWidget {
  final SettingsService settings;

  const ProxySection({
    super.key,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final String proxyModeSubtitle = switch (settings.proxyMode) {
      AppProxyMode.system => l10n.proxyModeSystemDesc,
      AppProxyMode.direct => l10n.proxyModeDirectDesc,
      AppProxyMode.custom =>
        '${settings.proxyCustomHost}:${settings.proxyCustomPort}',
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        SettingsSectionHeader(
          title: l10n.proxySettingsTitle,
          description: l10n.proxySettingsDescription,
        ),
        SettingsGroupCard(
          title: l10n.proxySettingsTitle,
          icon: Icons.vpn_lock_rounded,
          children: [
            SettingsDropdownTile<AppProxyMode>(
              title: l10n.proxyMode,
              subtitle: proxyModeSubtitle,
              value: settings.proxyMode,
              options: [
                SettingsDropdownOption(
                  value: AppProxyMode.system,
                  label: l10n.proxyModeSystem,
                ),
                SettingsDropdownOption(
                  value: AppProxyMode.direct,
                  label: l10n.proxyModeDirect,
                ),
                SettingsDropdownOption(
                  value: AppProxyMode.custom,
                  label: l10n.proxyModeCustom,
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                settings.proxyMode = value;
                if (value == AppProxyMode.custom &&
                    settings.proxyCustomHost.trim().isEmpty) {
                  final result = await showCustomProxyDialog(
                    context,
                    initialHost: settings.proxyCustomHost,
                    initialPort: settings.proxyCustomPort,
                    initialBypass: settings.proxyCustomBypass,
                  );
                  if (result != null) {
                    settings.proxyCustomHost = result.host;
                    settings.proxyCustomPort = result.port;
                    settings.proxyCustomBypass = result.bypass;
                  }
                }
              },
            ),
            if (settings.proxyMode == AppProxyMode.custom) ...[
              ListTile(
                leading: const Icon(Icons.settings_ethernet_rounded),
                title: Text(l10n.proxyModeCustom),
                subtitle: Text(
                  '${settings.proxyCustomHost}:${settings.proxyCustomPort}'
                  '${settings.proxyCustomBypass.isNotEmpty ? '  ·  ${settings.proxyCustomBypass}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    final result = await showCustomProxyDialog(
                      context,
                      initialHost: settings.proxyCustomHost,
                      initialPort: settings.proxyCustomPort,
                      initialBypass: settings.proxyCustomBypass,
                    );
                    if (result != null) {
                      settings.proxyCustomHost = result.host;
                      settings.proxyCustomPort = result.port;
                      settings.proxyCustomBypass = result.bypass;
                    }
                  },
                  child: Text(l10n.edit),
                ),
                onTap: () async {
                  final result = await showCustomProxyDialog(
                    context,
                    initialHost: settings.proxyCustomHost,
                    initialPort: settings.proxyCustomPort,
                    initialBypass: settings.proxyCustomBypass,
                  );
                  if (result != null) {
                    settings.proxyCustomHost = result.host;
                    settings.proxyCustomPort = result.port;
                    settings.proxyCustomBypass = result.bypass;
                  }
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}
