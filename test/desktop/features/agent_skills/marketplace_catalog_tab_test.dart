// 职责: 验证三种桌面平台的广场搜索、来源打开、导入和刷新布局。
// 关联文件:
//   lib/desktop/features/agent_skills/marketplace_catalog_tab.dart
//   test/shared/widgets/agent_skill/marketplace_test_support.dart
import 'package:flutter/material.dart';
import 'package:reveric/desktop/features/agent_skills/marketplace_catalog_tab.dart';
import '../../../shared/widgets/agent_skill/marketplace_test_support.dart';

void main() => marketplaceInteractionTests([
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
], (onImport) => MarketplaceCatalogTab(onImport: onImport));
