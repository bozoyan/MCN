#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""调试程序 - 检查TextGenerationWorker问题"""
import sys
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QTimer
import threading
import time

# 模拟导入主要组件
sys.path.insert(0, '/Volumes/AI/AI/MCN')

def test_worker_thread():
    """测试工作线程是否正常"""
    from storyboard_generator import TextGenerationWorker

    app = QApplication(sys.argv)

    # 创建测试变量
    results = []
    errors = []

    def on_progress(msg):
        print(f"Progress: {msg}")

    def on_reasoning(text):
        print(f"Reasoning updated: {len(text)} chars")

    def on_finished(success, reasoning, result):
        print(f"Finished - Success: {success}")
        if success:
            print(f"Result length: {len(result)} chars")
        else:
            print(f"Error: {result}")
        results.append((success, reasoning, result))
        app.quit()

    # 创建工作线程
    worker = TextGenerationWorker(
        content="你好",
        system_prompt="请简单回复并展示思考过程。"
    )

    # 连接信号
    worker.progress_updated.connect(on_progress)
    worker.reasoning_updated.connect(on_reasoning)
    worker.finished.connect(on_finished)

    print("Starting worker thread...")
    worker.start()

    # 设置超时
    QTimer.singleShot(30000, app.quit)  # 30秒超时

    # 运行应用
    return app.exec_()

if __name__ == "__main__":
    print("Testing TextGenerationWorker...")
    exit_code = test_worker_thread()
    print(f"Exit code: {exit_code}")