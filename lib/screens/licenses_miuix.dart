import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../adaptive/miuix_chrome.dart';
import '../widgets/license_data.dart';

class MiuixLicensesPage extends StatefulWidget {
  const MiuixLicensesPage({super.key});

  @override
  State<MiuixLicensesPage> createState() => _MiuixLicensesPageState();
}

class _MiuixLicensesPageState extends State<MiuixLicensesPage> {
  late final Future<List<PackageLicenses>> _licenses = collectLicenses();

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '第三方许可证',
        navigationIcon: miuixBarAction(
          icon: 'back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      content: (padding) {
        return FutureBuilder<List<PackageLicenses>>(
          future: _licenses,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return Padding(
                padding: padding,
                child: const Center(child: MiuixInfiniteProgressIndicator()),
              );
            }
            return ListView(
              padding: padding.add(const EdgeInsets.fromLTRB(12, 0, 12, 32)),
              children: [
                MiuixCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < data.length; i++)
                        MiuixArrowPreference(
                          title: data[i].package,
                          summary: '${data[i].licenses.length} 条许可证',
                          onClick: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    MiuixLicenseDetailPage(item: data[i]),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class MiuixLicenseDetailPage extends StatelessWidget {
  const MiuixLicenseDetailPage({super.key, required this.item});

  final PackageLicenses item;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: item.package,
        navigationIcon: miuixBarAction(
          icon: 'back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      content: (padding) {
        return ListView.builder(
          padding: padding.add(const EdgeInsets.fromLTRB(20, 8, 20, 32)),
          itemCount: item.licenses.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: SelectableText(
                licenseText(item.licenses[index]),
                style: theme.textStyles.body2.copyWith(
                  height: 1.45,
                  decoration: TextDecoration.none,
                  color: theme.colors.onSurface,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
