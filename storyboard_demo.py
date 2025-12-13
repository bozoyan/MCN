#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 分镜脚本与图片生成器 - 演示版本
基于原始 story.py 功能的 PyQt5 重构版本
"""
import os
import sys
import json
import requests
from datetime import datetime
from io import BytesIO
from PIL import Image
from openai import OpenAI

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QTextEdit, QProgressBar, QMessageBox,
                            QScrollArea, QGroupBox, QFileDialog, QSplitter,
                            QSpinBox, QComboBox, QFormLayout, QDialog,
                            QDialogButtonBox, QTabWidget)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer
from PyQt5.QtGui import QFont, QPixmap, QImage
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, PrimaryPushButton, PushButton,
                          LineEdit, ComboBox, ProgressBar, InfoBar, InfoBarPosition,
                          setTheme, Theme, SmoothScrollArea, CardWidget)

# API 配置
MODEL_API_KEY = os.getenv('MODELSCOPE_SDK_TOKEN')

# 简化版配置管理器
class SimpleConfigManager:
    def __init__(self):
        self.config = {
            "api_key": MODEL_API_KEY or "",
            "text_model": "Qwen/Qwen3-235B-A22B-Thinking-2507",
            "image_model": "bozoyan/F_fei",
            "default_image_count": 9
        }

    def get(self, key, default=None):
        return self.config.get(key, default)
    
    def set(self, key, value):
        self.config[key] = value

config_manager = SimpleConfigManager()

# 文本生成线程
class TextWorker(QThread):
    progress_updated = pyqtSignal(str)
    reasoning_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str, str)

    def __init__(self, content, system_prompt):
        super().__init__()
        self.content = content
        self.system_prompt = system_prompt
        self.is_cancelled = False

    def run(self):
        try:
            self.progress_updated.emit("正在初始化AI模型...")
            
            api_key = config_manager.get('api_key')
            if not api_key:
                self.finished.emit(False, "", "API密钥未配置，请在设置中配置MODELSCOPE_SDK_TOKEN环境变量")
                return

            client = OpenAI(
                base_url='https://api-inference.modelscope.cn/v1/',
                api_key=api_key,
            )

            extra_body = {"enable_thinking": True}
            self.progress_updated.emit("正在生成内容...")
            
            response = client.chat.completions.create(
                model='Qwen/Qwen3-235B-A22B-Thinking-2507',
                messages=[
                    {'role': 'system', 'content': self.system_prompt},
                    {'role': 'user', 'content': self.content}
                ],
                stream=True,
                extra_body=extra_body
            )

            reasoning_text = ""
            final_answer = ""
            done_reasoning = False

            for chunk in response:
                if self.is_cancelled:
                    break

                reasoning_chunk = chunk.choices[0].delta.reasoning_content
                answer_chunk = chunk.choices[0].delta.content

                if reasoning_chunk:
                    reasoning_text += reasoning_chunk
                    self.reasoning_updated.emit(reasoning_text)
                elif answer_chunk:
                    if not done_reasoning:
                        done_reasoning = True
                    final_answer += answer_chunk
                    self.progress_updated.emit(f"生成中... {len(final_answer)} 字符")

            if not self.is_cancelled:
                self.finished.emit(True, reasoning_text, final_answer)
            else:
                self.finished.emit(False, "", "任务已取消")

        except Exception as e:
            self.finished.emit(False, "", f"生成失败: {str(e)}")

# 图片生成线程
class ImageWorker(QThread):
    progress_updated = pyqtSignal(int, str)
    image_generated = pyqtSignal(int, object, str)
    finished = pyqtSignal(bool, list, list)

    def __init__(self, prompts, image_count=9):
        super().__init__()
        self.prompts = prompts
        self.image_count = image_count
        self.images = [None] * image_count
        self.urls = [''] * image_count

    def run(self):
        try:
            api_key = config_manager.get('api_key')
            if not api_key:
                self.finished.emit(False, [], [])
                return

            url = 'https://api-inference.modelscope.cn/v1/images/generations'
            model_id = config_manager.get('image_model', 'bozoyan/F_fei')

            for i in range(min(self.image_count, len(self.prompts))):
                if not self.prompts[i]:
                    continue

                self.progress_updated.emit(int((i / self.image_count) * 80), f"生成第 {i+1} 张图片...")

                payload = {
                    'model': model_id,
                    'prompt': self.prompts[i],
                    'n': 1,
                    'negative_prompt': 'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry,(worst quality:2),(low quality:2),(normal quality:2),lowres,normal quality,((monochrome)),((grayscale)),skin spots,acnes,skin blemishes,age spot,(ugly:1.33),(duplicate:1.33),(morbid:1.21),(mutilated:1.21),(tranny:1.33),mutated hands,(poorly drawn hands:1.5),blurry,(bad anatomy:1.21),(bad proportions:1.33),extra limbs,(disfigured:1.33),(missing arms:1.33),(extra legs:1.33),(fused fingers:1.61),(too many fingers:1.61),(unclear eyes:1.33),lowers,bad hands,missing fingers,extra digit,bad hands,missing fingers,(((extra arms and legs))),DeepNegativeV1.x_V175T,EasyNegative,EasyNegativeV2,',
                    'steps': 30,
                    'guidance': 3.5,
                    'sampler': 'Euler',
                    'size': '900x1600'
                }

                headers = {
                    'Authorization': f'Bearer {api_key}',
                    'Content-Type': 'application/json'
                }

                response = requests.post(
                    url,
                    data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                    headers=headers,
                    timeout=120
                )

                self.progress_updated.emit(int((i / self.image_count) * 80) + 10, f"下载第 {i+1} 张图片...")

                if response.status_code == 200:
                    response_data = response.json()
                    if 'images' in response_data and len(response_data['images']) > 0:
                        image_url = response_data['images'][0]['url']
                        self.urls[i] = image_url

                        img_response = requests.get(image_url, timeout=60)
                        if img_response.status_code == 200:
                            img = Image.open(BytesIO(img_response.content))
                            self.images[i] = img
                            self.image_generated.emit(i, img, image_url)

            self.progress_updated.emit(100, "图片生成完成!")
            self.finished.emit(True, self.images, self.urls)

        except Exception as e:
            self.finished.emit(False, self.images, self.urls)

# 图片预览卡片
class ImageCard(CardWidget):
    def __init__(self, index):
        super().__init__()
        self.index = index
        self.image = None
        self.url = ""
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        self.title_label = QLabel(f"分镜 {self.index + 1}")
        self.title_label.setAlignment(Qt.AlignCenter)
        self.title_label.setStyleSheet("font-weight: bold; color: #666;")
        layout.addWidget(self.title_label)

        self.image_label = QLabel()
        self.image_label.setMinimumSize(200, 200)
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #f9f9f9;")
        self.image_label.setText("等待生成...")
        layout.addWidget(self.image_label)

        self.status_label = QLabel("未生成")
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("color: #999; font-size: 12px;")
        layout.addWidget(self.status_label)

        self.save_btn = PushButton(FluentIcon.DOWNLOAD, "保存")
        self.save_btn.setEnabled(False)
        self.save_btn.clicked.connect(self.save_image)
        layout.addWidget(self.save_btn)

    def set_image(self, image, url):
        self.image = image
        self.url = url
        
        if image:
            pixmap = QPixmap.fromImage(image)
            scaled_pixmap = pixmap.scaled(
                self.image_label.size(),
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation
            )
            self.image_label.setPixmap(scaled_pixmap)
            self.status_label.setText("已生成")
            self.status_label.setStyleSheet("color: #4CAF50; font-size: 12px;")
            self.save_btn.setEnabled(True)
        else:
            self.image_label.setText("生成失败")
            self.status_label.setText("生成失败")
            self.status_label.setStyleSheet("color: #F44336; font-size: 12px;")

    def save_image(self):
        if self.image:
            file_path, _ = QFileDialog.getSaveFileName(
                self, f"保存分镜 {self.index + 1}", 
                f"storyboard_{self.index + 1}.png",
                "PNG Files (*.png);;All Files (*)"
            )
            if file_path:
                try:
                    pil_image = Image.fromqimage(self.image)
                    pil_image.save(file_path)
                    QMessageBox.information(self, "成功", f"图片已保存到: {file_path}")
                except Exception as e:
                    QMessageBox.critical(self, "错误", f"保存失败: {str(e)}")

# 主界面
class StoryboardDemo(QMainWindow):
    def __init__(self):
        super().__init__()
        self.current_titles = []
        self.current_summaries = []
        self.current_prompts = []
        self.image_cards = []
        self.init_ui()

    def init_ui(self):
        self.setWindowTitle("🎬 BOZO-MCN 分镜脚本与图片生成器 v2.0 (Demo)")
        self.setGeometry(100, 100, 1400, 900)

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        layout = QVBoxLayout(central_widget)

        # 标题
        title = SubtitleLabel("🎬 AI分镜脚本与图片生成器")
        title.setFont(QFont("", 18, QFont.Bold))
        layout.addWidget(title)

        # 主要内容区域
        splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(splitter)

        # 左侧：输入和控制
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)

        # 故事内容输入
        content_group = QGroupBox("📝 故事内容")
        content_layout = QVBoxLayout()
        
        self.content_edit = QTextEdit()
        self.content_edit.setPlaceholderText("请输入您的故事内容或创意描述...")
        self.content_edit.setMinimumHeight(150)
        content_layout.addWidget(self.content_edit)
        
        content_group.setLayout(content_layout)
        left_layout.addWidget(content_group)

        # 生成分镜标题
        title_group = QGroupBox("🎭 分镜标题")
        title_layout = QVBoxLayout()
        
        title_btn_layout = QHBoxLayout()
        self.generate_title_btn = PrimaryPushButton(FluentIcon.ADD, "生成分镜标题")
        self.generate_title_btn.clicked.connect(self.generate_titles)
        title_btn_layout.addWidget(self.generate_title_btn)
        
        self.title_progress = ProgressBar()
        self.title_progress.setFixedHeight(8)
        title_btn_layout.addWidget(self.title_progress)
        
        title_layout.addLayout(title_btn_layout)
        
        self.title_output = QTextEdit()
        self.title_output.setPlaceholderText("生成的分镜标题...")
        self.title_output.setMaximumHeight(150)
        title_layout.addWidget(self.title_output)
        
        title_group.setLayout(title_layout)
        left_layout.addWidget(title_group)

        # 生成分镜描述
        summary_group = QGroupBox("📝 分镜描述")
        summary_layout = QVBoxLayout()
        
        summary_btn_layout = QHBoxLayout()
        self.generate_summary_btn = PrimaryPushButton(FluentIcon.EDIT, "生成分镜描述")
        self.generate_summary_btn.clicked.connect(self.generate_summaries)
        summary_btn_layout.addWidget(self.generate_summary_btn)
        
        self.summary_progress = ProgressBar()
        self.summary_progress.setFixedHeight(8)
        summary_btn_layout.addWidget(self.summary_progress)
        
        summary_layout.addLayout(summary_btn_layout)
        
        self.summary_output = QTextEdit()
        self.summary_output.setPlaceholderText("生成的分镜描述...")
        self.summary_output.setMaximumHeight(150)
        summary_layout.addWidget(self.summary_output)
        
        summary_group.setLayout(summary_layout)
        left_layout.addWidget(summary_group)

        left_layout.addStretch()
        splitter.addWidget(left_widget)

        # 右侧：图片生成和预览
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)

        # 图片生成控制
        image_control_group = QGroupBox("🎨 图片生成")
        image_control_layout = QVBoxLayout()
        
        self.generate_all_btn = PrimaryPushButton(FluentIcon.PLAY, "一键生成全部")
        self.generate_all_btn.clicked.connect(self.generate_all)
        image_control_layout.addWidget(self.generate_all_btn)
        
        self.image_progress = ProgressBar()
        self.image_progress.setFixedHeight(8)
        image_control_layout.addWidget(self.image_progress)
        
        self.image_status = QLabel("准备就绪")
        image_control_layout.addWidget(self.image_status)
        
        image_control_group.setLayout(image_control_layout)
        right_layout.addWidget(image_control_group)

        # 图片预览区域
        preview_group = QGroupBox("🖼️ 图片预览")
        preview_layout = QVBoxLayout()
        
        scroll_area = ScrollArea()
        scroll_widget = QWidget()
        self.image_grid = QGridLayout(scroll_widget)
        
        self.init_image_cards()
        
        scroll_area.setWidget(scroll_widget)
        scroll_area.setWidgetResizable(True)
        preview_layout.addWidget(scroll_area)
        
        preview_group.setLayout(preview_layout)
        right_layout.addWidget(preview_group)

        # 导出按钮
        export_btn = PrimaryPushButton(FluentIcon.SAVE, "导出Markdown")
        export_btn.clicked.connect(self.export_markdown)
        right_layout.addWidget(export_btn)

        right_layout.addStretch()
        splitter.addWidget(right_widget)
        
        splitter.setSizes([700, 700])

    def init_image_cards(self):
        """初始化图片卡片"""
        for i in range(9):
            card = ImageCard(i)
            self.image_cards.append(card)
            row = i // 3
            col = i % 3
            self.image_grid.addWidget(card, row, col)

    def generate_titles(self):
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请输入故事内容")
            return

        system_prompt = """你是一位专业的故事绘本撰写专家，擅长电影级别的故事绘本脚本编辑。请根据用户提供的一段话或一个叙事事件内容，展开联想拓展形成一个完整的故事情节。通过故事情节的时间线拆解生成从头到尾9个完整吸引人的故事绘本分镜标题脚本。每个分镜脚本标题控制在64字以内，分镜脚本标题需要有景别，视角，运镜，画面内容，遵循主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言+价值主张的原则。
    分镜脚本标题应该具有吸引力，精炼，能够引起观看者的兴趣，同时准确反映该分镜的核心内容。"""

        self.generate_title_btn.setEnabled(False)
        self.title_progress.setValue(0)

        worker = TextWorker(content, system_prompt)
        worker.progress_updated.connect(lambda msg: self.title_progress.setValue(50))
        worker.finished.connect(self.on_titles_finished)
        worker.start()

    def on_titles_finished(self, success, reasoning, result):
        self.generate_title_btn.setEnabled(True)
        self.title_progress.setValue(100 if success else 0)

        if success:
            self.title_output.setText(result)
            # 解析标题
            titles = [t.strip() for t in result.split('\n') if t.strip()]
            self.current_titles = titles[:9] + [''] * (9 - len(titles))
            QMessageBox.information(self, "成功", "分镜标题生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")

    def generate_summaries(self):
        titles_text = self.title_output.toPlainText().strip()
        if not titles_text:
            QMessageBox.warning(self, "警告", "请先生成分镜标题")
            return

        system_prompt = """你是一位专业的短视频脚本描述专家，擅长电影级别的视频脚本编辑描述。请根据用户提供的故事绘本分镜脚本标题，按批次生成该脚本片段短视频描述，每个片段按序号生成一段丰富的视频脚本描述文字，每个分镜脚本描述控制在120字以内。"""

        self.generate_summary_btn.setEnabled(False)
        self.summary_progress.setValue(0)

        worker = TextWorker(titles_text, system_prompt)
        worker.progress_updated.connect(lambda msg: self.summary_progress.setValue(50))
        worker.finished.connect(self.on_summaries_finished)
        worker.start()

    def on_summaries_finished(self, success, reasoning, result):
        self.generate_summary_btn.setEnabled(True)
        self.summary_progress.setValue(100 if success else 0)

        if success:
            self.summary_output.setText(result)
            # 解析描述
            summaries = [s.strip() for s in result.split('\n') if s.strip()]
            self.current_summaries = summaries[:9] + [''] * (9 - len(summaries))
            QMessageBox.information(self, "成功", "分镜描述生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")

    def generate_all(self):
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请输入故事内容")
            return

        self.generate_all_btn.setEnabled(False)
        
        # 生成图片提示词并生成图片
        prompts = []
        for i in range(9):
            if i < len(self.current_summaries) and self.current_summaries[i]:
                # 简化的提示词生成
                prompt = f"Create an image based on: {self.current_summaries[i]}, Face the camera, showing the upper body, high quality, detailed, cinematic lighting"
                prompts.append(prompt)
            else:
                prompts.append("")

        self.current_prompts = prompts
        self.start_image_generation()

    def start_image_generation(self):
        """开始图片生成"""
        self.image_progress.setValue(0)
        self.image_status.setText("开始生成图片...")

        # 重置图片卡片
        for card in self.image_cards:
            card.set_image(None, "")
            card.status_label.setText("等待中...")

        worker = ImageWorker(self.current_prompts)
        worker.progress_updated.connect(self.on_image_progress)
        worker.image_generated.connect(self.on_image_generated)
        worker.finished.connect(self.on_images_finished)
        worker.start()

    def on_image_progress(self, value, message):
        self.image_progress.setValue(value)
        self.image_status.setText(message)

    def on_image_generated(self, index, image, url):
        if index < len(self.image_cards):
            # 转换PIL Image到QImage
            qimage = QImage(image.tobytes(), image.size[0], image.size[1], QImage.Format_RGB888)
            self.image_cards[index].set_image(qimage, url)

    def on_images_finished(self, success, images, urls):
        self.generate_all_btn.setEnabled(True)
        if success:
            QMessageBox.information(self, "完成", "图片生成完成！")
        else:
            QMessageBox.warning(self, "警告", "图片生成完成，但部分图片可能失败")

    def export_markdown(self):
        if not self.current_titles and not self.current_summaries:
            QMessageBox.warning(self, "警告", "没有可导出的内容")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self, "导出Markdown", 
            f"storyboard_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md",
            "Markdown Files (*.md)"
        )

        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write("# 🎬 AI分镜脚本与配图\n\n")
                    f.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
                    f.write("---\n\n")

                    for i in range(9):
                        f.write(f"## 📺 分镜 {i+1}\n\n")
                        
                        if i < len(self.current_titles) and self.current_titles[i]:
                            f.write(f"**🎭 分镜标题:** {self.current_titles[i]}\n\n")
                        
                        if i < len(self.current_summaries) and self.current_summaries[i]:
                            f.write(f"**📝 分镜描述:** {self.current_summaries[i]}\n\n")
                        
                        if i < len(self.current_prompts) and self.current_prompts[i]:
                            f.write(f"**🎨 AI绘图提示词:** {self.current_prompts[i]}\n\n")
                        
                        if i < len(self.image_cards) and self.image_cards[i].url:
                            f.write(f"**🖼️ 图片:**\n")
                            f.write(f"![分镜{i+1}]({self.image_cards[i].url})\n\n")
                        
                        f.write("---\n\n")

                QMessageBox.information(self, "成功", f"Markdown文件已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"导出失败: {str(e)}")

def main():
    # 设置高DPI支持
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    app = QApplication(sys.argv)
    app.setApplicationName("BOZO-MCN分镜生成器")
    app.setApplicationVersion("2.0")

    # 设置主题
    setTheme(Theme.DARK)

    # 检查API密钥
    if not MODEL_API_KEY:
        QMessageBox.warning(None, "API密钥未配置", 
                          "ModelScope API密钥未配置。\n请设置环境变量 MODELSCOPE_SDK_TOKEN 或在代码中配置。")

    window = StoryboardDemo()
    window.show()

    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
