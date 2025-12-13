import os
import time
import sys
import re
import shutil
import subprocess
import requests
import json
import logging
from datetime import datetime
from PIL import Image
import chardet
from concurrent.futures import ThreadPoolExecutor, as_completed
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QCheckBox,
                            QComboBox, QSpinBox, QProgressBar, QMessageBox,
                            QSplitter, QFrame, QScrollArea, QGroupBox, QDoubleSpinBox,
                            QDialog, QDialogButtonBox, QFormLayout)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl, QSettings
from PyQt5.QtGui import QFont, QIcon, QDesktopServices
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, CheckBox, SpinBox,
                          ProgressBar, InfoBar, InfoBarPosition, ToolTipFilter,
                          setTheme, Theme, FluentIcon as FIcon, SmoothScrollArea)

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 配置管理器
class ConfigManager:
    """配置文件管理器"""

    def __init__(self, config_file="config.json"):
        self.config_file = config_file
        self.config = self.load_config()

    def load_config(self):
        """加载配置文件"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"加载配置文件失败: {e}")
                return self.get_default_config()
        else:
            logger.info("配置文件不存在，使用默认配置")
            return self.get_default_config()

    def get_default_config(self):
        """获取默认配置"""
        return {
            "paths": {
                "whisper_binary": "whisper.cpp/build/bin/whisper-cli",
                "whisper_model": "whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin",
                "ffmpeg_binary": "ffmpeg"
            },
            "api": {
                "siliconcloud_key": "",
                "base_url": "https://api.siliconflow.cn/v1/chat/completions",
                "model": "Qwen/Qwen2.5-Coder-32B-Instruct"
            },
            "processing": {
                "max_concurrent_workers": 4,
                "batch_size": 10,
                "timeout_seconds": 120
            },
            "ui": {
                "theme": "dark",
                "window_width": 1400,
                "window_height": 900
            },
            "directories": {
                "temp": "temp",
                "srt": "SRT",
                "speech": "speech",
                "font": "font"
            }
        }

    def save_config(self):
        """保存配置文件"""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
            logger.info("配置文件保存成功")
            return True
        except Exception as e:
            logger.error(f"保存配置文件失败: {e}")
            return False

    def get(self, key_path, default=None):
        """获取配置值"""
        keys = key_path.split('.')
        value = self.config
        for key in keys:
            if isinstance(value, dict) and key in value:
                value = value[key]
            else:
                return default
        return value

    def set(self, key_path, value):
        """设置配置值"""
        keys = key_path.split('.')
        config = self.config
        for key in keys[:-1]:
            if key not in config:
                config[key] = {}
            config = config[key]
        config[keys[-1]] = value

# 环境检查器
class EnvironmentChecker:
    """环境依赖检查器"""

    @staticmethod
    def check_dependencies():
        """检查必要的依赖"""
        dependencies = {
            'ffmpeg': 'ffmpeg -version',
            'whisper': 'whisper --help'  # 备用检查
        }

        results = {}
        for name, command in dependencies.items():
            try:
                result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=10)
                results[name] = result.returncode == 0
            except (subprocess.TimeoutExpired, Exception):
                results[name] = False

        return results

    @staticmethod
    def check_directories():
        """检查并创建必要的目录"""
        directories = ['temp', 'SRT', 'speech', 'font']
        created_dirs = []

        for dir_name in directories:
            dir_path = os.path.join(os.getcwd(), dir_name)
            if not os.path.exists(dir_path):
                os.makedirs(dir_path, exist_ok=True)
                created_dirs.append(dir_name)

        return created_dirs

# API密钥设置对话框
class ApiKeyDialog(QDialog):
    """API密钥设置对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("API密钥设置")
        self.setMinimumWidth(400)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 表单布局
        form_layout = QFormLayout()

        self.api_key_edit = LineEdit()
        self.api_key_edit.setPlaceholderText("请输入SiliconCloud API密钥...")
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        form_layout.addRow("SiliconCloud API密钥:", self.api_key_edit)

        self.base_url_edit = LineEdit()
        self.base_url_edit.setText("https://api.siliconflow.cn/v1/chat/completions")
        form_layout.addRow("API基础URL:", self.base_url_edit)

        self.model_edit = LineEdit()
        self.model_edit.setText("Qwen/Qwen2.5-Coder-32B-Instruct")
        form_layout.addRow("模型名称:", self.model_edit)

        layout.addLayout(form_layout)

        # 按钮
        button_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

    def get_settings(self):
        return {
            'api_key': self.api_key_edit.text().strip(),
            'base_url': self.base_url_edit.text().strip(),
            'model': self.model_edit.text().strip()
        }

# 全局配置管理器
config_manager = ConfigManager()

# 配置常量
TITLE_FONT = QFont("Microsoft YaHei", 16)
LABEL_FONT = QFont("Microsoft YaHei", 12)
ENTRY_FONT = QFont("Microsoft YaHei", 10)

# 工作线程类
class WorkerThread(QThread):
    """工作线程基类"""
    progress_updated = pyqtSignal(int)
    log_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.is_cancelled = False
        self.process = None

    def cancel(self):
        """取消当前任务"""
        self.is_cancelled = True
        if self.process:
            self.process.terminate()
            self.process.wait(timeout=5)

    def run_command(self, cmd, shell=False):
        """执行命令并处理结果"""
        try:
            if shell:
                self.process = subprocess.Popen(cmd, shell=True, capture_output=True, text=True)
                stdout, stderr = self.process.communicate()
                return self.process.returncode, stdout, stderr
            else:
                self.process = subprocess.Popen(cmd, capture_output=True, text=True)
                stdout, stderr = self.process.communicate()
                return self.process.returncode, stdout, stderr
        except Exception as e:
            return -1, "", str(e)

class VideoConversionThread(WorkerThread):
    """视频转换线程"""

    def __init__(self, video_path, output_path, mode="mute", parent=None):
        super().__init__(parent)
        self.video_path = video_path
        self.output_path = output_path
        self.mode = mode

    def run(self):
        try:
            if self.is_cancelled:
                return

            ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')

            if self.mode == "mute":
                cmd = [ffmpeg_path, "-y", "-i", self.video_path, "-an", self.output_path]
            elif self.mode == "audio":
                cmd = [ffmpeg_path, "-y", "-i", self.video_path, "-vn", "-acodec", "pcm_s16le", self.output_path]
            else:
                self.finished.emit(False, f"不支持的模式: {self.mode}")
                return

            self.log_updated.emit(f"开始处理: {os.path.basename(self.video_path)}")
            self.progress_updated.emit(10)

            returncode, stdout, stderr = self.run_command(cmd)

            if self.is_cancelled:
                self.finished.emit(False, "任务已取消")
                return

            if returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                error_msg = f"处理失败: {stderr}" if stderr else "处理失败，未知错误"
                self.finished.emit(False, error_msg)

        except Exception as e:
            self.finished.emit(False, f"处理异常: {str(e)}")

class VideoSplitThread(WorkerThread):
    """视频分割线程"""

    def __init__(self, video_path, output_dir, segment_name, count, parent=None):
        super().__init__(parent)
        self.video_path = video_path
        self.output_dir = output_dir
        self.segment_name = segment_name
        self.count = count

    def run(self):
        try:
            if self.is_cancelled:
                return

            ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')

            # 获取视频时长
            cmd_duration = [ffmpeg_path, "-i", self.video_path]
            returncode, stdout, stderr = self.run_command(cmd_duration)

            if returncode != 0 and returncode != 1:  # ffmpeg返回1表示成功但无输出流
                self.finished.emit(False, f"获取视频信息失败: {stderr}")
                return

            # 解析视频时长
            duration_match = re.search(r'Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})', stderr)
            if not duration_match:
                self.finished.emit(False, "无法获取视频时长")
                return

            hours, minutes, seconds = map(float, duration_match.groups())
            total_duration = hours * 3600 + minutes * 60 + seconds
            segment_duration = total_duration / self.count

            self.log_updated.emit(f"视频总时长: {total_duration:.2f}秒，分成{self.count}段，每段{segment_duration:.2f}秒")

            # 分割视频
            for i in range(self.count):
                if self.is_cancelled:
                    return

                start_time = i * segment_duration
                output_path = os.path.join(self.output_dir, f"{self.segment_name}_part{i+1:02d}.mp4")

                cmd = [
                    ffmpeg_path, "-y",
                    "-ss", str(start_time),
                    "-i", self.video_path,
                    "-t", str(segment_duration),
                    "-c", "copy",
                    output_path
                ]

                self.log_updated.emit(f"正在分割第{i+1}段...")
                progress = int((i + 1) / self.count * 100)
                self.progress_updated.emit(progress)

                returncode, stdout, stderr = self.run_command(cmd)

                if returncode != 0:
                    self.finished.emit(False, f"分割第{i+1}段失败: {stderr}")
                    return

            self.progress_updated.emit(100)
            self.finished.emit(True, f"视频分割完成，共{self.count}段")

        except Exception as e:
            self.finished.emit(False, f"视频分割异常: {str(e)}")

class MergeVideoAudioThread(WorkerThread):
    """合并视频和音频线程"""

    def __init__(self, video_folder, audio_path, output_path, cover_path=None, parent=None):
        super().__init__(parent)
        self.video_folder = video_folder
        self.audio_path = audio_path
        self.output_path = output_path
        self.cover_path = cover_path

    def run(self):
        try:
            if self.is_cancelled:
                return

            ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')

            # 获取视频文件列表
            video_files = [f for f in os.listdir(self.video_folder)
                          if f.lower().endswith(('.mp4', '.mov', '.avi'))]
            video_files.sort()

            if not video_files:
                self.finished.emit(False, "文件夹中没有找到视频文件")
                return

            self.log_updated.emit(f"找到{len(video_files)}个视频文件")

            # 创建文件列表
            list_file = os.path.join(os.getcwd(), 'temp', 'video_list.txt')
            with open(list_file, 'w') as f:
                for video_file in video_files:
                    video_path = os.path.join(self.video_folder, video_file)
                    f.write(f"file '{video_path}'\n")

            self.progress_updated.emit(20)

            # 合并视频
            merged_video = os.path.join(os.getcwd(), 'temp', 'merged_video.mp4')
            cmd = [
                ffmpeg_path, "-y",
                "-f", "concat",
                "-safe", "0",
                "-i", list_file,
                "-c", "copy",
                merged_video
            ]

            self.log_updated.emit("正在合并视频片段...")
            returncode, stdout, stderr = self.run_command(cmd)

            if returncode != 0:
                self.finished.emit(False, f"合并视频失败: {stderr}")
                return

            self.progress_updated.emit(50)

            # 添加音频
            final_cmd = [
                ffmpeg_path, "-y",
                "-i", merged_video,
                "-i", self.audio_path,
                "-c:v", "copy",
                "-c:a", "aac",
                "-map", "0:v:0",
                "-map", "1:a:0",
                self.output_path
            ]

            if self.cover_path and os.path.exists(self.cover_path):
                final_cmd.insert(2, "-i")
                final_cmd.insert(3, self.cover_path)
                final_cmd.extend(["-map", "2:v:0", "-disposition:v:0", "attached_pic"])

            self.log_updated.emit("正在添加音频...")
            returncode, stdout, stderr = self.run_command(final_cmd)

            if returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.finished.emit(True, self.output_path)
            else:
                self.finished.emit(False, f"添加音频失败: {stderr}")

            # 清理临时文件
            if os.path.exists(list_file):
                os.remove(list_file)
            if os.path.exists(merged_video):
                os.remove(merged_video)

        except Exception as e:
            self.finished.emit(False, f"合并视频音频异常: {str(e)}")

class MergeVideoWithZoomThread(WorkerThread):
    """带缩放效果的视频合并线程"""

    def __init__(self, video_folder, audio_path, output_path, zoom_end, filter_type, parent=None):
        super().__init__(parent)
        self.video_folder = video_folder
        self.audio_path = audio_path
        self.output_path = output_path
        self.zoom_end = zoom_end
        self.filter_type = filter_type

    def run(self):
        try:
            if self.is_cancelled:
                return

            ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')

            # 获取视频文件列表
            video_files = [f for f in os.listdir(self.video_folder)
                          if f.lower().endswith(('.mp4', '.mov', '.avi'))]
            video_files.sort()

            if not video_files:
                self.finished.emit(False, "文件夹中没有找到视频文件")
                return

            self.log_updated.emit(f"找到{len(video_files)}个视频文件，开始创建复杂滤镜...")

            # 构建复杂滤镜
            inputs = []
            filter_parts = []
            total_duration = 0

            for i, video_file in enumerate(video_files):
                video_path = os.path.join(self.video_folder, video_file)
                inputs.extend(["-i", video_path])

            inputs.extend(["-i", self.audio_path])

            # 获取音频时长
            cmd_duration = [ffmpeg_path, "-i", self.audio_path]
            returncode, stdout, stderr = self.run_command(cmd_duration)

            audio_duration = 0
            if returncode != 0 and returncode != 1:
                duration_match = re.search(r'Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})', stderr)
                if duration_match:
                    hours, minutes, seconds = map(float, duration_match.groups())
                    audio_duration = hours * 3600 + minutes * 60 + seconds

            segment_duration = audio_duration / len(video_files)

            # 创建缩放滤镜
            for i in range(len(video_files)):
                start_time = i * segment_duration
                end_time = (i + 1) * segment_duration

                if self.filter_type == "scale+zoom":
                    filter_expr = f"[{i}:v]scale=2*iw:2*ih,crop=iw:ih,zoompan=z='if(lt(on,{segment_duration}),1+{self.zoom_end-1}*on/{segment_duration},{self.zoom_end})':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080[v{i}]"
                elif self.filter_type == "scale+zoompan":
                    filter_expr = f"[{i}:v]scale=1920:1080,zoompan=z='1+{self.zoom_end-1}*on/{segment_duration}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:fps=30[v{i}]"
                else:
                    filter_expr = f"[{i}:v]scale=1920:1080[v{i}]"

                filter_parts.append(filter_expr)

            # 连接所有视频片段
            for i in range(len(video_files)):
                filter_parts.append(f"[v{i}][{i+len(video_files)}:a]")

            filter_parts.append(f"concat=n={len(video_files)}:v=1:a=1[outv][outa]")

            filter_complex = ";".join(filter_parts)

            self.progress_updated.emit(30)

            # 执行合成
            cmd = [
                ffmpeg_path, "-y"
            ] + inputs + [
                "-filter_complex", filter_complex,
                "-map", "[outv]",
                "-map", "[outa]",
                "-c:v", "libx264",
                "-c:a", "aac",
                "-preset", "medium",
                self.output_path
            ]

            self.log_updated.emit("正在应用滤镜并合并...")
            returncode, stdout, stderr = self.run_command(cmd)

            if returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.finished.emit(True, self.output_path)
            else:
                self.finished.emit(False, f"缩放合并失败: {stderr}")

        except Exception as e:
            self.finished.emit(False, f"缩放合并异常: {str(e)}")

class ImageToVideoThread(WorkerThread):
    """图片转视频线程"""

    def __init__(self, image_path, output_path, size, duration, parent=None):
        super().__init__(parent)
        self.image_path = image_path
        self.output_path = output_path
        self.size = size
        self.duration = duration

    def run(self):
        try:
            if self.is_cancelled:
                return

            width, height = self.size.split('x')
            fps = 30
            img_name = os.path.splitext(os.path.basename(self.image_path))[0]
            temp_dir = os.path.join(os.getcwd(), 'temp')
            bg_img = os.path.join(temp_dir, f"{img_name}-bg.jpg")

            os.makedirs(temp_dir, exist_ok=True)

            self.progress_updated.emit(10)
            ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')

            # 生成模糊背景
            cmd_bg = [
                ffmpeg_path, "-y", "-loop", "1", "-framerate", str(fps), "-t", str(self.duration),
                "-i", self.image_path,
                "-vf", f"scale=2*{width}:2*{height},boxblur=20:1,crop={width}:{height}",
                "-q:v", "3", bg_img
            ]

            returncode, stdout, stderr = self.run_command(cmd_bg)
            if returncode != 0:
                logger.warning(f"背景生成失败，继续使用原图: {stderr}")
                bg_img = self.image_path

            self.progress_updated.emit(50)

            # 合成前景+背景
            filter_complex = (
                f"[0:v]scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=rgba[fg];"
                f"[1:v]scale={width}:{height}[bg];"
                f"[bg][fg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=1,fade=t=out:st={self.duration-1}:d=1"
            )

            cmd = [
                ffmpeg_path, "-y",
                "-loop", "1", "-framerate", str(fps), "-t", str(self.duration), "-i", self.image_path,
                "-i", bg_img,
                "-filter_complex", filter_complex,
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-r", str(fps),
                self.output_path
            ]

            returncode, stdout, stderr = self.run_command(cmd)

            if self.is_cancelled:
                self.finished.emit(False, "任务已取消")
                return

            if returncode == 0 and os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"生成完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                error_msg = f"转换失败: {stderr}" if stderr else "转换失败，未知错误"
                self.finished.emit(False, error_msg)

            # 清理临时背景文件
            if bg_img != self.image_path and os.path.exists(bg_img):
                os.remove(bg_img)

        except Exception as e:
            self.finished.emit(False, f"转换异常: {str(e)}")

class SRTGenerationThread(WorkerThread):
    """字幕生成线程"""

    def __init__(self, audio_path, output_path, max_line_length=30, parent=None):
        super().__init__(parent)
        self.audio_path = audio_path
        self.output_path = output_path
        self.max_line_length = max_line_length

    def run(self):
        try:
            if self.is_cancelled:
                return

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

                ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')
                cmd_ffmpeg = [ffmpeg_path, "-y", "-i", self.audio_path, wav_path]

                self.log_updated.emit("正在转换音频格式...")
                returncode, stdout, stderr = self.run_command(cmd_ffmpeg)

                if returncode != 0:
                    self.finished.emit(False, f"音频格式转换失败: {stderr}")
                    return

            self.progress_updated.emit(30)

            # whisper.cpp命令
            whisper_bin = config_manager.get('paths.whisper_binary', 'whisper')
            whisper_model = config_manager.get('paths.whisper_model', 'ggml-large-v3-turbo-q5_0.bin')
            of_path = os.path.splitext(self.output_path)[0]
            threads = min(os.cpu_count() or 4, config_manager.get('processing.max_concurrent_workers', 4))

            # 检查whisper文件是否存在
            if not os.path.exists(whisper_bin):
                self.finished.emit(False, f"Whisper二进制文件不存在: {whisper_bin}")
                return

            if not os.path.exists(whisper_model):
                self.finished.emit(False, f"Whisper模型文件不存在: {whisper_model}")
                return

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

            # 尝试使用不同的方式执行whisper
            try:
                # 首先尝试直接执行
                returncode, stdout, stderr = self.run_command(cmd_whisper)

                # 如果直接执行失败，尝试使用shell激活conda环境
                if returncode != 0:
                    shell_cmd = f"source ~/.zshrc && conda activate modelscope && {' '.join(cmd_whisper)}"
                    result = subprocess.run(shell_cmd, shell=True, capture_output=True, text=True,
                                         executable="/bin/zsh", timeout=config_manager.get('processing.timeout_seconds', 120))
                    returncode, stdout, stderr = result.returncode, result.stdout, result.stderr

            except subprocess.TimeoutExpired:
                self.finished.emit(False, "字幕生成超时")
                return

            self.progress_updated.emit(80)

            if os.path.exists(self.output_path):
                self.progress_updated.emit(100)
                self.log_updated.emit(f"字幕生成完成: {os.path.basename(self.output_path)}")
                self.finished.emit(True, self.output_path)
            else:
                error_msg = f"字幕文件生成失败" + (f": {stderr}" if stderr else "")
                self.finished.emit(False, error_msg)

            # 清理临时wav文件
            if wav_path != self.audio_path and os.path.exists(wav_path):
                os.remove(wav_path)

        except Exception as e:
            self.finished.emit(False, f"字幕生成异常: {str(e)}")

class SRTToTextThread(WorkerThread):
    """SRT转文本线程"""

    def __init__(self, srt_path, output_path, parent=None):
        super().__init__(parent)
        self.srt_path = srt_path
        self.output_path = output_path

    def run(self):
        try:
            if self.is_cancelled:
                return

            self.progress_updated.emit(10)

            # 检测编码
            with open(self.srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'
                logger.info(f"检测到文件编码: {enc}")

            self.progress_updated.emit(30)

            lines = []
            content = raw.decode(enc, errors='replace')

            for line in content.splitlines():
                line = line.strip()
                if line.isdigit():
                    continue
                if re.match(r"\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}", line):
                    continue
                if not line:
                    continue
                lines.append(line)

            merged_text = '\n'.join(lines)  # 使用换行符连接，而不是空字符串

            with open(self.output_path, 'w', encoding='utf-8') as f:
                f.write(merged_text)

            self.progress_updated.emit(100)
            self.finished.emit(True, self.output_path)

        except Exception as e:
            self.finished.emit(False, f"SRT转文本异常: {str(e)}")

class SRTTranslateThread(WorkerThread):
    """SRT翻译线程"""

    def __init__(self, srt_path, output_path, target_language="English", parent=None):
        super().__init__(parent)
        self.srt_path = srt_path
        self.output_path = output_path
        self.target_language = target_language

    def run(self):
        try:
            if self.is_cancelled:
                return

            self.progress_updated.emit(10)

            # 检测编码
            with open(self.srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'

            srt_content = raw.decode(enc, errors='replace')
            self.progress_updated.emit(30)

            # 获取API配置
            api_key = config_manager.get('api.siliconcloud_key')
            if not api_key:
                # 尝试从环境变量获取
                api_key = os.environ.get("SiliconCloud_API_KEY")

            if not api_key:
                self.finished.emit(False, "未检测到API KEY，请在设置中配置")
                return

            base_url = config_manager.get('api.base_url', 'https://api.siliconflow.cn/v1/chat/completions')
            model = config_manager.get('api.model', 'Qwen/Qwen2.5-Coder-32B-Instruct')
            timeout = config_manager.get('processing.timeout_seconds', 120)

            prompt = f"帮我将输入的srt字幕文本内容翻译转换为{self.target_language}。保持srt文本结构，序号，时间都不变，只需要翻译内容，并输出srt格式的翻译内容就可以，不需要其他额外注释和说明。\n\n" + srt_content

            payload = {
                "model": model,
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
            self.log_updated.emit("正在调用翻译API...")

            try:
                resp = requests.post(base_url, json=payload, headers=headers, timeout=timeout)

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
                    error_detail = resp.text if resp.text else f"HTTP {resp.status_code}"
                    self.finished.emit(False, f"API请求失败: {error_detail}")

            except requests.exceptions.Timeout:
                self.finished.emit(False, "翻译请求超时")
            except requests.exceptions.ConnectionError:
                self.finished.emit(False, "网络连接错误")
            except Exception as e:
                self.finished.emit(False, f"翻译请求异常: {str(e)}")

        except Exception as e:
            self.finished.emit(False, f"翻译异常: {str(e)}")

# 功能页面基类
class BasePage(QWidget):
    """页面基类"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.worker_threads = []
        self.active_workers = 0
        self.max_workers = config_manager.get('processing.max_concurrent_workers', 4)

        # 创建线程池
        self.thread_pool = ThreadPoolExecutor(max_workers=self.max_workers)

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

    def add_worker(self, worker):
        """添加工作线程"""
        self.worker_threads.append(worker)
        self.active_workers += 1

        worker.finished.connect(self.on_worker_finished)
        worker.start()

    def on_worker_finished(self):
        """工作线程完成回调"""
        self.active_workers -= 1

    def cancel_all_workers(self):
        """取消所有工作线程"""
        for worker in self.worker_threads:
            if worker.isRunning():
                worker.cancel()
        self.thread_pool.shutdown(wait=False)

    def cleanup_workers(self):
        """清理工作线程"""
        self.cancel_all_workers()

        # 等待所有线程结束
        for worker in self.worker_threads:
            if worker.isRunning():
                worker.quit()
                worker.wait(3000)  # 等待3秒

        self.worker_threads.clear()
        self.active_workers = 0

    def closeEvent(self, event):
        """页面关闭时清理资源"""
        self.cleanup_workers()
        super().closeEvent(event)

class VideoConvertPage(BasePage):
    """视频转换页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.batch_completed = 0
        self.batch_total = 0
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
            temp_dir = os.path.join(os.getcwd(), 'temp')
            os.makedirs(temp_dir, exist_ok=True)

            if mode == "mute":
                output_path = os.path.join(temp_dir, f"{output_name}-{ts}.mp4")
            else:
                output_path = os.path.join(temp_dir, f"{output_name}-{ts}.wav")

            worker = VideoConversionThread(video_path, output_path, mode, self)
            worker.progress_updated.connect(self.progress_bar.setValue)
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(self.on_conversion_finished)
            self.add_worker(worker)
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

        # 限制批量处理数量
        batch_size = config_manager.get('processing.batch_size', 10)
        if len(video_files) > batch_size:
            video_files = video_files[:batch_size]
            self.show_warning("批量处理限制", f"单次最多处理{batch_size}个文件，已选择前{batch_size}个")

        self.show_info("批量处理", f"找到 {len(video_files)} 个视频文件，开始处理...")

        self.batch_total = len(video_files)
        self.batch_completed = 0
        self.progress_bar.setValue(0)

        ts = datetime.now().strftime("%Y%m%d%H%M")
        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        for i, video_file in enumerate(video_files):
            video_path = os.path.join(folder_path, video_file)
            base_name = os.path.splitext(video_file)[0]

            if mode == "mute":
                output_path = os.path.join(temp_dir, f"{base_name}-mute-{ts}.mp4")
            else:
                output_path = os.path.join(temp_dir, f"{base_name}-audio-{ts}.wav")

            worker = VideoConversionThread(video_path, output_path, mode, self)
            worker.progress_updated.connect(lambda v, idx=i: self.update_batch_progress(v, idx))
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(lambda success, msg, idx=i: self.on_batch_conversion_finished(success, msg, idx))
            self.add_worker(worker)

    def update_batch_progress(self, value, worker_idx):
        """更新批量进度"""
        if self.batch_total > 0:
            # 每个任务的权重相等
            task_progress = value / 100
            overall_progress = ((self.batch_completed + task_progress) / self.batch_total) * 100
            self.progress_bar.setValue(int(overall_progress))

    def on_conversion_finished(self, success, message):
        if success:
            self.show_success("完成", f"转换完成: {message}")
        else:
            self.show_error("错误", f"转换失败: {message}")
        self.progress_bar.setValue(0)

    def on_batch_conversion_finished(self, success, message, worker_idx):
        """批量转换完成回调"""
        self.batch_completed += 1

        if success:
            self.show_info("进度", f"文件 {self.batch_completed}/{self.batch_total} 完成")
        else:
            self.show_error("错误", f"文件 {self.batch_completed} 失败: {message}")

        if self.batch_completed >= self.batch_total:
            self.progress_bar.setValue(100)
            self.show_success("批量完成", f"批量转换完成，共处理 {self.batch_total} 个文件")
            QTimer.singleShot(2000, lambda: self.progress_bar.setValue(0))

    def split_video(self):
        video_path = self.video_path_edit.text().strip()
        segment_name = self.segment_name_edit.text().strip() or "segment"
        count = self.split_count_spin.value()

        if not video_path or not os.path.exists(video_path):
            self.show_error("错误", "请选择有效的视频文件")
            return

        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        worker = VideoSplitThread(video_path, temp_dir, segment_name, count, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_split_finished)
        self.add_worker(worker)
        self.show_info("开始分割", f"正在分割视频为{count}段...")

    def on_split_finished(self, success, message):
        if success:
            self.show_success("分割完成", f"视频分割完成: {message}")
        else:
            self.show_error("分割失败", f"视频分割失败: {message}")
        self.progress_bar.setValue(0)