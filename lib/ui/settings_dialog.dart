import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store/markdown_vault.dart';
import '../store/page_repository.dart';
import '../sync/api_client.dart';
import '../sync/sync_engine.dart';
import 'theme.dart';

/// Settings: self-hosted sync configuration and markdown vault controls.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.repository,
    required this.syncEngine,
    required this.vault,
  });

  final PageRepository repository;
  final SyncEngine syncEngine;
  final MarkdownVault? vault;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _vaultPath;
  late final TextEditingController _import;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController();
    _token = TextEditingController();
    _vaultPath = TextEditingController(text: widget.vault?.rootPath ?? '');
    _import = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final url = await widget.repository.setting('serverUrl') as String? ?? '';
    if (!mounted) return;
    _url.text = url;
    final vaultPath = await widget.repository.setting('vaultPath') as String?;
    if (!mounted) return;
    if (vaultPath != null && widget.vault != null) {
      widget.vault!.rootPath = vaultPath;
      _vaultPath.text = vaultPath;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _vaultPath.dispose();
    _import.dispose();
    super.dispose();
  }

  Future<void> _saveSync() async {
    try {
      await widget.syncEngine.configure(
          serverUrl: _url.text.trim(), token: _token.text.trim());
      unawaited(widget.syncEngine.runOnce());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sync configured — it now runs every 15 seconds')));
      }
    } catch (error) {
      if (mounted) setState(() => _testResult = error.toString());
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testResult = 'Testing…');
    final api = AnamneApi(baseUrl: _url.text.trim(), token: _token.text.trim());
    try {
      await api.health();
      if (mounted) setState(() => _testResult = 'Connection OK');
    } on AnamneApiException catch (error) {
      if (mounted) setState(() => _testResult =
          'Failed: ${error.message}${error.statusCode == null ? '' : ' (${error.statusCode})'}');
    } catch (error) {
      if (mounted) setState(() => _testResult = 'Failed: $error');
    }
    finally { api.close(); }
  }

  Future<void> _disableSync() async {
    await widget.syncEngine.disable();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync disabled — local only mode')));
    }
  }

  Future<void> _saveVaultPath() async {
    if (widget.vault == null) return;
    widget.vault!.rootPath = _vaultPath.text.trim();
    await widget.repository.setSetting('vaultPath', _vaultPath.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault path saved')));
    }
  }

  Future<void> _importJson() async {
    try {
      await widget.repository.importJson(_import.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Workspace imported')));
      }
    } catch (error) {
      if (mounted) setState(() => _testResult = 'Import failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 460,
        child: ListView(shrinkWrap: true, children: [
          const Text('Self-hosted sync',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://anamne.example.com',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'API token',
                hintText: 'Bearer token with editor or admin role',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              onPressed: _saveSync,
              icon: const Icon(Icons.cloud_upload_outlined, size: 17),
              label: const Text('Save & sync'),
            ),
            OutlinedButton.icon(
              onPressed: _testConnection,
              icon: const Icon(Icons.wifi_tethering_outlined, size: 17),
              label: const Text('Test'),
            ),
            TextButton.icon(
              onPressed: _disableSync,
              icon: const Icon(Icons.cloud_off_outlined, size: 17),
              label: const Text('Disable'),
            ),
          ]),
          if (_testResult != null)
            Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(_testResult!,
                    style: const TextStyle(fontSize: 12.5, color: muted))),
          const Divider(height: 28),
          if (widget.vault != null) ...[
            const Text('Markdown vault (Obsidian-compatible)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(
              controller: _vaultPath,
              decoration: const InputDecoration(
                  labelText: 'Vault folder',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _saveVaultPath,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: const Text('Save path'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final written = await widget.vault!.mirrorAll();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(widget.vault!.lastError ??
                            'Wrote $written files')));
                  }
                },
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Mirror now'),
              ),
            ]),
            if (widget.vault!.lastError != null)
              Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(widget.vault!.lastError!,
                      style: const TextStyle(fontSize: 12.5, color: dangerRed))),
            const Divider(height: 28),
          ],
          const Text('Import portable JSON',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _import,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'Paste an anamne.pages export…',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _importJson,
            icon: const Icon(Icons.upload_outlined, size: 17),
            label: const Text('Import into workspace'),
          ),
          TextButton.icon(
            onPressed: () async {
              final json = await widget.repository.exportJson();
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Full workspace JSON copied')));
              }
            },
            icon: const Icon(Icons.copy_outlined, size: 17),
            label: const Text('Copy full workspace JSON'),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
