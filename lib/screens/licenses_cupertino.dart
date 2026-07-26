import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;

import '../widgets/license_data.dart';

/// iOS 风格的第三方许可证列表页。
class CupertinoLicensesPage extends StatefulWidget {
  const CupertinoLicensesPage({super.key});

  @override
  State<CupertinoLicensesPage> createState() => _CupertinoLicensesPageState();
}

class _CupertinoLicensesPageState extends State<CupertinoLicensesPage> {
  late final Future<List<PackageLicenses>> _licenses = collectLicenses();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('第三方许可证')),
      child: SafeArea(
        child: FutureBuilder<List<PackageLicenses>>(
          future: _licenses,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CupertinoActivityIndicator());
            }
            return ListView(
              children: [
                CupertinoListSection.insetGrouped(
                  children: [
                    for (final item in data)
                      CupertinoListTile.notched(
                        title: Text(item.package),
                        additionalInfo: Text('${item.licenses.length}'),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute<void>(
                              builder: (_) =>
                                  CupertinoLicenseDetailPage(item: item),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 单个包的许可证全文。
class CupertinoLicenseDetailPage extends StatelessWidget {
  final PackageLicenses item;

  const CupertinoLicenseDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(item.package)),
      child: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: item.licenses.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: SelectableText(
              licenseText(item.licenses[index]),
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ),
      ),
    );
  }
}
