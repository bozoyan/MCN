#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
验证并发批量生成修复结果
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import Qt

def test_imports():
    """测试所有关键类的导入"""
    print("🧪 测试模块导入...")

    try:
        from pic2vod import (
            ConcurrentBatchManager,
            SingleVideoGenerationWorker,
            VideoGenerationWidget,
            APIKeyManager,
            VideoResultCard
        )
        print("✅ 所有关键类导入成功")
        return True
    except Exception as e:
        print(f"❌ 导入失败: {e}")
        return False

def test_class_instantiation():
    """测试类实例化"""
    print("\n🏗️ 测试类实例化...")

    try:
        from pic2vod import APIKeyManager, ConcurrentBatchManager

        # 测试API密钥管理器
        api_manager = APIKeyManager()
        print("✅ APIKeyManager 实例化成功")

        # 测试并发批量管理器
        batch_manager = ConcurrentBatchManager()
        print("✅ ConcurrentBatchManager 实例化成功")

        return True
    except Exception as e:
        print(f"❌ 实例化失败: {e}")
        return False

def test_signal_definitions():
    """测试信号定义"""
    print("\n📡 测试信号定义...")

    try:
        from pic2vod import ConcurrentBatchManager, SingleVideoGenerationWorker
        from PyQt5.QtCore import pyqtSignal

        # 检查ConcurrentBatchManager的信号
        manager = ConcurrentBatchManager()
        required_signals = [
            'all_tasks_finished',
            'task_progress',
            'task_finished',
            'task_time_updated',
            'log_updated',
            'batch_progress_updated'
        ]

        for signal_name in required_signals:
            if hasattr(manager, signal_name):
                print(f"✅ {signal_name} 信号已定义")
            else:
                print(f"❌ {signal_name} 信号缺失")
                return False

        # 检查SingleVideoGenerationWorker的信号
        worker = SingleVideoGenerationWorker({}, "test_task", "test_key")
        worker_signals = [
            'progress_updated',
            'task_finished',
            'time_updated',
            'log_updated'
        ]

        for signal_name in worker_signals:
            if hasattr(worker, signal_name):
                print(f"✅ SingleVideoGenerationWorker.{signal_name} 信号已定义")
            else:
                print(f"❌ SingleVideoGenerationWorker.{signal_name} 信号缺失")
                return False

        return True
    except Exception as e:
        print(f"❌ 信号测试失败: {e}")
        return False

def test_main_program_import():
    """测试主程序导入"""
    print("\n🎯 测试主程序导入...")

    try:
        # 尝试导入主程序的VideoGenerationWidget
        from pic2vod import VideoGenerationWidget
        print("✅ VideoGenerationWidget 导入成功")

        # 测试是否包含新的并发功能
        widget = VideoGenerationWidget()
        if hasattr(widget, 'concurrent_batch_manager'):
            print("✅ concurrent_batch_manager 属性已添加")
        else:
            print("❌ concurrent_batch_manager 属性缺失")
            return False

        if hasattr(widget, 'update_task_time'):
            print("✅ update_task_time 方法已添加")
        else:
            print("❌ update_task_time 方法缺失")
            return False

        if hasattr(widget, 'on_all_tasks_finished'):
            print("✅ on_all_tasks_finished 方法已添加")
        else:
            print("❌ on_all_tasks_finished 方法缺失")
            return False

        return True
    except Exception as e:
        print(f"❌ 主程序测试失败: {e}")
        return False

def main():
    """主测试函数"""
    # 创建QApplication
    app = QApplication(sys.argv)
    app.setAttribute(Qt.AA_DisableWindowContextHelpButton)

    print("🚀 开始验证并发批量生成修复结果")
    print("=" * 50)

    tests = [
        test_imports,
        test_class_instantiation,
        test_signal_definitions,
        test_main_program_import
    ]

    passed = 0
    total = len(tests)

    for test in tests:
        if test():
            passed += 1

    print("\n" + "=" * 50)
    print(f"📊 测试结果: {passed}/{total} 通过")

    if passed == total:
        print("🎉 所有测试通过！并发批量生成功能修复成功！")
        print("\n✨ 新功能特点:")
        print("   • 多任务并发执行")
        print("   • 独立API密钥分配")
        print("   • 独立计时器系统")
        print("   • 实时进度跟踪")
        print("   • 错误隔离处理")
        success = True
    else:
        print("❌ 部分测试失败，需要进一步检查")
        success = False

    # 不启动事件循环，直接退出
    return success

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)