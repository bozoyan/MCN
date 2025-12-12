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
                            QSplitter, QFrame, QScrollArea, QGroupBox, QDoubleSpinBox,
                            QMenu, QAction, QDialog, QFormLayout, QDialogButtonBox)
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
                font-size: 14px;
                padding: 5px;
                background-color: #ffff00;
                border: 1px solid #dcdcdc;
                border-radius: 8px;
            }
            QMenu::item {
                padding: 8px 30px;
                border-radius: 4px;
            }
            QMenu::item:selected {
                background-color: #f0f0f0;
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
        # 添加首页
        self.addSubInterface(
            self.create_home_page(),
            FluentIcon.HOME,
            "首页",
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


    def create_home_page(self):
        """创建首页"""
        self.home_page = HomePage(self)
        self.home_page.setObjectName("home_page")
        return self.home_page

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