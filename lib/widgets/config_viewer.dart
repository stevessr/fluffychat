import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConfigViewer extends StatefulWidget {
  const ConfigViewer({super.key});

  @override
  State<ConfigViewer> createState() => _ConfigViewerState();
}

class _ConfigViewerState extends State<ConfigViewer> {
  void _changeSetting(
    AppSettings appSetting,
    SharedPreferences store,
    String initialValue,
  ) async {
    if (appSetting is AppSettings<bool>) {
      await appSetting.setItem(store, !(initialValue == 'true'));
      setState(() {});
      return;
    }

    final value = await showTextInputDialog(
      context: context,
      title: appSetting.name,
      hintText: appSetting.defaultValue.toString(),
      initialText: initialValue,
    );
    if (value == null) return;

    if (appSetting is AppSettings<String>) {
      await appSetting.setItem(store, value);
    }
    if (appSetting is AppSettings<int>) {
      await appSetting.setItem(store, int.parse(value));
    }
    if (appSetting is AppSettings<double>) {
      await appSetting.setItem(store, double.parse(value));
    }

    setState(() {});
  }

  Future<void> _copyToken(BuildContext context) async {
    final client = Matrix.of(context).client;
    final token = client.accessToken;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No access token available'),
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
      ),
    );
  }

  Future<void> _confirmAndCopyToken(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: const Text('Copy current access token to clipboard?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _copyToken(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced configurations'),
        leading: BackButton(
          onPressed: () => context.go('/'),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'copy_access_token') {
                _confirmAndCopyToken(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'copy_access_token',
                child: Text('copy accesstoken'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.errorContainer,
            child: Text(
              'Changing configs by hand is untested! Use without any warranty!',
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: AppSettings.values.length,
              itemBuilder: (context, i) {
                final store = Matrix.of(context).store;
                final appSetting = AppSettings.values[i];
                var value = '';
                if (appSetting is AppSettings<String>) {
                  value = appSetting.getItem(store);
                }
                if (appSetting is AppSettings<int>) {
                  value = appSetting.getItem(store).toString();
                }
                if (appSetting is AppSettings<bool>) {
                  value = appSetting.getItem(store).toString();
                }
                if (appSetting is AppSettings<double>) {
                  value = appSetting.getItem(store).toString();
                }
                return ListTile(
                  title: Text(appSetting.name),
                  subtitle: Text(value),
                  onTap: () => _changeSetting(appSetting, store, value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
