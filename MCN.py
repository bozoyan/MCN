import os
import time
import sys
import re
import shutil
import subprocess
import requests
import json
from datetime import datetime
from PIL import Image
import chardet
from concurrent.futures import ThreadPoolExecutor
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QCheckBox,
                            QComboBox, QSpinBox, QProgressBar, QMessageBox,
                            QSplitter, QFrame, QScrollArea, QGroupBox, QDoubleSpinBox)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl
from PyQt5.QtGui import QFont, QIcon, QDesktopServices
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, CheckBox, SpinBox,
                          ProgressBar, InfoBar, InfoBarPosition, ToolTipFilter,
                          setTheme, Theme, FluentIcon as FIcon, SmoothScrollArea)

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

            # 检查音频格式并转换
            ext = os.path.splitext(self.audio_path)[1].lower()
            wav_path = self.audio_path
            if ext != ".wav":
                srt_dir = os.path.join(os.getcwd(), 'SRT')
                os.makedirs(srt_dir, exist_ok=True)
                base_name = os.path.splitext(os.path.basename(self.audio_path))[0]
                ts = datetime.now().strftime("%Y%m%d%H%M")
                wav_path = os.path.join(srt_dir, f"{base_name}-{ts}.wav")

                cmd_ffmpeg = ["ffmpeg", "-y", "-i", self.audio_path, wav_path]
                subprocess.run(cmd_ffmpeg)

            self.progress_updated.emit(30)

            # whisper.cpp命令
            whisper_bin = "/Users/yons/AI/whisper.cpp/build/bin/whisper-cli"
            whisper_model = "/Users/yons/AI/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin"
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

            self.log_updated.emit("开始生成字幕...")
            shell_cmd = f"source ~/.zshrc && conda activate modelscope && {' '.join(cmd_whisper)}"

            result = subprocess.run(shell_cmd, shell=True, capture_output=True, text=True, executable="/bin/zsh")

            self.progress_updated.emit(80)

            if os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"字幕生成完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                self.finished.emit(False, "字幕文件生成失败")

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
                "model": "Qwen/Qwen2.5-Coder-32B-Instruct",
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
                "max_tokens": 4096,
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
        self.video_path_edit = LineEdit()
        self.video_path_edit.setPlaceholderText("请选择视频文件...")
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
        self.batch_path_edit = LineEdit()
        self.batch_path_edit.setPlaceholderText("选择包含视频的文件夹...")
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

    def split_video(self):
        video_path = self.video_path_edit.text().strip()
        segment_name = self.segment_name_edit.text().strip() or "segment"
        count = self.split_count_spin.value()

        if not video_path or not os.path.exists(video_path):
            self.show_error("错误", "请选择有效的视频文件")
            return

        # 这里实现视频分割逻辑
        self.show_info("功能开发中", "视频分割功能正在开发中...")

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
        self.image_path_edit = LineEdit()
        self.image_path_edit.setPlaceholderText("选择单个图片文件...")
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
        self.batch_folder_edit = LineEdit()
        self.batch_folder_edit.setPlaceholderText("选择包含图片的文件夹...")
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
            "9:16 (900x1600)", "16:9 (1600x900)", "1:2 (870x1740)",
            "2:1 (1740x870)", "自定义"
        ]
        self.size_combo.addItems(size_options)
        self.size_combo.setCurrentIndex(3)  # 默认9:16
        self.size_combo.currentTextChanged.connect(self.on_size_changed)
        self.size_combo.setFixedHeight(35)
        video_layout.addWidget(self.size_combo, 0, 1)

        video_layout.addWidget(QLabel("自定义尺寸:"), 1, 0)
        self.size_edit = LineEdit()
        self.size_edit.setText("900x1600")
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
        self.cover_path_edit = LineEdit()
        self.cover_path_edit.setPlaceholderText("选择封面图片文件 (可选)...")
        self.cover_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.cover_path_edit, 0, 1)

        cover_btn = PushButton(FluentIcon.PHOTO, "浏览")
        cover_btn.setFixedWidth(80)
        cover_btn.clicked.connect(lambda: self.browse_file("cover"))
        file_layout.addWidget(cover_btn, 0, 2)

        file_layout.addWidget(QLabel("视频片段文件夹:"), 1, 0)
        self.video_folder_edit = LineEdit()
        self.video_folder_edit.setPlaceholderText("选择包含视频片段的文件夹...")
        self.video_folder_edit.setFixedHeight(35)
        file_layout.addWidget(self.video_folder_edit, 1, 1)

        video_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        video_folder_btn.setFixedWidth(80)
        video_folder_btn.clicked.connect(lambda: self.browse_file("video_folder"))
        file_layout.addWidget(video_folder_btn, 1, 2)

        file_layout.addWidget(QLabel("音频文件:"), 2, 0)
        self.audio_path_edit = LineEdit()
        self.audio_path_edit.setPlaceholderText("选择音频文件...")
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

    def merge_videos(self):
        video_folder = self.video_folder_edit.text().strip()
        audio_path = self.audio_path_edit.text().strip()
        output_name = self.output_name_edit.text().strip() or "output"

        if not video_folder or not audio_path:
            self.show_error("错误", "请选择视频文件夹和音频文件")
            return

        # 这里实现基础合并逻辑
        self.show_info("功能开发中", "基础合并功能正在开发中...")

    def merge_with_zoom(self):
        video_folder = self.video_folder_edit.text().strip()
        audio_path = self.audio_path_edit.text().strip()
        output_name = self.output_name_edit.text().strip() or "output"
        zoom_end = self.zoom_end_spin.value()
        filter_type = self.filter_combo.currentText()

        if not video_folder or not audio_path:
            self.show_error("错误", "请选择视频文件夹和音频文件")
            return

        # 这里实现缩放合并逻辑
        self.show_info("功能开发中", "缩放合并功能正在开发中...")

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
        self.audio_path_edit = LineEdit()
        self.audio_path_edit.setPlaceholderText("选择音频文件...")
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
        self.srt_path_edit = LineEdit()
        self.srt_path_edit.setPlaceholderText("选择SRT字幕文件...")
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
        self.srt_path_edit = LineEdit()
        self.srt_path_edit.setPlaceholderText("选择SRT字幕文件...")
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

            # 读取原SRT文件获取时间轴
            with open(srt_path, 'r', encoding='utf-8') as f:
                srt_content = f.read()

            # 提取时间轴
            times = re.findall(r'(\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3})', srt_content)

            # 获取新内容行
            new_lines = content.split('\n')
            new_lines = [line.strip() for line in new_lines if line.strip()]

            if not new_lines:
                self.show_error("错误", "字幕内容为空")
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
        self.video_path_edit = LineEdit()
        self.video_path_edit.setPlaceholderText("选择视频文件...")
        self.video_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.video_path_edit, 0, 1)

        video_btn = PushButton(FluentIcon.VIDEO, "浏览")
        video_btn.setFixedWidth(80)
        video_btn.clicked.connect(lambda: self.browse_file("video"))
        file_layout.addWidget(video_btn, 0, 2)

        file_layout.addWidget(QLabel("SRT字幕文件:"), 1, 0)
        self.srt_path_edit = LineEdit()
        self.srt_path_edit.setPlaceholderText("选择SRT字幕文件...")
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
        self.font_path_edit = LineEdit()
        self.font_path_edit.setText("font/Light.otf")
        self.font_path_edit.setPlaceholderText("选择字体文件...")
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
            FluentIcon.LINK,
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
    app.setApplicationVersion("2.0")

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