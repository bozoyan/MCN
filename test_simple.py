#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""简单测试程序"""
import sys
from PyQt5.QtWidgets import QApplication, QWidget, QVBoxLayout, QPushButton, QTextEdit, QLabel
from PyQt5.QtCore import Qt, QThread, pyqtSignal
from openai import OpenAI

# API配置
API_KEY = ""

class SimpleTestWorker(QThread):
    """简化的测试工作线程"""
    progress_updated = pyqtSignal(str)
    reasoning_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str, str)

    def __init__(self, content, system_prompt):
        super().__init__()
        self.content = content
        self.system_prompt = system_prompt
        self.is_cancelled = False

    def cancel(self):
        self.is_cancelled = True

    def run(self):
        try:
            self.progress_updated.emit("正在初始化...")

            client = OpenAI(
                base_url='https://api-inference.modelscope.cn/v1',
                api_key=API_KEY,
            )

            self.progress_updated.emit("正在生成...")

            response = client.chat.completions.create(
                model='Qwen/Qwen3-235B-A22B-Thinking-2507',
                messages=[
                    {'role': 'system', 'content': self.system_prompt},
                    {'role': 'user', 'content': self.content}
                ],
                stream=True
            )

            reasoning_text = ""
            final_answer = ""
            update_counter = 0

            for chunk in response:
                if self.is_cancelled:
                    break

                try:
                    if not chunk.choices or len(chunk.choices) == 0:
                        continue

                    choice = chunk.choices[0]
                    if not hasattr(choice, 'delta') or not choice.delta:
                        continue

                    delta = choice.delta
                    reasoning_chunk = getattr(delta, 'reasoning_content', None)
                    answer_chunk = getattr(delta, 'content', None)

                    if reasoning_chunk and reasoning_chunk != '':
                        reasoning_text += reasoning_chunk
                        update_counter += 1
                        # 每30个chunk更新一次，减少频率
                        if update_counter % 30 == 0:
                            self.reasoning_updated.emit(reasoning_text)
                    elif answer_chunk and answer_chunk != '':
                        final_answer += answer_chunk
                        self.progress_updated.emit(f"生成中... 字数: {len(final_answer)}")

                except Exception as e:
                    print(f"错误: {e}")
                    continue

            if not self.is_cancelled:
                if reasoning_text:
                    self.reasoning_updated.emit(reasoning_text)
                self.finished.emit(True, reasoning_text, final_answer)

        except Exception as e:
            self.finished.emit(False, "", f"错误: {str(e)}")


class SimpleTestWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("简单测试")
        self.setGeometry(100, 100, 600, 500)

        layout = QVBoxLayout()

        # 按钮
        self.btn = QPushButton("开始测试")
        self.btn.clicked.connect(self.start_test)
        layout.addWidget(self.btn)

        # 状态
        self.status_label = QLabel("准备就绪")
        layout.addWidget(self.status_label)

        # 思考过程
        self.thinking_edit = QTextEdit()
        self.thinking_edit.setMaximumHeight(200)
        self.thinking_edit.setPlaceholderText("AI思考过程...")
        layout.addWidget(QLabel("思考过程:"))
        layout.addWidget(self.thinking_edit)

        # 结果
        self.result_edit = QTextEdit()
        self.result_edit.setPlaceholderText("生成结果...")
        layout.addWidget(QLabel("结果:"))
        layout.addWidget(self.result_edit)

        self.setLayout(layout)
        self.worker = None

    def start_test(self):
        self.btn.setEnabled(False)
        self.status_label.setText("正在测试...")
        self.thinking_edit.clear()
        self.result_edit.clear()

        content = "你好"
        prompt = "请简单回复并展示你的思考过程。"

        self.worker = SimpleTestWorker(content, prompt)
        self.worker.progress_updated.connect(self.update_progress)
        self.worker.reasoning_updated.connect(self.update_thinking)
        self.worker.finished.connect(self.on_finished)
        self.worker.start()

    def update_progress(self, msg):
        self.status_label.setText(msg)

    def update_thinking(self, text):
        # 限制长度
        if len(text) > 1000:
            text = text[-1000:]
            if not text.startswith("..."):
                text = "..." + text
        self.thinking_edit.setPlainText(text)
        # 滚动到底部
        cursor = self.thinking_edit.textCursor()
        cursor.movePosition(cursor.End)
        self.thinking_edit.setTextCursor(cursor)

    def on_finished(self, success, reasoning, result):
        self.btn.setEnabled(True)
        if success:
            self.status_label.setText("完成!")
            self.result_edit.setPlainText(result)
        else:
            self.status_label.setText(f"失败: {reasoning}")
            self.result_edit.setPlainText(f"错误: {result}")

        if self.worker:
            self.worker.deleteLater()
            self.worker = None


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SimpleTestWindow()
    window.show()
    sys.exit(app.exec_())