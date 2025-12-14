#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试模板管理功能
"""

import sys
import os

# 添加当前目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 导入配置管理器
from storyboard_generator import config_manager

def test_template_management():
    """测试模板管理功能"""
    print("🧪 测试模板管理功能...")

    # 1. 获取初始模板
    print("\n1. 初始模板列表:")
    templates = config_manager.get('prompt_templates', {})
    for key, template in templates.items():
        print(f"  - {key}: {template.get('name', 'N/A')}")

    # 2. 测试模板分类
    print("\n2. 模板分类测试:")
    types = ['story_title', 'story_summary', 'image_prompt']
    for template_type in types:
        type_templates = {k: v for k, v in templates.items() if k.startswith(template_type)}
        print(f"  {template_type}: {len(type_templates)} 个模板")
        for key, template in type_templates.items():
            print(f"    - {template.get('name', key)}")

    # 3. 测试添加新模板
    print("\n3. 测试添加新模板:")
    test_template = {
        'name': '测试模板',
        'template': '这是一个测试模板内容'
    }

    if config_manager.save_template('story_title_test_template', test_template):
        print("  ✅ 新模板保存成功")
    else:
        print("  ❌ 新模板保存失败")

    # 4. 验证新模板
    print("\n4. 验证新模板:")
    templates_after = config_manager.get('prompt_templates', {})
    if 'story_title_test_template' in templates_after:
        print("  ✅ 新模板已添加")
        saved_template = templates_after['story_title_test_template']
        print(f"    名称: {saved_template.get('name')}")
        print(f"    内容: {saved_template.get('template')[:50]}...")
    else:
        print("  ❌ 新模板未找到")

    # 5. 测试删除模板
    print("\n5. 测试删除模板:")
    templates = config_manager.get('prompt_templates', {})
    if 'story_title_test_template' in templates:
        del templates['story_title_test_template']
        config_manager.set('prompt_templates', templates)
        config_manager.save_config()
        print("  ✅ 测试模板已删除")
    else:
        print("  ❌ 测试模板未找到，无法删除")

    print("\n✅ 模板管理功能测试完成!")

if __name__ == "__main__":
    test_template_management()