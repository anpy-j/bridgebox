import 'package:flutter/material.dart';
import '../services/remote_ops.dart';
import 'workspace/overview_tab.dart';
import 'workspace/services_tab.dart';
import 'workspace/containers_tab.dart';
import 'workspace/images_tab.dart';

export 'workspace/overview_tab.dart';
export 'workspace/services_tab.dart';
export 'workspace/containers_tab.dart';
export 'workspace/images_tab.dart';

class WorkspaceTabs extends StatelessWidget {
  const WorkspaceTabs({super.key, required this.ops, required this.index});

  final RemoteOps ops;
  final int index;

  @override
  Widget build(BuildContext context) {
    return switch (index) {
      0 => OverviewTab(ops: ops),
      1 => ServicesTab(ops: ops),
      2 => ContainersTab(ops: ops),
      _ => ImagesTab(ops: ops),
    };
  }
}
