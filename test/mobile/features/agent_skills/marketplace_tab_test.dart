// 职责: 验证 Android 窄屏广场的搜索、来源打开、导入和刷新布局。
// 关联文件:
//   lib/mobile/features/agent_skills/marketplace_tab.dart
//   test/shared/widgets/agent_skill/marketplace_test_support.dart
import 'package:flutter/material.dart';
import 'package:reveric/mobile/features/agent_skills/marketplace_tab.dart';
import '../../../shared/widgets/agent_skill/marketplace_test_support.dart';

void main() => marketplaceInteractionTests([
  TargetPlatform.android,
], (onImport) => MarketplaceAgentSkillTab(onImport: onImport));
