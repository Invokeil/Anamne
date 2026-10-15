import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'store/markdown_vault.dart';
import 'store/page_repository.dart';
import 'sync/sync_engine.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AnamneApp(repository: PageRepository.open()));
}

class AnamneApp extends StatelessWidget {
  const AnamneApp({super.key, required this.repository});
  final Future<PageRepository> repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Anamne',
    debugShowCheckedModeBanner: false,
    theme: anamneTheme(),
    home: FutureBuilder<PageRepository>(
      future: repository,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('Could not open local workspace: ${snapshot.error}'),
          )));
        }
        if (!snapshot.hasData) return const BrandLoading();
        return WorkspaceShell(repository: snapshot.data!);
      },
    ),
  );
}

/// Wires the repository to its sync engine and markdown vault once storage
/// is open. Sync works on every platform; the file vault needs a filesystem.
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, required this.repository});
  final PageRepository repository;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  late final SyncEngine syncEngine;
  late final Future<MarkdownVault?> vaultFuture;

  @override
  void initState() {
    super.initState();
    syncEngine = SyncEngine(widget.repository);
    vaultFuture = _openVault();
  }

  Future<MarkdownVault?> _openVault() async {
    final supported = await _vaultSupported();
    if (!supported) return null;
    try {
      final directory = await getApplicationSupportDirectory();
      final stored = await widget.repository.setting('vaultPath') as String?;
      final vault = MarkdownVault(widget.repository,
          stored ?? path.join(directory.path, 'vault'));
      return vault;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _vaultSupported() async => !kIsWeb;

  @override
  void dispose() {
    syncEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MarkdownVault?>(
      future: vaultFuture,
      builder: (context, snapshot) {
        final vault = snapshot.data;
        return Workspace(
          repository: widget.repository,
          syncEngine: syncEngine,
          vault: vault,
        );
      },
    );
  }
}

class BrandLoading extends StatefulWidget {
  const BrandLoading({super.key});
  @override
  State<BrandLoading> createState() => _BrandLoadingState();
}

class _BrandLoadingState extends State<BrandLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(animation: controller, builder: (context, _) {
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          final progress = reduceMotion ? 0.5 : controller.value;
          final breathing = 1 - (2 * progress - 1).abs();
          const size = 92.0;
          const dot = size * 52 / 512;
          return SizedBox(width: size, height: size, child: Stack(children: [
            Positioned.fill(child: Opacity(
              opacity: reduceMotion ? 1 : 0.55 + 0.45 * breathing,
              child: Transform.scale(scale: 0.98 + 0.02 * breathing,
                child: SvgPicture.asset('assets/brand/anamne-loading-mark.svg',
                  semanticsLabel: 'Anamne loading')),
            )),
            Positioned(left: size / 2 - dot / 2, top: size * 356 / 512 - dot / 2,
              width: dot, height: dot, child: Stack(alignment: Alignment.center, children: [
                if (!reduceMotion) Transform.scale(scale: 1 + 2.2 * progress,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: ink.withValues(alpha: 0.6 * (1 - progress))))),
                ),
                Transform.scale(scale: reduceMotion ? 1 : 1 + 0.25 * breathing,
                  child: const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF0B0B0F),
                    shape: BoxShape.circle), child: SizedBox.expand())),
              ])),
          ]));
        }),
        const SizedBox(height: 12),
        const Text('Anamne', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ],
    )),
  );
}
