import os
import time
import sys
import re
import shutil
import subprocess
import requests
import json
import logging
import platform
import webbrowser
from datetime import datetime
from pathlib import Path
from PIL import Image
import chardet
from concurrent.futures import ThreadPoolExecutor
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QCheckBox,
                            QComboBox, QSpinBox, QProgressBar, QMessageBox,
                            QSplitter, QFrame, QScrollArea, QGroupBox, QDoubleSpinBox,
                            QMenu, QAction, QDialog, QFormLayout, QDialogButtonBox,
                            QStackedWidget, QTableWidget, QTableWidgetItem, QHeaderView,
                            QSizePolicy)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl, QSize, QRunnable, QThreadPool, QObject, pyqtSlot as Slot
from PyQt5.QtGui import QFont, QIcon, QDesktopServices, QColor, QCursor
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, CheckBox, SpinBox,
                          ProgressBar, InfoBar, InfoBarPosition, ToolTipFilter,
                          setTheme, Theme, FluentIcon as FIcon, FluentIcon as FIF,
                          SmoothScrollArea, Pivot, TableWidget, SegmentedWidget,
                          TextEdit, SimpleCardWidget, RoundMenu, Action)

# 配置常量 - 使用系统默认字体
TITLE_FONT = QFont()
TITLE_FONT.setPointSize(16)
LABEL_FONT = QFont()
LABEL_FONT.setPointSize(12)
ENTRY_FONT = QFont()
ENTRY_FONT.setPointSize(10)

# 工作线程类
class WorkerThread(QThread):
    """工作线程基类"""
    progress_updated = pyqtSignal(int)
    log_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str)

    def __init__(self):
        super().__init__()
        self.is_cancelled = False

class VideoConversionThread(WorkerThread):
    """视频转换线程"""

    def __init__(self, video_path, output_path, mode="mute"):
        super().__init__()
        self.video_path = video_path
        self.output_path = output_path
        self.mode = mode

    def run(self):
        try:
            if self.mode == "mute":
                cmd = ["ffmpeg", "-y", "-i", self.video_path, "-an", self.output_path]
            elif self.mode == "audio":
                cmd = ["ffmpeg", "-y", "-i", self.video_path, "-vn", "-acodec", "pcm_s16le", self.output_path]

            self.log_updated.emit(f"开始处理: {os.path.basename(self.video_path)}")

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                self.finished.emit(False, f"处理失败: {result.stderr}")
        except Exception as e:
            self.finished.emit(False, f"处理异常: {str(e)}")

class ImageToVideoThread(WorkerThread):
    """图片转视频线程"""

    def __init__(self, image_path, output_path, size, duration):
        super().__init__()
        self.image_path = image_path
        self.output_path = output_path
        self.size = size
        self.duration = duration

    def run(self):
        try:
            width, height = self.size.split('x')
            fps = 30
            img_name = os.path.splitext(os.path.basename(self.image_path))[0]
            temp_dir = os.path.join(os.getcwd(), 'temp')
            bg_img = os.path.join(temp_dir, f"{img_name}-bg.jpg")

            self.progress_updated.emit(10)

            # 生成模糊背景
            cmd_bg = [
                "ffmpeg", "-y", "-loop", "1", "-framerate", str(fps), "-t", str(self.duration),
                "-i", self.image_path,
                "-vf", f"scale=2*{width}:2*{height},boxblur=20:1,crop={width}:{height}",
                "-q:v", "3", bg_img
            ]
            subprocess.run(cmd_bg)

            self.progress_updated.emit(50)

            # 合成前景+背景
            filter_complex = (
                f"[0:v]scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=rgba[fg];"
                f"[1:v]scale={width}:{height}[bg];"
                f"[bg][fg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=1,fade=t=out:st={self.duration-1}:d=1"
            )
            cmd = [
                "ffmpeg", "-y",
                "-loop", "1", "-framerate", str(fps), "-t", str(self.duration), "-i", self.image_path,
                "-i", bg_img,
                "-filter_complex", filter_complex,
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-r", str(fps),
                self.output_path
            ]

            subprocess.run(cmd)

            self.progress_updated.emit(100)
            self.log_updated.emit(f"生成完成: {os.path.basename(self.output_path)}")
            self.finished.emit(True, self.output_path)

        except Exception as e:
            self.finished.emit(False, f"转换异常: {str(e)}")

class SRTGenerationThread(WorkerThread):
    """字幕生成线程"""

    def __init__(self, audio_path, output_path, max_line_length=30):
        super().__init__()
        self.audio_path = audio_path
        self.output_path = output_path
        self.max_line_length = max_line_length

    def run(self):
        try:
            self.progress_updated.emit(10)
            self.log_updated.emit(f"开始处理: {os.path.basename(self.audio_path)}")

            # 检查音频格式并转换
            ext = os.path.splitext(self.audio_path)[1].lower()
            wav_path = self.audio_path
            
            srt_dir = os.path.join(os.getcwd(), 'SRT')
            os.makedirs(srt_dir, exist_ok=True)
            
            if ext != ".wav":
                base_name = os.path.splitext(os.path.basename(self.audio_path))[0]
                ts = datetime.now().strftime("%Y%m%d%H%M")
                wav_path = os.path.join(srt_dir, f"{base_name}-{ts}.wav")

                self.log_updated.emit("正在转换音频为WAV格式...")
                cmd_ffmpeg = ["ffmpeg", "-y", "-i", self.audio_path, wav_path]
                result = subprocess.run(cmd_ffmpeg, capture_output=True, text=True)
                if result.returncode != 0:
                    self.finished.emit(False, f"音频转换失败: {result.stderr}")
                    return

            self.progress_updated.emit(30)

            # whisper.cpp命令
            aipath = os.environ.get("AIPATH")
            if not aipath:
                self.finished.emit(False, "未检测到AIPATH AI目录变量")
                return
            whisper_bin = os.path.join(aipath, "whisper.cpp/build/bin/whisper-cli")
            whisper_model = os.path.join(aipath, "whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin")
            
            if not os.path.exists(whisper_bin):
                self.finished.emit(False, f"找不到whisper程序: {whisper_bin}")
                return
            if not os.path.exists(whisper_model):
                self.finished.emit(False, f"找不到whisper模型: {whisper_model}")
                return

            of_path = os.path.splitext(self.output_path)[0]
            threads = os.cpu_count() or 4

            cmd_whisper = [
                whisper_bin,
                "-m", whisper_model,
                "-f", wav_path,
                "-l", "zh",
                "-ml", str(self.max_line_length),
                "-osrt",
                "-of", of_path,
                "-t", str(threads),
            ]

            self.log_updated.emit("正在生成字幕(Whisper)...")
            
            # 使用更可靠的 shell 命令执行方式
            shell_cmd = f"source ~/.zshrc && conda activate modelscope && {' '.join(cmd_whisper)}"
            
            # 记录执行的命令（隐藏敏感信息如果需要，这里主要是本地路径）
            print(f"Executing: {shell_cmd}")
            
            result = subprocess.run(shell_cmd, shell=True, capture_output=True, text=True, executable="/bin/zsh")

            self.progress_updated.emit(80)

            # 检查输出文件
            if os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"字幕生成完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                # 尝试查找可能的副作用文件（例如 .srt.srt）
                potential_path = of_path + ".srt.srt"
                if os.path.exists(potential_path):
                     os.rename(potential_path, self.output_path)
                     self.progress_updated.emit(100)
                     self.log_updated.emit(f"字幕生成完成: {os.path.basename(self.output_path)}")
                     self.finished.emit(True, self.output_path)
                else:
                    error_msg = result.stderr if result.stderr else result.stdout
                    self.finished.emit(False, f"字幕生成失败: {error_msg[:200]}")

        except Exception as e:
            self.finished.emit(False, f"字幕生成异常: {str(e)}")

class SRTToTextThread(WorkerThread):
    """SRT转文本线程"""

    def __init__(self, srt_path, output_path):
        super().__init__()
        self.srt_path = srt_path
        self.output_path = output_path

    def run(self):
        try:
            self.progress_updated.emit(10)

            # 检测编码
            with open(self.srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'

            self.progress_updated.emit(30)

            lines = []
            for line in raw.decode(enc, errors='replace').splitlines():
                line = line.strip()
                if line.isdigit():
                    continue
                if re.match(r"\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}", line):
                    continue
                if not line:
                    continue
                lines.append(line)

            merged_text = ''.join(lines)

            with open(self.output_path, 'w', encoding='utf-8') as f:
                f.write(merged_text)

            self.progress_updated.emit(100)
            self.finished.emit(True, self.output_path)

        except Exception as e:
            self.finished.emit(False, f"SRT转文本异常: {str(e)}")

class SRTTranslateThread(WorkerThread):
    """SRT翻译线程"""

    def __init__(self, srt_path, output_path, target_language="English"):
        super().__init__()
        self.srt_path = srt_path
        self.output_path = output_path
        self.target_language = target_language

    def run(self):
        try:
            self.progress_updated.emit(10)

            # 检测编码
            with open(self.srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'

            srt_content = raw.decode(enc, errors='replace')

            self.progress_updated.emit(30)

            # API翻译
            api_key = os.environ.get("SiliconCloud_API_KEY")
            if not api_key:
                self.finished.emit(False, "未检测到API KEY")
                return

            url = "https://api.siliconflow.cn/v1/chat/completions"
            prompt = f"帮我将输入的srt字幕文本内容翻译转换为{self.target_language}。保持srt文本结构，序号，时间都不变，只需要翻译内容，并输出srt格式的翻译内容就可以，不需要其他额外注释和说明。\n\n" + srt_content

            payload = {
                "model": "Qwen/Qwen3-Next-80B-A3B-Instruct",
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
                "max_tokens": 8192,
                "response_format": {"type": "text"}
            }

            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }

            self.progress_updated.emit(50)
            resp = requests.post(url, json=payload, headers=headers, timeout=120)

            if resp.status_code == 200:
                result = resp.json()
                content = result.get("choices", [{}])[0].get("message", {}).get("content", "").strip()

                if content:
                    with open(self.output_path, 'w', encoding='utf-8') as f:
                        f.write(content)
                    self.progress_updated.emit(100)
                    self.finished.emit(True, self.output_path)
                else:
                    self.finished.emit(False, "API未返回有效翻译内容")
            else:
                self.finished.emit(False, f"API请求失败: {resp.text}")

        except Exception as e:
            self.finished.emit(False, f"翻译异常: {str(e)}")

class AudioCoverExtractThread(WorkerThread):
    """音频封面提取线程"""

    def __init__(self, audio_path, output_path):
        super().__init__()
        self.audio_path = audio_path
        self.output_path = output_path

    def run(self):
        try:
            self.progress_updated.emit(10)
            self.log_updated.emit(f"开始提取: {os.path.basename(self.audio_path)}")

            # 使用ffmpeg提取音频封面
            cmd = [
                "ffmpeg", "-y", "-i", self.audio_path,
                "-an",  # 禁用音频输出
                self.output_path
            ]

            result = subprocess.run(cmd, capture_output=True, text=True)

            self.progress_updated.emit(80)

            # 检查输出文件是否真的生成了
            if result.returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"封面提取完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                # 如果没有找到封面流，删除可能生成的空文件
                if os.path.exists(self.output_path):
                    os.remove(self.output_path)
                self.finished.emit(False, f"未发现封面: {os.path.basename(self.audio_path)}")

        except Exception as e:
            self.finished.emit(False, f"封面提取异常: {str(e)}")

class VideoFrameExtractThread(WorkerThread):
    """视频帧提取线程"""

    def __init__(self, video_path, output_path, frame_type="first", custom_time="00:00:00"):
        super().__init__()
        self.video_path = video_path
        self.output_path = output_path
        self.frame_type = frame_type  # first, last, custom
        self.custom_time = custom_time

    def run(self):
        try:
            self.progress_updated.emit(10)
            self.log_updated.emit(f"开始提取: {os.path.basename(self.video_path)}")

            # 如果是尾帧，需要先获取视频时长
            timestamp = self.custom_time
            if self.frame_type == "last":
                # 获取视频时长
                cmd_probe = [
                    "ffprobe", "-v", "error", "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1", self.video_path
                ]
                result = subprocess.run(cmd_probe, capture_output=True, text=True)
                try:
                    duration = float(result.stdout.strip())
                    # 尾帧时间点为总时长-1秒
                    timestamp = str(int(duration - 1))
                    # 格式化为 HH:MM:SS
                    hours = int(timestamp) // 3600
                    minutes = (int(timestamp) % 3600) // 60
                    seconds = int(timestamp) % 60
                    timestamp = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
                except ValueError:
                    timestamp = "00:00:05"
            elif self.frame_type == "first":
                timestamp = "00:00:00"

            # 使用ffmpeg提取指定帧
            cmd = [
                "ffmpeg", "-y", "-i", self.video_path,
                "-ss", timestamp,
                "-vframes", "1",
                "-q:v", "2",  # 图片质量（1-31，1质量最高）
                self.output_path
            ]

            result = subprocess.run(cmd, capture_output=True, text=True)

            self.progress_updated.emit(80)

            if result.returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                frame_label = "_首帧" if self.frame_type == "first" else ("_尾帧" if self.frame_type == "last" else f"_{self.custom_time}")
                self.log_updated.emit(f"帧提取完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                self.finished.emit(False, f"帧提取失败: {result.stderr}")

        except Exception as e:
            self.finished.emit(False, f"帧提取异常: {str(e)}")

# 功能页面类
class BasePage(QWidget):
    """页面基类"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.worker_threads = []
        self.thread_pool = ThreadPoolExecutor(max_workers=4)

    def show_info(self, title, message):
        """显示信息"""
        InfoBar.info(title=title, content=message, orient=Qt.Horizontal,
                    isClosable=True, position=InfoBarPosition.TOP, duration=3000, parent=self)

    def show_success(self, title, message):
        """显示成功信息"""
        InfoBar.success(title=title, content=message, orient=Qt.Horizontal,
                      isClosable=True, position=InfoBarPosition.TOP, duration=3000, parent=self)

    def show_error(self, title, message):
        """显示错误信息"""
        InfoBar.error(title=title, content=message, orient=Qt.Horizontal,
                    isClosable=True, position=InfoBarPosition.TOP, duration=5000, parent=self)

    def show_warning(self, title, message):
        """显示警告信息"""
        InfoBar.warning(title=title, content=message, orient=Qt.Horizontal,
                      isClosable=True, position=InfoBarPosition.TOP, duration=4000, parent=self)

    def get_file_path(self, title, filter_str):
        """获取文件路径"""
        file_path, _ = QFileDialog.getOpenFileName(self, title, "", filter_str)
        return file_path

    def get_folder_path(self, title):
        """获取文件夹路径"""
        folder_path = QFileDialog.getExistingDirectory(self, title)
        return folder_path

class ButtonEditDialog(QDialog):
    """按钮编辑对话框"""

    def __init__(self, button_data=None, parent=None):
        super().__init__(parent)
        self.button_data = button_data or {}
        self.setWindowTitle("编辑按钮" if button_data else "新增按钮")
        self.setMinimumWidth(500)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        # 辅助函数：创建带标签的输入框
        def create_field(label_text, widget):
            field_layout = QVBoxLayout()
            field_layout.setSpacing(5)
            label = QLabel(label_text)
            label.setStyleSheet("font-size: 14px; font-weight: bold;")
            field_layout.addWidget(label)
            field_layout.addWidget(widget)
            return field_layout

        # 按钮标题
        self.title_edit = LineEdit()
        self.title_edit.setText(self.button_data.get("title", ""))
        self.title_edit.setFixedHeight(35)
        layout.addLayout(create_field("按钮标题:", self.title_edit))

        # Conda 环境
        self.env_edit = LineEdit()
        self.env_edit.setText(self.button_data.get("env", "") or "")
        self.env_edit.setPlaceholderText("留空表示不使用 conda，或输入环境名如 modelscope")
        self.env_edit.setFixedHeight(35)
        layout.addLayout(create_field("Conda 环境:", self.env_edit))

        # 工作目录
        self.cwd_edit = LineEdit()
        self.cwd_edit.setText(self.button_data.get("cwd", "."))
        self.cwd_edit.setPlaceholderText("当前目录用 . 表示")
        self.cwd_edit.setFixedHeight(35)
        layout.addLayout(create_field("工作目录:", self.cwd_edit))

        # 执行命令
        self.cmd_edit = QTextEdit()
        self.cmd_edit.setPlainText(self.button_data.get("cmd", ""))
        self.cmd_edit.setMinimumHeight(100)
        # 用样式表统一样式（如果 LineEdit 有特定样式）
        self.cmd_edit.setStyleSheet("border: 1px solid rgba(0, 0, 0, 0.1); border-radius: 5px; padding: 5px;")
        layout.addLayout(create_field("执行命令:", self.cmd_edit))

        layout.addStretch()

        # 按钮
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def get_data(self):
        """获取编辑后的数据"""
        return {
            "title": self.title_edit.text().strip(),
            "env": self.env_edit.text().strip() or None,
            "cwd": self.cwd_edit.text().strip() or ".",
            "cmd": self.cmd_edit.toPlainText().strip()
        }

class HomePage(BasePage):
    """首页 - AIGC 操作管理平台"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.buttons_file = os.path.join(os.path.dirname(__file__), "buttons.json")
        self.buttons_data = []
        self.load_buttons()
        self.init_ui()

    def load_buttons(self):
        """从 JSON 文件加载按钮配置"""
        try:
            if os.path.exists(self.buttons_file):
                with open(self.buttons_file, 'r', encoding='utf-8') as f:
                    self.buttons_data = json.load(f)
            else:
                self.buttons_data = []
                self.save_buttons()
        except Exception as e:
            self.buttons_data = []
            print(f"加载按钮配置失败: {str(e)}")

    def save_buttons(self):
        """保存按钮配置到 JSON 文件"""
        try:
            with open(self.buttons_file, 'w', encoding='utf-8') as f:
                json.dump(self.buttons_data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存按钮配置失败: {str(e)}")

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🚀 AIGC 操作管理平台")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 创建滚动区域
        scroll = SmoothScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll_widget = QWidget()
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setContentsMargins(20, 20, 20, 20)

        # 按钮网格容器
        self.button_grid_widget = QWidget()
        self.button_grid_layout = QGridLayout(self.button_grid_widget)
        self.button_grid_layout.setSpacing(24) # 增加间距
        scroll_layout.addWidget(self.button_grid_widget)

        scroll_layout.addStretch()
        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        # 底部按钮
        bottom_layout = QHBoxLayout()
        add_btn = PrimaryPushButton(FluentIcon.ADD, "添加新按钮")
        add_btn.setFixedHeight(40)
        add_btn.clicked.connect(self.add_button)
        bottom_layout.addWidget(add_btn)

        refresh_btn = PushButton(FluentIcon.SYNC, "刷新按钮")
        refresh_btn.setFixedHeight(40)
        refresh_btn.clicked.connect(self.refresh_buttons)
        bottom_layout.addWidget(refresh_btn)

        bottom_layout.addStretch()
        layout.addLayout(bottom_layout)

        # 渲染按钮
        self.render_buttons()

    def render_buttons(self):
        """渲染所有按钮"""
        # 清空现有按钮
        while self.button_grid_layout.count():
            item = self.button_grid_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        # 创建新按钮
        max_cols = 5 # 每行4个，使按钮更宽更显眼
        for idx, btn_data in enumerate(self.buttons_data):
            row, col = divmod(idx, max_cols)
            btn = PrimaryPushButton(btn_data.get("title", "未命名"))
            btn.setFixedSize(200, 70)
            # 美化按钮样式
            btn.setStyleSheet("""
                QPushButton {
                    font-size: 16px;
                    font-weight: bold;
                    border-radius: 12px;
                    padding: 10px;
                    background-color: #4CAF50;
                }
            """)
            
            # 绑定点击事件
            btn.clicked.connect(lambda checked, data=btn_data: self.execute_button(data))
            
            # 绑定右键菜单
            btn.setContextMenuPolicy(Qt.CustomContextMenu)
            btn.customContextMenuRequested.connect(
                lambda pos, button=btn, data=btn_data, index=idx: self.show_context_menu(button, data, index)
            )
            
            self.button_grid_layout.addWidget(btn, row, col)

    def show_context_menu(self, button, button_data, index):
        """显示右键菜单"""
        menu = QMenu(self)
        # 美化菜单样式
        menu.setStyleSheet("""
            QMenu {
                font-size: 16px;
                padding: 10px;
                background-color: #666666;
                border-radius: 8px;
                color:#111111;
            }
            QMenu::item {
                padding: 8px 30px;
                border-radius: 4px;
            }
            QMenu::item:selected {
                background-color: #f0f0ff;
            }
        """)
        
        edit_action = QAction(FluentIcon.EDIT.icon(), "编辑按钮", self)
        edit_action.triggered.connect(lambda: self.edit_button(index))
        menu.addAction(edit_action)
        
        delete_action = QAction(FluentIcon.DELETE.icon(), "删除按钮", self)
        delete_action.triggered.connect(lambda: self.delete_button(index))
        menu.addAction(delete_action)
        
        menu.exec_(button.mapToGlobal(button.rect().center()))

    def execute_button(self, button_data):
        """执行按钮命令"""
        try:
            cwd = button_data.get("cwd", ".")
            if cwd == ".":
                cwd = os.path.dirname(__file__)
            
            cmd = button_data.get("cmd", "")
            env = button_data.get("env")
            
            if not cmd:
                self.show_warning("警告", "按钮没有配置执行命令")
                return
            
            # 构建完整命令
            if env:
                full_cmd = f"source ~/.zshrc && conda activate {env} && cd '{cwd}' && {cmd}"
            else:
                full_cmd = f"cd '{cwd}' && {cmd}"
            
            # 在新终端窗口中执行（macOS）
            applescript = f'''
            tell application "Terminal"
                activate
                do script "{full_cmd}"
            end tell
            '''
            
            subprocess.Popen(["osascript", "-e", applescript])
            self.show_success("执行", f"已启动: {button_data.get('title', '未命名')}")
            
        except Exception as e:
            self.show_error("错误", f"执行失败: {str(e)}")

    def add_button(self):
        """添加新按钮"""
        dialog = ButtonEditDialog(parent=self)
        if dialog.exec_() == QDialog.Accepted:
            new_data = dialog.get_data()
            if new_data.get("title") and new_data.get("cmd"):
                self.buttons_data.append(new_data)
                self.save_buttons()
                self.render_buttons()
                self.show_success("成功", f"已添加按钮: {new_data['title']}")
            else:
                self.show_warning("警告", "按钮标题和命令不能为空")

    def edit_button(self, index):
        """编辑按钮"""
        if 0 <= index < len(self.buttons_data):
            dialog = ButtonEditDialog(self.buttons_data[index], parent=self)
            if dialog.exec_() == QDialog.Accepted:
                updated_data = dialog.get_data()
                if updated_data.get("title") and updated_data.get("cmd"):
                    self.buttons_data[index] = updated_data
                    self.save_buttons()
                    self.render_buttons()
                    self.show_success("成功", f"已更新按钮: {updated_data['title']}")
                else:
                    self.show_warning("警告", "按钮标题和命令不能为空")

    def delete_button(self, index):
        """删除按钮"""
        if 0 <= index < len(self.buttons_data):
            button_title = self.buttons_data[index].get("title", "未命名")
            reply = QMessageBox.question(
                self, "确认删除",
                f"确定要删除按钮 '{button_title}' 吗？",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No
            )
            if reply == QMessageBox.Yes:
                self.buttons_data.pop(index)
                self.save_buttons()
                self.render_buttons()
                self.show_success("成功", f"已删除按钮: {button_title}")

    def refresh_buttons(self):
        """刷新按钮"""
        self.load_buttons()
        self.render_buttons()
        self.show_info("刷新", "按钮已刷新")

class VoiceManagerPage(BasePage):
    """声音管理平台"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎵 声音操作管理平台")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 顶部导航 Pivot
        self.pivot = Pivot(self)
        self.pivot.addItem(routeKey="user_voice", text="用户预置音色")
        self.pivot.addItem(routeKey="system_voice", text="使用系统音色")
        self.pivot.addItem(routeKey="base64_upload", text="Base64上传音色")
        self.pivot.addItem(routeKey="file_upload", text="音频文件上传")
        self.pivot.addItem(routeKey="voice_list", text="云端音色列表")
        self.pivot.addItem(routeKey="delete_voice", text="删除云端音色")
        layout.addWidget(self.pivot)

        # 堆叠窗口
        self.stackedWidget = QStackedWidget(self)
        layout.addWidget(self.stackedWidget)

        # 添加子页面
        self.stackedWidget.addWidget(self.create_user_voice_tab())
        self.stackedWidget.addWidget(self.create_system_voice_tab())
        self.stackedWidget.addWidget(self.create_base64_upload_tab())
        self.stackedWidget.addWidget(self.create_file_upload_tab())
        self.stackedWidget.addWidget(self.create_voice_list_tab())
        self.stackedWidget.addWidget(self.create_delete_voice_tab())

        # 连接信号
        self.pivot.currentItemChanged.connect(
            lambda k: self.stackedWidget.setCurrentIndex(
                ["user_voice", "system_voice", "base64_upload", "file_upload", "voice_list", "delete_voice"].index(k)
            )
        )

    def create_tab_widget(self):
        """创建子标签页的基础 Widget"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(15)
        layout.addStretch() # 底部填充
        return widget, layout

    def create_form_row(self, label_text, widget):
        """创建表单行"""
        row = QHBoxLayout()
        label = BodyLabel(label_text)
        label.setFixedWidth(100)
        row.addWidget(label)
        row.addWidget(widget)
        return row

    def get_api_key(self):
        key = os.environ.get("SiliconCloud_API_KEY")
        if not key:
            self.show_error("错误", "请设置环境变量 SiliconCloud_API_KEY")
            return None
        return key

    # --- 1. 用户预置音色 ---
    def create_user_voice_tab(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)

        self.uv_model = ComboBox()
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.uv_model.addItems(model_options)
        self.uv_model.setCurrentText("FunAudioLLM/CosyVoice2-0.5B")
        layout.addLayout(self.create_form_row("模型名称:", self.uv_model))

        self.uv_uri = LineEdit()
        self.uv_uri.setPlaceholderText("speech:xxxx:xxxx:xxxx")
        layout.addLayout(self.create_form_row("音色URI:", self.uv_uri))

        layout.addWidget(BodyLabel("输入文本:"))
        self.uv_text = QTextEdit()
        self.uv_text.setPlaceholderText("请输入要生成的文本内容...")
        self.uv_text.setMinimumHeight(120)
        layout.addWidget(self.uv_text)

        format_layout = QHBoxLayout()
        format_layout.addWidget(BodyLabel("输出格式:"))
        self.uv_format = ComboBox()
        self.uv_format.addItems(["mp3", "wav", "opus", "pcm"])
        self.uv_format.setFixedWidth(150)
        format_layout.addWidget(self.uv_format)
        format_layout.addStretch()
        layout.addLayout(format_layout)

        btn = PrimaryPushButton("生成语音")
        btn.setFixedWidth(200)
        btn.clicked.connect(self.generate_user_voice)
        layout.addWidget(btn, 0, Qt.AlignHCenter)
        layout.addStretch()
        return widget

    def generate_user_voice(self):
        self.generate_voice(
            self.uv_model.currentText(),
            self.uv_uri.text(),
            self.uv_text.toPlainText(),
            self.uv_format.currentText()
        )

    # --- 2. 使用系统音色 ---
    def create_system_voice_tab(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)

        self.sv_model = ComboBox()
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.sv_model.addItems(model_options)
        self.sv_model.setCurrentText("FunAudioLLM/CosyVoice2-0.5B")
        layout.addLayout(self.create_form_row("模型名称:", self.sv_model))

        self.sv_voice = ComboBox()
        voice_options = [
            ("沉稳男声", "alex"), ("低沉男声", "benjamin"), ("磁性男声", "charles"), ("欢快男声", "david"),
            ("沉稳女声", "anna"), ("激情女声", "bella"), ("温柔女声", "claire"), ("欢快女声", "diana")
        ]
        for name, code in voice_options:
            self.sv_voice.addItem(f"{name} ({code})", code)
        layout.addLayout(self.create_form_row("选择系统音色:", self.sv_voice))

        layout.addWidget(BodyLabel("输入文本:"))
        self.sv_text = QTextEdit()
        self.sv_text.setPlaceholderText("请输入要生成的文本内容...")
        self.sv_text.setMinimumHeight(120)
        layout.addWidget(self.sv_text)

        format_layout = QHBoxLayout()
        format_layout.addWidget(BodyLabel("输出格式:"))
        self.sv_format = ComboBox()
        self.sv_format.addItems(["mp3", "wav", "opus", "pcm"])
        self.sv_format.setFixedWidth(150)
        format_layout.addWidget(self.sv_format)
        format_layout.addStretch()
        layout.addLayout(format_layout)

        btn = PrimaryPushButton("生成语音")
        btn.setFixedWidth(200)
        btn.clicked.connect(self.generate_system_voice)
        layout.addWidget(btn, 0, Qt.AlignHCenter)
        layout.addStretch()
        return widget

    def generate_system_voice(self):
        voice_code = self.sv_voice.itemData(self.sv_voice.currentIndex())
        voice_uri = f"{self.sv_model.currentText()}:{voice_code}"
        self.generate_voice(
            self.sv_model.currentText(),
            voice_uri,
            self.sv_text.toPlainText(),
            self.sv_format.currentText(),
            voice_code
        )

    # 通用语音生成逻辑
    def generate_voice(self, model, voice, text, fmt, filename_prefix=None):
        api_key = self.get_api_key()
        if not api_key: return
        if not text.strip():
            self.show_error("错误", "请输入文本内容")
            return

        ts = datetime.now().strftime("%Y%m%d%H%M")
        name = filename_prefix if filename_prefix else (voice.split(":")[-1] if ":" in voice else "voice")
        os.makedirs("speech", exist_ok=True)
        output_path = os.path.abspath(f"speech/{name}-{ts}.{fmt}")

        url = "https://api.siliconflow.cn/v1/audio/speech"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        data = {
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": fmt
        }

        try:
            self.show_info("处理中", "正在生成语音...")
            response = requests.post(url, headers=headers, json=data, stream=True)
            if response.status_code == 200:
                with open(output_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=1024):
                        if chunk: f.write(chunk)
                
                self.show_success("成功", f"语音生成完成: {output_path}")
                # 尝试打开文件夹
                if sys.platform == "darwin":
                    subprocess.run(["open", os.path.dirname(output_path)])
                elif sys.platform == "win32":
                    os.startfile(os.path.dirname(output_path))
            else:
                self.show_error("生成失败", response.text)
        except Exception as e:
            self.show_error("异常", str(e))

    # --- 3. Base64上传 ---
    def create_base64_upload_tab(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)

        self.b64_model = ComboBox()
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.b64_model.addItems(model_options)
        self.b64_model.setCurrentText("FunAudioLLM/CosyVoice2-0.5B")
        layout.addLayout(self.create_form_row("模型名称:", self.b64_model))

        self.b64_name = LineEdit()
        self.b64_name.setPlaceholderText("自定义音色名称")
        layout.addLayout(self.create_form_row("音色名称:", self.b64_name))

        self.b64_text = LineEdit()
        self.b64_text.setPlaceholderText("输入生成的参考文本")
        layout.addLayout(self.create_form_row("参考文本:", self.b64_text))

        layout.addWidget(BodyLabel("Base64音频数据:"))
        self.b64_data = QTextEdit()
        self.b64_data.setPlaceholderText("粘贴Base64音频字符串...")
        self.b64_data.setMinimumHeight(150)
        layout.addWidget(self.b64_data)

        btn = PrimaryPushButton("上传音色")
        btn.setFixedWidth(200)
        btn.clicked.connect(self.upload_base64)
        layout.addWidget(btn, 0, Qt.AlignHCenter)
        layout.addStretch()
        return widget

    def upload_base64(self):
        api_key = self.get_api_key()
        if not api_key: return

        url = "https://api.siliconflow.cn/v1/uploads/audio/voice"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        data = {
            "model": self.b64_model.currentText(),
            "customName": self.b64_name.text(),
            "audio": self.b64_data.toPlainText().strip(),
            "text": self.b64_text.text()
        }

        try:
            self.show_info("上传中", "正在上传音色...")
            resp = requests.post(url, headers=headers, json=data)
            if resp.status_code == 200:
                self.show_success("成功", f"上传成功: {resp.json().get('uri', '未知URI')}")
            else:
                self.show_error("失败", resp.text)
        except Exception as e:
            self.show_error("异常", str(e))

    # --- 4. 文件上传 ---
    def create_file_upload_tab(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)

        self.fu_model = ComboBox()
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.fu_model.addItems(model_options)
        self.fu_model.setCurrentText("FunAudioLLM/CosyVoice2-0.5B")
        layout.addLayout(self.create_form_row("模型名称:", self.fu_model))

        self.fu_name = LineEdit()
        self.fu_name.setPlaceholderText("自定义音色名称")
        layout.addLayout(self.create_form_row("音色名称:", self.fu_name))

        file_layout = QHBoxLayout()
        file_layout.addWidget(BodyLabel("音频文件:"))
        self.fu_path = DraggableLineEdit(self, "audio")
        self.fu_path.setPlaceholderText("选择或拖拽音频文件到此处...")
        file_layout.addWidget(self.fu_path)
        browse_btn = PushButton("浏览")
        browse_btn.clicked.connect(lambda: self.fu_path.setText(self.get_file_path("选择音频", "Audio (*.mp3 *.wav *.opus)")))
        file_layout.addWidget(browse_btn)
        layout.addLayout(file_layout)

        layout.addWidget(BodyLabel("参考文本:"))
        self.fu_text = QTextEdit()
        self.fu_text.setPlaceholderText("输入音频对应的参考文本...")
        self.fu_text.setMinimumHeight(100)
        layout.addWidget(self.fu_text)

        btn = PrimaryPushButton("上传音色")
        btn.setFixedWidth(200)
        btn.clicked.connect(self.upload_file)
        layout.addWidget(btn, 0, Qt.AlignHCenter)
        layout.addStretch()
        return widget

    def upload_file(self):
        api_key = self.get_api_key()
        if not api_key: return
        file_path = self.fu_path.text()
        if not os.path.exists(file_path):
            self.show_error("错误", "文件不存在")
            return

        url = "https://api.siliconflow.cn/v1/uploads/audio/voice"
        headers = {"Authorization": f"Bearer {api_key}"}

        try:
            self.show_info("上传中", "正在上传文件...")
            with open(file_path, "rb") as f:
                files = {"file": f}
                data = {
                    "model": self.fu_model.currentText(),
                    "customName": self.fu_name.text(),
                    "text": self.fu_text.toPlainText().strip()
                }
                resp = requests.post(url, headers=headers, files=files, data=data)

            if resp.status_code == 200:
                self.show_success("成功", f"上传成功: {resp.json().get('uri', '未知URI')}")
            else:
                self.show_error("失败", resp.text)
        except Exception as e:
            self.show_error("异常", str(e))

    # --- 5. 云端音色列表 ---
    def create_voice_list_tab(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)

        # 刷新按钮
        refresh_btn = PushButton(FluentIcon.SYNC, "刷新列表")
        refresh_btn.clicked.connect(self.refresh_voice_list)
        layout.addWidget(refresh_btn, 0, Qt.AlignLeft)

        # 列表
        self.voice_table = TableWidget(self)
        self.voice_table.setColumnCount(4)
        self.voice_table.setHorizontalHeaderLabels(["音色名称", "模型", "URI", "文本"])
        self.voice_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.voice_table.itemClicked.connect(self.copy_uri_from_table)
        layout.addWidget(self.voice_table)

        return widget

    def refresh_voice_list(self):
        api_key = self.get_api_key()
        if not api_key: return

        url = "https://api.siliconflow.cn/v1/audio/voice/list"
        headers = {"Authorization": f"Bearer {api_key}"}

        try:
            self.show_info("加载中", "正在获取音色列表...")
            resp = requests.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json().get("result", [])
                self.voice_table.setRowCount(len(data))
                for i, item in enumerate(data):
                    self.voice_table.setItem(i, 0, QTableWidgetItem(item.get("customName", "")))
                    self.voice_table.setItem(i, 1, QTableWidgetItem(item.get("model", "")))
                    self.voice_table.setItem(i, 2, QTableWidgetItem(item.get("uri", "")))
                    self.voice_table.setItem(i, 3, QTableWidgetItem(item.get("text", "")))
                self.show_success("成功", f"加载了 {len(data)} 个音色")
            else:
                self.show_error("失败", resp.text)
        except Exception as e:
            self.show_error("异常", str(e))

    def copy_uri_from_table(self, item):
        row = item.row()
        uri = self.voice_table.item(row, 2).text()
        QApplication.clipboard().setText(uri)
        self.show_info("已复制", f"URI 已复制到剪贴板: {uri}")

    # --- 6. 删除云端音色 ---
    def create_delete_voice_tab(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)
        
        layout.addWidget(BodyLabel("输入要删除的音色 URI:"))
        self.del_uri = LineEdit()
        self.del_uri.setPlaceholderText("speech:xxxx:xxxx:xxxx")
        layout.addWidget(self.del_uri)

        del_btn = PrimaryPushButton(FluentIcon.DELETE, "删除音色")
        del_btn.setFixedWidth(200)
        del_btn.clicked.connect(self.delete_voice)
        layout.addWidget(del_btn, 0, Qt.AlignHCenter)

        layout.addStretch()
        return widget

    def delete_voice(self):
        api_key = self.get_api_key()
        if not api_key: return
        uri = self.del_uri.text().strip()
        if not uri: return

        url = "https://api.siliconflow.cn/v1/audio/voice/deletions"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        reply = QMessageBox.question(self, "确认删除", f"确定要删除音色 {uri} 吗？", 
                                   QMessageBox.Yes | QMessageBox.No)
        if reply != QMessageBox.Yes: return

        try:
            resp = requests.post(url, headers=headers, json={"uri": uri})
            if resp.status_code == 200:
                self.show_success("成功", "删除成功")
                self.del_uri.clear()
            else:
                self.show_error("失败", resp.text)
        except Exception as e:
            self.show_error("异常", str(e))


class APIVoiceWorkerSignals(QObject):
    """API声音生成工作线程信号"""
    finished = pyqtSignal(str, str)  # local_path, audio_url
    errno = pyqtSignal(str, str)  # error_type, error_message
    progress = pyqtSignal(int, str, str)  # row, status, message


class APIVoiceWorker(QRunnable):
    """API语音合成工作线程 - 使用轮询机制，支持队列满自动切换密钥"""

    # 查询API URL
    QUERY_URL = "https://api.bizyair.cn/w/v1/webapp/task/openapi/query"
    CREATE_URL = "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"

    # 超时设置（秒）
    SUBMIT_TIMEOUT = 300  # 提交任务超时：5分钟（音频base64可能很大）
    QUERY_TIMEOUT = 60    # 查询任务超时：1分钟
    DOWNLOAD_TIMEOUT = 180  # 下载音频超时：3分钟

    # 队列满错误码
    QUEUE_FULL_CODE = 30039

    def __init__(self, api_keys_list, start_key_index, voice_color, target_text, voice_colors_data, task_row):
        """
        初始化工作线程
        :param api_keys_list: API密钥列表（支持自动切换）
        :param start_key_index: 起始密钥索引（从全局索引继续，避免冲突）
        :param voice_color: 音色名称
        :param target_text: 目标文本
        :param voice_colors_data: 音色数据
        :param task_row: 任务在表格中的行号
        """
        super().__init__()
        self.api_keys_list = api_keys_list  # 完整的API密钥列表
        self.current_key_index = start_key_index  # 从指定索引开始，避免从头开始
        self.voice_color = voice_color
        self.target_text = target_text
        self.voice_colors_data = voice_colors_data
        self.task_row = task_row  # 任务在表格中的行号
        self.signals = APIVoiceWorkerSignals()

    @Slot()
    def run(self):
        try:
            import time

            # 查找选中的音色数据
            selected_voice = None
            for voice in self.voice_colors_data:
                if voice['title'] == self.voice_color:
                    selected_voice = voice
                    break

            if not selected_voice:
                raise Exception(f"未找到音色: {self.voice_color}")

            # 获取音频URL（直接使用slicer_opt.json中的URL）
            audio_url = selected_voice['filename']

            logging.info(f"[+]音频URL: {audio_url}")

            if not audio_url:
                raise Exception(f"音频URL为空")

            # 直接使用音频URL，不需要base64编码
            data = {
                "web_app_id": 45578,
                "suppress_preview_output": False,
                "input_values": {
                    "40:FB_Qwen3TTSVoiceClone.target_text": self.target_text,
                    "24:LoadAudio.audio": audio_url,  # 直接使用URL
                    "40:FB_Qwen3TTSVoiceClone.ref_text": selected_voice['content']
                }
            }

            logging.info(f"[+]目标文本: {self.target_text[:50]}...")
            logging.info(f"[+]参考文本: {selected_voice['content'][:50]}...")

            # 第一步：提交任务（支持自动切换密钥重试）
            request_id = None
            headers = None
            max_retries = len(self.api_keys_list)  # 最多重试所有密钥数量次

            for retry_count in range(max_retries):
                # 获取当前密钥
                api_key = self.api_keys_list[self.current_key_index]
                headers = {
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {api_key}"
                }

                logging.info(f"[+]尝试提交任务 (密钥 {self.current_key_index + 1}/{len(self.api_keys_list)})")

                # 发送请求
                self.signals.progress.emit(self.task_row, "提交", "正在提交任务...")
                response = requests.post(self.CREATE_URL, headers=headers, json=data, timeout=self.SUBMIT_TIMEOUT)
                result = response.json()

                logging.info(f"[+]API提交响应: {result}")

                # 检查是否队列满
                if result.get('code') == self.QUEUE_FULL_CODE:
                    # 队列满，切换到下一个密钥重试
                    self.current_key_index = (self.current_key_index + 1) % len(self.api_keys_list)
                    retry_msg = result.get('message', '队列已满')
                    logging.info(f"[+]队列满，切换密钥重试: {retry_msg}")
                    self.signals.progress.emit(self.task_row, "队列满", f"队列已满，重试中 ({retry_count + 1}/{max_retries})")
                    time.sleep(1)  # 短暂等待后重试
                    continue

                # 检查是否成功获得 request_id
                if result.get('request_id'):
                    request_id = result['request_id']
                    logging.info(f"[+]任务ID: {request_id}")
                    self.signals.progress.emit(self.task_row, "提交", "任务提交成功")

                    # 检查任务是否已经完成（status == 'Success'）
                    if result.get('status') == 'Success' and result.get('outputs'):
                        # 任务已完成，直接下载音频
                        audio_url = result['outputs'][0]['object_url']
                        output_ext = result['outputs'][0].get('output_ext', '.mp3')  # 获取实际文件扩展名
                        logging.info(f"[+]任务已完成，音频URL: {audio_url}")
                        logging.info(f"[+]文件格式: {output_ext}")

                        # 下载音频文件
                        self.signals.progress.emit(self.task_row, "下载", "正在下载音频文件...")
                        download_response = requests.get(audio_url, timeout=self.DOWNLOAD_TIMEOUT)
                        if download_response.status_code == 200:
                            # 保存到output目录
                            output_dir = Path("output")
                            output_dir.mkdir(exist_ok=True)

                            # 使用合成文本的前20个字符作为文件名
                            safe_filename = "".join(c for c in self.target_text[:20] if c.isalnum() or c in (' ', '-', '_')).strip()
                            if not safe_filename:
                                safe_filename = f"voice_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
                            filename = f"{safe_filename}{output_ext}"  # 使用实际扩展名
                            save_path = output_dir / filename

                            with open(save_path, 'wb') as f:
                                f.write(download_response.content)

                            logging.info(f"[+]音频文件已保存到: {save_path}")
                            # 返回 (本地路径, URL)
                            self.signals.finished.emit(str(save_path), audio_url)
                            return
                        else:
                            raise Exception(f"下载音频失败: {download_response.status_code}")

                    break  # 成功提交但任务未完成，退出重试循环进入轮询
                else:
                    # 其他错误，不再重试
                    error_msg = result.get('message', 'API返回失败')
                    raise Exception(f"API提交失败: {error_msg}")

            # 如果所有密钥都尝试过仍未成功
            if not request_id:
                raise Exception(f"所有API密钥队列已满或无法使用，请稍后再试")

            # 第二步：等待30秒后开始轮询
            self.signals.progress.emit(self.task_row, "等待", "等待云端处理... (30秒)")
            for i in range(30, 0, -5):
                time.sleep(5)
                self.signals.progress.emit(self.task_row, "等待", f"等待处理中... ({i}秒)")

            # 第三步：轮询查询结果
            max_polls = 24  # 最多轮询24次 (2分钟)
            poll_interval = 5  # 每5秒查询一次

            for poll_count in range(max_polls):
                time.sleep(poll_interval)

                query_data = {"request_id": request_id}
                query_response = requests.post(self.QUERY_URL, headers=headers, json=query_data, timeout=self.QUERY_TIMEOUT)
                query_result = query_response.json()

                logging.info(f"[+]轮询查询 {poll_count + 1}: {query_result.get('status', 'Unknown')}")

                remaining_time = (max_polls - poll_count) * poll_interval
                self.signals.progress.emit(self.task_row, "处理中", f"生成中... ({remaining_time}秒)")

                if query_result.get('status') == 'Success':
                    # 任务完成，获取音频URL
                    if query_result.get('outputs'):
                        audio_url = query_result['outputs'][0]['object_url']
                        output_ext = query_result['outputs'][0].get('output_ext', '.mp3')  # 获取实际文件扩展名
                        logging.info(f"[+]音频URL: {audio_url}")
                        logging.info(f"[+]文件格式: {output_ext}")

                        # 下载音频文件
                        self.signals.progress.emit(self.task_row, "下载", "正在下载音频文件...")
                        download_response = requests.get(audio_url, timeout=self.DOWNLOAD_TIMEOUT)
                        if download_response.status_code == 200:
                            # 保存到output目录
                            output_dir = Path("output")
                            output_dir.mkdir(exist_ok=True)

                            # 使用合成文本的前20个字符作为文件名
                            safe_filename = "".join(c for c in self.target_text[:20] if c.isalnum() or c in (' ', '-', '_')).strip()
                            if not safe_filename:
                                safe_filename = f"voice_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
                            filename = f"{safe_filename}{output_ext}"  # 使用实际扩展名
                            save_path = output_dir / filename

                            with open(save_path, 'wb') as f:
                                f.write(download_response.content)

                            logging.info(f"[+]音频文件已保存到: {save_path}")
                            # 返回 (本地路径, URL)
                            self.signals.finished.emit(str(save_path), audio_url)
                            return
                        else:
                            raise Exception(f"下载音频失败: {download_response.status_code}")
                    else:
                        raise Exception("API返回成功但无音频输出")
                elif query_result.get('status') == 'Failed':
                    error_msg = query_result.get('message', '任务执行失败')
                    raise Exception(f"API任务失败: {error_msg}")
                # 其他状态继续轮询

            raise Exception("轮询超时，任务未在预期时间内完成")

        except requests.exceptions.Timeout as e:
            error_msg = f"请求超时，请检查网络连接或稍后重试 (超时限制: {self.SUBMIT_TIMEOUT}秒)"
            logging.error(error_msg)
            self.signals.errno.emit("TIMEOUT_ERROR", error_msg)
        except requests.exceptions.RequestException as e:
            error_msg = f"调用API时网络错误: {e}"
            logging.error(error_msg)
            self.signals.errno.emit("NETWORK_ERROR", error_msg)
        except Exception as e:
            error_msg = f"处理API声音生成时发生错误: {e}"
            logging.error(error_msg)
            self.signals.errno.emit("UNKNOWN_ERROR", error_msg)


class APIVoiceApiWidget(BasePage):
    """API声音生成界面 - 支持密钥文件和批量处理"""

    HISTORY_FILE = Path("api_voice_history.json")
    DEFAULT_KEY_FILE = "/Volumes/BO/AI/custom_nodes/comfyui_bozo/key/siliconflow_API_key.txt"

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.voice_colors_data = []
        self.api_keys = []  # 密钥列表
        self.current_key_index = 0  # 当前使用的密钥索引
        self.history = []
        self.active_tasks = 0  # 活跃任务计数
        self.thread_pool = QThreadPool()
        self.thread_pool.setMaxThreadCount(5)  # 支持并发任务
        self.load_voice_colors()
        self.load_api_keys(self.DEFAULT_KEY_FILE)
        self.init_ui()
        self.load_history()  # 需要在 init_ui 之后调用，因为 history_table 在 init_ui 中创建

    def load_voice_colors(self):
        """从slicer_opt.json加载音色数据"""
        config_path = Path("slicer_opt.json")
        if config_path.exists():
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    self.voice_colors_data = json.load(f)
                logging.info(f"[+]加载了 {len(self.voice_colors_data)} 个音色")
            except Exception as e:
                logging.error(f"加载音色数据失败: {e}")
                self.voice_colors_data = []
        else:
            logging.warning(f"音色配置文件不存在: {config_path}")
            self.voice_colors_data = []

    def load_api_keys(self, key_file_path):
        """从密钥文件加载API密钥"""
        try:
            key_path = Path(key_file_path)
            if key_path.exists():
                with open(key_path, 'r', encoding='utf-8') as f:
                    # 读取所有非空行
                    self.api_keys = [line.strip() for line in f.readlines() if line.strip()]
                logging.info(f"[+]加载了 {len(self.api_keys)} 个API密钥")
                self.update_key_status()
                return True
            else:
                logging.warning(f"密钥文件不存在: {key_file_path}")
                self.api_keys = []
                self.update_key_status()
                return False
        except Exception as e:
            logging.error(f"加载密钥文件失败: {e}")
            self.api_keys = []
            self.update_key_status()
            return False

    def get_next_api_key(self):
        """获取下一个API密钥（轮询）"""
        if not self.api_keys:
            return None
        key = self.api_keys[self.current_key_index]
        self.current_key_index = (self.current_key_index + 1) % len(self.api_keys)
        return key

    def update_key_status(self):
        """更新密钥状态显示"""
        if hasattr(self, 'key_status_label'):
            if self.api_keys:
                self.key_status_label.setText(f"密钥: {len(self.api_keys)}个 (当前: 第{self.current_key_index + 1}个)")
            else:
                self.key_status_label.setText("密钥: 未加载")
                self.key_status_label.setStyleSheet("color: red; font-size: 10px;")

    def load_history(self):
        """加载历史记录"""
        if self.HISTORY_FILE.exists():
            try:
                with open(self.HISTORY_FILE, 'r', encoding='utf-8') as f:
                    self.history = json.load(f)
                for item in self.history:
                    self.add_history_item_to_table(item['text'], item.get('local_path', ''), item.get('audio_url', ''))
            except (IOError, json.JSONDecodeError) as e:
                logging.error(f"加载历史记录失败: {e}")
                self.history = []

    def save_history(self):
        """保存历史记录"""
        try:
            with open(self.HISTORY_FILE, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, ensure_ascii=False, indent=4)
        except IOError as e:
            logging.error(f"保存历史记录失败: {e}")

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 顶部一行：音色选择 + 密钥文件
        top_layout = QHBoxLayout()

        # 音色选择
        voice_label = BodyLabel("音色:", self)
        voice_label.setFixedWidth(50)
        self.voice_combo = ComboBox(self)
        self.voice_combo.addItems([voice['title'] for voice in self.voice_colors_data])
        self.voice_combo.currentIndexChanged.connect(self.on_voice_changed)
        top_layout.addWidget(voice_label)
        top_layout.addWidget(self.voice_combo)

        # 音色描述
        self.voice_desc_label = BodyLabel("", self)
        self.voice_desc_label.setStyleSheet("color: gray; font-size: 10px;")
        self.voice_desc_label.setMaximumWidth(200)
        top_layout.addWidget(self.voice_desc_label)

        top_layout.addSpacing(20)

        # 密钥文件路径
        key_file_label = BodyLabel("密钥文件:", self)
        self.key_file_input = LineEdit(self)
        self.key_file_input.setText(self.DEFAULT_KEY_FILE)
        self.key_file_input.setReadOnly(True)
        key_browse_button = PushButton("浏览", self)
        key_browse_button.setFixedWidth(60)
        key_browse_button.clicked.connect(self.browse_key_file)
        top_layout.addWidget(key_file_label)
        top_layout.addWidget(self.key_file_input)
        top_layout.addWidget(key_browse_button)

        # 密钥状态
        self.key_status_label = BodyLabel("", self)
        self.key_status_label.setStyleSheet("color: #0078d4; font-size: 10px;")
        top_layout.addWidget(self.key_status_label)

        layout.addLayout(top_layout)

        # 多行文本输入框（顶部）
        self.text_input = TextEdit(self)
        self.text_input.setPlaceholderText("在此输入需要合成语音的文本...")
        self.text_input.setFixedHeight(100)
        layout.addWidget(self.text_input)

        # 状态显示标签
        self.status_label = BodyLabel("", self)
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("color: #0078d4; font-size: 12px;")
        layout.addWidget(self.status_label)

        # 任务记录表格（任务模式）
        task_label = BodyLabel("任务记录:", self)
        layout.addWidget(task_label)

        self.history_table = TableWidget(self)
        self.history_table.setColumnCount(4)
        self.history_table.setHorizontalHeaderLabels(['文本', '状态', '文件', '操作'])
        self.history_table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.history_table.customContextMenuRequested.connect(self.show_context_menu)
        header = self.history_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Stretch)
        header.setSectionResizeMode(1, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.history_table.setWordWrap(True)
        self.history_table.setMaximumHeight(200)
        layout.addWidget(self.history_table)

        # 声音生成按钮（支持多次点击）
        self.generate_button = PushButton("生成声音", self)
        self.generate_button.clicked.connect(self.generate_voice)
        layout.addWidget(self.generate_button)

        # 初始化音色描述和密钥状态
        if self.voice_colors_data:
            self.on_voice_changed(0)

    def browse_key_file(self):
        """浏览密钥文件"""
        file, _ = QFileDialog.getOpenFileName(self, "选择密钥文件", "", "文本文件 (*.txt);;所有文件 (*.*)")
        if file:
            self.key_file_input.setText(file)
            self.load_api_keys(file)

    def on_voice_changed(self, index):
        """音色选择改变时的处理"""
        if 0 <= index < len(self.voice_colors_data):
            voice = self.voice_colors_data[index]
            ref_text = voice['content']
            if len(ref_text) > 25:
                ref_text = ref_text[:25] + "..."
            self.voice_desc_label.setText(f"参考: {ref_text}")

    def add_history_item_to_table(self, text, local_path, audio_url, status="已完成"):
        """添加历史记录到表格"""
        row_count = self.history_table.rowCount()
        self.history_table.insertRow(row_count)

        # 文本
        text_item = QTableWidgetItem(text)
        text_item.setFlags(text_item.flags() & ~Qt.ItemIsEditable)
        self.history_table.setItem(row_count, 0, text_item)

        # 状态
        status_item = QTableWidgetItem(status)
        status_item.setFlags(status_item.flags() & ~Qt.ItemIsEditable)
        if status == "已完成":
            status_item.setForeground(QColor("green"))
        elif status == "处理中":
            status_item.setForeground(QColor("orange"))
        elif status == "错误":
            status_item.setForeground(QColor("red"))
        self.history_table.setItem(row_count, 1, status_item)

        # 文件名
        file_name = os.path.basename(local_path) if local_path else audio_url
        file_item = QTableWidgetItem(file_name)
        file_item.setFlags(file_item.flags() & ~Qt.ItemIsEditable)
        file_item.setData(Qt.UserRole, {'local_path': local_path, 'audio_url': audio_url})
        self.history_table.setItem(row_count, 2, file_item)

        # 操作按钮
        play_button = PushButton(FIF.PLAY, "播放")
        play_button.clicked.connect(lambda _, r=row_count: self.play_audio(r))
        self.history_table.setCellWidget(row_count, 3, play_button)
        self.history_table.resizeRowsToContents()

    def update_task_status(self, row, status):
        """更新任务状态"""
        if row < self.history_table.rowCount():
            status_item = self.history_table.item(row, 1)
            status_item.setText(status)
            if status == "已完成":
                status_item.setForeground(QColor("green"))
            elif status == "处理中":
                status_item.setForeground(QColor("orange"))
            elif status == "错误":
                status_item.setForeground(QColor("red"))

    def play_audio(self, row):
        """播放音频"""
        item = self.history_table.item(row, 2)
        data = item.data(Qt.UserRole)
        local_path = data.get('local_path', '')

        if local_path and os.path.exists(local_path):
            try:
                if platform.system() == "Windows":
                    os.startfile(local_path)
                elif platform.system() == "Darwin":
                    subprocess.Popen(["open", local_path])
                else:
                    subprocess.Popen(["xdg-open", local_path])
            except Exception as e:
                InfoBar.error('播放失败', f'无法播放文件: {e}', parent=self)
        elif data.get('audio_url'):
            try:
                webbrowser.open(data['audio_url'])
            except Exception as e:
                InfoBar.error('打开失败', f'无法打开URL: {e}', parent=self)
        else:
            InfoBar.warning('文件不存在', '音频文件不存在。', parent=self)

    def show_context_menu(self, pos):
        """显示右键菜单"""
        row = self.history_table.rowAt(pos.y())
        if row < 0:
            return

        menu = RoundMenu(parent=self)
        play_action = Action(FIF.PLAY, '播放音频')
        open_file_action = Action(FIF.FOLDER, '打开文件')
        open_url_action = Action(FIF.LINK, '打开URL')
        delete_action = Action(FIF.DELETE, '删除此条记录')

        menu.addActions([play_action, open_file_action, open_url_action, delete_action])

        play_action.triggered.connect(lambda: self.play_audio(row))
        open_file_action.triggered.connect(lambda: self.open_file(row))
        open_url_action.triggered.connect(lambda: self.open_url(row))
        delete_action.triggered.connect(lambda: self.delete_history_item(row))

        menu.exec(QCursor.pos())

    def open_file(self, row):
        """打开文件所在目录"""
        item = self.history_table.item(row, 2)
        data = item.data(Qt.UserRole)
        local_path = data.get('local_path', '')

        if local_path and os.path.exists(local_path):
            try:
                directory = os.path.dirname(local_path)
                if platform.system() == "Windows":
                    os.startfile(directory)
                elif platform.system() == "Darwin":
                    subprocess.Popen(["open", directory])
                else:
                    subprocess.Popen(["xdg-open", directory])
            except Exception as e:
                InfoBar.error('打开失败', f'无法打开目录: {e}', parent=self)
        else:
            InfoBar.warning('文件不存在', '本地文件不存在。', parent=self)

    def open_url(self, row):
        """打开音频URL"""
        item = self.history_table.item(row, 2)
        data = item.data(Qt.UserRole)
        audio_url = data.get('audio_url', '')

        if audio_url:
            try:
                webbrowser.open(audio_url)
            except Exception as e:
                InfoBar.error('打开失败', f'无法打开URL: {e}', parent=self)
        else:
            InfoBar.warning('URL不存在', '没有保存的URL。', parent=self)

    def delete_history_item(self, row):
        """删除历史记录"""
        self.history_table.removeRow(row)
        if row < len(self.history):
            del self.history[row]
            self.save_history()
        InfoBar.success('已删除', '该条历史记录已删除。', parent=self)

    def generate_voice(self):
        """生成声音 - 支持批量处理"""
        text = self.text_input.toPlainText().strip()
        if not text:
            InfoBar.warning('内容为空', '请输入需要合成的文本。', parent=self)
            return

        # 检查密钥列表
        if not self.api_keys:
            InfoBar.warning('密钥为空', '请先加载密钥文件。', parent=self)
            return

        if not self.voice_colors_data:
            InfoBar.warning('音色数据为空', '未找到音色配置数据。', parent=self)
            return

        voice_color = self.voice_combo.currentText()

        # 添加到历史记录（初始状态为处理中）
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        new_task = {
            'text': text,
            'local_path': '',
            'audio_url': '',
            'timestamp': timestamp,
            'status': '处理中'
        }
        self.history.insert(0, new_task)
        self.add_history_item_to_table(text, '', '', '处理中')
        task_row = 0  # 新任务总是在第一行

        # 增加活跃任务计数
        self.active_tasks += 1
        self.update_status_display()

        # 获取当前密钥索引，并更新到下一个（避免所有任务都从密钥1开始）
        start_key_index = self.current_key_index
        self.current_key_index = (self.current_key_index + 1) % len(self.api_keys)

        # 启动工作线程（传递完整的API密钥列表、起始密钥索引和任务行号）
        worker = APIVoiceWorker(self.api_keys, start_key_index, voice_color, text, self.voice_colors_data, task_row)
        worker.signals.progress.connect(self.on_task_progress)
        worker.signals.finished.connect(lambda lp, au: self.on_task_finished(task_row, lp, au))
        worker.signals.errno.connect(lambda err: self.on_task_error(task_row, err))
        self.thread_pool.start(worker)

        # 更新密钥状态显示
        self.update_key_status()

    def on_task_progress(self, row, status, message):
        """任务进度更新 - 支持每个任务的独立倒计时"""
        # 更新表格中对应任务行的状态
        if row < self.history_table.rowCount():
            # 更新状态列
            status_item = self.history_table.item(row, 1)
            if status_item:
                status_item.setText(message)
                # 根据状态设置颜色
                if status == "准备":
                    status_item.setForeground(QColor("#666666"))
                elif status == "编码":
                    status_item.setForeground(QColor("#0078d4"))
                elif status == "提交":
                    status_item.setForeground(QColor("#0066cc"))
                elif status == "队列满":
                    status_item.setForeground(QColor("#ff0066"))  # 红色表示队列满
                elif status == "等待":
                    status_item.setForeground(QColor("#ff9900"))
                elif status == "处理中":
                    status_item.setForeground(QColor("#ff6600"))
                elif status == "下载":
                    status_item.setForeground(QColor("#009933"))

        # 更新全局状态标签
        if self.active_tasks > 0:
            self.status_label.setText(f"正在处理 {self.active_tasks} 个任务...")

    def on_task_finished(self, row, local_path, audio_url):
        """任务完成回调"""
        # 减少活跃任务计数
        self.active_tasks -= 1

        # 更新历史记录
        if row < len(self.history):
            self.history[row]['local_path'] = local_path
            self.history[row]['audio_url'] = audio_url
            self.history[row]['status'] = '已完成'
            self.save_history()

            # 更新表格
            self.update_task_status(row, '已完成')

            # 更新文件列
            file_item = self.history_table.item(row, 2)
            file_name = os.path.basename(local_path)
            file_item.setText(file_name)
            file_item.setData(Qt.UserRole, {'local_path': local_path, 'audio_url': audio_url})

        InfoBar.success('生成成功', f'音频文件已保存', parent=self)
        self.update_status_display()

    def on_task_error(self, row, error_message):
        """任务错误回调"""
        # 减少活跃任务计数
        self.active_tasks -= 1

        # 更新历史记录
        if row < len(self.history):
            self.history[row]['status'] = '错误'
            self.history[row]['error'] = error_message
            self.save_history()
            self.update_task_status(row, '错误')

        InfoBar.error('生成失败', error_message, parent=self)
        self.update_status_display()

    def update_status_display(self):
        """更新状态显示"""
        if self.active_tasks > 0:
            self.status_label.setText(f"正在处理 {self.active_tasks} 个任务...")
        else:
            self.status_label.setText("")


class VideoConvertPage(BasePage):
    """视频转换页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎬 视频转换工具")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 视频文件选择组
        video_group = QGroupBox("视频文件")
        video_layout = QGridLayout()

        video_layout.addWidget(QLabel("选择视频文件:"), 0, 0)
        self.video_path_edit = DraggableLineEdit(self, "video")
        self.video_path_edit.setPlaceholderText("选择或拖拽视频文件到此处...")
        self.video_path_edit.setFixedHeight(35)
        video_layout.addWidget(self.video_path_edit, 0, 1)

        browse_btn = PushButton(FluentIcon.FOLDER, "浏览")
        browse_btn.setFixedWidth(80)
        browse_btn.clicked.connect(self.browse_video)
        video_layout.addWidget(browse_btn, 0, 2)

        video_group.setLayout(video_layout)
        layout.addWidget(video_group)

        # 批量处理组
        batch_group = QGroupBox("批量处理")
        batch_layout = QGridLayout()

        self.batch_checkbox = CheckBox("启用批量处理")
        self.batch_checkbox.stateChanged.connect(self.toggle_batch_mode)
        batch_layout.addWidget(self.batch_checkbox, 0, 0)

        batch_layout.addWidget(QLabel("批量文件夹:"), 1, 0)
        self.batch_path_edit = DraggableLineEdit(self, "video_folder")
        self.batch_path_edit.setPlaceholderText("选择或拖拽包含视频的文件夹...")
        self.batch_path_edit.setFixedHeight(35)
        self.batch_path_edit.setEnabled(False)
        batch_layout.addWidget(self.batch_path_edit, 1, 1)

        batch_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        batch_folder_btn.setFixedWidth(80)
        batch_folder_btn.clicked.connect(self.browse_batch_folder)
        batch_folder_btn.setEnabled(False)
        self.batch_folder_btn = batch_folder_btn
        batch_layout.addWidget(batch_folder_btn, 1, 2)

        batch_group.setLayout(batch_layout)
        layout.addWidget(batch_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("无声视频名称:"), 0, 0)
        self.mute_name_edit = LineEdit()
        self.mute_name_edit.setPlaceholderText("输入无声视频文件名...")
        self.mute_name_edit.setFixedHeight(35)
        output_layout.addWidget(self.mute_name_edit, 0, 1)

        mute_btn = PrimaryPushButton(FluentIcon.VIDEO, "转换无声视频")
        mute_btn.setFixedWidth(150)
        mute_btn.clicked.connect(lambda: self.convert_video("mute"))
        output_layout.addWidget(mute_btn, 0, 2)

        output_layout.addWidget(QLabel("音频文件名称:"), 1, 0)
        self.audio_name_edit = LineEdit()
        self.audio_name_edit.setPlaceholderText("输入音频文件名...")
        self.audio_name_edit.setFixedHeight(35)
        output_layout.addWidget(self.audio_name_edit, 1, 1)

        audio_btn = PrimaryPushButton(FluentIcon.MUSIC, "提取音频")
        audio_btn.setFixedWidth(150)
        audio_btn.clicked.connect(lambda: self.convert_video("audio"))
        output_layout.addWidget(audio_btn, 1, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        # 视频分割组
        split_group = QGroupBox("视频分割")
        split_layout = QGridLayout()

        split_layout.addWidget(QLabel("片段名称:"), 0, 0)
        self.segment_name_edit = LineEdit()
        self.segment_name_edit.setPlaceholderText("输入视频片段名称...")
        self.segment_name_edit.setFixedHeight(35)
        split_layout.addWidget(self.segment_name_edit, 0, 1)

        split_layout.addWidget(QLabel("分割数量:"), 1, 0)
        self.split_count_spin = SpinBox()
        self.split_count_spin.setRange(2, 100)
        self.split_count_spin.setValue(3)
        self.split_count_spin.setFixedHeight(35)
        split_layout.addWidget(self.split_count_spin, 1, 1)

        split_btn = PrimaryPushButton(FluentIcon.CUT, "分割视频")
        split_btn.setFixedWidth(150)
        split_btn.clicked.connect(self.split_video)
        split_layout.addWidget(split_btn, 1, 2)

        split_group.setLayout(split_layout)
        layout.addWidget(split_group)

        # 视频分辨率转换组
        resize_group = QGroupBox("视频分辨率转换")
        resize_layout = QGridLayout()

        # 缩放模式选择
        resize_layout.addWidget(QLabel("缩放模式:"), 0, 0)
        self.scale_mode_combo = ComboBox()
        self.scale_mode_combo.addItems(["按宽度等比例缩放", "按高度等比例缩放", "自定义宽高"])
        self.scale_mode_combo.setFixedHeight(35)
        self.scale_mode_combo.currentTextChanged.connect(self.on_scale_mode_changed)
        resize_layout.addWidget(self.scale_mode_combo, 0, 1)

        # 宽度输入
        resize_layout.addWidget(QLabel("宽度:"), 1, 0)
        self.width_spin = SpinBox()
        self.width_spin.setRange(100, 7680)
        self.width_spin.setValue(1920)
        self.width_spin.setFixedHeight(35)
        resize_layout.addWidget(self.width_spin, 1, 1)

        # 高度输入
        resize_layout.addWidget(QLabel("高度:"), 2, 0)
        self.height_spin = SpinBox()
        self.height_spin.setRange(100, 4320)
        self.height_spin.setValue(1080)
        self.height_spin.setFixedHeight(35)
        self.height_spin.setEnabled(False)  # 默认按宽度等比例，高度禁用
        resize_layout.addWidget(self.height_spin, 2, 1)

        resize_btn = PrimaryPushButton(FluentIcon.ZOOM, "转换分辨率")
        resize_btn.setFixedWidth(150)
        resize_btn.clicked.connect(self.resize_video)
        resize_layout.addWidget(resize_btn, 2, 2)

        resize_group.setLayout(resize_layout)
        layout.addWidget(resize_group)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_video(self):
        file_path = self.get_file_path("选择视频文件",
            "视频文件 (*.mp4 *.mov *.avi);;所有文件 (*)")
        if file_path:
            self.video_path_edit.setText(file_path)

    def browse_batch_folder(self):
        folder_path = self.get_folder_path("选择批量处理文件夹")
        if folder_path:
            self.batch_path_edit.setText(folder_path)

    def toggle_batch_mode(self, state):
        is_checked = state == Qt.Checked
        self.video_path_edit.setEnabled(not is_checked)
        self.batch_path_edit.setEnabled(is_checked)
        self.batch_folder_btn.setEnabled(is_checked)

    def convert_video(self, mode):
        if self.batch_checkbox.isChecked():
            self.batch_convert(mode)
        else:
            video_path = self.video_path_edit.text().strip()
            if not video_path or not os.path.exists(video_path):
                self.show_error("错误", "请选择有效的视频文件")
                return

            if mode == "mute":
                output_name = self.mute_name_edit.text().strip() or "mute_video"
            else:
                output_name = self.audio_name_edit.text().strip() or "audio"

            ts = datetime.now().strftime("%Y%m%d%H%M")
            if mode == "mute":
                output_path = os.path.join(os.getcwd(), 'temp', f"{output_name}-{ts}.mp4")
            else:
                output_path = os.path.join(os.getcwd(), 'temp', f"{output_name}-{ts}.wav")

            os.makedirs(os.path.dirname(output_path), exist_ok=True)

            worker = VideoConversionThread(video_path, output_path, mode)
            worker.progress_updated.connect(self.progress_bar.setValue)
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(self.on_conversion_finished)
            worker.start()

            self.worker_threads.append(worker)
            self.show_info("开始处理", f"正在处理: {os.path.basename(video_path)}")

    def batch_convert(self, mode):
        folder_path = self.batch_path_edit.text().strip()
        if not folder_path or not os.path.exists(folder_path):
            self.show_error("错误", "请选择有效的批量处理文件夹")
            return

        video_files = [f for f in os.listdir(folder_path)
                      if f.lower().endswith(('.mp4', '.mov', '.avi'))]

        if not video_files:
            self.show_error("错误", "文件夹中没有找到视频文件")
            return

        self.show_info("批量处理", f"找到 {len(video_files)} 个视频文件，开始处理...")

        ts = datetime.now().strftime("%Y%m%d%H%M")
        total_files = len(video_files)
        completed = 0

        for video_file in video_files:
            video_path = os.path.join(folder_path, video_file)
            base_name = os.path.splitext(video_file)[0]

            if mode == "mute":
                output_path = os.path.join(os.getcwd(), 'temp', f"{base_name}-mute-{ts}.mp4")
            else:
                output_path = os.path.join(os.getcwd(), 'temp', f"{base_name}-audio-{ts}.wav")

            worker = VideoConversionThread(video_path, output_path, mode)
            worker.progress_updated.connect(lambda v: self.update_batch_progress(v, total_files))
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(self.on_batch_conversion_finished)
            worker.start()

            self.worker_threads.append(worker)

    def update_batch_progress(self, value, total_files):
        # 简单的批量进度显示逻辑
        pass

    def on_conversion_finished(self, success, message):
        if success:
            self.show_success("完成", f"转换完成: {message}")
        else:
            self.show_error("错误", f"转换失败: {message}")
        self.progress_bar.setValue(0)

    def on_batch_conversion_finished(self, success, message):
        # 批量完成逻辑
        self.on_conversion_finished(success, message)

    def on_scale_mode_changed(self, text):
        """缩放模式变化时的处理"""
        if text == "按宽度等比例缩放":
            self.width_spin.setEnabled(True)
            self.height_spin.setEnabled(False)
        elif text == "按高度等比例缩放":
            self.width_spin.setEnabled(False)
            self.height_spin.setEnabled(True)
        else:  # 自定义宽高
            self.width_spin.setEnabled(True)
            self.height_spin.setEnabled(True)

    def resize_video(self):
        """视频分辨率转换"""
        video_path = self.video_path_edit.text().strip()
        if not video_path or not os.path.exists(video_path):
            self.show_error("错误", "请选择有效的视频文件")
            return

        scale_mode = self.scale_mode_combo.currentText()
        width = self.width_spin.value()
        height = self.height_spin.value()

        # 确保宽高是偶数（FFmpeg要求）
        width = width if width % 2 == 0 else width - 1
        height = height if height % 2 == 0 else height - 1

        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        base_name = os.path.splitext(os.path.basename(video_path))[0]
        ts = datetime.now().strftime("%Y%m%d%H%M")
        output_path = os.path.join(temp_dir, f"{base_name}-resized-{ts}.mp4")

        try:
            # 根据模式构建缩放参数
            if scale_mode == "按宽度等比例缩放":
                scale_filter = f"scale={width}:-2"  # -2表示保持宽高比且为偶数
            elif scale_mode == "按高度等比例缩放":
                scale_filter = f"scale=-2:{height}"
            else:  # 自定义宽高
                scale_filter = f"scale={width}:{height}"

            cmd = [
                "ffmpeg", "-y", "-i", video_path,
                "-vf", scale_filter,
                "-c:v", "libx264", "-preset", "fast", "-crf", "18",
                "-c:a", "copy",
                output_path
            ]

            self.show_info("开始转换", f"正在转换分辨率: {scale_filter}")
            self.progress_bar.setValue(30)

            result = subprocess.run(cmd, capture_output=True, text=True)

            if os.path.exists(output_path) and os.path.getsize(output_path) > 1024:
                self.progress_bar.setValue(100)
                self.show_success("完成", f"分辨率转换完成: {output_path}")
            else:
                self.show_error("错误", f"分辨率转换失败: {result.stderr}")

        except Exception as e:
            self.show_error("错误", f"分辨率转换异常: {str(e)}")
        finally:
            self.progress_bar.setValue(0)

    def split_video(self):
        """视频分割功能"""
        video_path = self.video_path_edit.text().strip()
        segment_name = self.segment_name_edit.text().strip() or "segment"
        count = self.split_count_spin.value()

        if not video_path or not os.path.exists(video_path):
            self.show_error("错误", "请选择有效的视频文件")
            return

        try:
            temp_dir = os.path.join(os.getcwd(), 'temp')
            ts = datetime.now().strftime("%Y%m%d%H%M")
            seg_dir = os.path.join(temp_dir, f"{segment_name}-{ts}")
            os.makedirs(seg_dir, exist_ok=True)

            # 获取视频总时长
            cmd_probe = [
                "ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1", video_path
            ]
            result = subprocess.run(cmd_probe, capture_output=True, text=True)

            try:
                duration = float(result.stdout.strip())
            except ValueError:
                self.show_error("错误", "无法获取视频时长")
                return

            seg_len = duration / count
            self.show_info("开始分割", f"视频总时长: {duration:.2f}秒, 每段: {seg_len:.2f}秒")

            for i in range(count):
                start = i * seg_len
                out_path = os.path.join(seg_dir, f"{segment_name}_{i+1}.mp4")

                cmd = [
                    "ffmpeg", "-y", "-i", video_path,
                    "-ss", str(start), "-t", str(seg_len),
                    "-c:v", "libx264", "-c:a", "copy", out_path
                ]

                subprocess.run(cmd, capture_output=True, text=True)
                progress = int((i + 1) / count * 100)
                self.progress_bar.setValue(progress)

            self.show_success("完成", f"视频分割完成，共{count}个片段: {seg_dir}")

        except Exception as e:
            self.show_error("错误", f"视频分割异常: {str(e)}")
        finally:
            self.progress_bar.setValue(0)

class ImageToVideoPage(BasePage):
    """图片转视频页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🖼️ 图片转视频")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 图片选择组
        image_group = QGroupBox("图片设置")
        image_layout = QGridLayout()

        image_layout.addWidget(QLabel("图片文件:"), 0, 0)
        self.image_path_edit = DraggableLineEdit(self, "image")
        self.image_path_edit.setPlaceholderText("选择或拖拽单个图片文件到此处...")
        self.image_path_edit.setFixedHeight(35)
        image_layout.addWidget(self.image_path_edit, 0, 1)

        image_btn = PushButton(FluentIcon.PHOTO, "浏览")
        image_btn.setFixedWidth(80)
        image_btn.clicked.connect(self.browse_image)
        image_layout.addWidget(image_btn, 0, 2)

        # 批量模式
        self.batch_checkbox = CheckBox("批量处理")
        self.batch_checkbox.stateChanged.connect(self.toggle_batch_mode)
        image_layout.addWidget(self.batch_checkbox, 1, 0)

        image_layout.addWidget(QLabel("批量文件夹:"), 2, 0)
        self.batch_folder_edit = DraggableLineEdit(self, "image_folder")
        self.batch_folder_edit.setPlaceholderText("选择或拖拽包含图片的文件夹...")
        self.batch_folder_edit.setFixedHeight(35)
        self.batch_folder_edit.setEnabled(False)
        image_layout.addWidget(self.batch_folder_edit, 2, 1)

        batch_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        batch_folder_btn.setFixedWidth(80)
        batch_folder_btn.clicked.connect(self.browse_batch_folder)
        batch_folder_btn.setEnabled(False)
        self.batch_folder_btn = batch_folder_btn
        image_layout.addWidget(batch_folder_btn, 2, 2)

        image_group.setLayout(image_layout)
        layout.addWidget(image_group)

        # 视频设置组
        video_group = QGroupBox("视频设置")
        video_layout = QGridLayout()

        # 视频尺寸预设
        video_layout.addWidget(QLabel("视频尺寸:"), 0, 0)
        self.size_combo = ComboBox()
        size_options = [
            "1:1 (1240x1240)", "3:4 (1080x1440)", "4:3 (1440x1080)",
            "9:16 (960x1706)", "16:9 (1706x960)", "1:2 (960x1920)",
            "2:1 (1920x960)", "自定义"
        ]
        self.size_combo.addItems(size_options)
        self.size_combo.setCurrentIndex(3)  # 默认9:16
        self.size_combo.currentTextChanged.connect(self.on_size_changed)
        self.size_combo.setFixedHeight(35)
        video_layout.addWidget(self.size_combo, 0, 1)

        video_layout.addWidget(QLabel("自定义尺寸:"), 1, 0)
        self.size_edit = LineEdit()
        self.size_edit.setText("960x1706")
        self.size_edit.setPlaceholderText("宽x高 (如 1920x1080)")
        self.size_edit.setFixedHeight(35)
        video_layout.addWidget(self.size_edit, 1, 1)

        video_layout.addWidget(QLabel("停留时长(秒):"), 2, 0)
        self.duration_spin = SpinBox()
        self.duration_spin.setRange(1, 60)
        self.duration_spin.setValue(6)
        self.duration_spin.setFixedHeight(35)
        video_layout.addWidget(self.duration_spin, 2, 1)

        video_group.setLayout(video_layout)
        layout.addWidget(video_group)

        # 生成按钮
        generate_btn = PrimaryPushButton(FluentIcon.PLAY, "生成视频片段")
        generate_btn.setFixedHeight(45)
        generate_btn.clicked.connect(self.generate_video)
        layout.addWidget(generate_btn)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_image(self):
        file_path = self.get_file_path("选择图片文件",
            "图片文件 (*.png *.jpg *.jpeg *.bmp);;所有文件 (*)")
        if file_path:
            self.image_path_edit.setText(file_path)

    def browse_batch_folder(self):
        folder_path = self.get_folder_path("选择图片文件夹")
        if folder_path:
            self.batch_folder_edit.setText(folder_path)

    def toggle_batch_mode(self, state):
        is_checked = state == Qt.Checked
        self.image_path_edit.setEnabled(not is_checked)
        self.batch_folder_edit.setEnabled(is_checked)
        self.batch_folder_btn.setEnabled(is_checked)

    def on_size_changed(self, text):
        if text == "自定义":
            self.size_edit.setEnabled(True)
        else:
            match = re.search(r'\((\d+x\d+)\)', text)
            if match:
                self.size_edit.setText(match.group(1))
            self.size_edit.setEnabled(False)

    def generate_video(self):
        if self.batch_checkbox.isChecked():
            self.batch_generate_video()
        else:
            image_path = self.image_path_edit.text().strip()
            if not image_path or not os.path.exists(image_path):
                self.show_error("错误", "请选择有效的图片文件")
                return

            self.generate_single_video(image_path)

    def generate_single_video(self, image_path):
        size = self.size_edit.text().strip()
        duration = self.duration_spin.value()

        if not re.match(r'\d+x\d+', size):
            self.show_error("错误", "请输入正确的尺寸格式 (如 1920x1080)")
            return

        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        img_name = os.path.splitext(os.path.basename(image_path))[0]
        output_path = os.path.join(temp_dir, f"{img_name}.mp4")

        worker = ImageToVideoThread(image_path, output_path, size, duration)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_generation_finished)
        worker.start()

        self.worker_threads.append(worker)
        self.show_info("开始生成", f"正在生成视频: {os.path.basename(image_path)}")

    def batch_generate_video(self):
        folder_path = self.batch_folder_edit.text().strip()
        if not folder_path or not os.path.exists(folder_path):
            self.show_error("错误", "请选择有效的图片文件夹")
            return

        image_files = [f for f in os.listdir(folder_path)
                      if f.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp'))]

        if not image_files:
            self.show_error("错误", "文件夹中没有找到图片文件")
            return

        self.show_info("批量处理", f"找到 {len(image_files)} 个图片文件，开始处理...")

        for image_file in image_files:
            image_path = os.path.join(folder_path, image_file)
            self.generate_single_video(image_path)

    def on_generation_finished(self, success, message):
        if success:
            self.show_success("完成", f"视频生成完成: {message}")
        else:
            self.show_error("错误", f"视频生成失败: {message}")
        self.progress_bar.setValue(0)

class MergeVideoAudioPage(BasePage):
    """合并视频与音频页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎵 合并视频与音频")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 文件选择组
        file_group = QGroupBox("文件选择")
        file_layout = QGridLayout()

        file_layout.addWidget(QLabel("封面文件:"), 0, 0)
        self.cover_path_edit = DraggableLineEdit(self, "image")
        self.cover_path_edit.setPlaceholderText("选择或拖拽封面图片文件 (可选)...")
        self.cover_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.cover_path_edit, 0, 1)

        cover_btn = PushButton(FluentIcon.PHOTO, "浏览")
        cover_btn.setFixedWidth(80)
        cover_btn.clicked.connect(lambda: self.browse_file("cover"))
        file_layout.addWidget(cover_btn, 0, 2)

        file_layout.addWidget(QLabel("视频片段文件夹:"), 1, 0)
        self.video_folder_edit = DraggableLineEdit(self, "video_folder")
        self.video_folder_edit.setPlaceholderText("选择或拖拽包含视频片段的文件夹...")
        self.video_folder_edit.setFixedHeight(35)
        file_layout.addWidget(self.video_folder_edit, 1, 1)

        video_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        video_folder_btn.setFixedWidth(80)
        video_folder_btn.clicked.connect(lambda: self.browse_file("video_folder"))
        file_layout.addWidget(video_folder_btn, 1, 2)

        file_layout.addWidget(QLabel("音频文件:"), 2, 0)
        self.audio_path_edit = DraggableLineEdit(self, "audio")
        self.audio_path_edit.setPlaceholderText("选择或拖拽音频文件到此处...")
        self.audio_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.audio_path_edit, 2, 1)

        audio_btn = PushButton(FluentIcon.MUSIC, "浏览")
        audio_btn.setFixedWidth(80)
        audio_btn.clicked.connect(lambda: self.browse_file("audio"))
        file_layout.addWidget(audio_btn, 2, 2)

        file_group.setLayout(file_layout)
        layout.addWidget(file_group)

        # 合并设置组
        merge_group = QGroupBox("合并设置")
        merge_layout = QGridLayout()

        merge_layout.addWidget(QLabel("输出视频名:"), 0, 0)
        self.output_name_edit = LineEdit()
        self.output_name_edit.setPlaceholderText("输入输出视频名称...")
        self.output_name_edit.setFixedHeight(35)
        merge_layout.addWidget(self.output_name_edit, 0, 1)

        # 缩放动画设置
        self.zoom_checkbox = CheckBox("启用缩放动画")
        self.zoom_checkbox.stateChanged.connect(self.toggle_zoom_controls)
        merge_layout.addWidget(self.zoom_checkbox, 1, 0)

        merge_layout.addWidget(QLabel("缩放结束值:"), 2, 0)
        self.zoom_end_spin = QDoubleSpinBox()
        self.zoom_end_spin.setRange(1.0, 5.0)
        self.zoom_end_spin.setValue(1.2)
        self.zoom_end_spin.setSingleStep(0.1)
        self.zoom_end_spin.setEnabled(False)
        merge_layout.addWidget(self.zoom_end_spin, 2, 1)

        merge_layout.addWidget(QLabel("滤镜类型:"), 3, 0)
        self.filter_combo = ComboBox()
        self.filter_combo.addItems(["scale+zoom", "scale+zoompan", "无"])
        self.filter_combo.setEnabled(False)
        merge_layout.addWidget(self.filter_combo, 3, 1)

        merge_group.setLayout(merge_layout)
        layout.addWidget(merge_group)

        # 操作按钮
        btn_layout = QHBoxLayout()

        merge_btn = PrimaryPushButton(FluentIcon.LINK, "基础合并")
        merge_btn.setFixedHeight(45)
        merge_btn.clicked.connect(self.merge_videos)
        btn_layout.addWidget(merge_btn)

        zoom_merge_btn = PrimaryPushButton(FluentIcon.FULL_SCREEN, "缩放合并")
        zoom_merge_btn.setFixedHeight(45)
        zoom_merge_btn.clicked.connect(self.merge_with_zoom)
        zoom_merge_btn.setEnabled(False)
        self.zoom_merge_btn = zoom_merge_btn
        btn_layout.addWidget(zoom_merge_btn)

        layout.addLayout(btn_layout)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_file(self, file_type):
        if file_type == "cover":
            file_path = self.get_file_path("选择封面文件",
                "图片文件 (*.png *.jpg *.jpeg *.bmp);;所有文件 (*)")
            if file_path:
                self.cover_path_edit.setText(file_path)
        elif file_type == "video_folder":
            folder_path = self.get_folder_path("选择视频片段文件夹")
            if folder_path:
                self.video_folder_edit.setText(folder_path)
        elif file_type == "audio":
            file_path = self.get_file_path("选择音频文件",
                "音频文件 (*.mp3 *.wav *.aac *.flac);;所有文件 (*)")
            if file_path:
                self.audio_path_edit.setText(file_path)

    def toggle_zoom_controls(self, state):
        is_checked = state == Qt.Checked
        self.zoom_end_spin.setEnabled(is_checked)
        self.filter_combo.setEnabled(is_checked)
        self.zoom_merge_btn.setEnabled(is_checked)

    def get_video_duration(self, video_path):
        """获取视频时长"""
        cmd = [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", video_path
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        try:
            return float(result.stdout.strip())
        except ValueError:
            return None

    def convert_png_to_jpg(self, png_path, jpg_path):
        """将PNG转换为JPG（封面需要）"""
        try:
            img = Image.open(png_path)
            rgb_img = img.convert('RGB')
            rgb_img.save(jpg_path, quality=95)
            return True
        except Exception:
            return False

    def merge_videos(self):
        """基础合并功能：合并视频片段并添加音频"""
        video_folder = self.video_folder_edit.text().strip()
        audio_path = self.audio_path_edit.text().strip()
        cover_path = self.cover_path_edit.text().strip()
        output_name = self.output_name_edit.text().strip() or "output"

        if not video_folder or not os.path.isdir(video_folder):
            self.show_error("错误", "请选择有效的视频文件夹")
            return

        if not audio_path or not os.path.isfile(audio_path):
            self.show_error("错误", "请选择有效的音频文件")
            return

        try:
            temp_dir = os.path.join(os.getcwd(), 'temp')
            os.makedirs(temp_dir, exist_ok=True)
            ts = datetime.now().strftime("%Y%m%d%H%M")

            # 获取视频文件列表
            videos = [f for f in os.listdir(video_folder) if f.lower().endswith('.mp4')]
            videos.sort()

            if not videos:
                self.show_error("错误", "视频文件夹中没有找到MP4文件")
                return

            self.show_info("开始合并", f"找到 {len(videos)} 个视频片段，开始合并...")
            self.progress_bar.setValue(10)

            # 生成文件列表
            filelist_path = os.path.join(temp_dir, "filelist.txt")
            with open(filelist_path, 'w') as f:
                for v in videos:
                    f.write(f"file '{os.path.join(video_folder, v)}'\n")

            # 合并视频片段
            concat_path = os.path.join(temp_dir, f"concat_{ts}.mp4")
            cmd_concat = [
                "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", filelist_path,
                "-c:v", "libx264", "-preset", "fast", "-crf", "18",
                "-c:a", "aac", "-b:a", "192k",
                concat_path
            ]
            result_concat = subprocess.run(cmd_concat, capture_output=True, text=True)

            if not os.path.isfile(concat_path):
                self.show_error("错误", f"合并视频片段失败: {result_concat.stderr}")
                return

            self.progress_bar.setValue(50)

            # 合成音视频
            out_path = os.path.join(temp_dir, f"{output_name}-{ts}.mp4")
            cmd_merge = [
                "ffmpeg", "-y", "-i", concat_path, "-i", audio_path,
                "-c:v", "libx264", "-preset", "fast", "-crf", "18",
                "-c:a", "aac", "-b:a", "192k",
                "-map", "0:v:0", "-map", "1:a:0",
                "-shortest", out_path
            ]
            result_merge = subprocess.run(cmd_merge, capture_output=True, text=True)

            if not os.path.isfile(out_path) or os.path.getsize(out_path) < 1024:
                self.show_error("错误", f"合成音视频失败: {result_merge.stderr}")
                return

            self.progress_bar.setValue(80)

            # 添加封面（如果有）
            if cover_path and os.path.isfile(cover_path):
                cover_ext = os.path.splitext(cover_path)[1].lower()
                cover_file_to_use = cover_path

                # PNG转JPG
                if cover_ext == ".png":
                    cover_jpg = os.path.join(temp_dir, f"cover_{ts}.jpg")
                    if self.convert_png_to_jpg(cover_path, cover_jpg):
                        cover_file_to_use = cover_jpg

                out_with_cover = os.path.join(temp_dir, f"{output_name}-{ts}-cover.mp4")
                cmd_cover = [
                    "ffmpeg", "-y", "-i", out_path, "-i", cover_file_to_use,
                    "-map", "0", "-map", "1", "-c", "copy",
                    "-disposition:v:1", "attached_pic", out_with_cover
                ]
                result_cover = subprocess.run(cmd_cover, capture_output=True, text=True)

                if os.path.isfile(out_with_cover) and os.path.getsize(out_with_cover) > 1024:
                    os.replace(out_with_cover, out_path)

            self.progress_bar.setValue(100)
            self.show_success("完成", f"视频合成完成: {out_path}")

        except Exception as e:
            self.show_error("错误", f"合并异常: {str(e)}")
        finally:
            self.progress_bar.setValue(0)

    def merge_with_zoom(self):
        """缩放合并功能：支持缩放滤镜效果"""
        video_folder = self.video_folder_edit.text().strip()
        audio_path = self.audio_path_edit.text().strip()
        output_name = self.output_name_edit.text().strip() or "output"
        zoom_end = self.zoom_end_spin.value()
        filter_type = self.filter_combo.currentText()

        if not video_folder or not os.path.isdir(video_folder):
            self.show_error("错误", "请选择有效的视频文件夹")
            return

        if not audio_path or not os.path.isfile(audio_path):
            self.show_error("错误", "请选择有效的音频文件")
            return

        try:
            temp_dir = os.path.join(os.getcwd(), 'temp')
            os.makedirs(temp_dir, exist_ok=True)
            ts = datetime.now().strftime("%Y%m%d%H%M")

            # 获取视频文件列表
            videos = [f for f in os.listdir(video_folder) if f.lower().endswith('.mp4')]
            videos.sort()

            if not videos:
                self.show_error("错误", "视频文件夹中没有找到MP4文件")
                return

            self.show_info("开始处理", f"找到 {len(videos)} 个视频片段，开始应用滤镜...")

            filtered_list = []
            zoom_ratio = zoom_end - 1

            for idx, v in enumerate(videos):
                in_path = os.path.join(video_folder, v)
                filtered_path = os.path.join(temp_dir, f"filtered_{idx+1}.mp4")

                # 获取视频时长
                duration = self.get_video_duration(in_path)
                if not duration or duration <= 0:
                    self.show_error("错误", f"无法获取视频时长: {in_path}")
                    return

                if filter_type in ["scale+zoom", "scale+zoompan"]:
                    # 构造缩放滤镜
                    vf_str = f"scale=iw*(1+{zoom_ratio}*t/{duration}):ih*(1+{zoom_ratio}*t/{duration}),crop=iw:ih"
                    cmd = [
                        "ffmpeg", "-y", "-i", in_path, "-vf", vf_str,
                        "-c:v", "libx264", "-c:a", "aac", filtered_path
                    ]
                else:
                    # 无滤镜
                    cmd = [
                        "ffmpeg", "-y", "-i", in_path,
                        "-c:v", "libx264", "-c:a", "copy", filtered_path
                    ]

                subprocess.run(cmd, capture_output=True, text=True)

                if not os.path.isfile(filtered_path):
                    self.show_error("错误", f"滤镜处理失败: {filtered_path}")
                    return

                filtered_list.append(filtered_path)
                progress = int((idx + 1) / len(videos) * 50)
                self.progress_bar.setValue(progress)

            # 生成文件列表并合并
            filelist_path = os.path.join(temp_dir, "filelist.txt")
            with open(filelist_path, "w") as f:
                for fp in filtered_list:
                    f.write(f"file '{fp}'\n")

            merged_path = os.path.join(temp_dir, f"{output_name}-{ts}-merged.mp4")
            cmd_concat = [
                "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", filelist_path,
                "-c", "copy", merged_path
            ]
            subprocess.run(cmd_concat, capture_output=True, text=True)

            if not os.path.isfile(merged_path):
                self.show_error("错误", "合并滤镜视频失败")
                return

            self.progress_bar.setValue(75)

            # 合成音视频
            final_path = os.path.join(temp_dir, f"{output_name}-{ts}-final.mp4")
            cmd_merge = [
                "ffmpeg", "-y", "-i", merged_path, "-i", audio_path,
                "-c:v", "copy", "-c:a", "aac", "-shortest", final_path
            ]
            subprocess.run(cmd_merge, capture_output=True, text=True)

            if not os.path.isfile(final_path):
                self.show_error("错误", "合成音视频失败")
                return

            self.progress_bar.setValue(100)
            self.show_success("完成", f"缩放合并完成: {final_path}")

        except Exception as e:
            self.show_error("错误", f"缩放合并异常: {str(e)}")
        finally:
            self.progress_bar.setValue(0)

class SubtitleGenerationPage(BasePage):
    """字幕生成页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("📝 生成字幕文件")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 音频文件选择
        audio_group = QGroupBox("音频文件")
        audio_layout = QGridLayout()

        audio_layout.addWidget(QLabel("音频文件:"), 0, 0)
        self.audio_path_edit = DraggableLineEdit(self, "audio")
        self.audio_path_edit.setPlaceholderText("选择或拖拽音频文件到此处...")
        self.audio_path_edit.setFixedHeight(35)
        audio_layout.addWidget(self.audio_path_edit, 0, 1)

        audio_btn = PushButton(FluentIcon.MUSIC, "浏览")
        audio_btn.setFixedWidth(80)
        audio_btn.clicked.connect(self.browse_audio)
        audio_layout.addWidget(audio_btn, 0, 2)

        audio_group.setLayout(audio_layout)
        layout.addWidget(audio_group)

        # 字幕生成设置
        srt_group = QGroupBox("字幕设置")
        srt_layout = QGridLayout()

        srt_layout.addWidget(QLabel("字幕文件名:"), 0, 0)
        self.srt_name_edit = LineEdit()
        self.srt_name_edit.setPlaceholderText("输入字幕文件名...")
        self.srt_name_edit.setFixedHeight(35)
        srt_layout.addWidget(self.srt_name_edit, 0, 1)

        srt_layout.addWidget(QLabel("每行字符数:"), 1, 0)
        self.char_count_spin = SpinBox()
        self.char_count_spin.setRange(10, 100)
        self.char_count_spin.setValue(30)
        self.char_count_spin.setFixedHeight(35)
        srt_layout.addWidget(self.char_count_spin, 1, 1)

        srt_group.setLayout(srt_layout)
        layout.addWidget(srt_group)

        # 生成按钮
        generate_btn = PrimaryPushButton(FluentIcon.DOCUMENT, "生成字幕文件")
        generate_btn.setFixedHeight(45)
        generate_btn.clicked.connect(self.generate_subtitle)
        layout.addWidget(generate_btn)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_audio(self):
        file_path = self.get_file_path("选择音频文件",
            "音频文件 (*.mp3 *.wav *.aac *.flac);;所有文件 (*)")
        if file_path:
            self.audio_path_edit.setText(file_path)

    def generate_subtitle(self):
        audio_path = self.audio_path_edit.text().strip()
        srt_name = self.srt_name_edit.text().strip() or "subtitle"
        char_count = self.char_count_spin.value()

        if not audio_path or not os.path.exists(audio_path):
            self.show_error("错误", "请选择有效的音频文件")
            return

        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d%H%M")
        output_path = os.path.join(srt_dir, f"{srt_name}-{ts}.srt")

        worker = SRTGenerationThread(audio_path, output_path, char_count)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_subtitle_finished)
        worker.start()

        self.worker_threads.append(worker)
        self.show_info("开始生成", f"正在生成字幕: {os.path.basename(audio_path)}")

    def on_subtitle_finished(self, success, message):
        if success:
            self.show_success("完成", f"字幕生成完成: {message}")
        else:
            self.show_error("错误", f"字幕生成失败: {message}")
        self.progress_bar.setValue(0)

class SubtitleTextPage(BasePage):
    """字幕转文本页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("📄 字幕转文本")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # SRT文件选择组
        srt_group = QGroupBox("SRT字幕文件")
        srt_layout = QGridLayout()

        srt_layout.addWidget(QLabel("SRT文件路径:"), 0, 0)
        self.srt_path_edit = DraggableLineEdit(self, "srt")
        self.srt_path_edit.setPlaceholderText("选择或拖拽SRT字幕文件到此处...")
        self.srt_path_edit.setFixedHeight(35)
        srt_layout.addWidget(self.srt_path_edit, 0, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "浏览")
        srt_btn.setFixedWidth(80)
        srt_btn.clicked.connect(self.browse_srt)
        srt_layout.addWidget(srt_btn, 0, 2)

        srt_group.setLayout(srt_layout)
        layout.addWidget(srt_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("TXT文件名:"), 0, 0)
        self.txt_name_edit = LineEdit()
        self.txt_name_edit.setPlaceholderText("输入输出文本文件名...")
        self.txt_name_edit.setFixedHeight(35)
        output_layout.addWidget(self.txt_name_edit, 0, 1)

        convert_btn = PrimaryPushButton(FluentIcon.DOWNLOAD, "保存为文本")
        convert_btn.setFixedWidth(150)
        convert_btn.clicked.connect(self.convert_srt_to_text)
        output_layout.addWidget(convert_btn, 0, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        # 翻译功能组
        translate_group = QGroupBox("翻译功能")
        translate_layout = QGridLayout()

        translate_layout.addWidget(QLabel("翻译SRT名称:"), 0, 0)
        self.translate_name_edit = LineEdit()
        self.translate_name_edit.setPlaceholderText("输入翻译后SRT文件名...")
        self.translate_name_edit.setFixedHeight(35)
        translate_layout.addWidget(self.translate_name_edit, 0, 1)

        translate_layout.addWidget(QLabel("目标语言:"), 1, 0)
        self.language_combo = ComboBox()
        language_options = [
            "英文", "中文", "繁体中文", "韩语", "日语", "俄语",
            "德语", "法语", "阿拉伯语", "越南语", "印地语",
            "西班牙语", "葡萄牙语"
        ]
        self.language_combo.addItems(language_options)
        self.language_combo.setCurrentIndex(0)  # 默认英文
        self.language_combo.setFixedHeight(35)
        translate_layout.addWidget(self.language_combo, 1, 1)

        translate_btn = PrimaryPushButton(FluentIcon.LANGUAGE, "翻译SRT文件")
        translate_btn.setFixedHeight(45)
        translate_btn.clicked.connect(self.translate_srt_file)
        translate_layout.addWidget(translate_btn, 1, 2)

        translate_group.setLayout(translate_layout)
        layout.addWidget(translate_group)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_srt(self):
        file_path = self.get_file_path("选择SRT字幕文件",
            "SRT字幕文件 (*.srt);;所有文件 (*)")
        if file_path:
            self.srt_path_edit.setText(file_path)

    def convert_srt_to_text(self):
        srt_path = self.srt_path_edit.text().strip()
        txt_name = self.txt_name_edit.text().strip() or "subtitle"

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)

        output_path = os.path.join(srt_dir, f"{txt_name}.txt")

        worker = SRTToTextThread(srt_path, output_path)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_srt_to_text_finished)
        worker.start()

        self.worker_threads.append(worker)
        self.show_info("开始转换", f"正在转换SRT到文本: {os.path.basename(srt_path)}")

    def translate_srt_file(self):
        srt_path = self.srt_path_edit.text().strip()
        output_name = self.translate_name_edit.text().strip() or "translated"
        target_language = self.language_combo.currentText()

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)

        # 语言映射
        lang_map = {
            "英文": "English",
            "中文": "Chinese",
            "繁体中文": "Traditional Chinese",
            "韩语": "Korean",
            "日语": "Japanese",
            "俄语": "Russian",
            "德语": "German",
            "法语": "French",
            "阿拉伯语": "Arabic",
            "越南语": "Vietnamese",
            "印地语": "Hindi",
            "西班牙语": "Spanish",
            "葡萄牙语": "Portuguese"
        }

        target_lang = lang_map.get(target_language, "English")
        output_path = os.path.join(srt_dir, f"{output_name}-{target_lang}.srt")

        worker = SRTTranslateThread(srt_path, output_path, target_lang)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_translate_finished)
        worker.start()

        self.worker_threads.append(worker)
        self.show_info("开始翻译", f"正在翻译SRT文件到{target_language}")

    def on_srt_to_text_finished(self, success, message):
        if success:
            self.show_success("完成", f"SRT转文本完成: {message}")
        else:
            self.show_error("错误", f"SRT转文本失败: {message}")
        self.progress_bar.setValue(0)

    def on_translate_finished(self, success, message):
        if success:
            self.show_success("完成", f"SRT翻译完成: {message}")
        else:
            self.show_error("错误", f"SRT翻译失败: {message}")
        self.progress_bar.setValue(0)

class AdjustSubtitlePage(BasePage):
    """调整字幕页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("✏️ 调整字幕文件")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # SRT文件选择组
        srt_group = QGroupBox("SRT字幕文件")
        srt_layout = QGridLayout()

        srt_layout.addWidget(QLabel("SRT文件路径:"), 0, 0)
        self.srt_path_edit = DraggableLineEdit(self, "srt")
        self.srt_path_edit.setPlaceholderText("选择或拖拽SRT字幕文件到此处...")
        self.srt_path_edit.setFixedHeight(35)
        srt_layout.addWidget(self.srt_path_edit, 0, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "浏览")
        srt_btn.setFixedWidth(80)
        srt_btn.clicked.connect(self.browse_srt)
        srt_layout.addWidget(srt_btn, 0, 2)

        srt_group.setLayout(srt_layout)
        layout.addWidget(srt_group)

        # 字幕内容编辑组
        content_group = QGroupBox("字幕内容编辑")
        content_layout = QVBoxLayout()

        content_label = QLabel("设置新的字幕内容 (一行一个字幕):")
        content_layout.addWidget(content_label)

        self.content_edit = QTextEdit()
        self.content_edit.setPlaceholderText("请输入字幕内容，每行一个字幕...")
        self.content_edit.setMinimumHeight(200)
        content_layout.addWidget(self.content_edit)

        content_group.setLayout(content_layout)
        layout.addWidget(content_group)

        # 操作按钮
        adjust_btn = PrimaryPushButton(FluentIcon.EDIT, "调整字幕文件")
        adjust_btn.setFixedHeight(45)
        adjust_btn.clicked.connect(self.adjust_subtitle)
        layout.addWidget(adjust_btn)

        layout.addStretch()

    def browse_srt(self):
        file_path = self.get_file_path("选择SRT字幕文件",
            "SRT字幕文件 (*.srt);;所有文件 (*)")
        if file_path:
            self.srt_path_edit.setText(file_path)

    def adjust_subtitle(self):
        """调整字幕文件内容"""
        srt_path = self.srt_path_edit.text().strip()
        content = self.content_edit.toPlainText().strip()

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        if not content:
            self.show_error("错误", "请输入字幕内容")
            return

        try:
            srt_dir = os.path.join(os.getcwd(), 'SRT')
            os.makedirs(srt_dir, exist_ok=True)

            base_name = os.path.splitext(os.path.basename(srt_path))[0]
            output_path = os.path.join(srt_dir, f"{base_name}-1.srt")

            # 使用 chardet 检测文件编码
            with open(srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'

            # 使用检测到的编码读取文件内容
            srt_content = raw.decode(enc, errors='replace')

            # 提取时间轴
            times = re.findall(r'(\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3})', srt_content)

            # 获取新内容行
            new_lines = content.split('\n')
            new_lines = [line.strip() for line in new_lines if line.strip()]

            if not new_lines:
                self.show_error("错误", "字幕内容为空")
                return

            if len(times) == 0:
                self.show_error("错误", "无法从SRT文件中提取时间轴信息")
                return

            # 生成新SRT文件
            with open(output_path, 'w', encoding='utf-8') as f:
                for i in range(min(len(new_lines), len(times))):
                    f.write(f"{i+1}\n")
                    f.write(f"{times[i]}\n")
                    f.write(f"{new_lines[i]}\n\n")

            self.show_success("完成", f"调整后的字幕文件已保存: {output_path}")

        except Exception as e:
            self.show_error("错误", f"调整字幕失败: {str(e)}")

class MergeSubtitlePage(BasePage):
    """整合视频字幕页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎬 整合视频字幕")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 文件选择组
        file_group = QGroupBox("文件选择")
        file_layout = QGridLayout()

        file_layout.addWidget(QLabel("视频文件:"), 0, 0)
        self.video_path_edit = DraggableLineEdit(self, "video")
        self.video_path_edit.setPlaceholderText("选择或拖拽视频文件到此处...")
        self.video_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.video_path_edit, 0, 1)

        video_btn = PushButton(FluentIcon.VIDEO, "浏览")
        video_btn.setFixedWidth(80)
        video_btn.clicked.connect(lambda: self.browse_file("video"))
        file_layout.addWidget(video_btn, 0, 2)

        file_layout.addWidget(QLabel("SRT字幕文件:"), 1, 0)
        self.srt_path_edit = DraggableLineEdit(self, "srt")
        self.srt_path_edit.setPlaceholderText("选择或拖拽SRT字幕文件到此处...")
        self.srt_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.srt_path_edit, 1, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "浏览")
        srt_btn.setFixedWidth(80)
        srt_btn.clicked.connect(lambda: self.browse_file("srt"))
        file_layout.addWidget(srt_btn, 1, 2)

        file_group.setLayout(file_layout)
        layout.addWidget(file_group)

        # 字幕样式设置组
        style_group = QGroupBox("字幕样式")
        style_layout = QGridLayout()

        style_layout.addWidget(QLabel("字体文件:"), 0, 0)
        self.font_path_edit = DraggableLineEdit(self, "font")
        self.font_path_edit.setText("font/Light.otf")
        self.font_path_edit.setPlaceholderText("选择或拖拽字体文件到此处...")
        self.font_path_edit.setFixedHeight(35)
        style_layout.addWidget(self.font_path_edit, 0, 1)

        font_btn = PushButton(FluentIcon.FONT, "浏览")
        font_btn.setFixedWidth(80)
        font_btn.clicked.connect(lambda: self.browse_file("font"))
        style_layout.addWidget(font_btn, 0, 2)

        style_layout.addWidget(QLabel("字体大小:"), 1, 0)
        self.font_size_spin = QSpinBox()
        self.font_size_spin.setRange(10, 72)
        self.font_size_spin.setValue(18)
        self.font_size_spin.setFixedHeight(35)
        style_layout.addWidget(self.font_size_spin, 1, 1)

        style_layout.addWidget(QLabel("背景色值:"), 2, 0)
        self.bg_color_edit = LineEdit()
        self.bg_color_edit.setText("#333333")
        self.bg_color_edit.setPlaceholderText("如 #333333")
        self.bg_color_edit.setFixedHeight(35)
        style_layout.addWidget(self.bg_color_edit, 2, 1)

        style_layout.addWidget(QLabel("字幕位置:"), 3, 0)
        self.position_combo = ComboBox()
        position_options = ["bottom", "top"]
        self.position_combo.addItems(position_options)
        self.position_combo.setCurrentIndex(0)
        self.position_combo.setFixedHeight(35)
        style_layout.addWidget(self.position_combo, 3, 1)

        style_group.setLayout(style_layout)
        layout.addWidget(style_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("输出视频名称:"), 0, 0)
        self.output_name_edit = LineEdit()
        self.output_name_edit.setPlaceholderText("输入输出视频名称...")
        self.output_name_edit.setFixedHeight(35)
        output_layout.addWidget(self.output_name_edit, 0, 1)

        merge_btn = PrimaryPushButton(FluentIcon.MEDIA, "整合总视频")
        merge_btn.setFixedHeight(45)
        merge_btn.clicked.connect(self.merge_video_subtitle)
        output_layout.addWidget(merge_btn, 0, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        layout.addStretch()

    def browse_file(self, file_type):
        if file_type == "video":
            file_path = self.get_file_path("选择视频文件",
                "视频文件 (*.mp4 *.mov *.avi);;所有文件 (*)")
            if file_path:
                self.video_path_edit.setText(file_path)
        elif file_type == "srt":
            file_path = self.get_file_path("选择SRT字幕文件",
                "SRT字幕文件 (*.srt);;所有文件 (*)")
            if file_path:
                self.srt_path_edit.setText(file_path)
        elif file_type == "font":
            file_path = self.get_file_path("选择字体文件",
                "字体文件 (*.otf *.ttf);;所有文件 (*)")
            if file_path:
                self.font_path_edit.setText(file_path)

    def merge_video_subtitle(self):
        video_path = self.video_path_edit.text().strip()
        srt_path = self.srt_path_edit.text().strip()
        font_path = self.font_path_edit.text().strip()
        font_size = self.font_size_spin.value()
        bg_color = self.bg_color_edit.text().strip()
        position = self.position_combo.currentText()
        output_name = self.output_name_edit.text().strip() or "output"

        # 验证输入
        if not all([video_path, srt_path, font_path]):
            self.show_error("错误", "请选择视频、字幕和字体文件")
            return

        if not all([os.path.exists(video_path), os.path.exists(srt_path), os.path.exists(font_path)]):
            self.show_error("错误", "请确保所有文件路径都有效")
            return

        try:
            temp_dir = os.path.join(os.getcwd(), 'temp')
            os.makedirs(temp_dir, exist_ok=True)

            ts = datetime.now().strftime("%Y%m%d%H%M")
            output_path = os.path.join(temp_dir, f"{output_name}-{ts}.mp4")

            # 位置映射
            pos_map = {"bottom": "2", "top": "8"}
            alignment = pos_map.get(position, "2")

            # 颜色格式转换（ASS格式：&HBBGGRR&）
            def hex_to_ass_color(hex_color):
                hex_color = hex_color.lstrip('#')
                if len(hex_color) == 6:
                    b, g, r = hex_color[4:6], hex_color[2:4], hex_color[0:2]
                    return f"&H00{b}{g}{r}&"
                elif len(hex_color) == 8:  # 带透明度
                    a, b, g, r = hex_color[0:2], hex_color[6:8], hex_color[4:6], hex_color[2:4]
                    return f"&H{a}{b}{g}{r}&"
                else:
                    return "&H000000&"

            ass_color = hex_to_ass_color(bg_color)

            # 字体名只要文件名不带扩展
            fontname = os.path.splitext(os.path.basename(font_path))[0]

            # 构造force_style
            force_style = f"FontName={fontname},FontSize={font_size},OutlineColour={ass_color},Alignment={alignment}"

            # FFmpeg命令
            cmd = [
                "ffmpeg", "-y", "-i", video_path, "-vf",
                f"subtitles='{srt_path}':force_style='{force_style}'",
                "-c:a", "copy", output_path
            ]

            self.show_info("开始整合", "正在整合视频和字幕...")

            # 执行FFmpeg命令
            result = subprocess.run(cmd, capture_output=True, text=True)

            if os.path.exists(output_path) and os.path.getsize(output_path) > 1024:
                self.show_success("完成", f"带字幕视频已保存: {output_path}")
            else:
                self.show_error("错误", f"整合失败: {result.stderr}")

        except Exception as e:
            self.show_error("错误", f"整合异常: {str(e)}")

class ImageExtractPage(BasePage):
    """图像提取页面 - 从音频/视频中提取封面或帧"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.audio_files = []  # 存储待处理的音频文件
        self.video_files = []  # 存储待处理的视频文件
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🖼️ 图像提取")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 创建选项卡
        self.pivot = Pivot(self)
        self.pivot.addItem(routeKey="audio_extract", text="音频封面提取")
        self.pivot.addItem(routeKey="video_extract", text="视频帧提取")
        layout.addWidget(self.pivot)

        # 堆叠窗口
        self.stackedWidget = QStackedWidget(self)
        layout.addWidget(self.stackedWidget)

        # 添加子页面
        self.stackedWidget.addWidget(self.create_audio_extract_tab())
        self.stackedWidget.addWidget(self.create_video_extract_tab())

        # 连接信号
        self.pivot.currentItemChanged.connect(
            lambda k: self.stackedWidget.setCurrentIndex(
                ["audio_extract", "video_extract"].index(k)
            )
        )

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def create_audio_extract_tab(self):
        """创建音频封面提取标签页"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)

        # 音频文件选择组
        audio_group = QGroupBox("音频文件选择")
        audio_layout = QGridLayout()

        audio_layout.addWidget(QLabel("添加音频文件:"), 0, 0)
        self.audio_file_edit = DraggableLineEdit(self, "audio")
        self.audio_file_edit.setPlaceholderText("选择或拖拽音频文件到此处...")
        self.audio_file_edit.setFixedHeight(35)
        audio_layout.addWidget(self.audio_file_edit, 0, 1)

        audio_browse_btn = PushButton(FluentIcon.FOLDER, "浏览")
        audio_browse_btn.setFixedWidth(80)
        audio_browse_btn.clicked.connect(self.browse_audio_files)
        audio_layout.addWidget(audio_browse_btn, 0, 2)

        # 批量音频文件夹
        audio_layout.addWidget(QLabel("批量文件夹:"), 1, 0)
        self.audio_folder_edit = DraggableLineEdit(self, "audio_folder")
        self.audio_folder_edit.setPlaceholderText("选择包含音频的文件夹...")
        self.audio_folder_edit.setFixedHeight(35)
        audio_layout.addWidget(self.audio_folder_edit, 1, 1)

        audio_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        audio_folder_btn.setFixedWidth(80)
        audio_folder_btn.clicked.connect(self.browse_audio_folder)
        audio_layout.addWidget(audio_folder_btn, 1, 2)

        audio_group.setLayout(audio_layout)
        layout.addWidget(audio_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("保存文件夹:"), 0, 0)
        self.audio_output_edit = LineEdit()
        self.audio_output_edit.setText("media/audio_covers")
        self.audio_output_edit.setPlaceholderText("选择保存文件夹...")
        self.audio_output_edit.setFixedHeight(35)
        output_layout.addWidget(self.audio_output_edit, 0, 1)

        output_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        output_folder_btn.setFixedWidth(80)
        output_folder_btn.clicked.connect(lambda: self.browse_output_folder("audio"))
        output_layout.addWidget(output_folder_btn, 0, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        # 操作按钮
        extract_btn = PrimaryPushButton(FluentIcon.DOWNLOAD, "批量提取封面")
        extract_btn.setFixedHeight(45)
        extract_btn.clicked.connect(self.extract_audio_covers)
        layout.addWidget(extract_btn)

        layout.addStretch()
        return widget

    def create_video_extract_tab(self):
        """创建视频帧提取标签页"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(0, 20, 0, 0)
        layout.setSpacing(15)

        # 视频文件选择组
        video_group = QGroupBox("视频文件选择")
        video_layout = QGridLayout()

        video_layout.addWidget(QLabel("添加视频文件:"), 0, 0)
        self.video_file_edit = DraggableLineEdit(self, "video")
        self.video_file_edit.setPlaceholderText("选择或拖拽视频文件到此处...")
        self.video_file_edit.setFixedHeight(35)
        video_layout.addWidget(self.video_file_edit, 0, 1)

        video_browse_btn = PushButton(FluentIcon.FOLDER, "浏览")
        video_browse_btn.setFixedWidth(80)
        video_browse_btn.clicked.connect(self.browse_video_files)
        video_layout.addWidget(video_browse_btn, 0, 2)

        # 批量视频文件夹
        video_layout.addWidget(QLabel("批量文件夹:"), 1, 0)
        self.video_folder_edit = DraggableLineEdit(self, "video_folder")
        self.video_folder_edit.setPlaceholderText("选择包含视频的文件夹...")
        self.video_folder_edit.setFixedHeight(35)
        video_layout.addWidget(self.video_folder_edit, 1, 1)

        video_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        video_folder_btn.setFixedWidth(80)
        video_folder_btn.clicked.connect(self.browse_video_folder)
        video_layout.addWidget(video_folder_btn, 1, 2)

        video_group.setLayout(video_layout)
        layout.addWidget(video_group)

        # 提取设置组
        extract_group = QGroupBox("提取设置")
        extract_layout = QGridLayout()

        extract_layout.addWidget(QLabel("提取模式:"), 0, 0)
        self.frame_type_combo = ComboBox()
        self.frame_type_combo.addItems(["首帧", "尾帧", "自定义时间"])
        self.frame_type_combo.setFixedHeight(35)
        self.frame_type_combo.currentTextChanged.connect(self.on_frame_type_changed)
        extract_layout.addWidget(self.frame_type_combo, 0, 1)

        extract_layout.addWidget(QLabel("自定义时间:"), 1, 0)
        self.custom_time_edit = LineEdit()
        self.custom_time_edit.setText("00:00:10")
        self.custom_time_edit.setPlaceholderText("HH:MM:SS")
        self.custom_time_edit.setFixedHeight(35)
        self.custom_time_edit.setEnabled(False)
        extract_layout.addWidget(self.custom_time_edit, 1, 1)

        extract_group.setLayout(extract_layout)
        layout.addWidget(extract_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("保存文件夹:"), 0, 0)
        self.video_output_edit = LineEdit()
        self.video_output_edit.setText("media/video_frames")
        self.video_output_edit.setPlaceholderText("选择保存文件夹...")
        self.video_output_edit.setFixedHeight(35)
        output_layout.addWidget(self.video_output_edit, 0, 1)

        output_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        output_folder_btn.setFixedWidth(80)
        output_folder_btn.clicked.connect(lambda: self.browse_output_folder("video"))
        output_layout.addWidget(output_folder_btn, 0, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        # 操作按钮
        extract_btn = PrimaryPushButton(FluentIcon.DOWNLOAD, "批量提取帧")
        extract_btn.setFixedHeight(45)
        extract_btn.clicked.connect(self.extract_video_frames)
        layout.addWidget(extract_btn)

        layout.addStretch()
        return widget

    def on_frame_type_changed(self, text):
        """帧类型变化时的处理"""
        self.custom_time_edit.setEnabled(text == "自定义时间")

    # 文件浏览方法
    def browse_audio_files(self):
        file_path = self.get_file_path("选择音频文件",
            "音频文件 (*.mp3 *.m4a *.aac *.flac *.wav *.ogg);;所有文件 (*)")
        if file_path:
            self.audio_file_edit.setText(file_path)

    def browse_audio_folder(self):
        folder_path = self.get_folder_path("选择音频文件夹")
        if folder_path:
            self.audio_folder_edit.setText(folder_path)

    def browse_video_files(self):
        file_path = self.get_file_path("选择视频文件",
            "视频文件 (*.mp4 *.mov *.avi *.mkv *.flv *.wmv);;所有文件 (*)")
        if file_path:
            self.video_file_edit.setText(file_path)

    def browse_video_folder(self):
        folder_path = self.get_folder_path("选择视频文件夹")
        if folder_path:
            self.video_folder_edit.setText(folder_path)

    def browse_output_folder(self, file_type):
        folder_path = self.get_folder_path("选择保存文件夹")
        if folder_path:
            if file_type == "audio":
                self.audio_output_edit.setText(folder_path)
            else:
                self.video_output_edit.setText(folder_path)

    # 提取方法
    def extract_audio_covers(self):
        """提取音频封面"""
        files_to_process = []

        # 添加单个文件
        single_file = self.audio_file_edit.text().strip()
        if single_file and os.path.exists(single_file):
            files_to_process.append(single_file)

        # 添加文件夹中的文件
        folder_path = self.audio_folder_edit.text().strip()
        if folder_path and os.path.exists(folder_path):
            for filename in os.listdir(folder_path):
                if filename.lower().endswith(('.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg')):
                    files_to_process.append(os.path.join(folder_path, filename))

        if not files_to_process:
            self.show_error("错误", "请选择音频文件或文件夹")
            return

        output_folder = self.audio_output_edit.text().strip() or "media/audio_covers"
        os.makedirs(output_folder, exist_ok=True)

        self.show_info("开始处理", f"正在处理 {len(files_to_process)} 个音频文件...")

        completed = 0
        for audio_path in files_to_process:
            base_name = os.path.splitext(os.path.basename(audio_path))[0]
            output_path = os.path.join(output_folder, f"{base_name}.jpg")

            worker = AudioCoverExtractThread(audio_path, output_path)
            worker.progress_updated.connect(lambda v: self.progress_bar.setValue(int((completed + v/100) / len(files_to_process) * 100)))
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(lambda success, msg, path=audio_path: self.on_audio_extract_finished(success, msg, path))
            worker.start()

            self.worker_threads.append(worker)
            completed += 1

    def extract_video_frames(self):
        """提取视频帧"""
        files_to_process = []

        # 添加单个文件
        single_file = self.video_file_edit.text().strip()
        if single_file and os.path.exists(single_file):
            files_to_process.append(single_file)

        # 添加文件夹中的文件
        folder_path = self.video_folder_edit.text().strip()
        if folder_path and os.path.exists(folder_path):
            for filename in os.listdir(folder_path):
                if filename.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.flv', '.wmv')):
                    files_to_process.append(os.path.join(folder_path, filename))

        if not files_to_process:
            self.show_error("错误", "请选择视频文件或文件夹")
            return

        output_folder = self.video_output_edit.text().strip() or "media/video_frames"
        os.makedirs(output_folder, exist_ok=True)

        frame_type_map = {"首帧": "first", "尾帧": "last", "自定义时间": "custom"}
        frame_type = frame_type_map.get(self.frame_type_combo.currentText(), "first")
        custom_time = self.custom_time_edit.text().strip()

        self.show_info("开始处理", f"正在处理 {len(files_to_process)} 个视频文件...")

        completed = 0
        for video_path in files_to_process:
            base_name = os.path.splitext(os.path.basename(video_path))[0]
            frame_label = "_首帧" if frame_type == "first" else ("_尾帧" if frame_type == "last" else f"_{custom_time}")
            output_path = os.path.join(output_folder, f"{base_name}{frame_label}.jpg")

            worker = VideoFrameExtractThread(video_path, output_path, frame_type, custom_time)
            worker.progress_updated.connect(lambda v: self.progress_bar.setValue(int((completed + v/100) / len(files_to_process) * 100)))
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(lambda success, msg, path=video_path: self.on_video_extract_finished(success, msg, path))
            worker.start()

            self.worker_threads.append(worker)
            completed += 1

    def on_audio_extract_finished(self, success, message, path):
        """音频提取完成回调"""
        if success:
            self.show_success("完成", f"封面提取成功: {os.path.basename(path)}")
        else:
            self.show_warning("跳过", f"{os.path.basename(path)}: {message}")

    def on_video_extract_finished(self, success, message, path):
        """视频提取完成回调"""
        if success:
            self.show_success("完成", f"帧提取成功: {os.path.basename(path)}")
        else:
            self.show_error("错误", f"{os.path.basename(path)}: {message}")


class DraggableLineEdit(LineEdit):
    """支持拖拽的LineEdit - 支持音频、视频、图片、SRT字幕、字体文件和文件夹"""

    def __init__(self, parent, drag_type):
        super().__init__(parent)
        self.drag_type = drag_type
        self.setAcceptDrops(True)

        # 定义各种文件类型的扩展名
        self.FILE_EXTENSIONS = {
            "audio": ('.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus'),
            "video": ('.mp4', '.mov', '.avi', '.mkv', '.flv', '.wmv'),
            "image": ('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'),
            "srt": ('.srt',),
            "font": ('.ttf', '.otf', '.woff', '.woff2'),
            "audio_folder": None,  # 文件夹类型
            "video_folder": None,
            "image_folder": None,
            "folder": None
        }

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.accept()
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        if event.mimeData().hasUrls():
            event.accept()
        else:
            event.ignore()

    def dropEvent(self, event):
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        for file_path in files:
            # 文件夹类型拖拽
            if "folder" in self.drag_type:
                if os.path.isdir(file_path):
                    self.setText(file_path)
                    break
            # 文件类型拖拽
            else:
                extensions = self.FILE_EXTENSIONS.get(self.drag_type, ())
                if extensions and file_path.lower().endswith(extensions) and os.path.exists(file_path):
                    self.setText(file_path)
                    break
                # 特殊处理：如果没有匹配扩展名，但文件存在且是文件，也接受
                elif extensions and os.path.isfile(file_path):
                    self.setText(file_path)
                    break


# 工作信号类
class WorkerSignals(QObject):
    """工作线程信号"""
    finished = pyqtSignal(str, str)  # output_path, message
    errno = pyqtSignal(str, str)  # output_path, error_message
    progress = pyqtSignal(str, int)  # message, percentage


# 音视频合并工作线程
class MergeMediaWorker(QRunnable):
    """音视频合并工作线程"""

    def __init__(self, files, output_path, media_type):
        super().__init__()
        self.files = files
        self.output_path = output_path
        self.media_type = media_type
        self.signals = WorkerSignals()

    def run(self):
        """执行合并"""
        try:
            # 创建输出目录
            os.makedirs(os.path.dirname(self.output_path), exist_ok=True)

            # 创建临时列表文件
            list_file = os.path.join(os.path.dirname(self.output_path), 'filelist.txt')
            with open(list_file, 'w', encoding='utf-8') as f:
                for file in self.files:
                    f.write(f"file '{file}'\n")

            # 使用 ffmpeg 合并
            cmd = [
                'ffmpeg',
                '-f', 'concat',
                '-safe', '0',
                '-i', list_file,
                '-c', 'copy',
                '-y',
                self.output_path
            ]

            self.signals.progress.emit(f"正在合并 {len(self.files)} 个文件...", 50)

            result = subprocess.run(cmd, capture_output=True, text=True)

            # 清理临时文件
            if os.path.exists(list_file):
                os.remove(list_file)

            if result.returncode == 0 and os.path.exists(self.output_path):
                file_type = "音频" if self.media_type == 'audio' else "视频"
                self.signals.progress.emit(f"{file_type}合并完成", 100)
                self.signals.finished.emit(
                    self.output_path,
                    f"{len(self.files)} 个{file_type}文件已成功合并到 {os.path.basename(self.output_path)}"
                )
            else:
                error_msg = result.stderr if result.stderr else "未知错误"
                self.signals.errno.emit(self.output_path, f"合并失败: {error_msg}")

        except Exception as e:
            self.signals.errno.emit(self.output_path, f"合并异常: {str(e)}")


class MergeMediaWidget(BasePage):
    """音视频合并界面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.files = []
        self.thread_pool = QThreadPool.globalInstance()
        self.processing = False
        self.media_type = 'audio'  # 默认音频模式

        # JSON配置文件路径
        self.config_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cache')
        os.makedirs(self.config_dir, exist_ok=True)
        self.config_file = os.path.join(self.config_dir, 'merge_media_config.json')

        # 先初始化UI
        self.init_ui()
        self.setAcceptDrops(True)

        # UI初始化完成后再加载配置
        self.load_config()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎵 音视频合并")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 选项卡切换（顶部）
        self.segmented = SegmentedWidget(self)
        self.segmented.addItem(routeKey='audio', text='音频合并', onClick=lambda: self.switch_mode('audio'))
        self.segmented.addItem(routeKey='video', text='视频合并', onClick=lambda: self.switch_mode('video'))
        self.segmented.setCurrentItem('audio')
        layout.addWidget(self.segmented)

        # 文件列表标签
        list_label = BodyLabel("源文件列表（可拖拽文件到此处添加）", self)
        list_label.setFont(LABEL_FONT)
        layout.addWidget(list_label)

        # 文件表格（自适应高度）
        self.table = TableWidget(self)
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(['文件名', '序号', '操作'])
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeToContents)
        self.table.setEditTriggers(TableWidget.NoEditTriggers)
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(TableWidget.SelectRows)
        # 禁用内部拖拽，改用按钮上下移
        self.table.setDragDropMode(TableWidget.DropOnly)
        self.table.setAcceptDrops(True)
        self.table.viewport().setAcceptDrops(True)
        # 设置拖拽行为
        self.table.dragEnterEvent = self.table_drag_enter_event
        self.table.dropEvent = self.table_drop_event
        # 设置表格可以自适应高度
        self.table.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        layout.addWidget(self.table)

        # 占位符（让上面的表格可以自适应高度）
        layout.addStretch()

        # 操作按钮区域
        button_layout = QHBoxLayout()

        add_button = PushButton(FIF.ADD, "添加文件", self)
        add_button.clicked.connect(self.select_files)
        button_layout.addWidget(add_button)

        up_button = PushButton(FIF.UP, "上移", self)
        up_button.clicked.connect(self.move_up)
        button_layout.addWidget(up_button)

        down_button = PushButton(FIF.DOWN, "下移", self)
        down_button.clicked.connect(self.move_down)
        button_layout.addWidget(down_button)

        remove_button = PushButton(FIF.DELETE, "移除选中", self)
        remove_button.clicked.connect(self.remove_selected)
        button_layout.addWidget(remove_button)

        clear_button = PushButton(FIF.CANCEL, "清空列表", self)
        clear_button.clicked.connect(self.clear_files)
        button_layout.addWidget(clear_button)

        button_layout.addStretch()
        layout.addLayout(button_layout)

        # 输出设置区域
        output_layout = QHBoxLayout()

        output_label = BodyLabel("输出目录：", self)
        output_label.setFixedWidth(80)
        self.output_input = LineEdit(self)
        self.output_input.setPlaceholderText("默认保存到 output 目录")
        self.output_input.setText(os.path.join(os.getcwd(), 'output'))
        self.output_input.setReadOnly(True)
        output_browse_button = PushButton("浏览", self)
        output_browse_button.clicked.connect(self.browse_output)
        output_layout.addWidget(output_label)
        output_layout.addWidget(self.output_input)
        output_layout.addWidget(output_browse_button)
        layout.addLayout(output_layout)

        # 日志区域
        log_label = BodyLabel("处理日志：", self)
        log_label.setFont(LABEL_FONT)
        layout.addWidget(log_label)

        self.log_text = QTextEdit(self)
        self.log_text.setReadOnly(True)
        self.log_text.setPlaceholderText("日志将显示在这里...")
        self.log_text.setMaximumHeight(150)
        layout.addWidget(self.log_text)

        # 开始合并按钮（最下方）
        self.merge_button = PrimaryPushButton(FIF.SYNC, "开始合并", self)
        self.merge_button.setMinimumHeight(45)
        self.merge_button.clicked.connect(self.start_merge)
        self.merge_button.setEnabled(False)
        layout.addWidget(self.merge_button)

    def switch_mode(self, mode):
        """切换音频/视频模式"""
        self.media_type = mode
        # 清空当前列表
        self.files.clear()
        self.table.setRowCount(0)
        self.update_merge_button_state()
        self.add_log(f"切换到 {'音频' if mode == 'audio' else '视频'} 合并模式")
        # 切换模式后重新加载对应模式的配置
        self.load_config()
    
    def move_up(self):
        """上移选中的文件"""
        current_row = self.table.currentRow()
        if current_row > 0:
            # 交换文件
            self.files[current_row], self.files[current_row - 1] = self.files[current_row - 1], self.files[current_row]
            # 重建表格
            self.refresh_table_from_files()
            # 保存配置
            self.save_config()
            # 重新选中
            self.table.selectRow(current_row - 1)
            self.add_log(f"上移：{os.path.basename(self.files[current_row - 1])}")
    
    def move_down(self):
        """下移选中的文件"""
        current_row = self.table.currentRow()
        if current_row >= 0 and current_row < len(self.files) - 1:
            # 交换文件
            self.files[current_row], self.files[current_row + 1] = self.files[current_row + 1], self.files[current_row]
            # 重建表格
            self.refresh_table_from_files()
            # 保存配置
            self.save_config()
            # 重新选中
            self.table.selectRow(current_row + 1)
            self.add_log(f"下移：{os.path.basename(self.files[current_row + 1])}")
    
    def load_config(self):
        """从JSON文件加载配置"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    
                # 根据当前模式加载对应的文件列表
                mode_key = 'audio' if self.media_type == 'audio' else 'video'
                if mode_key in config and isinstance(config[mode_key], list):
                    # 只保留仍然存在的文件
                    valid_files = []
                    for item in config[mode_key]:
                        if os.path.exists(item['path']):
                            valid_files.append(item['path'])
                    
                    self.files = valid_files
                    
                    # 重建表格
                    self.refresh_table_from_files()
                    
                    if valid_files:
                        self.add_log(f"已加载 {len(valid_files)} 个文件")
                else:
                    self.files = []
                    self.table.setRowCount(0)
        except Exception as e:
            logging.error(f"加载配置文件失败: {str(e)}")
            self.files = []
            self.table.setRowCount(0)
    
    def save_config(self):
        """保存配置到JSON文件"""
        try:
            config = {}
            
            # 保存音频文件列表
            audio_files = []
            if self.media_type == 'audio':
                for index, file_path in enumerate(self.files):
                    audio_files.append({
                        'path': file_path,
                        'sequence': index + 1
                    })
            config['audio'] = audio_files
            
            # 保存视频文件列表
            video_files = []
            if self.media_type == 'video':
                for index, file_path in enumerate(self.files):
                    video_files.append({
                        'path': file_path,
                        'sequence': index + 1
                    })
            config['video'] = video_files
            
            # 写入JSON文件
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(config, f, ensure_ascii=False, indent=2)
                
        except Exception as e:
            logging.error(f"保存配置文件失败: {str(e)}")
    
    def refresh_table_from_files(self):
        """从files列表重建表格"""
        # 清空表格
        self.table.setRowCount(0)
        
        # 重新填充表格
        for index, file_path in enumerate(self.files):
            row = self.table.rowCount()
            self.table.insertRow(row)
            
            # 文件名
            name_item = QTableWidgetItem(os.path.basename(file_path))
            name_item.setData(Qt.UserRole, file_path)
            self.table.setItem(row, 0, name_item)
            
            # 序号
            seq_item = QTableWidgetItem(str(index + 1))
            seq_item.setTextAlignment(Qt.AlignCenter)
            self.table.setItem(row, 1, seq_item)
            
            # 操作按钮
            op_button = PushButton(FIF.DELETE, "删除", self)
            op_button.clicked.connect(lambda checked, r=row: self.remove_row(r))
            self.table.setCellWidget(row, 2, op_button)

    def select_files(self):
        """选择文件对话框"""
        if self.media_type == 'audio':
            files, _ = QFileDialog.getOpenFileNames(self, "选择音频文件", "",
                                                    "音频文件 (*.mp3 *.wav *.ogg *.flac *.aac *.m4a)")
        else:
            files, _ = QFileDialog.getOpenFileNames(self, "选择视频文件", "",
                                                    "视频文件 (*.mp4 *.avi *.mov *.mkv *.ts *.flv)")

        for file in files:
            self.add_file(file)

    def add_file(self, file_path):
        """添加文件到列表"""
        if file_path in self.files:
            InfoBar.warning("提示", f"文件 {os.path.basename(file_path)} 已存在", parent=self,
                          position=InfoBarPosition.TOP, duration=2000)
            return

        self.files.append(file_path)
        row_count = self.table.rowCount()

        # 文件名
        name_item = QTableWidgetItem(os.path.basename(file_path))
        name_item.setData(Qt.UserRole, file_path)

        # 序号
        seq_item = QTableWidgetItem(str(row_count + 1))
        seq_item.setTextAlignment(Qt.AlignCenter)

        # 操作按钮
        op_button = PushButton(FIF.DELETE, "删除", self)
        op_button.clicked.connect(lambda checked, row=row_count: self.remove_row(row))

        self.table.insertRow(row_count)
        self.table.setItem(row_count, 0, name_item)
        self.table.setItem(row_count, 1, seq_item)
        self.table.setCellWidget(row_count, 2, op_button)

        self.update_merge_button_state()
        self.add_log(f"添加文件：{os.path.basename(file_path)}")
        # 保存配置
        self.save_config()

    def remove_row(self, row):
        """删除指定行"""
        if 0 <= row < self.table.rowCount():
            file_path = self.table.item(row, 0).data(Qt.UserRole)
            self.files.remove(file_path)
            self.table.removeRow(row)
            self.refresh_table_from_files()
            self.update_merge_button_state()
            # 保存配置
            self.save_config()

    def remove_selected(self):
        """移除选中的行"""
        selected_rows = set(index.row() for index in self.table.selectedIndexes())
        if not selected_rows:
            InfoBar.warning("提示", "请先选择要移除的文件", parent=self,
                          position=InfoBarPosition.TOP, duration=2000)
            return

        # 从后往前删除，避免索引变化
        for row in sorted(selected_rows, reverse=True):
            file_path = self.table.item(row, 0).data(Qt.UserRole)
            self.files.remove(file_path)
            self.table.removeRow(row)

        self.refresh_table_from_files()
        self.update_merge_button_state()
        # 保存配置
        self.save_config()

    def clear_files(self):
        """清空文件列表"""
        self.files.clear()
        self.table.setRowCount(0)
        self.update_merge_button_state()
        self.add_log("已清空文件列表")
        # 保存配置
        self.save_config()

    def browse_output(self):
        """浏览输出目录"""
        dir_path = QFileDialog.getExistingDirectory(self, "选择输出目录", self.output_input.text())
        if dir_path:
            self.output_input.setText(dir_path)

    def update_merge_button_state(self):
        """更新合并按钮状态"""
        has_files = len(self.files) > 0
        self.merge_button.setEnabled(has_files and not self.processing)

    def start_merge(self):
        """开始合并"""
        if not self.files:
            InfoBar.warning("提示", "请先添加文件", parent=self, position=InfoBarPosition.TOP, duration=2000)
            return

        if self.processing:
            return

        # 生成输出文件名（时间戳）
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        if self.media_type == 'audio':
            output_file = f"audio_merge_{timestamp}.mp3"
        else:
            output_file = f"video_merge_{timestamp}.mp4"

        output_path = os.path.join(self.output_input.text(), output_file)

        self.processing = True
        self.merge_button.setEnabled(False)
        self.add_log(f"开始合并 {len(self.files)} 个 {'音频' if self.media_type == 'audio' else '视频'} 文件...")

        worker = MergeMediaWorker(self.files, output_path, self.media_type)
        worker.signals.finished.connect(self.on_merge_finished)
        worker.signals.errno.connect(self.on_merge_error)
        self.thread_pool.start(worker)

    def on_merge_finished(self, output_path, message):
        """合并完成回调"""
        self.processing = False
        self.update_merge_button_state()
        self.add_log(f"✅ {message}")
        InfoBar.success("成功", message, parent=self, position=InfoBarPosition.TOP, duration=3000)

        # 打开输出目录
        output_dir = os.path.dirname(output_path)
        try:
            if platform.system() == "Windows":
                os.startfile(output_dir)
            elif platform.system() == "Darwin":
                subprocess.Popen(["open", output_dir])
            else:
                subprocess.Popen(["xdg-open", output_dir])
        except Exception as e:
            logging.error(f"无法打开目录：{str(e)}")

    def on_merge_error(self, output_path, error_message):
        """合并错误回调"""
        self.processing = False
        self.update_merge_button_state()
        self.add_log(f"❌ 合并失败：{error_message}")
        InfoBar.error("失败", error_message, parent=self, position=InfoBarPosition.TOP, duration=3000)

    def add_log(self, message):
        """添加日志消息"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_text.append(f"[{timestamp}] {message}")

    # 拖拽事件处理
    def dragEnterEvent(self, event):
        """拖拽进入事件"""
        if event.mimeData().hasUrls():
            event.accept()
        else:
            event.ignore()

    def dropEvent(self, event):
        """拖拽放置事件"""
        urls = event.mimeData().urls()
        for url in urls:
            file_path = url.toLocalFile()
            if os.path.isfile(file_path):
                # 根据当前模式检查文件类型
                if self.media_type == 'audio':
                    audio_exts = ['.mp3', '.wav', '.ogg', '.flac', '.aac', '.m4a']
                    if any(file_path.lower().endswith(ext) for ext in audio_exts):
                        self.add_file(file_path)
                    else:
                        InfoBar.warning("提示", "请拖拽音频文件", parent=self,
                                      position=InfoBarPosition.TOP, duration=2000)
                else:
                    video_exts = ['.mp4', '.avi', '.mov', '.mkv', '.ts', '.flv']
                    if any(file_path.lower().endswith(ext) for ext in video_exts):
                        self.add_file(file_path)
                    else:
                        InfoBar.warning("提示", "请拖拽视频文件", parent=self,
                                      position=InfoBarPosition.TOP, duration=2000)

    def table_drag_enter_event(self, event):
        """表格拖拽进入事件"""
        if event.mimeData().hasUrls():
            event.accept()
        else:
            super(self.table.__class__, self.table).dragEnterEvent(event)

    def table_drop_event(self, event):
        """表格拖拽放置事件"""
        if event.mimeData().hasUrls():
            # 将文件添加到列表末尾
            self.dropEvent(event)
        else:
            # 处理行拖拽重排
            super(self.table.__class__, self.table).dropEvent(event)


# 主窗口类
class MainWindow(FluentWindow):
    def __init__(self):
        super().__init__()

        self.init_window()
        self.init_navigation()

    def init_window(self):
        """初始化主窗口"""
        self.setWindowTitle("BOZO-MCN 多媒体编辑器 2.0")
        self.setMinimumSize(1200, 800)
        self.resize(1400, 900)

        # 设置应用图标（窗口标题栏和任务栏）
        icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png")
        if os.path.exists(icon_path):
            self.setWindowIcon(QIcon(icon_path))

    def init_navigation(self):
        """初始化导航栏"""
        # 添加首页
        self.addSubInterface(
            self.create_home_page(),
            FluentIcon.HOME,
            "首页",
            NavigationItemPosition.TOP
        )

        # 添加图像提取
        self.addSubInterface(
            self.create_image_extract_page(),
            FluentIcon.PHOTO,
            "图像提取",
            NavigationItemPosition.TOP
        )

        # 添加音视频合并
        self.addSubInterface(
            self.create_merge_media_page(),
            FluentIcon.MUSIC,
            "音视频合并",
            NavigationItemPosition.TOP
        )

        # 添加声音管理
        self.addSubInterface(
            self.create_voice_manager_page(),
            FluentIcon.MICROPHONE,
            "声音管理",
            NavigationItemPosition.TOP
        )

        # 添加API声音生成
        self.addSubInterface(
            self.create_api_voice_page(),
            FluentIcon.ROBOT,
            "API声音生成",
            NavigationItemPosition.TOP
        )

        # 添加导航项
        self.addSubInterface(
            self.create_video_convert_page(),
            FluentIcon.VIDEO,
            "视频转换",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_image_to_video_page(),
            FluentIcon.PHOTO,
            "图片转视频",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_merge_page(),
            FluentIcon.PLAY,
            "合并视频音频",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_subtitle_page(),
            FluentIcon.DOCUMENT,
            "生成字幕",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_subtitle_text_page(),
            FluentIcon.FONT,
            "字幕转文本",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_adjust_subtitle_page(),
            FluentIcon.EDIT,
            "调整字幕",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_merge_subtitle_page(),
            FluentIcon.MEDIA,
            "整合字幕",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_settings_page(),
            FluentIcon.SETTING,
            "设置",
            NavigationItemPosition.BOTTOM
        )


    def create_home_page(self):
        """创建首页"""
        self.home_page = HomePage(self)
        self.home_page.setObjectName("home_page")
        return self.home_page

    def create_voice_manager_page(self):
        """创建声音管理页面"""
        self.voice_manager_page = VoiceManagerPage(self)
        self.voice_manager_page.setObjectName("voice_manager_page")
        return self.voice_manager_page

    def create_api_voice_page(self):
        """创建API声音生成页面"""
        page = APIVoiceApiWidget(self)
        page.setObjectName("api_voice_page")
        return page

    def create_video_convert_page(self):
        """创建视频转换页面"""
        self.video_convert_page = VideoConvertPage(self)
        self.video_convert_page.setObjectName("video_convert_page")
        return self.video_convert_page

    def create_image_to_video_page(self):
        """创建图片转视频页面"""
        self.image_to_video_page = ImageToVideoPage(self)
        self.image_to_video_page.setObjectName("image_to_video_page")
        return self.image_to_video_page

    def create_merge_page(self):
        """创建合并页面"""
        self.merge_page = MergeVideoAudioPage(self)
        self.merge_page.setObjectName("merge_page")
        return self.merge_page

    def create_subtitle_page(self):
        """创建字幕生成页面"""
        self.subtitle_page = SubtitleGenerationPage(self)
        self.subtitle_page.setObjectName("subtitle_page")
        return self.subtitle_page

    def create_subtitle_text_page(self):
        """创建字幕转文本页面"""
        page = SubtitleTextPage(self)
        page.setObjectName("subtitle_text_page")
        return page

    def create_adjust_subtitle_page(self):
        """创建调整字幕页面"""
        page = AdjustSubtitlePage(self)
        page.setObjectName("adjust_subtitle_page")
        return page

    def create_merge_subtitle_page(self):
        """创建整合字幕页面"""
        page = MergeSubtitlePage(self)
        page.setObjectName("merge_subtitle_page")
        return page

    def create_image_extract_page(self):
        """创建图像提取页面"""
        page = ImageExtractPage(self)
        page.setObjectName("image_extract_page")
        return page

    def create_merge_media_page(self):
        """创建音视频合并页面"""
        page = MergeMediaWidget(self)
        page.setObjectName("merge_media_page")
        return page

    def create_settings_page(self):
        """创建设置页面"""
        from qfluentwidgets import ScrollArea, SmoothScrollArea

        page = SmoothScrollArea()
        page.setObjectName("settings_page")
        widget = QWidget()
        layout = QVBoxLayout(widget)

        title = SubtitleLabel("⚙️ 设置")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 主题切换
        theme_group = QGroupBox("界面主题")
        theme_layout = QVBoxLayout()

        from qfluentwidgets import setTheme, Theme, RadioButton

        self.light_radio = RadioButton("浅色主题")
        self.dark_radio = RadioButton("深色主题")
        self.dark_radio.setChecked(True)

        self.light_radio.clicked.connect(lambda: setTheme(Theme.LIGHT))
        self.dark_radio.clicked.connect(lambda: setTheme(Theme.DARK))

        theme_layout.addWidget(self.light_radio)
        theme_layout.addWidget(self.dark_radio)
        theme_group.setLayout(theme_layout)

        layout.addWidget(theme_group)

        # 打开文件夹按钮
        folders_group = QGroupBox("常用文件夹")
        folders_layout = QGridLayout()

        font_btn = PushButton(FluentIcon.FONT, "字体文件夹")
        font_btn.clicked.connect(lambda: self.open_folder("font"))
        folders_layout.addWidget(font_btn, 0, 0)

        temp_btn = PushButton(FluentIcon.FOLDER, "临时文件")
        temp_btn.clicked.connect(lambda: self.open_folder("temp"))
        folders_layout.addWidget(temp_btn, 0, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "字幕文件夹")
        srt_btn.clicked.connect(lambda: self.open_folder("SRT"))
        folders_layout.addWidget(srt_btn, 1, 0)

        speech_btn = PushButton(FluentIcon.MICROPHONE, "语音文件夹")
        speech_btn.clicked.connect(lambda: self.open_folder("speech"))
        folders_layout.addWidget(speech_btn, 1, 1)

        folders_group.setLayout(folders_layout)
        layout.addWidget(folders_group)

        layout.addStretch()

        page.setWidget(widget)
        page.setWidgetResizable(True)
        return page

    def open_folder(self, folder_name):
        """打开指定文件夹"""
        folder_path = os.path.join(os.getcwd(), folder_name)
        os.makedirs(folder_path, exist_ok=True)

        if sys.platform == "darwin":  # macOS
            subprocess.run(["open", folder_path])
        elif sys.platform == "win32":  # Windows
            subprocess.run(["explorer", folder_path])
        else:  # Linux
            subprocess.run(["xdg-open", folder_path])

def main():
    # 屏蔽 Qt 字体相关的警告日志（Segoe UI 在 macOS 上不存在的警告）
    os.environ["QT_LOGGING_RULES"] = "qt.qpa.fonts.warning=false"

    # 设置高DPI支持
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    # 在创建 QApplication 前注册字体替换，将 Windows 字体映射到 macOS 系统字体
    QFont.insertSubstitution("Segoe UI", ".AppleSystemUIFont")
    QFont.insertSubstitution("Microsoft YaHei", "PingFang SC")

    app = QApplication(sys.argv)

    # 设置全局默认字体
    default_font = QFont()
    default_font.setPointSize(12)
    app.setFont(default_font)

    # 设置应用信息
    app.setApplicationName("BOZO-MCN多媒体编辑器")
    app.setApplicationVersion("2.2.1")

    # 设置应用图标（用于 Dock/任务栏）
    icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png")
    if os.path.exists(icon_path):
        app.setWindowIcon(QIcon(icon_path))

    # 设置深色主题
    setTheme(Theme.DARK)

    # 创建主窗口
    window = MainWindow()
    window.show()

    sys.exit(app.exec_())

if __name__ == "__main__":
    main()