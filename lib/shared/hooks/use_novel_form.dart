import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class NovelFormController {
  const NovelFormController({
    required this.titleController,
    required this.descriptionController,
    required this.tags,
    required this.addTag,
    required this.removeTag,
    required this.selectedCoverPath,
    required this.setSelectedCoverPath,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final List<String> tags;
  final ValueSetter<String> addTag;
  final ValueSetter<String> removeTag;
  final ValueNotifier<String?> selectedCoverPath;
  final ValueSetter<String?> setSelectedCoverPath;

  String getTagsJson() => jsonEncode(tags);

  void setTagsFromJson(String? json) {
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      tags.clear();
      tags.addAll(list.cast<String>());
    } catch (_) {}
  }
}

NovelFormController useNovelForm() {
  final titleController = useTextEditingController();
  final descriptionController = useTextEditingController();
  final tags = useState<List<String>>([]);
  final selectedCoverPath = useState<String?>(null);

  return NovelFormController(
    titleController: titleController,
    descriptionController: descriptionController,
    tags: tags.value,
    addTag: (tag) {
      final trimmed = tag.trim();
      if (trimmed.isNotEmpty && !tags.value.contains(trimmed)) {
        tags.value = [...tags.value, trimmed];
      }
    },
    removeTag: (tag) {
      tags.value = tags.value.where((t) => t != tag).toList();
    },
    selectedCoverPath: selectedCoverPath,
    setSelectedCoverPath: (value) => selectedCoverPath.value = value,
  );
}
