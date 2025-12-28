#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图片转视频生成模块 (pic2vod) - 增强且优化版-V2.0.1
基于 BizyAir API 的图片转视频功能，支持批量生成和更美观的界面
"""

import os
import sys
import json
import time
import threading
import requests
import base64
import re
import traceback
import platform
import subprocess
from datetime import datetime

# 尝试导入图像处理库
try:
    from PIL import Image
    import io
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# 尝试导入多媒体组件
try:
    from PyQt5.QtMultimediaWidgets import QVideoWidget
    from PyQt5.QtMultimedia import QMediaPlayer, QMediaContent
    MULTIMEDIA_AVAILABLE = True
except ImportError:
    MULTIMEDIA_AVAILABLE = False
    print("警告: PyQt5多媒体组件不可用，视频播放功能将被禁用")
    # 创建占位符类以避免导入错误
    class QVideoWidget:
        def __init__(self, *args, **kwargs):
            pass
    class QMediaPlayer:
        def __init__(self, *args, **kwargs):
            pass
        def setVideoOutput(self, widget):
            pass
        def setMedia(self, content):
            pass
        def play(self):
            pass
        def stop(self):
            pass
        def pause(self):
            pass
    class QMediaContent:
        def __init__(self, url):
            pass

from PyQt5.QtCore import QThread, pyqtSignal, QTimer, Qt, QMimeData, QUrl, QObject, QCoreApplication
from PyQt5.QtWidgets import QSizePolicy
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QLineEdit, QTextEdit, QPushButton, QComboBox,
                            QSpinBox, QProgressBar, QMessageBox, QFileDialog,
                            QGroupBox, QTabWidget, QSplitter, QFrame,
                            QGridLayout, QScrollArea, QSlider, QCheckBox, QDialog, QSizePolicy)
from PyQt5.QtGui import QPixmap, QDragEnterEvent, QDropEvent, QPalette, QDesktopServices, QColor

import qfluentwidgets as qf
from qfluentwidgets import (FluentIcon, CardWidget, ElevatedCardWidget,
                          SmoothScrollArea, SubtitleLabel, BodyLabel,
                          PrimaryPushButton, PushButton, LineEdit, ComboBox,
                          ProgressBar, InfoBar, InfoBarPosition,
                          SwitchButton, InfoBadge, TeachingTip, TeachingTipTailPosition,
                          StrongBodyLabel, CaptionLabel)

# 导入配置管理器（如果可用）
try:
    # 假设 config_manager 和 MODEL_API_KEY 可以在此处导入
    from storyboard_generator import config_manager, MODEL_API_KEY
except ImportError:
    MODEL_API_KEY = os.getenv('SiliconCloud_API_KEY')
    class ConfigManager:
        def get(self, key, default=None):
            return default
        def set(self, key, value):
            pass
    config_manager = ConfigManager()

# --- 1. 工具模块 (Utils) ---
class Utils:
    """通用工具方法集合"""

    LOG_DIR = "logs"

    @staticmethod
    def log_message(message, log_updated_signal=None, task_name=None):
        """记录日志消息，并尝试通过信号发送给UI"""
        if not os.path.exists(Utils.LOG_DIR):
            os.makedirs(Utils.LOG_DIR)

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        task_prefix = f"[{task_name}] " if task_name else ""
        log_entry = f"[{timestamp}] {task_prefix}{message}"

        if log_updated_signal:
            log_updated_signal.emit(log_entry)
        
        # 写入日志文件
        log_file = os.path.join(Utils.LOG_DIR, "pic2vod_generation.log")
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"写入日志失败: {e}")

    @staticmethod
    def compress_image(image_data, log_updated_signal=None):
        """压缩图像数据"""
        if not HAS_PIL:
            Utils.log_message("⚠️ PIL未安装，跳过图片压缩", log_updated_signal)
            return image_data

        try:
            # 将二进制数据转换为 PIL Image
            image = Image.open(io.BytesIO(image_data))

            # 转换为 RGB（如果是 RGBA 或其他格式）
            if image.mode in ('RGBA', 'LA', 'P'):
                background = Image.new('RGB', image.size, (255, 255, 255))
                if image.mode == 'P':
                    image = image.convert('RGBA')
                background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                image = background.convert('RGB')

            # 调整图片大小，保持宽高比
            max_dimension = 1280
            width, height = image.size
            
            if max(width, height) > max_dimension:
                ratio = max_dimension / max(width, height)
                new_size = tuple(int(dim * ratio) for dim in image.size)
                image = image.resize(new_size, Image.Resampling.LANCZOS)
                Utils.log_message(f"🖼️ 尺寸调整: {width}×{height} → {new_size[0]}×{new_size[1]}", log_updated_signal)
            
            # 压缩图片质量
            output = io.BytesIO()
            # 使用 JPEG 格式压缩，质量 85%
            image.save(output, format='JPEG', quality=85, optimize=True)
            compressed_data = output.getvalue()
            output.close()

            Utils.log_message(f"✅ 图片压缩成功: {len(image_data)} → {len(compressed_data)} 字节", log_updated_signal)
            return compressed_data

        except Exception as e:
            Utils.log_message(f"❌ 图片压缩失败，使用原始数据: {str(e)}", log_updated_signal)
            return image_data

    @staticmethod
    def open_folder(folder_path):
        """根据操作系统打开文件夹"""
        if not os.path.exists(folder_path):
            os.makedirs(folder_path)

        system = platform.system()
        try:
            if system == "Windows":
                os.startfile(folder_path)
            elif system == "Darwin":  # macOS
                subprocess.run(["open", folder_path])
            else:  # Linux
                subprocess.run(["xdg-open", folder_path])
            return True
        except Exception as e:
            print(f"❌ 打开文件夹失败: {str(e)}")
            return False

# --- 2. 视频设置配置管理 ---
class VideoSettingsManager:
    """视频设置配置管理器"""

    def __init__(self, config_file="video_settings.json"):
        self.config_file = config_file
        self.default_settings = {
            "video_params": {
                "width": 480,
                "height": 854,
                "duration": 5,  # 降低到5秒
                "num_frames": 81  # 5秒 × 16 + 1 = 81帧
            },
            "api_settings": {
                "key_file": "",
                "key_text": "",  # 密钥文本（直接输入的密钥）
                "key_source": "file",  # 密钥来源：file, env, text
                "web_app_id_single": 39386,  # 单图片转视频 Web App ID
                "web_app_id_frames": 39388,  # 首尾帧图片转视频 Web App ID
                "web_app_id_video": 38808,  # 视频换人物 Web App ID
                "api_url": "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
            },
            "ui_settings": {
                "last_export_dir": "output"
            }
        }

    def load_settings(self):
        """加载配置文件"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                return self._merge_settings(self.default_settings, settings)
            else:
                return self.default_settings.copy()
        except Exception as e:
            print(f"加载视频设置失败: {e}")
            return self.default_settings.copy()

    def save_settings(self, settings):
        """保存配置文件"""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(settings, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"保存视频设置失败: {e}")
            return False

    # ... 其他 getter/setter 方法不变 ...

    def get_video_params(self):
        """获取视频参数"""
        settings = self.load_settings()
        return settings.get("video_params", self.default_settings["video_params"])

    def set_video_params(self, width, height, duration, num_frames=None):
        """设置视频参数"""
        settings = self.load_settings()
        if num_frames is None:
            num_frames = duration * 16 + 1  # 自动计算帧数

        settings["video_params"] = {
            "width": width,
            "height": height,
            "duration": duration,
            "num_frames": num_frames
        }

        return self.save_settings(settings)

    def get_api_settings(self):
        """获取API设置"""
        settings = self.load_settings()
        return settings.get("api_settings", self.default_settings["api_settings"])

    def set_api_settings(self, key_file="", web_app_id_single=39386, web_app_id_frames=39388, web_app_id_video=38808, api_url=None, key_text="", key_source="file"):
        """设置API参数

        Args:
            key_file: 密钥文件路径
            web_app_id_single: 单图片转视频 Web App ID
            web_app_id_frames: 首尾帧图片转视频 Web App ID
            web_app_id_video: 视频换人物 Web App ID
            api_url: API 请求地址
            key_text: 密钥文本（直接输入的密钥）
            key_source: 密钥来源 (file, env, text)
        """
        settings = self.load_settings()

        current_api_url = settings.get("api_settings", {}).get("api_url", "https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
        if api_url is None:
            api_url = current_api_url

        settings["api_settings"] = {
            "key_file": key_file,
            "key_text": key_text,
            "key_source": key_source,
            "web_app_id_single": web_app_id_single,
            "web_app_id_frames": web_app_id_frames,
            "web_app_id_video": web_app_id_video,
            "api_url": api_url
        }
        return self.save_settings(settings)

    def _merge_settings(self, defaults, loaded):
        """合并配置，确保所有必要字段都存在"""
        result = defaults.copy()
        for key, value in loaded.items():
            if key in result:
                if isinstance(value, dict) and isinstance(result[key], dict):
                    # 递归合并字典
                    result[key] = {**result[key], **value}
                else:
                    result[key] = value
            else:
                result[key] = value # 添加新键
        return result

# --- 3. API密钥管理器 ---
class APIKeyManager:
    """API密钥管理器"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.key_text = ""  # 密钥文本
        self.current_key_index = 0
        self.web_app_id_single = 39386  # 单图片转视频 Web App ID
        self.web_app_id_frames = 39388  # 首尾帧图片转视频 Web App ID
        self.web_app_id_video = 38808  # 视频换人物 Web App ID
        self.key_source = "file"  # "file", "env" 或 "text"

    def load_keys_from_file(self, file_path):
        """从文件加载API密钥"""
        try:
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    # 过滤掉注释行和空行
                    keys = [line.strip() for line in f.readlines() if line.strip() and not line.strip().startswith('#')]
                self.api_keys = [key for key in keys if len(key) > 10]  # 过滤掉无效密钥
                self.key_file = file_path
                return True
        except Exception as e:
            print(f"加载API密钥文件失败: {e}")
        return False
    
    def load_keys_from_text(self, key_text):
        """从文本加载API密钥（支持多行，每行一个密钥）"""
        try:
            if key_text:
                # 按行分割，过滤掉注释行和空行
                keys = [line.strip() for line in key_text.split('\n') if line.strip() and not line.strip().startswith('#')]
                self.api_keys = [key for key in keys if len(key) > 10]  # 过滤掉无效密钥
                self.key_text = key_text
                return True
        except Exception as e:
            print(f"加载API密钥文本失败: {e}")
        return False

    def get_next_key(self):
        """获取下一个可用的API密钥"""
        if self.key_source == "env":
            # 如果是系统变量，只返回系统变量
            return os.getenv('SiliconCloud_API_KEY')
        elif self.key_source == "text":
            # 如果是文本密钥，从已加载的密钥列表中轮询
            if not self.api_keys:
                return None
            if self.current_key_index >= len(self.api_keys):
                self.current_key_index = 0
            key = self.api_keys[self.current_key_index]
            self.current_key_index += 1
            return key
        else:
            # 文件密钥
            if not self.api_keys:
                return None
            if self.current_key_index >= len(self.api_keys):
                self.current_key_index = 0
            key = self.api_keys[self.current_key_index]
            self.current_key_index += 1
            return key

    def get_available_keys_count(self):
        """获取可用密钥数量"""
        if self.key_source == "env":
            env_key = os.getenv('SiliconCloud_API_KEY')
            return 1 if env_key else 0
        elif self.key_source == "text":
            return len(self.api_keys)
        else:
            return len(self.api_keys)

    def get_all_keys(self):
        """获取所有可用的API密钥"""
        if self.key_source == "env":
            env_key = os.getenv('SiliconCloud_API_KEY')
            return [env_key] if env_key else []
        elif self.key_source == "text":
            return self.api_keys
        else:
            return self.api_keys

    def set_key_source(self, source):
        """设置密钥源"""
        self.key_source = source
        self.current_key_index = 0  # 重置索引

    def get_key_source(self):
        """获取当前密钥源"""
        return self.key_source

    def get_key_source_display(self):
        """获取密钥源显示文本"""
        if self.key_source == "env":
            return "系统变量"
        elif self.key_source == "text":
            return "密钥文本"
        else:
            return "文件密钥"

# --- 4. 独立任务视频生成工作线程 (SingleVideoGenerationWorker) ---
class SingleVideoGenerationWorker(QThread):
    """单个视频生成工作线程 - 支持独立计时和并发执行"""
    progress_updated = pyqtSignal(int, str, str)  # progress, message, task_id
    task_finished = pyqtSignal(bool, str, dict, str)  # success, message, result_data, task_id
    time_updated = pyqtSignal(str, str)  # time_string, task_id
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, task, task_id, api_key, api_manager, video_mode="single"):
        """
        Args:
            task: 任务数据
            task_id: 任务ID
            api_key: API密钥
            api_manager: API管理器
            video_mode: 视频生成模式 ("single" 或 "frames")
        """
        super().__init__()
        self.task = task
        self.task_id = task_id
        self.api_key = api_key
        self.api_manager = api_manager
        self.video_mode = video_mode  # "single" 或 "frames"
        self.start_time = None
        self.is_cancelled = False
        self.time_update_active = False

    def log_message(self, message):
        """记录日志消息"""
        task_name = self.task.get('name', f'任务 {self.task_id}')
        Utils.log_message(message, self.log_updated, task_name)

    def run(self):
        """运行单个视频生成任务"""
        self.start_time = time.time()
        # Timer logic moved to UI thread (TaskStatusCard)
        task_name = self.task.get('name', f'任务 {self.task_id}')

        try:
            self.log_message(f"🚀 开始生成视频: {task_name}")
            self.progress_updated.emit(5, "初始化任务...", self.task_id)

            if not self.api_key:
                self.log_message(f"❌ API密钥未配置或为空")
                self.task_finished.emit(False, "API密钥未配置", {}, self.task_id)
                return

            # 准备请求数据
            image_input = self.task.get('image_input', '')
            prompt = self.task.get('prompt', '')
            width = self.task.get('width', 480)
            height = self.task.get('height', 854)
            num_frames = self.task.get('num_frames', 81)

            self.progress_updated.emit(10, "处理图片数据...", self.task_id)
            
            # 准备输出目录
            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)
            
            # 统一文件名生成逻辑：[原文件名]_[时间戳]
            timestamp_str = datetime.now().strftime("%H%M%S")
            base_filename = f"task_{self.task_id}_{timestamp_str}"
            
            # 尝试提取文件名作为基础名
            if isinstance(image_input, str):
                if image_input.startswith('http'):
                     try:
                        url_path = image_input.split('?')[0] # 去除参数
                        name = os.path.basename(url_path)
                        name_without_ext = os.path.splitext(name)[0]
                        if name_without_ext:
                            # 过滤非法字符
                            clean_name = re.sub(r'[^\w\-_]', '_', name_without_ext)
                            base_filename = f"{clean_name}_{timestamp_str}"
                     except:
                        pass
                elif not image_input.startswith('data:'):
                    # 本地文件
                    image_path = self.task.get('image_path', '')
                    if image_path:
                        name = os.path.basename(image_path)
                        name_without_ext = os.path.splitext(name)[0]
                        clean_name = re.sub(r'[^\w\-_]', '_', name_without_ext)
                        base_filename = f"{clean_name}_{timestamp_str}"

            image_save_path = ""
            
            # 图像格式检查和转换（优化并统一处理本地文件和纯base64）
            image_value = image_input
            image_data = None

            if isinstance(image_input, str):
                if image_input.startswith('http'):
                    self.log_message(f"🌐 使用网络图片URL: {image_input}")
                    # 下载图片用于缩略图
                    try:
                        resp = requests.get(image_input, timeout=30)
                        if resp.status_code == 200:
                            image_data = resp.content
                    except Exception as e:
                        self.log_message(f"⚠️ 下载网络图片失败(仅影响缩略图): {e}")

                elif not image_input.startswith('data:'):
                    # 可能是纯base64或本地文件内容
                    image_path = self.task.get('image_path', '')
                    image_type = 'image/jpeg' 

                    if image_path and os.path.exists(image_path):
                        # 本地文件路径
                        with open(image_path, 'rb') as f:
                            image_data = f.read()
                        self.log_message(f"📁 从本地路径加载图片: {image_path}")
                    elif image_input:
                        # 纯 base64 数据
                        try:
                            image_data = base64.b64decode(image_input)
                            self.log_message(f"📝 识别为纯 Base64 数据")
                        except:
                            self.log_message(f"⚠️ 无法识别的图片输入格式")
                            self.task_finished.emit(False, "图片输入格式错误", {}, self.task_id)
                            return
                    
                    if image_data:
                        # 压缩图片
                        max_size = 8 * 1024 * 1024 # 8MB 限制
                        if len(image_data) > max_size:
                            self.log_message(f"⚠️ 图片过大({len(image_data)}字节)，开始压缩...")
                            image_data = Utils.compress_image(image_data, self.log_updated)
                            
                        import imghdr
                        detected_type = imghdr.what(None, image_data)
                        if detected_type:
                            image_type = f'image/{detected_type}'

                        base64_data = base64.b64encode(image_data).decode('utf-8')
                        image_value = f"data:{image_type};base64,{base64_data}"
                        self.log_message(f"✅ 已转换为data URL格式 ({image_type})")
                    else:
                        self.log_message(f"❌ 无法获取有效的图片数据")
                        self.task_finished.emit(False, "无法获取有效的图片数据", {}, self.task_id)
                        return
            
            # 保存缩略图
            if image_data:
                try:
                    thumb_filename = f"{base_filename}.jpg"
                    thumb_path = os.path.join(output_dir, thumb_filename)
                    
                    # 使用 PIL 调整图片大小为视频尺寸 (使用 Crop to Fill 模式，避免拉伸变形)
                    from PIL import Image, ImageOps
                    import io
                    
                    img = Image.open(io.BytesIO(image_data))
                    # 转换模式
                    if img.mode in ('RGBA', 'LA'):
                        background = Image.new(img.mode[:-1], img.size, (255, 255, 255))
                        background.paste(img, img.split()[-1])
                        img = background
                    elif img.mode != 'RGB':
                        img = img.convert('RGB')
                    
                    # 获取目标尺寸 (确保是整数)
                    target_width = int(self.task.get('width', 480))
                    target_height = int(self.task.get('height', 854))
                    
                    # 使用 ImageOps.fit 进行智能裁剪缩放 (保持比例，充满画面)
                    img_resized = ImageOps.fit(img, (target_width, target_height), method=Image.Resampling.LANCZOS)
                    
                    img_resized.save(thumb_path, 'JPEG', quality=90)
                    image_save_path = thumb_path
                    self.log_message(f"🖼️ 已保存缩略图(已裁剪为 {target_width}x{target_height}): {thumb_filename}")
                    
                except Exception as e:
                    # 如果调整大小失败，回退到直接保存
                    self.log_message(f"⚠️ 调整缩略图尺寸失败: {e}，尝试直接保存...")
                    try:
                        with open(thumb_path, 'wb') as f:
                            f.write(image_data)
                        image_save_path = thumb_path
                        self.log_message(f"🖼️ 已保存原图作为缩略图: {thumb_filename}")
                    except Exception as e2:
                        self.log_message(f"⚠️ 保存缩略图失败: {e2}")
            
            # 检查是否取消
            if self.is_cancelled:
                self.log_message("⏹️ 任务已取消")
                return

            self.progress_updated.emit(30, "发送API请求...", self.task_id)

            # 根据视频模式构建不同的 BizyAir API 请求数据格式
            if self.video_mode == "frames":
                # 首尾帧图片转视频模式
                end_image_input = self.task.get('end_image_input', '')
                end_image_value = end_image_input

                # 处理尾图（与首图类似的处理逻辑）
                if isinstance(end_image_input, str) and not end_image_input.startswith('http') and not end_image_input.startswith('data:'):
                    end_image_path = self.task.get('end_image_path', '')
                    if end_image_path and os.path.exists(end_image_path):
                        with open(end_image_path, 'rb') as f:
                            end_image_data = f.read()

                        # 压缩尾图
                        max_size = 8 * 1024 * 1024
                        if len(end_image_data) > max_size:
                            self.log_message(f"⚠️ 尾图过大({len(end_image_data)}字节)，开始压缩...")
                            end_image_data = Utils.compress_image(end_image_data, self.log_updated)

                        import imghdr
                        detected_type = imghdr.what(None, end_image_data)
                        end_image_type = f'image/{detected_type}' if detected_type else 'image/jpeg'

                        end_base64_data = base64.b64encode(end_image_data).decode('utf-8')
                        end_image_value = f"data:{end_image_type};base64,{end_base64_data}"
                        self.log_message(f"✅ 尾图已转换为data URL格式 ({end_image_type})")

                bizyair_request_data = {
                    "web_app_id": self.api_manager.web_app_id_frames,  # 使用首尾帧 Web App ID
                    "suppress_preview_output": False,
                    "input_values": {
                        "67:LoadImage.image": image_value,  # 首图
                        "99:LoadImage.image": end_image_value,  # 尾图
                        "100:easy int.value": width,
                        "101:easy int.value": height,
                        "89:WanVideoImageToVideoEncode.num_frames": num_frames
                    }
                }
                self.log_message(f"📋 使用首尾帧模式，Web App ID: {self.api_manager.web_app_id_frames}")
            elif self.video_mode == "video":
                # 视频换人物模式
                video_input = self.task.get('video_input', '')
                video_value = video_input

                # 处理视频输入（本地文件或URL）
                if isinstance(video_input, str) and not video_input.startswith('http') and not video_input.startswith('data:'):
                    video_path = self.task.get('video_path', '')
                    if video_path and os.path.exists(video_path):
                        # 对于本地视频文件，读取并转换为base64
                        with open(video_path, 'rb') as f:
                            video_data = f.read()

                        # 检查视频文件大小（视频文件可能很大）
                        max_size = 100 * 1024 * 1024  # 100MB限制
                        if len(video_data) > max_size:
                            self.log_message(f"⚠️ 视频文件过大({len(video_data)}字节)，可能影响上传速度")

                        # 转换为base64 data URL
                        video_base64 = base64.b64encode(video_data).decode('utf-8')
                        video_value = f"data:video/mp4;base64,{video_base64}"
                        self.log_message(f"✅ 视频已转换为data URL格式 (video/mp4)")

                bizyair_request_data = {
                    "web_app_id": self.api_manager.web_app_id_video,  # 使用视频换人物 Web App ID
                    "suppress_preview_output": False,
                    "input_values": {
                        "196:LoadVideo.file": video_value,  # 视频文件
                        "57:LoadImage.image": image_value,  # 目标人物图片
                        "65:WanVideoTextEncodeCached.positive_prompt": prompt,  # 提示词
                        "220:ImageResizeKJv2.width": width,
                        "220:ImageResizeKJv2.height": height
                    }
                }
                self.log_message(f"📋 使用视频换人物模式，Web App ID: {self.api_manager.web_app_id_video}")
            else:
                # 单图片转视频模式（原有逻辑）
                bizyair_request_data = {
                    "web_app_id": self.api_manager.web_app_id_single,  # 使用单图片 Web App ID
                    "suppress_preview_output": False,
                    "input_values": {
                        "67:LoadImage.image": image_value,  # data URL 或 URL 格式
                        "68:ImageResizeKJv2.width": width,
                        "68:ImageResizeKJv2.height": height,
                        "16:WanVideoTextEncode.positive_prompt": prompt,
                        "89:WanVideoImageToVideoEncode.num_frames": num_frames
                    }
                }
                self.log_message(f"📋 使用单图片模式，Web App ID: {self.api_manager.web_app_id_single}")

            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }
            
            # 获取配置的 API URL，如果未配置则使用默认值
            default_api_url = "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
            api_url = default_api_url
            if hasattr(self.api_manager, 'api_url') and self.api_manager.api_url:
                api_url = self.api_manager.api_url
            
            base_url = api_url
            self.log_message(f"📤 发送BizyAir API请求: {base_url}")
            
            # --- API请求和错误处理统一 ---
            try:
                # 禁用代理设置，确保国内API免受全局代理影响
                proxies = {"http": None, "https": None}
                
                response = requests.post(
                    base_url,
                    headers=headers,
                    json=bizyair_request_data,
                    timeout=(300, 1200),  # 5分钟连接超时，20分钟读取超时
                    proxies=proxies
                )
                
                self.log_message(f"📡 API响应状态: {response.status_code}")
                response.raise_for_status() # 抛出 HTTPError 4xx/5xx

                result_data = response.json()
                self.log_message(f"📋 API响应内容: {json.dumps(result_data, ensure_ascii=False, indent=2)}")

                request_id = result_data.get('request_id')
                status = result_data.get('status', '').lower()

                if not request_id:
                    error_msg = result_data.get('message', 'API响应格式错误：缺少request_id')
                    self.task_finished.emit(False, error_msg, {}, self.task_id)
                    return

                # 处理立即失败的情况
                if status == 'failed':
                    error_info = result_data.get('error', result_data.get('message', '任务执行失败'))
                    self.task_finished.emit(False, f"视频生成失败: {error_info}", {}, self.task_id)
                    return

                video_url = None
                
                # 如果任务立即完成且有输出
                if status == 'success' and 'outputs' in result_data:
                    outputs = result_data['outputs']
                    if outputs and len(outputs) > 0:
                        video_url = outputs[0].get('object_url', '')

                # 如果任务还在处理中，查询状态
                if not video_url:
                    self.progress_updated.emit(50, "查询任务状态...", self.task_id)
                    video_url = self.check_video_status(request_id)

                if video_url:
                    self.progress_updated.emit(90, "获取视频URL成功", self.task_id)

                    result = {
                        'id': request_id,
                        'url': video_url,
                        'width': width,
                        'height': height,
                        'num_frames': num_frames,
                        'prompt': prompt,
                        'task_name': task_name,
                        'timestamp': datetime.now().isoformat(),
                        'base_filename': base_filename,  # 传递统一的基础文件名
                        'thumbnail_path': image_save_path
                    }

                    self.progress_updated.emit(100, "任务完成！", self.task_id)
                    self.task_finished.emit(True, "视频生成成功", result, self.task_id)
                else:
                    self.task_finished.emit(False, "视频生成失败或超时", {}, self.task_id)
            
            except requests.exceptions.HTTPError as http_err:
                error_msg = f"API请求失败: HTTP {response.status_code}"
                try:
                    error_detail = response.json()
                    detail_msg = error_detail.get('message', '未知错误')
                    error_msg += f" - {detail_msg}"

                    # 特殊处理API超时错误
                    if response.status_code == 500 and '最大读取时长' in detail_msg:
                        self.log_message(f"⚠️ API云端处理超时(服务器限制约10-20分钟)")
                        self.log_message(f"💡 建议: 减少视频时长/帧数,或降低分辨率")
                        error_msg = "API云端处理超时(已达到最大时长),建议使用更短的视频或更低分辨率"
                except:
                    error_msg += f" - {response.text[:200]}"
                self.log_message(f"❌ {error_msg}")
                self.task_finished.emit(False, error_msg, {}, self.task_id)
            
            except requests.exceptions.Timeout:
                self.log_message(f"❌ API请求超时")
                self.task_finished.emit(False, "API请求超时", {}, self.task_id)
            
            except requests.exceptions.RequestException as e:
                self.log_message(f"❌ 网络错误: {str(e)}")
                self.task_finished.emit(False, f"网络错误: {str(e)}", {}, self.task_id)
            
            except Exception as e:
                self.log_message(f"❌ 任务执行异常: {str(e)} - {traceback.format_exc()}")
                self.task_finished.emit(False, f"任务执行异常: {str(e)}", {}, self.task_id)

        finally:
            self.time_update_active = False  # 停止计时更新

    def check_video_status(self, request_id):
        """查询BizyAir任务状态 (合并原 check_video_status_bizyair)"""
        max_attempts = 360  # 最大尝试次数（30分钟）
        check_interval = 5  # 检查间隔5秒

        for attempt in range(max_attempts):
            if self.is_cancelled:
                self.log_message("⏹️ 任务已取消")
                return None

            try:
                headers = {
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}"
                }

                # BizyAir查询任务状态的API端点
                response = requests.get(
                    f"https://api.bizyair.cn/w/v1/webapp/task/openapi/query?request_id={request_id}",
                    headers=headers,
                    timeout=30,
                    proxies={"http": None, "https": None}  # 禁用代理
                )
                
                response.raise_for_status() # 抛出 HTTPError 4xx/5xx

                data = response.json()
                status = data.get('status', '').lower()

                # 更新进度（查询阶段：50% 到 80%）
                self.progress_updated.emit(
                    min(80, 50 + (attempt * 30 // max_attempts)),
                    f"检查进度... ({status.capitalize()})",
                    self.task_id
                )
                
                if status == 'success' and 'outputs' in data:
                    outputs = data['outputs']
                    if outputs and len(outputs) > 0:
                        video_url = outputs[0].get('object_url', '')
                        if video_url:
                            self.log_message(f"🎉 视频生成完成: {video_url}")
                            return video_url

                elif status == 'failed':
                    error_info = data.get('error', '生成失败')
                    self.log_message(f"❌ 视频生成失败: {error_info}")
                    return None

                else:
                    self.log_message(f"⏳ 视频生成中... ({status.capitalize()}) - 第{attempt+1}次检查")

            except requests.exceptions.RequestException as e:
                self.log_message(f"⚠️ 状态查询异常: {str(e)}")

            # 如果不是最后一次尝试，等待后继续
            if attempt < max_attempts - 1:
                time.sleep(check_interval)

        self.log_message(f"⏰ 视频生成超时 ({max_attempts * check_interval // 60}分钟)")
        return None

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True
        self.time_update_active = False

# --- 5. 任务调度器 (用于延迟启动) ---
class TaskScheduler(QThread):
    """任务调度器 - 在独立线程中处理延迟任务启动"""
    schedule_task = pyqtSignal(dict, str, str, str)  # task, task_id, api_key, video_mode

    def __init__(self, parent=None):
        super().__init__(parent)
        self.pending_tasks = []  # (delay_seconds, task, task_id, api_key, video_mode)

    def add_scheduled_task(self, delay_seconds, task, task_id, api_key, video_mode="single"):
        """添加延迟任务"""
        self.pending_tasks.append((delay_seconds, task, task_id, api_key, video_mode))

    def run(self):
        """执行调度"""
        # 按延迟时间排序
        self.pending_tasks.sort(key=lambda x: x[0])

        last_schedule_time = 0
        for delay_seconds, task, task_id, api_key, video_mode in self.pending_tasks:
            # 计算相对延迟
            relative_delay = delay_seconds - last_schedule_time
            if relative_delay > 0:
                self.msleep(int(relative_delay * 1000))  # 转换为毫秒
            last_schedule_time = delay_seconds

            # 发送任务启动信号
            self.schedule_task.emit(task, task_id, api_key, video_mode)

        self.pending_tasks.clear()

# --- 6. 并发批量任务管理器 ---
class ConcurrentBatchManager(QObject):
    """并发批量任务管理器"""
    all_tasks_finished = pyqtSignal()  # 所有任务完成信号
    task_progress = pyqtSignal(int, str, str)  # 进度更新 (progress, message, task_id)
    task_finished = pyqtSignal(bool, str, dict, str)  # 任务完成 (success, message, result_data, task_id)
    task_time_updated = pyqtSignal(str, str)  # 任务时间更新 (time_string, task_id)
    log_updated = pyqtSignal(str)  # 日志更新
    batch_progress_updated = pyqtSignal(int, int)  # 批量进度更新 (completed, total)

    def __init__(self, api_manager=None):
        super().__init__()
        self.workers = {}  # task_id -> worker
        self.completed_tasks = 0
        self.total_tasks = 0
        self.task_counter = 0 # 累计任务计数器
        self.api_manager = api_manager if api_manager is not None else APIKeyManager()
        self.scheduler = TaskScheduler()
        self.scheduler.schedule_task.connect(self.start_scheduled_task)

    def log_message(self, message):
        Utils.log_message(message, self.log_updated, "批量管理器")

    def start_scheduled_task(self, task, task_id, api_key, video_mode):
        """启动调度器中的任务"""
        if task_id in self.workers:
            # 创建工作线程
            worker = SingleVideoGenerationWorker(task, task_id, api_key, self.api_manager, video_mode)
            self.workers[task_id] = worker

            # 连接信号
            worker.progress_updated.connect(self.task_progress)
            worker.task_finished.connect(self.on_single_task_finished)
            worker.time_updated.connect(self.task_time_updated)
            worker.log_updated.connect(self.log_updated)

            # 立即启动任务
            worker.start()
            self.log_message(f"🚀 已启动任务 {task_id}，使用密钥 {api_key[:10]}...")

    def add_tasks(self, task_map, key_file=None):
        """添加任务到并发队列 task_map: {task_id: task} - 真正的并发执行"""
        new_tasks_count = len(task_map)
        if new_tasks_count == 0:
            return

        self.total_tasks += new_tasks_count

        # 加载API密钥
        if key_file:
            self.api_manager.load_keys_from_file(key_file)

        available_keys = self.api_manager.get_all_keys()
        if not available_keys:
            self.log_message("❌ 错误: 没有可用的API密钥")
            for task_id in task_map.keys():
                self.task_finished.emit(False, "没有可用的API密钥", {}, task_id)
            # 如果没有正在运行的任务，发送全部完成信号
            if not self.workers:
                self.all_tasks_finished.emit()
            return

        self.log_message(f"🚀 添加 {new_tasks_count} 个新任务到队列 (当前并发: {len(self.workers) + new_tasks_count})")
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

        # 如果调度器正在运行，先停止它
        if self.scheduler.isRunning():
            self.scheduler.quit()
            self.scheduler.wait(1000)

        # 为任务分配API密钥并添加到调度器
        current_batch_index = 0
        task_items = list(task_map.items())

        for task_id, task in task_items:
            # 循环分配API密钥 (使用累计计数器确保轮询)
            key_index = (self.task_counter + current_batch_index) % len(available_keys)
            api_key = available_keys[key_index]
            current_batch_index += 1

            # 获取视频模式（默认为单图片模式）
            video_mode = task.get('video_mode', 'single')

            # 计算延迟时间（第一个任务0秒，后续任务间隔20秒）
            delay_seconds = (current_batch_index - 1) * 20

            # 添加到调度器
            self.scheduler.add_scheduled_task(delay_seconds, task, task_id, api_key, video_mode)

            # 预先在workers字典中占位，防止重复创建
            self.workers[task_id] = None

        # 启动调度器（在独立线程中运行，不阻塞主线程）
        self.scheduler.start()
        self.log_message(f"⏰ 任务调度器已启动，{new_tasks_count}个任务将在20秒间隔内并发执行")

        self.task_counter += new_tasks_count

    def on_single_task_finished(self, success, message, result_data, task_id):
        """单个任务完成的回调"""
        self.completed_tasks += 1
        self.update_batch_progress()

        # 将任务完成信号传递给主界面
        self.task_finished.emit(success, message, result_data, task_id)

        # 移除已完成的工作线程
        if task_id in self.workers:
            worker = self.workers.pop(task_id)
            if worker is not None:  # 检查不是占位符None
                if worker.isRunning():
                    worker.quit()
                    worker.wait(3000)
                worker.deleteLater()

        # 检查是否所有任务都已完成
        if self.completed_tasks >= self.total_tasks:
            self.log_message(f"✅ 所有任务完成！成功: {self.completed_tasks}/{self.total_tasks}")
            self.all_tasks_finished.emit()
            # 重置状态
            self.completed_tasks = 0
            self.total_tasks = 0
            self.workers.clear()

    def update_batch_progress(self):
        """更新批量进度"""
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

    def cancel_all_tasks(self):
        """取消所有任务"""
        self.log_message("⏹️ 正在取消所有任务...")

        # 停止调度器
        if self.scheduler.isRunning():
            self.scheduler.quit()
            self.scheduler.wait(1000)
            self.log_message("⏹️ 任务调度器已停止")

        # 先取消所有任务
        for worker in self.workers.values():
            if worker is not None:  # 检查不是占位符None
                worker.cancel()

        # 等待所有线程结束
        for task_id, worker in list(self.workers.items()):
            if worker is not None and worker.isRunning():
                self.log_message(f"⏹️ 等待任务 {task_id} 结束...")
                worker.quit()
                worker.wait(2000) # 等待最多2秒
            if worker is not None:
                worker.deleteLater()
            self.workers.pop(task_id, None)

        self.log_message("✅ 所有任务已清理。")
        self.completed_tasks = self.total_tasks # 视为已完成，避免卡死
        self.batch_progress_updated.emit(self.total_tasks, self.total_tasks)
        self.all_tasks_finished.emit() # 发送完成信号，清理主UI状态

# --- 7. 图片拖拽上传小部件 ---
class ImageDropWidget(QFrame):
    # ... (代码不变) ...
    """支持拖拽上传的图片区域"""
    image_dropped = pyqtSignal(str, str)  # image_path, base64_data

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.current_image_path = ""
        self.base64_data = ""
        self.current_image_data = ""  # 添加缺失的属性
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 15, 15, 15)  # 减少边距让界面更紧凑

        # 图片显示区域
        self.image_label = QLabel()
        self.image_label.setFixedSize(260, 160)  # 减小尺寸让界面更紧凑
        self.image_label.setStyleSheet("""
            QLabel {
                border: 2px dashed #505050;
                border-radius: 8px;
                background-color: #2a2a2a;
                color: #888888;
                font-size: 13px;
            }
        """)
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setText("请拖拽图片到这里\n或点击选择文件")
        layout.addWidget(self.image_label, alignment=Qt.AlignCenter)

        # 选择文件按钮
        self.select_btn = PushButton("选择图片文件")  # 移除图标
        self.select_btn.setFixedHeight(32)
        self.select_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #4a90e2;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.select_btn.clicked.connect(self.select_file)
        layout.addWidget(self.select_btn)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self.setStyleSheet("background-color: #e3f2fd;")

    def dragLeaveEvent(self, event):
        self.setStyleSheet("")

    def dropEvent(self, event: QDropEvent):
        self.setStyleSheet("")
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        for file_path in files:
            if file_path.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp')):
                self.load_image(file_path)
                break

    def select_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择图片文件",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"
        )
        if file_path:
            self.load_image(file_path)

    def load_image(self, file_path):
        try:
            # 加载图片并缩放
            pixmap = QPixmap(file_path)
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    300, 200,
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                self.image_label.setPixmap(scaled_pixmap)

                # 转换为base64
                with open(file_path, 'rb') as f:
                    image_data = f.read()

                    # 尝试压缩
                    compressed_data = Utils.compress_image(image_data)

                    self.base64_data = base64.b64encode(compressed_data).decode('utf-8')

                self.current_image_path = file_path
                self.current_image_data = self.base64_data
                self.image_dropped.emit(file_path, self.base64_data)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载图片失败: {str(e)}")

    def clear_image(self):
        self.image_label.clear()
        self.image_label.setText("请拖拽图片到这里\n或点击选择文件")
        self.current_image_path = ""
        self.base64_data = ""
        self.current_image_data = ""

# --- 7.1 视频拖拽上传小部件 ---
class VideoDropWidget(QFrame):
    """支持拖拽上传的视频区域"""
    video_dropped = pyqtSignal(str, str)  # video_path, video_url_or_base64

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.current_video_path = ""
        self.video_data = ""  # 可以是URL或base64编码的视频数据
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 15, 15, 15)

        # 视频显示区域（使用文本提示）
        self.video_label = QLabel()
        self.video_label.setFixedSize(260, 160)
        self.video_label.setStyleSheet("""
            QLabel {
                border: 2px dashed #505050;
                border-radius: 8px;
                background-color: #2a2a2a;
                color: #888888;
                font-size: 13px;
            }
        """)
        self.video_label.setAlignment(Qt.AlignCenter)
        self.video_label.setText("请拖拽视频到这里\n或点击选择文件")
        layout.addWidget(self.video_label, alignment=Qt.AlignCenter)

        # 选择文件按钮
        self.select_btn = PushButton("选择视频文件")
        self.select_btn.setFixedHeight(32)
        self.select_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #4a90e2;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.select_btn.clicked.connect(self.select_file)
        layout.addWidget(self.select_btn)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self.setStyleSheet("background-color: #e3f2fd;")

    def dragLeaveEvent(self, event):
        self.setStyleSheet("")

    def dropEvent(self, event: QDropEvent):
        self.setStyleSheet("")
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        for file_path in files:
            if file_path.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm')):
                self.load_video(file_path)
                break

    def select_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择视频文件",
            "",
            "视频文件 (*.mp4 *.avi *.mov *.mkv *.webm)"
        )
        if file_path:
            self.load_video(file_path)

    def load_video(self, file_path):
        try:
            self.current_video_path = file_path
            # 对于本地视频文件，我们直接使用文件路径
            # 也可以选择读取并编码为base64，但视频文件通常很大
            self.video_data = file_path  # 使用本地路径

            # 更新显示
            file_name = os.path.basename(file_path)
            self.video_label.setText(f"✅ 已加载视频:\n{file_name}")

            self.video_dropped.emit(file_path, self.video_data)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载视频失败: {str(e)}")

    def load_video_from_url(self, url):
        """从URL加载视频"""
        try:
            self.current_video_path = ""
            self.video_data = url
            self.video_label.setText(f"✅ 已加载视频URL:\n{url[:50]}...")
            self.video_dropped.emit(url, url)
        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载视频URL失败: {str(e)}")

    def clear_video(self):
        self.video_label.clear()
        self.video_label.setText("请拖拽视频到这里\n或点击选择文件")
        self.current_video_path = ""
        self.video_data = ""

# --- 8. 任务状态卡片 (TaskStatusCard) ---
class TaskStatusCard(CardWidget):
    """任务状态展示卡片 - 简约美观大气设计"""

    def __init__(self, task_id, task_name, task_params, parent=None):
        super().__init__(parent)
        self.task_id = task_id
        self.task_name = task_name
        self.task_params = task_params
        self.progress = 0
        self.time_string = "00:00:00"
        self.status = "等待开始"
        self.key_source = "文件密钥"
        
        # 内部计时器
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_timer)
        self.start_ts = None
        self.is_timing = False
        
        self.init_ui()

    def init_ui(self):
        """初始化UI"""
        self.setFixedHeight(145)  # 增加高度以容纳更多信息
        self.setStyleSheet("""
            CardWidget {
                background-color: #1e1e1e;
                border: 1px solid #404040;
                border-radius: 8px;
                margin: 2px;
            }
            CardWidget:hover {
                border: 1px solid #4a90e2;
            }
        """)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 12, 15, 12)
        layout.setSpacing(8)

        # 第一行：任务名称和状态
        top_layout = QHBoxLayout()

        # 任务名称
        self.name_label = StrongBodyLabel(self.task_name)
        self.name_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: 600;")
        top_layout.addWidget(self.name_label)

        # 弹性空间
        top_layout.addStretch()

        # 状态标签
        self.status_label = CaptionLabel(self.status)
        self.status_label.setStyleSheet("color: #cccccc; font-size: 11px; padding: 4px 8px; background: #333333; border-radius: 4px;")
        top_layout.addWidget(self.status_label)

        layout.addLayout(top_layout)

        # 第二行：任务参数
        params_layout = QHBoxLayout()

        # 帧数、尺寸信息
        width = self.task_params.get('width', 480)
        height = self.task_params.get('height', 854)
        num_frames = self.task_params.get('num_frames', 81)

        params_text = f"{width}×{height} · {num_frames}帧"
        self.params_label = CaptionLabel(params_text)
        self.params_label.setStyleSheet("color: #888888; font-size: 12px;")
        params_layout.addWidget(self.params_label)

        # 弹性空间
        params_layout.addStretch()

        # 密钥类型标签
        self.key_type_label = CaptionLabel(self.key_source)
        self.key_type_label.setStyleSheet("color: #4a90e2; font-size: 11px; padding: 4px 8px; background: #2a3a4a; border-radius: 4px;")
        params_layout.addWidget(self.key_type_label)

        layout.addLayout(params_layout)

        # 第三行：提示词（单行显示，超出部分省略）
        prompt = self.task_params.get('prompt', '')
        if prompt:
            # 限制提示词长度
            if len(prompt) > 50:
                prompt_display = prompt[:47] + "..."
            else:
                prompt_display = prompt

            self.prompt_label = CaptionLabel(prompt_display)
            self.prompt_label.setStyleSheet("color: #aaaaaa; font-size: 11px;")
            self.prompt_label.setWordWrap(False)
            layout.addWidget(self.prompt_label)
        
        # 进度信息（滚动或固定文本）
        self.progress_msg_label = CaptionLabel("")
        self.progress_msg_label.setStyleSheet("color: #999999; font-size: 11px; min-height: 14px;")
        layout.addWidget(self.progress_msg_label)


        # 第四行：进度条和时间
        progress_layout = QHBoxLayout()

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(4)
        progress_layout.addWidget(self.progress_bar)

        # 时间显示
        self.time_label = CaptionLabel(self.time_string)
        self.time_label.setStyleSheet("color: #666666; font-size: 11px; min-width: 70px;")
        self.time_label.setAlignment(Qt.AlignRight)
        progress_layout.addWidget(self.time_label)

        layout.addLayout(progress_layout)

    def update_progress(self, progress, message):
        """更新进度"""
        self.progress = progress
        self.progress_bar.setValue(progress)

        # 进度小于100时显示滚动信息
        if progress < 100:
            self.status = "生成中"
            # 根据进度更新状态标签颜色
            if progress >= 50:
                self.status_label.setStyleSheet("color: #ffc107; font-size: 11px; padding: 4px 8px; background: #fff3cd; border-radius: 4px;")
            else:
                self.status_label.setStyleSheet("color: #17a2b8; font-size: 11px; padding: 4px 8px; background: #e6f7ff; border-radius: 4px;")
            
            # 显示当前操作信息
            self.progress_msg_label.setText(message)
        
        self.status_label.setText(self.status)

    def start_timing(self):
        """开始计时"""
        if not self.is_timing:
            self.is_timing = True
            self.start_ts = time.time()
            self.timer.start(1000) # 每秒更新

    def stop_timing(self):
        """停止计时"""
        if self.is_timing:
            self.is_timing = False
            self.timer.stop()
            # 确保最后一次更新
            self.update_timer()

    def update_timer(self):
        """更新时间显示"""
        if self.start_ts:
            elapsed = time.time() - self.start_ts
            hours = int(elapsed // 3600)
            minutes = int((elapsed % 3600) // 60)
            seconds = int(elapsed % 60)
            self.time_string = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            self.time_label.setText(self.time_string)

    def update_time(self, time_string):
        """更新时间显示"""
        self.time_string = time_string
        self.time_label.setText(time_string)
        
        # 滚动信息处理 (只在进行中时滚动)
        if self.progress < 100 and self.progress > 0:
            elapsed = int(time.time() - self.parent().concurrent_batch_manager.workers[self.task_id].start_time) if self.parent().concurrent_batch_manager.workers[self.task_id].start_time else 0
            dots = "." * ((elapsed % 3) + 1)
            scroll_text = f"· 正在生成视频{dots}请耐心等待 ·"
            self.progress_msg_label.setText(scroll_text)
            
    def set_key_source(self, key_source):
        """设置密钥源类型"""
        self.key_source = key_source
        self.key_type_label.setText(key_source)

        # 根据密钥源类型设置不同颜色
        if key_source == "系统变量":
            self.key_type_label.setStyleSheet("color: #17a2b8; font-size: 11px; padding: 4px 8px; background: #e6f7ff; border-radius: 4px;")
        else:
            self.key_type_label.setStyleSheet("color: #28a745; font-size: 11px; padding: 4px 8px; background: #e8f5e8; border-radius: 4px;")

    def set_completed(self, success=True, message=""):
        """设置任务完成状态"""
        self.progress = 100
        self.progress_bar.setValue(100)
        self.progress_msg_label.setText(message) # 显示最终信息

        if success:
            self.status = "任务完成"
            self.status_label.setStyleSheet("color: #28a745; font-size: 11px; padding: 4px 8px; background: #e8f5e8; border-radius: 4px;")
            self.setStyleSheet("""
                CardWidget {
                    background-color: #2e3a2e;
                    border: 1px solid #28a745;
                    border-radius: 8px;
                    margin: 2px;
                }
            """)
        else:
            self.status = "生成失败"
            self.status_label.setStyleSheet("color: #dc3545; font-size: 11px; padding: 4px 8px; background: #ffebee; border-radius: 4px;")
            self.setStyleSheet("""
                CardWidget {
                    background-color: #3a2a2a;
                    border: 1px solid #dc3545;
                    border-radius: 8px;
                    margin: 2px;
                }
            """)
        self.status_label.setText(self.status)

# --- 9. 视频结果卡片 (VideoResultCard) ---
class VideoResultCard(CardWidget):
    """视频结果展示卡片 (优化版本，用于展示已完成任务)"""

    def __init__(self, video_data, task_id, parent=None):
        super().__init__(parent)
        self.video_data = video_data
        self.task_id = task_id
        self.parent = parent
        self.local_video_path = None # 用于存储本地下载路径
        self.completion_time = video_data.get('timestamp', '')  # 获取完成时间
        self.is_visible = True  # 控制卡片可见性
        self.init_ui()

        # 尝试自动下载
        self.auto_download_video(self.video_data.get('url', ''))


    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 15, 15, 15)
        layout.setSpacing(10)

        # 任务标题、状态和控制按钮
        header_layout = QHBoxLayout()
        title_label = StrongBodyLabel(f"{self.video_data.get('task_name', f'任务_{self.task_id}')}")
        title_label.setStyleSheet("font-size: 14px; font-weight: bold; color: #ffffff;")
        header_layout.addWidget(title_label)

        header_layout.addStretch()

        # 隐藏按钮
        self.hide_btn = QPushButton("👁")
        self.hide_btn.setFixedSize(24, 24)
        self.hide_btn.setStyleSheet("""
            QPushButton {
                background-color: transparent;
                border: none;
                border-radius: 12px;
                color: #888888;
                font-size: 14px;
                padding: 0;
            }
            QPushButton:hover {
                background-color: #404040;
                color: #ffffff;
            }
            QPushButton:pressed {
                background-color: #505050;
            }
        """)
        self.hide_btn.setToolTip("隐藏/显示任务卡片")
        self.hide_btn.clicked.connect(self.toggle_visibility)
        header_layout.addWidget(self.hide_btn)

        # 状态和时间标签容器
        status_time_layout = QVBoxLayout()
        status_time_layout.setSpacing(2)

        self.download_status_label = QLabel("正在下载...")
        self.download_status_label.setStyleSheet("color: #f39c12; font-size: 12px; font-weight: bold;")
        status_time_layout.addWidget(self.download_status_label)

        # 完成时间标签
        self.completion_time_label = QLabel("")
        self.completion_time_label.setStyleSheet("color: #666666; font-size: 10px;")
        if self.completion_time:
            try:
                # 解析时间戳并格式化显示
                dt = datetime.fromisoformat(self.completion_time.replace('Z', '+00:00'))
                formatted_time = dt.strftime("%m-%d %H:%M:%S")
                self.completion_time_label.setText(f"完成时间: {formatted_time}")
            except:
                # 如果解析失败，直接显示原始时间戳
                self.completion_time_label.setText(f"完成时间: {self.completion_time}")
        status_time_layout.addWidget(self.completion_time_label)

        header_layout.addLayout(status_time_layout)
        layout.addLayout(header_layout)

        # 视频信息
        info_layout = QHBoxLayout()

        size_label = CaptionLabel(f"尺寸: {self.video_data.get('width', 480)}×{self.video_data.get('height', 854)}")
        size_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(size_label)

        info_layout.addSpacing(15)

        frames_label = CaptionLabel(f"帧数: {self.video_data.get('num_frames', 81)}帧")
        frames_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(frames_label)

        info_layout.addStretch()

        layout.addLayout(info_layout)
        
        # 提示词
        prompt_text = self.video_data.get('prompt', '')
        if prompt_text:
            prompt_preview = prompt_text[:120] + "..." if len(prompt_text) > 80 else prompt_text
            prompt_label = CaptionLabel(f"提示词: {prompt_preview}")
            prompt_label.setStyleSheet("color: #888888; font-size: 11px;")
            prompt_label.setWordWrap(True)
            layout.addWidget(prompt_label)

        # 操作按钮和URL展示区域
        button_url_layout = QHBoxLayout()

        # 按钮组
        button_group = QVBoxLayout()
        
        self.view_btn = PushButton("本地播放")
        self.view_btn.setFixedSize(80, 30)
        self.view_btn.clicked.connect(self.view_video)
        button_group.addWidget(self.view_btn)

        self.copy_url_btn = PushButton("复制URL")
        self.copy_url_btn.setFixedSize(80, 30)
        self.copy_url_btn.clicked.connect(self.copy_url)
        button_group.addWidget(self.copy_url_btn)

        button_url_layout.addLayout(button_group)
        button_url_layout.addSpacing(10)

        # URL文本展示区域
        self.url_text_label = QLabel()
        self.url_text_label.setWordWrap(True)
        self.url_text_label.setText(self.video_data.get('url', ''))
        self.url_text_label.setStyleSheet("""
            QLabel {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 6px 8px;
                color: #e0e0e0;
                font-size: 11px;
                font-family: 'Consolas', 'Monaco', monospace;
            }
        """)
        self.url_text_label.setMaximumHeight(80) # 限制高度
        button_url_layout.addWidget(self.url_text_label)
        
        layout.addLayout(button_url_layout)

        # 设置卡片样式
        self.setStyleSheet("""
            VideoResultCard {
                background-color: #2a2a2a;
                border: 1px solid #404040;
                border-radius: 8px;
                margin: 5px;
            }
            VideoResultCard:hover {
                border: 1px solid #4a90e2;
            }
        """)

    def auto_download_video(self, video_url):
        """自动下载视频到output文件夹"""
        if not video_url:
            self.download_status_label.setText("URL缺失")
            self.download_status_label.setStyleSheet("color: #dc3545; font-size: 12px; font-weight: bold;")
            return
        
        # 生成文件名
        task_name = self.video_data.get('task_name', 'video')
        base_filename = self.video_data.get('base_filename', '')
        
        if base_filename:
            filename = f"{base_filename}.mp4" # 直接使用基础名，不加 _vod
        else:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = re.sub(r'[^\w\-_.]', '_', f"{task_name}_{timestamp}.mp4")

        # 创建下载工作线程
        self.download_worker = VideoDownloadWorker(video_url, filename)
        self.download_worker.progress_updated.connect(self.on_download_progress)
        self.download_worker.download_finished.connect(self.on_download_finished)

        if hasattr(self.parent, 'add_log'):
            self.download_worker.log_updated.connect(self.parent.add_log)

        self.download_worker.start()

    def on_download_progress(self, progress, message):
        """下载进度更新"""
        self.download_status_label.setText(f"下载中: {progress}%")
        self.download_status_label.setStyleSheet("color: #f39c12; font-size: 12px; font-weight: bold;")

    def on_download_finished(self, success, message, local_path):
        """下载完成回调"""
        if success and local_path:
            self.local_video_path = local_path
            # 构建状态文本，包含完成时间
            completion_time_text = ""
            if self.completion_time:
                try:
                    dt = datetime.fromisoformat(self.completion_time.replace('Z', '+00:00'))
                    formatted_time = dt.strftime("%m-%d %H:%M:%S")
                    completion_time_text = f" · {formatted_time}"
                except:
                    pass

            self.download_status_label.setText(f"本地已保存{completion_time_text}")
            self.download_status_label.setStyleSheet("color: #28a745; font-size: 12px; font-weight: bold;")

            # 隐藏单独的完成时间标签，因为已经合并到状态标签中
            self.completion_time_label.hide()
        else:
            self.download_status_label.setText("下载失败/远程")
            self.download_status_label.setStyleSheet("color: #dc3545; font-size: 12px; font-weight: bold;")

            if hasattr(self.parent, 'add_log'):
                self.parent.add_log(f"❌ 任务 {self.task_id} 自动下载失败: {message}")

    def view_video(self):
        """播放视频（优先本地，其次远程）"""
        if self.local_video_path and os.path.exists(self.local_video_path):
            self.parent.play_task_video(self.local_video_path, os.path.basename(self.local_video_path))
        else:
            video_url = self.video_data.get('url', '')
            if video_url:
                # 使用系统默认浏览器或播放器打开URL
                QDesktopServices.openUrl(QUrl(video_url))
                if hasattr(self.parent, 'add_log'):
                    self.parent.add_log(f"🌐 任务 {self.task_id} 尝试打开远程视频: {video_url}")
            else:
                QMessageBox.warning(self, "警告", "视频URL不可用")

    def copy_url(self):
        """复制视频URL"""
        video_url = self.video_data.get('url', '')
        if video_url:
            clipboard = QCoreApplication.clipboard()
            clipboard.setText(video_url)

            InfoBar.success(
                title="成功",
                content="视频URL已复制到剪贴板",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=2000,
                parent=self
            )
        else:
            QMessageBox.warning(self, "警告", "视频URL不可用")

    def toggle_visibility(self):
        """切换卡片可见性"""
        self.is_visible = not self.is_visible

        if self.is_visible:
            # 恢复显示所有内容
            self.hide_btn.setText("👁")
            self.hide_btn.setToolTip("隐藏任务卡片")
            self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)  # 恢复原始大小策略
            # 显示所有子控件
            for i in range(self.layout().count()):
                item = self.layout().itemAt(i)
                if item and item.widget():
                    item.widget().show()
            # 恢复原始样式
            self.setStyleSheet("""
                VideoResultCard {
                    background-color: #2a2a2a;
                    border: 1px solid #404040;
                    border-radius: 8px;
                    margin: 5px;
                }
                VideoResultCard:hover {
                    border: 1px solid #4a90e2;
                }
            """)
        else:
            # 隐藏卡片内容，只保留标题栏和隐藏按钮
            self.hide_btn.setText("👁‍🗨")
            self.hide_btn.setToolTip("显示任务卡片")
            # 设置固定高度，只显示标题栏
            current_width = self.width() if self.width() > 0 else 300
            self.setFixedSize(current_width, 50)

            # 只保留 header_layout 的显示，隐藏其他内容
            header_layout = self.layout().itemAt(0).layout() if self.layout().count() > 0 else None
            if header_layout:
                # 保留标题和隐藏按钮
                for i in range(header_layout.count()):
                    item = header_layout.itemAt(i)
                    if item and item.widget():
                        if item.widget() in [self.hide_btn]:
                            item.widget().show()
                        elif isinstance(item.widget(), QLabel) and "任务_" in item.widget().text():
                            # 调整标题样式以适应小尺寸
                            title_widget = item.widget()
                            title_widget.setStyleSheet("font-size: 12px; font-weight: bold; color: #ffffff;")
                            title_widget.show()
                        else:
                            item.widget().hide()

            # 隐藏其他布局
            for i in range(1, self.layout().count()):
                item = self.layout().itemAt(i)
                if item and item.widget():
                    item.widget().hide()

            # 设置简化样式
            self.setStyleSheet("""
                VideoResultCard {
                    background-color: #333333;
                    border: 1px solid #555555;
                    border-radius: 6px;
                    margin: 2px;
                }
                VideoResultCard:hover {
                    border: 1px solid #666666;
                }
            """)

        # 通知父组件更新布局
        if self.parent:
            self.parent.update()


# --- 10. 视频下载工作线程 (VideoDownloadWorker) ---
class VideoDownloadWorker(QThread):
    # ... (代码不变，仅修正 import os/re/requests 为外部引用) ...
    """视频下载工作线程"""
    progress_updated = pyqtSignal(int, str)  # progress, message
    download_finished = pyqtSignal(bool, str, str)  # success, message, local_path
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, video_url, filename):
        super().__init__()
        self.video_url = video_url
        self.filename = filename
        self.is_cancelled = False

    def run(self):
        """下载视频"""
        try:
            # 确保output目录存在
            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)

            local_path = os.path.join(output_dir, self.filename)

            self.progress_updated.emit(10, "开始下载视频...")
            self.log_updated.emit(f"🎬 开始下载视频: {self.filename}")

            # 使用requests下载文件 (禁用代理)
            response = requests.get(self.video_url, stream=True, timeout=300, proxies={"http": None, "https": None})
            response.raise_for_status()

            total_size = int(response.headers.get('content-length', 0))
            downloaded_size = 0

            with open(local_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if self.is_cancelled:
                        if os.path.exists(local_path):
                            os.remove(local_path)
                        self.download_finished.emit(False, "下载已取消", "")
                        return

                    f.write(chunk)
                    downloaded_size += len(chunk)

                    if total_size > 0:
                        progress = min(90, int((downloaded_size / total_size) * 70) + 20)
                        self.progress_updated.emit(progress, f"下载中... {downloaded_size}/{total_size} 字节")

            # 验证文件是否下载成功
            if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                file_size = os.path.getsize(local_path)
                self.progress_updated.emit(100, "下载完成！")
                self.progress_updated.emit(100, "下载完成！")
                self.log_updated.emit(f"视频下载完成: {local_path} ({file_size} 字节)")
                self.download_finished.emit(True, "下载完成", local_path)
            else:
                self.download_finished.emit(False, "下载失败：文件不完整", "")

        except requests.exceptions.RequestException as e:
            self.download_finished.emit(False, f"网络错误: {str(e)}", "")
            self.log_updated.emit(f"❌ 下载失败: {str(e)}")
        except Exception as e:
            self.download_finished.emit(False, f"下载异常: {str(e)}", "")
            self.log_updated.emit(f"💥 下载异常: {str(e)}")

    def cancel(self):
        """取消下载"""
        self.is_cancelled = True

# --- 11. 主要的视频生成界面 (VideoGenerationWidget) ---
class VideoGenerationWidget(QWidget):
    """视频生成主界面 - 增强版"""

    def __init__(self, parent=None):
        super().__init__(parent)
        super().__init__(parent)
        self.concurrent_batch_manager = None
        self.batch_tasks = []
        self.api_manager = APIKeyManager()
        self.batch_tasks = []
        self.api_manager = APIKeyManager()
        self.settings_manager = VideoSettingsManager()
        
        # 加载 API URL 配置
        api_settings = self.settings_manager.get_api_settings()
        self.api_manager.api_url = api_settings.get("api_url", "https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
        
        self.is_generating = False
        self.key_file_path = None # 用于存储密钥文件路径

        # 任务状态卡片管理器
        self.task_status_cards = {}  # task_id -> TaskStatusCard

        # 初始化隐藏的参数控件
        self.init_hidden_params_controls()

        self.init_ui()
        self.load_settings()

        # 初始化并保持并发管理器
        self.init_concurrent_manager()

    def init_concurrent_manager(self):
        """初始化并发管理器"""
        self.concurrent_batch_manager = ConcurrentBatchManager(self.api_manager)
        self.concurrent_batch_manager.task_progress.connect(self.update_task_progress)
        self.concurrent_batch_manager.task_finished.connect(self.on_task_finished)
        self.concurrent_batch_manager.task_time_updated.connect(self.update_task_time)
        self.concurrent_batch_manager.log_updated.connect(self.add_log)
        self.concurrent_batch_manager.batch_progress_updated.connect(self.update_batch_progress)
        self.concurrent_batch_manager.all_tasks_finished.connect(self.on_all_tasks_finished)

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(8, 8, 8, 8)

        # 设置深色主题整体样式 (省略重复的样式代码，假设已在外部加载)

        # 顶部控制栏 - 密钥设置
        top_bar = self.create_top_bar()
        layout.addWidget(top_bar)

        # 创建分割器
        splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(splitter)

        # 左侧控制面板
        left_panel = self.create_control_panel()
        splitter.addWidget(left_panel)

        # 右侧结果面板
        right_panel = self.create_result_panel()
        splitter.addWidget(right_panel)

        # 设置分割比例
        splitter.setSizes([450, 750])

    # ... (create_top_bar, show_api_settings_dialog, update_key_status 方法不变) ...
    def create_top_bar(self):
        """创建顶部控制栏（深色主题）"""
        bar = QFrame()
        bar.setFixedHeight(60)
        bar.setStyleSheet("""
            QFrame {
                background-color: #2a2a2a;
                border-radius: 8px;
                margin: 2px;
            }
        """)
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(12, 12, 12, 12)

        title = QLabel("图片转视频生成")
        title.setStyleSheet("font-size: 18px; font-weight: bold; color: #ffffff;")
        layout.addWidget(title)

        layout.addSpacing(20)

        # 单个生成按钮
        self.single_generate_btn = PrimaryPushButton("单个生成")
        self.single_generate_btn.setFixedSize(100, 32)
        self.single_generate_btn.clicked.connect(self.generate_single_video)
        self.single_generate_btn.setStyleSheet("""
            QPushButton {
                background-color: #007bff;
                border: none;
                border-radius: 4px;
                color: #ffffff;
                font-size: 13px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #0069d9;
            }
            QPushButton:pressed {
                background-color: #0056b3;
            }
        """)
        layout.addWidget(self.single_generate_btn)

        layout.addSpacing(10)

        # 批量生成按钮
        self.batch_generate_btn = PrimaryPushButton("批量生成")
        self.batch_generate_btn.setFixedSize(100, 32)
        self.batch_generate_btn.clicked.connect(self.generate_batch_videos)
        self.batch_generate_btn.setStyleSheet("""
            QPushButton {
                background-color: #007bff;
                border: none;
                border-radius: 4px;
                color: #ffffff;
                font-size: 13px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #0069d9;
            }
            QPushButton:pressed {
                background-color: #545b62;
            }
        """)
        layout.addWidget(self.batch_generate_btn)
        
        layout.addSpacing(10)

        # 打开文件夹按钮
        self.open_output_btn = PushButton("打开文件夹")
        self.open_output_btn.setFixedSize(100, 32)
        self.open_output_btn.clicked.connect(self.open_output_folder)
        self.open_output_btn.setStyleSheet("""
            QPushButton {
                background-color: #343a40;
                border: 1px solid #495057;
                border-radius: 4px;
                color: #e9ecef;
                font-size: 13px;
            }
            QPushButton:hover {
                background-color: #23272b;
                border-color: #dee2e6;
            }
        """)
        layout.addWidget(self.open_output_btn)



        layout.addStretch()

        self.key_status_label = QLabel("密钥: 未配置")
        self.key_status_label.setStyleSheet("""
            color: #cccccc;
            padding: 6px 15px;
            background: #333333;
            border-radius: 6px;
            border: 1px solid #404040;
            font-size: 12px;
            min-width: 120px;
        """)
        layout.addWidget(self.key_status_label)

        self.webapp_id_label = QLabel(f"单图:{self.api_manager.web_app_id_single} | 首尾帧:{self.api_manager.web_app_id_frames}")
        self.webapp_id_label.setStyleSheet("""
            color: #4a90e2;
            padding: 6px 15px;
            background: #2a3a4a;
            border-radius: 6px;
            border: 1px solid #4a90e2;
            font-size: 12px;
            font-weight: bold;
            min-width: 180px;
        """)
        layout.addWidget(self.webapp_id_label)

        self.settings_btn = PushButton("API 密钥设置")
        self.settings_btn.setFixedSize(130, 32)
        self.settings_btn.clicked.connect(self.show_api_settings_dialog)
        self.settings_btn.setStyleSheet("""
            QPushButton {
                border: none;
                background-color: #17a2b8;
                border-radius: 4px;
                color: #ffffff;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
            }
        """)
        layout.addWidget(self.settings_btn)

        separator = QLabel("|")
        separator.setStyleSheet("color: #666666; font-size: 14px; margin: 0 8px;")
        layout.addWidget(separator)

        self.video_settings_top_btn = PrimaryPushButton("视频参数")
        self.video_settings_top_btn.setFixedHeight(32)
        self.video_settings_top_btn.clicked.connect(self.show_video_settings_dialog)
        self.video_settings_top_btn.setStyleSheet("""
            QPushButton {
                background-color: #17a2b8;
                border: none;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
                font-weight: 500;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #138496;
            }
            QPushButton:pressed {
                background-color: #117a8b;
            }
        """)
        layout.addWidget(self.video_settings_top_btn)

        self.current_params_top_label = QLabel("当前: 480×854, 5秒, 81帧")
        self.current_params_top_label.setStyleSheet("""
            QLabel {
                color: #cccccc;
                font-size: 11px;
                padding: 6px 10px;
                background-color: #333333;
                border-radius: 6px;
            }
        """)
        layout.addWidget(self.current_params_top_label)

        return bar

    def show_api_settings_dialog(self):
        """显示API设置对话框"""
        dialog = APISettingsDialog(self.api_manager, self)
        if dialog.exec_() == QDialog.Accepted:
            self.update_key_status()
            self.webapp_id_label.setText(f"单图:{self.api_manager.web_app_id_single} | 首尾帧:{self.api_manager.web_app_id_frames} | 换人物:{self.api_manager.web_app_id_video}")
            self.save_settings()

    def update_key_status(self):
        """更新密钥状态显示"""
        try:
            available_keys = self.api_manager.get_available_keys_count()
            key_source = self.api_manager.get_key_source()
            key_source_display = self.api_manager.get_key_source_display()

            if available_keys > 0:
                text = f"{key_source_display}: {available_keys}个可用"

                # 根据密钥源设置不同的颜色
                if key_source == "env":
                    style = """
                        color: #17a2b8;
                        padding: 6px 15px;
                        background: #e6f7ff;
                        border-radius: 6px;
                        border: 1px solid #17a2b8;
                        font-size: 12px;
                        min-width: 120px;
                    """
                elif key_source == "text":
                    style = """
                        color: #fd7e14;
                        padding: 6px 15px;
                        background: #fff3cd;
                        border-radius: 6px;
                        border: 1px solid #fd7e14;
                        font-size: 12px;
                        min-width: 120px;
                    """
                else:  # file
                    style = """
                        color: #28a745;
                        padding: 6px 15px;
                        background: #e8f5e8;
                        border-radius: 6px;
                        border: 1px solid #28a745;
                        font-size: 12px;
                        min-width: 120px;
                    """
            else:
                text = f"{key_source_display}: 未配置"
                style = """
                    color: #dc3545;
                    padding: 6px 15px;
                    background: #ffebee;
                    border-radius: 6px;
                    border: 1px solid #dc3545;
                    font-size: 12px;
                    min-width: 120px;
                """

            self.key_status_label.setText(text)
            self.key_status_label.setStyleSheet(style)
        except Exception as e:
            self.add_log(f"更新密钥状态显示失败: {e}")

    # ... (create_control_panel, create_image_input_group, on_input_type_changed, on_image_dropped 方法不变) ...
    def create_control_panel(self):
        """创建控制面板（选项卡模式）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(6)
        layout.setContentsMargins(8, 8, 8, 8)

        # 创建选项卡控件
        self.mode_tabs = QTabWidget()
        self.mode_tabs.setStyleSheet("""
            QTabWidget::pane {
                border: 1px solid #404040;
                background-color: #2A2A2A;
                border-radius: 4px;
            }
            QTabBar::tab {
                background-color: #333333;
                color: #cccccc;
                padding: 8px 20px;
                margin-right: 2px;
                border: 1px solid #404040;
                border-bottom: none;
                border-top-left-radius: 4px;
                border-top-right-radius: 4px;
            }
            QTabBar::tab:selected {
                background-color: #2A2A2A;
                color: #ffffff;
                border-bottom: 2px solid #4a90e2;
            }
            QTabBar::tab:hover {
                background-color: #3a3a3a;
            }
        """)

        # 单图片转视频选项卡
        single_tab = self.create_single_image_tab()
        self.mode_tabs.addTab(single_tab, "单图片转视频")

        # 首尾帧图片转视频选项卡
        frames_tab = self.create_frames_image_tab()
        self.mode_tabs.addTab(frames_tab, "首尾帧转视频")

        # 视频换人物选项卡
        video_tab = self.create_video_replace_tab()
        self.mode_tabs.addTab(video_tab, "视频换人物")

        layout.addWidget(self.mode_tabs)

        return panel

    def create_single_image_tab(self):
        """创建单图片转视频选项卡"""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(6)
        layout.setContentsMargins(8, 8, 8, 8)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("""
            QScrollArea { background-color: #2A2A2A; border: none; }
            QScrollBar:vertical { background-color: #2a2a2a; width: 8px; border-radius: 4px; }
            QScrollBar::handle:vertical { background-color: #4a4a4a; border-radius: 4px; min-height: 20px; }
            QScrollBar::handle:vertical:hover { background-color: #5a5a5a; }
        """)

        scroll_widget = QWidget()
        scroll_widget.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setSpacing(6)

        # 图片输入组
        image_group = self.create_image_input_group()
        scroll_layout.addWidget(image_group)
        
        # 提示词输入组
        prompt_group = self.create_prompt_group()
        scroll_layout.addWidget(prompt_group)

        # 批量任务组
        batch_group = self.create_batch_group()
        scroll_layout.addWidget(batch_group)

        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        return tab

    def create_frames_image_tab(self):
        """创建首尾帧图片转视频选项卡"""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(6)
        layout.setContentsMargins(8, 8, 8, 8)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("""
            QScrollArea { background-color: #2A2A2A; border: none; }
            QScrollBar:vertical { background-color: #2a2a2a; width: 8px; border-radius: 4px; }
            QScrollBar::handle:vertical { background-color: #4a4a4a; border-radius: 4px; min-height: 20px; }
            QScrollBar::handle:vertical:hover { background-color: #5a5a5a; }
        """)

        scroll_widget = QWidget()
        scroll_widget.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setSpacing(6)

        # 首图输入组
        start_image_label = QLabel("首帧图片:")
        start_image_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: bold; padding: 5px 0;")
        scroll_layout.addWidget(start_image_label)
        
        self.frames_start_drop_widget = ImageDropWidget()
        self.frames_start_drop_widget.image_dropped.connect(self.on_frames_start_image_dropped)
        scroll_layout.addWidget(self.frames_start_drop_widget)

        # 尾图输入组
        end_image_label = QLabel("尾帧图片:")
        end_image_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: bold; padding: 5px 0;")
        scroll_layout.addWidget(end_image_label)
        
        self.frames_end_drop_widget = ImageDropWidget()
        self.frames_end_drop_widget.image_dropped.connect(self.on_frames_end_image_dropped)
        scroll_layout.addWidget(self.frames_end_drop_widget)

        # 批量任务组（首尾帧模式）
        batch_group_frames = self.create_batch_group_frames()
        scroll_layout.addWidget(batch_group_frames)

        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        return tab

    def create_video_replace_tab(self):
        """创建视频换人物选项卡"""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(6)
        layout.setContentsMargins(8, 8, 8, 8)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("""
            QScrollArea { background-color: #2A2A2A; border: none; }
            QScrollBar:vertical { background-color: #2a2a2a; width: 8px; border-radius: 4px; }
            QScrollBar::handle:vertical { background-color: #4a4a4a; border-radius: 4px; min-height: 20px; }
            QScrollBar::handle:vertical:hover { background-color: #5a5a5a; }
        """)

        scroll_widget = QWidget()
        scroll_widget.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setSpacing(6)

        # 视频输入组
        video_input_label = QLabel("源视频文件:")
        video_input_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: bold; padding: 5px 0;")
        scroll_layout.addWidget(video_input_label)

        # 视频输入方式选择
        self.video_input_type_combo = ComboBox()
        self.video_input_type_combo.addItems(["本地文件上传", "视频URL"])
        self.video_input_type_combo.setFixedHeight(32)
        self.video_input_type_combo.setStyleSheet("""
            QComboBox {
                background-color: #333333;
                border: 1px solid #505050;
                border-radius: 4px;
                color: #ffffff;
                padding: 4px 10px;
                min-height: 20px;
            }
            QComboBox:hover {
                border: 1px solid #4a90e2;
            }
            QComboBox::drop-down {
                border: none;
                background-color: #404040;
                width: 20px;
            }
            QComboBox QAbstractItemView {
                background-color: #333333;
                border: 1px solid #505050;
                selection-background-color: #4a90e2;
                color: #ffffff;
            }
        """)
        self.video_input_type_combo.currentIndexChanged.connect(self.on_video_input_type_changed)
        scroll_layout.addWidget(self.video_input_type_combo)

        # 视频URL输入框
        self.video_url_widget = QWidget()
        video_url_layout = QVBoxLayout(self.video_url_widget)
        video_url_layout.setContentsMargins(0, 0, 0, 0)
        self.video_url_edit = LineEdit()
        self.video_url_edit.setFixedHeight(32)
        self.video_url_edit.setPlaceholderText("输入视频URL地址...")
        self.video_url_edit.setStyleSheet("""
            QLineEdit {
                background-color: #333333;
                border: 1px solid #505050;
                border-radius: 4px;
                color: #ffffff;
                padding: 4px 10px;
            }
            QLineEdit:hover {
                border: 1px solid #4a90e2;
            }
        """)
        video_url_layout.addWidget(self.video_url_edit)
        scroll_layout.addWidget(self.video_url_widget)

        # 视频文件上传组件
        self.video_upload_widget = QWidget()
        video_upload_layout = QVBoxLayout(self.video_upload_widget)
        video_upload_layout.setContentsMargins(0, 0, 0, 0)
        self.video_drop_widget = VideoDropWidget()
        self.video_drop_widget.video_dropped.connect(self.on_video_dropped)
        video_upload_layout.addWidget(self.video_drop_widget)
        scroll_layout.addWidget(self.video_upload_widget)

        self.video_input_type_combo.setCurrentIndex(0)
        self.on_video_input_type_changed(0)

        # 目标人物图片输入组
        target_image_label = QLabel("目标人物图片:")
        target_image_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: bold; padding: 5px 0;")
        scroll_layout.addWidget(target_image_label)

        self.video_target_drop_widget = ImageDropWidget()
        self.video_target_drop_widget.image_dropped.connect(self.on_video_target_image_dropped)
        scroll_layout.addWidget(self.video_target_drop_widget)

        # 提示词输入组
        prompt_group = self.create_prompt_group()
        scroll_layout.addWidget(prompt_group)

        # 批量任务组（视频换人物模式）
        batch_group_video = self.create_batch_group_video()
        scroll_layout.addWidget(batch_group_video)

        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        return tab

    def on_video_input_type_changed(self, index):
        """视频输入方式改变"""
        is_url = index == 1
        self.video_url_widget.setVisible(is_url)
        self.video_upload_widget.setVisible(not is_url)

    def on_video_dropped(self, file_path, video_data):
        """处理视频拖拽事件"""
        self.add_log(f"📁 已加载视频: {os.path.basename(file_path) if file_path else 'URL'}")

    def on_video_target_image_dropped(self, file_path, base64_data):
        """处理目标人物图片拖拽事件"""
        self.add_log(f"📁 已加载目标人物图片: {os.path.basename(file_path)}")

    def create_image_input_group(self):
        """创建图片输入组（深色主题）"""
        group = QGroupBox("")
        layout = QVBoxLayout(group)
        layout.setSpacing(0)

        self.input_type_combo = ComboBox()
        self.input_type_combo.addItems(["本地文件上传", "图片URL"])
        self.input_type_combo.setFixedHeight(32)
        # ... (QComboBox 样式代码) ...
        self.input_type_combo.currentIndexChanged.connect(self.on_input_type_changed)
        layout.addWidget(self.input_type_combo)

        self.url_widget = QWidget()
        url_layout = QVBoxLayout(self.url_widget)
        url_layout.setContentsMargins(0, 0, 0, 0)
        self.image_url_edit = LineEdit()
        self.image_url_edit.setFixedHeight(32)
        self.image_url_edit.setPlaceholderText("输入图片URL地址...")
        # ... (QLineEdit 样式代码) ...
        url_layout.addWidget(self.image_url_edit)
        layout.addWidget(self.url_widget)

        self.upload_widget = QWidget()
        upload_layout = QVBoxLayout(self.upload_widget)
        upload_layout.setContentsMargins(0, 0, 0, 0)
        self.drop_widget = ImageDropWidget()
        self.drop_widget.image_dropped.connect(self.on_image_dropped)
        upload_layout.addWidget(self.drop_widget)
        layout.addWidget(self.upload_widget)

        self.input_type_combo.setCurrentIndex(0)
        self.on_input_type_changed(0)

        return group

    def on_input_type_changed(self, index):
        """输入方式改变"""
        is_url = index == 1
        self.url_widget.setVisible(is_url)
        self.upload_widget.setVisible(not is_url)

    def on_image_dropped(self, file_path, base64_data):
        """处理图片拖拽事件"""
        self.add_log(f"📁 已加载图片: {os.path.basename(file_path)}")

    def on_frames_start_image_dropped(self, file_path, base64_data):
        """处理首帧图片拖拽事件"""
        self.add_log(f"📁 已加载首帧图片: {os.path.basename(file_path)}")

    def on_frames_end_image_dropped(self, file_path, base64_data):
        """处理尾帧图片拖拽事件"""
        self.add_log(f"📁 已加载尾帧图片: {os.path.basename(file_path)}")

    def create_batch_group_frames(self):
        """创建批量任务组（首尾帧模式）"""
        group = QGroupBox("")
        layout = QVBoxLayout(group)
        layout.setSpacing(0)

        self.task_list_widget_frames = QWidget()
        self.task_list_layout_frames = QVBoxLayout(self.task_list_widget_frames)
        self.task_list_layout_frames.setSpacing(0)

        self.task_scroll_frames = QScrollArea()
        self.task_scroll_frames.setWidgetResizable(True)
        self.task_scroll_frames.setFixedHeight(130)
        self.task_scroll_frames.setWidget(self.task_list_widget_frames)

        task_title = QLabel("待处理任务:")
        task_title.setStyleSheet("color: #ffffff; font-size: 18px; font-weight: bold; padding: 2px 0;")
        layout.addWidget(task_title)
        layout.addWidget(self.task_scroll_frames)

        add_task_layout = QHBoxLayout()
        self.add_task_btn_frames = PushButton("+ 添加到任务列表 +")
        self.add_task_btn_frames.setFixedSize(240, 36)
        self.add_task_btn_frames.clicked.connect(self.add_to_batch_tasks_frames)
        add_task_layout.addWidget(self.add_task_btn_frames)

        self.clear_tasks_btn_frames = PushButton("X 清空任务 X")
        self.clear_tasks_btn_frames.setFixedSize(240, 36)
        self.clear_tasks_btn_frames.clicked.connect(self.clear_batch_tasks_frames)
        add_task_layout.addWidget(self.clear_tasks_btn_frames)

        layout.addLayout(add_task_layout)

        return group

    def create_batch_group_video(self):
        """创建批量任务组（视频换人物模式）"""
        group = QGroupBox("")
        layout = QVBoxLayout(group)
        layout.setSpacing(0)

        self.task_list_widget_video = QWidget()
        self.task_list_layout_video = QVBoxLayout(self.task_list_widget_video)
        self.task_list_layout_video.setSpacing(0)

        self.task_scroll_video = QScrollArea()
        self.task_scroll_video.setWidgetResizable(True)
        self.task_scroll_video.setFixedHeight(130)
        self.task_scroll_video.setWidget(self.task_list_widget_video)

        task_title = QLabel("待处理任务:")
        task_title.setStyleSheet("color: #ffffff; font-size: 18px; font-weight: bold; padding: 2px 0;")
        layout.addWidget(task_title)
        layout.addWidget(self.task_scroll_video)

        add_task_layout = QHBoxLayout()
        self.add_task_btn_video = PushButton("+ 添加到任务列表 +")
        self.add_task_btn_video.setFixedSize(240, 36)
        self.add_task_btn_video.clicked.connect(self.add_to_batch_tasks_video)
        add_task_layout.addWidget(self.add_task_btn_video)

        self.clear_tasks_btn_video = PushButton("X 清空任务 X")
        self.clear_tasks_btn_video.setFixedSize(240, 36)
        self.clear_tasks_btn_video.clicked.connect(self.clear_batch_tasks_video)
        add_task_layout.addWidget(self.clear_tasks_btn_video)

        layout.addLayout(add_task_layout)

        return group

    # 初始化首尾帧任务列表
    def init_frames_tasks(self):
        """初始化首尾帧任务列表"""
        if not hasattr(self, 'batch_tasks_frames'):
            self.batch_tasks_frames = []

    # ... (create_batch_group, create_prompt_group, create_actions_group 方法不变) ...
    def create_batch_group(self):
        """创建批量任务组（深色主题）"""
        group = QGroupBox("")
        layout = QVBoxLayout(group)
        layout.setSpacing(0)

        self.task_list_widget = QWidget()
        self.task_list_layout = QVBoxLayout(self.task_list_widget)
        self.task_list_layout.setSpacing(0)

        self.task_scroll = QScrollArea()
        self.task_scroll.setWidgetResizable(True)
        self.task_scroll.setFixedHeight(130)
        self.task_scroll.setWidget(self.task_list_widget)

        task_title = QLabel("待处理任务:")
        task_title.setStyleSheet("color: #ffffff; font-size: 18px; font-weight: bold; padding: 2px 0;")
        layout.addWidget(task_title)
        layout.addWidget(self.task_scroll)

        add_task_layout = QHBoxLayout()
        self.add_task_btn = PushButton("+ 添加到任务列表 +")
        self.add_task_btn.setFixedSize(240, 36)
        # ... (QPushButton 样式代码) ...
        self.add_task_btn.clicked.connect(self.add_to_batch_tasks)
        add_task_layout.addWidget(self.add_task_btn)

        self.clear_tasks_btn = PushButton("X 清空任务 X")
        self.clear_tasks_btn.setFixedSize(240, 36)
        # ... (QPushButton 样式代码) ...
        self.clear_tasks_btn.clicked.connect(self.clear_batch_tasks)
        add_task_layout.addWidget(self.clear_tasks_btn)

        layout.addLayout(add_task_layout)

        return group

    def create_prompt_group(self):
        """创建提示词输入组（无标题无边框）"""
        prompt_edit = QTextEdit()
        prompt_edit.setPlaceholderText("输入视频生成的提示词，例如：美女跳舞、风景变化等...")
        prompt_edit.setMinimumHeight(40)
        prompt_edit.setMaximumHeight(200)
        prompt_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        prompt_edit.setStyleSheet("padding: 10px; background: #202020; border-radius: 4px;font-size:18px; margin-right:20px;")

        # 根据调用位置返回不同的引用
        # 如果 self.prompt_edit 还不存在,说明是第一次调用(单图片选项卡)
        # 如果 self.prompt_edit_video 还不存在但 self.prompt_edit 存在,说明是第二次调用(视频换人物选项卡)
        if not hasattr(self, 'prompt_edit'):
            self.prompt_edit = prompt_edit
        elif not hasattr(self, 'prompt_edit_video'):
            self.prompt_edit_video = prompt_edit

        return prompt_edit
        
    def create_actions_group(self):
        """创建操作按钮组（深色主题）"""
        group = QGroupBox("")
        layout = QVBoxLayout(group)
        layout.setContentsMargins(10, 15, 10, 10)

        button_layout = QHBoxLayout()
        button_layout.setSpacing(10)

        self.single_generate_btn = PrimaryPushButton("单个生成")
        self.single_generate_btn.setFixedSize(120, 36)
        # ... (QPushButton 样式代码) ...
        self.single_generate_btn.clicked.connect(self.generate_single_video)
        button_layout.addWidget(self.single_generate_btn)

        self.batch_generate_btn = PrimaryPushButton("批量生成")
        self.batch_generate_btn.setFixedSize(120, 36)
        # ... (QPushButton 样式代码) ...
        self.batch_generate_btn.clicked.connect(self.generate_batch_videos)
        button_layout.addWidget(self.batch_generate_btn)

        button_layout.addStretch()

        layout.addLayout(button_layout)

        return group


    def init_hidden_params_controls(self):
        """初始化隐藏的参数控件（供对话框使用）"""
        # 预设分辨率（隐藏）
        self.resolution_combo = ComboBox()
        self.resolution_combo.addItems([
            "自定义", "480p - 9:16 (480×854)", "480p - 16:9 (854×480)",
             "720p - 9:16 (720×1280)", "720p - 16:9 (1280×720)",
            "1080p - 9:16 (1080×1920)", "1080p - 16:9 (1920×1080)"
        ])
        self.resolution_combo.currentIndexChanged.connect(self.on_resolution_changed)

        # 自定义尺寸（隐藏）
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 4096)
        self.width_spin.setValue(480)
        self.width_spin.setSingleStep(64)

        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 4096)
        self.height_spin.setValue(854)
        self.height_spin.setSingleStep(64)

        # 视频时长（隐藏）
        self.duration_spin = QSpinBox()
        self.duration_spin.setRange(1, 30)
        self.duration_spin.setValue(5)
        self.duration_spin.setSingleStep(1)
        self.duration_spin.valueChanged.connect(lambda value: self.update_frames(value))

        # 帧数显示（隐藏）
        self.frames_label = QLabel("81")

    def update_frames(self, seconds=None):
        """根据秒数更新帧数显示"""
        if seconds is None:
            seconds = self.duration_spin.value()

        frames = seconds * 16 + 1
        self.frames_label.setText(str(frames))

        # 同时更新对话框中的显示（如果存在）
        if hasattr(self, 'video_settings_dialog') and self.video_settings_dialog:
            if hasattr(self.video_settings_dialog, 'frames_label'):
                self.video_settings_dialog.frames_label.setText(f"总帧数: {frames}")

    def show_video_settings_dialog(self):
        """显示视频参数设置对话框"""
        dialog = VideoSettingsDialog(self)
        self.video_settings_dialog = dialog # 保存引用
        if dialog.exec_() == QDialog.Accepted:
            self.update_current_params_display()
            self.video_settings_dialog = None # 清理引用

    def update_current_params_display(self):
        """更新当前参数显示"""
        try:
            width = self.width_spin.value()
            height = self.height_spin.value()
            duration = self.duration_spin.value()
            frames = self.frames_label.text()
            params_text = f"当前: {width}×{height}, {duration}秒, {frames}帧"
            
            # 更新顶部导航栏中的显示
            if hasattr(self, 'current_params_top_label'):
                self.current_params_top_label.setText(params_text)
        except AttributeError:
            default_params = "当前: 480×854, 5秒, 81帧"
            if hasattr(self, 'current_params_top_label'):
                self.current_params_top_label.setText(default_params)
        
    def on_resolution_changed(self, index):
        """预设分辨率改变"""
        resolutions = {
            1: (480, 854),   # 480p - 9:16
            2: (854, 480),   # 480p - 16:9
            3: (720, 1280),  # 720p - 9:16
            4: (1280, 720),  # 720p - 16:9
            5: (1080, 1920), # 1080p - 9:16
            6: (1920, 1080)  # 1080p - 16:9
        }

        if index in resolutions:
            width, height = resolutions[index]
            self.width_spin.setValue(width)
            self.height_spin.setValue(height)
            
    # ... (add_to_batch_tasks, update_task_list_display, create_task_card, remove_task, clear_batch_tasks 方法不变) ...
    def add_to_batch_tasks(self):
        """添加到批量任务列表"""
        image_input = self.get_current_image_input()
        prompt = self.prompt_edit.toPlainText().strip()

        if not image_input:
            QMessageBox.warning(self, "警告", "请先选择图片")
            return

        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        task = {
            'name': f"任务_{len(self.batch_tasks)+1}",
            'image_input': image_input,
            'image_path': self.drop_widget.current_image_path if self.input_type_combo.currentIndex() == 0 else '',
            'prompt': prompt,
            'width': self.width_spin.value(),
            'height': self.height_spin.value(),
            'num_frames': self.duration_spin.value() * 16 + 1,
            'timestamp': datetime.now().isoformat()
        }

        self.batch_tasks.append(task)
        self.update_task_list_display()
        self.add_log(f"📝 已添加任务: {task['name']}")

    def update_task_list_display(self):
        """更新任务列表显示"""
        while self.task_list_layout.count():
            item = self.task_list_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        for i, task in enumerate(self.batch_tasks):
            task_card = self.create_task_card(task, i)
            self.task_list_layout.addWidget(task_card)

    def create_task_card(self, task, index):
        """创建任务卡片"""
        card = CardWidget()
        card.setFixedHeight(48)
        # ... (CardWidget 样式代码) ...
        layout = QHBoxLayout(card)
        layout.setContentsMargins(10, 5, 10, 5)

        info_layout = QVBoxLayout()
        name_label = QLabel(task['name'])
        name_label.setStyleSheet("font-weight: bold; color: #ffffff; font-size: 14px;")
        info_layout.addWidget(name_label)

        prompt_label = QLabel(f"提示词: {task['prompt'][:30]}...")
        prompt_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(prompt_label)

        layout.addLayout(info_layout)
        layout.addStretch()

        delete_btn = PushButton("X")
        delete_btn.setFixedSize(30, 30)
        # ... (QPushButton 样式代码) ...
        delete_btn.clicked.connect(lambda: self.remove_task(index))
        layout.addWidget(delete_btn)

        return card

    def remove_task(self, index):
        """删除任务"""
        if 0 <= index < len(self.batch_tasks):
            task_name = self.batch_tasks[index]['name']
            del self.batch_tasks[index]
            self.update_task_list_display()
            self.add_log(f"🗑️ 已删除任务: {task_name}")

    def clear_batch_tasks(self):
        """清空批量任务"""
        self.batch_tasks.clear()
        self.update_task_list_display()
        self.clear_task_status_cards()
        self.add_log("🗑️ 已清空所有任务")

    # 首尾帧模式的任务管理方法
    def add_to_batch_tasks_frames(self):
        """添加到批量任务列表（首尾帧模式）"""
        # 初始化首尾帧任务列表
        if not hasattr(self, 'batch_tasks_frames'):
            self.batch_tasks_frames = []

        start_image_input = self.frames_start_drop_widget.base64_data
        end_image_input = self.frames_end_drop_widget.base64_data

        if not start_image_input:
            QMessageBox.warning(self, "警告", "请先选择首帧图片")
            return

        if not end_image_input:
            QMessageBox.warning(self, "警告", "请先选择尾帧图片")
            return

        task = {
            'name': f"首尾帧任务_{len(self.batch_tasks_frames)+1}",
            'image_input': start_image_input,
            'image_path': self.frames_start_drop_widget.current_image_path,
            'end_image_input': end_image_input,
            'end_image_path': self.frames_end_drop_widget.current_image_path,
            'width': self.width_spin.value(),
            'height': self.height_spin.value(),
            'num_frames': self.duration_spin.value() * 16 + 1,
            'timestamp': datetime.now().isoformat(),
            'video_mode': 'frames'  # 标记为首尾帧模式
        }

        self.batch_tasks_frames.append(task)
        self.update_task_list_display_frames()
        self.add_log(f"📝 已添加首尾帧任务: {task['name']}")

    def update_task_list_display_frames(self):
        """更新任务列表显示（首尾帧模式）"""
        while self.task_list_layout_frames.count():
            item = self.task_list_layout_frames.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        if hasattr(self, 'batch_tasks_frames'):
            for i, task in enumerate(self.batch_tasks_frames):
                task_card = self.create_task_card_frames(task, i)
                self.task_list_layout_frames.addWidget(task_card)

    def create_task_card_frames(self, task, index):
        """创建任务卡片（首尾帧模式）"""
        card = CardWidget()
        card.setFixedHeight(48)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(10, 5, 10, 5)

        info_layout = QVBoxLayout()
        name_label = QLabel(task['name'])
        name_label.setStyleSheet("font-weight: bold; color: #ffffff; font-size: 14px;")
        info_layout.addWidget(name_label)

        info_text = f"首尾帧模式 · {task['width']}×{task['height']}"
        info_label = QLabel(info_text)
        info_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(info_label)

        layout.addLayout(info_layout)
        layout.addStretch()

        delete_btn = PushButton("X")
        delete_btn.setFixedSize(30, 30)
        delete_btn.clicked.connect(lambda: self.remove_task_frames(index))
        layout.addWidget(delete_btn)

        return card

    def remove_task_frames(self, index):
        """删除任务（首尾帧模式）"""
        if not hasattr(self, 'batch_tasks_frames'):
            return
        if 0 <= index < len(self.batch_tasks_frames):
            task_name = self.batch_tasks_frames[index]['name']
            del self.batch_tasks_frames[index]
            self.update_task_list_display_frames()
            self.add_log(f"🗑️ 已删除任务: {task_name}")
    def clear_batch_tasks_frames(self):
        """清空批量任务（首尾帧模式）"""
        if not hasattr(self, 'batch_tasks_frames'):
            self.batch_tasks_frames = []
        self.batch_tasks_frames.clear()
        self.update_task_list_display_frames()
        self.add_log("🗑️ 已清空所有首尾帧任务")

    # 视频换人物模式的任务管理方法
    def add_to_batch_tasks_video(self):
        """添加到批量任务列表（视频换人物模式）"""
        # 初始化视频换人物任务列表
        if not hasattr(self, 'batch_tasks_video'):
            self.batch_tasks_video = []

        # 获取视频输入
        if self.video_input_type_combo.currentIndex() == 1:
            # URL输入
            video_input = self.video_url_edit.text().strip()
            video_path = ""
        else:
            # 本地文件
            video_input = self.video_drop_widget.video_data
            video_path = self.video_drop_widget.current_video_path

        if not video_input:
            QMessageBox.warning(self, "警告", "请先选择源视频文件")
            return

        # 获取目标人物图片
        target_image_input = self.video_target_drop_widget.base64_data
        if not target_image_input:
            QMessageBox.warning(self, "警告", "请先选择目标人物图片")
            return

        # 使用视频换人物选项卡的提示词输入框
        prompt = self.prompt_edit_video.toPlainText().strip() if hasattr(self, 'prompt_edit_video') else ""
        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频换人物提示词")
            return

        task = {
            'name': f"视频换人物任务_{len(self.batch_tasks_video)+1}",
            'video_input': video_input,
            'video_path': video_path,
            'image_input': target_image_input,
            'image_path': self.video_target_drop_widget.current_image_path,
            'prompt': prompt,
            'width': self.width_spin.value(),
            'height': self.height_spin.value(),
            'num_frames': 0,  # 视频换人物不需要帧数
            'timestamp': datetime.now().isoformat(),
            'video_mode': 'video'  # 标记为视频换人物模式
        }

        self.batch_tasks_video.append(task)
        self.update_task_list_display_video()
        self.add_log(f"📝 已添加视频换人物任务: {task['name']}")

    def update_task_list_display_video(self):
        """更新任务列表显示（视频换人物模式）"""
        while self.task_list_layout_video.count():
            item = self.task_list_layout_video.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        if hasattr(self, 'batch_tasks_video'):
            for i, task in enumerate(self.batch_tasks_video):
                task_card = self.create_task_card_video(task, i)
                self.task_list_layout_video.addWidget(task_card)

    def create_task_card_video(self, task, index):
        """创建任务卡片（视频换人物模式）"""
        card = CardWidget()
        card.setFixedHeight(48)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(10, 5, 10, 5)

        info_layout = QVBoxLayout()
        name_label = QLabel(task['name'])
        name_label.setStyleSheet("font-weight: bold; color: #ffffff; font-size: 14px;")
        info_layout.addWidget(name_label)

        info_text = f"视频换人物 · {task['width']}×{task['height']}"
        info_label = QLabel(info_text)
        info_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(info_label)

        layout.addLayout(info_layout)
        layout.addStretch()

        delete_btn = PushButton("X")
        delete_btn.setFixedSize(30, 30)
        delete_btn.clicked.connect(lambda: self.remove_task_video(index))
        layout.addWidget(delete_btn)

        return card

    def remove_task_video(self, index):
        """删除任务（视频换人物模式）"""
        if not hasattr(self, 'batch_tasks_video'):
            return
        if 0 <= index < len(self.batch_tasks_video):
            task_name = self.batch_tasks_video[index]['name']
            del self.batch_tasks_video[index]
            self.update_task_list_display_video()
            self.add_log(f"🗑️ 已删除任务: {task_name}")

    def clear_batch_tasks_video(self):
        """清空批量任务（视频换人物模式）"""
        if not hasattr(self, 'batch_tasks_video'):
            self.batch_tasks_video = []
        self.batch_tasks_video.clear()
        self.update_task_list_display_video()
        self.add_log("🗑️ 已清空所有视频换人物任务")

    # ... (create_result_panel, clear_task_status_cards 方法不变) ...
    def create_result_panel(self):
        """创建结果展示面板（深色主题）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(10)
        layout.setContentsMargins(5, 0, 0, 0)

        self.result_tabs = QTabWidget()
        # ... (QTabWidget 样式代码) ...

        # 视频列表Tab
        self.video_list_widget = QWidget()
        video_list_layout = QVBoxLayout(self.video_list_widget)
        video_list_layout.setContentsMargins(10, 10, 10, 10)
        video_list_layout.setSpacing(10)

        self.batch_progress_bar = ProgressBar()
        self.batch_progress_bar.setFixedHeight(15)
        self.batch_progress_label = QLabel("准备就绪")
        video_list_layout.addWidget(self.batch_progress_label)
        video_list_layout.addWidget(self.batch_progress_bar)

        list_title = QLabel("📋 生成结果:")
        list_title.setStyleSheet("font-size: 16px; font-weight: bold; color: #ffffff; margin-bottom: 5px;")
        video_list_layout.addWidget(list_title)

        self.video_scroll = SmoothScrollArea()
        self.video_scroll_widget = QWidget()
        self.video_scroll_layout = QVBoxLayout(self.video_scroll_widget)
        self.video_scroll_layout.setSpacing(10)
        self.video_scroll.setWidget(self.video_scroll_widget)
        self.video_scroll.setWidgetResizable(True)
        # self.video_scroll.setFixedHeight(450) # 取消固定高度，使其自适应填充
        video_list_layout.addWidget(self.video_scroll)

        self.result_tabs.addTab(self.video_list_widget, "视频列表-任务")


        # 日志Tab
        self.log_widget = QWidget()
        log_layout = QVBoxLayout(self.log_widget)
        log_layout.setContentsMargins(10, 10, 10, 10)
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        # ... (QTextEdit 样式代码) ...
        log_layout.addWidget(QLabel("操作日志:"))
        log_layout.addWidget(self.log_text)

        log_controls = QHBoxLayout()
        clear_log_btn = PushButton("清空日志")
        clear_log_btn.clicked.connect(self.clear_log)
        log_controls.addWidget(clear_log_btn)

        save_log_btn = PushButton("保存日志")
        save_log_btn.clicked.connect(self.save_log)
        log_controls.addWidget(save_log_btn)

        log_controls.addStretch()
        log_layout.addLayout(log_controls)

        self.result_tabs.addTab(self.log_widget, "操作日志")
        layout.addWidget(self.result_tabs)

        return panel

    def clear_task_status_cards(self):
        """清空任务状态卡片"""
        for task_id, card in self.task_status_cards.items():
            if card and hasattr(card, 'deleteLater'):
                card.deleteLater()
        self.task_status_cards.clear()
        
    def create_task_status_card(self, task_id, task):
        """创建任务状态卡片"""
        # 清理旧卡片
        if task_id in self.task_status_cards:
            old_card = self.task_status_cards[task_id]
            if hasattr(old_card, 'deleteLater'):
                old_card.deleteLater()

        task_params = {
            'width': task.get('width', 480),
            'height': task.get('height', 854),
            'num_frames': task.get('num_frames', 81),
            'prompt': task.get('prompt', '')
        }

        card = TaskStatusCard(
            task_id=task_id,
            task_name=task.get('name', f'任务 {task_id}'),
            task_params=task_params,
            parent=self
        )

        # 获取当前任务的密钥源类型
        current_task_key_source = self.api_manager.get_key_source_display()
        card.set_key_source(current_task_key_source)

        self.video_scroll_layout.insertWidget(0, card)

        self.task_status_cards[task_id] = card
        
    # ... (update_task_status_card, update_task_time_card, complete_task_status_card, get_current_image_input 方法不变) ...
    def update_task_status_card(self, task_id, progress, message):
        """更新任务状态卡片"""
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].update_progress(progress, message)

    def update_task_time_card(self, task_id, time_string):
        """更新任务时间显示"""
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].update_time(time_string)

    def complete_task_status_card(self, task_id, success, message=""):
        """完成任务状态卡片"""
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].stop_timing() # 停止计时
            self.task_status_cards[task_id].set_completed(success, message)
            
    def get_current_image_input(self):
        """获取当前图片输入"""
        if self.input_type_combo.currentIndex() == 1:
            return self.image_url_edit.text().strip()
        else:
            return self.drop_widget.base64_data

    # ... (generate_single_video, generate_batch_videos, execute_concurrent_tasks 方法不变) ...
    def generate_single_video(self):
        """生成单个视频 - 支持单图片、首尾帧和视频换人物三种模式"""
        # 获取当前选项卡索引
        current_tab = self.mode_tabs.currentIndex()

        if current_tab == 0:
            # 单图片转视频模式
            input_type = self.input_type_combo.currentIndex()
            prompt = self.prompt_edit.toPlainText().strip() if hasattr(self, 'prompt_edit') else ""

            if input_type == 1:
                image_input = self.image_url_edit.text().strip()
                if not image_input:
                    QMessageBox.warning(self, "警告", "请输入图片URL")
                    return
            else:
                if not hasattr(self.drop_widget, 'base64_data') or not self.drop_widget.base64_data:
                    QMessageBox.warning(self, "警告", "请先上传图片文件")
                    return
                image_input = self.drop_widget.base64_data

            if not prompt:
                QMessageBox.warning(self, "警告", "请输入视频提示词")
                return

            timestamp = datetime.now().strftime("%H%M%S")
            task = {
                'name': f"单个任务_{timestamp}",
                'image_input': image_input,
                'image_path': self.drop_widget.current_image_path if self.input_type_combo.currentIndex() == 0 else '',
                'prompt': prompt,
                'width': self.width_spin.value(),
                'height': self.height_spin.value(),
                'num_frames': self.duration_spin.value() * 16 + 1,
                'video_mode': 'single'
            }

            self.execute_concurrent_tasks([task])

        elif current_tab == 1:
            # 首尾帧图片转视频模式
            start_image_input = self.frames_start_drop_widget.base64_data
            end_image_input = self.frames_end_drop_widget.base64_data

            if not start_image_input:
                QMessageBox.warning(self, "警告", "请先选择首帧图片")
                return

            if not end_image_input:
                QMessageBox.warning(self, "警告", "请先选择尾帧图片")
                return

            timestamp = datetime.now().strftime("%H%M%S")
            task = {
                'name': f"首尾帧单个任务_{timestamp}",
                'image_input': start_image_input,
                'image_path': self.frames_start_drop_widget.current_image_path,
                'end_image_input': end_image_input,
                'end_image_path': self.frames_end_drop_widget.current_image_path,
                'width': self.width_spin.value(),
                'height': self.height_spin.value(),
                'num_frames': self.duration_spin.value() * 16 + 1,
                'video_mode': 'frames'
            }

            self.execute_concurrent_tasks([task])

        else:  # current_tab == 2
            # 视频换人物模式
            # 获取视频输入
            if self.video_input_type_combo.currentIndex() == 1:
                # URL输入
                video_input = self.video_url_edit.text().strip()
                video_path = ""
                if not video_input:
                    QMessageBox.warning(self, "警告", "请输入视频URL")
                    return
            else:
                # 本地文件
                video_input = self.video_drop_widget.video_data
                video_path = self.video_drop_widget.current_video_path
                if not video_input:
                    QMessageBox.warning(self, "警告", "请先选择源视频文件")
                    return

            # 获取目标人物图片
            target_image_input = self.video_target_drop_widget.base64_data
            if not target_image_input:
                QMessageBox.warning(self, "警告", "请先选择目标人物图片")
                return

            # 使用视频换人物选项卡的提示词输入框
            prompt = self.prompt_edit_video.toPlainText().strip() if hasattr(self, 'prompt_edit_video') else ""
            if not prompt:
                QMessageBox.warning(self, "警告", "请输入视频换人物提示词")
                return

            timestamp = datetime.now().strftime("%H%M%S")
            task = {
                'name': f"视频换人物单个任务_{timestamp}",
                'video_input': video_input,
                'video_path': video_path,
                'image_input': target_image_input,
                'image_path': self.video_target_drop_widget.current_image_path,
                'prompt': prompt,
                'width': self.width_spin.value(),
                'height': self.height_spin.value(),
                'num_frames': 0,  # 视频换人物不需要帧数
                'video_mode': 'video'
            }

            self.execute_concurrent_tasks([task])

    def generate_batch_videos(self):
        """生成批量视频 - 支持单图片、首尾帧和视频换人物三种模式"""
        # 获取当前选项卡索引
        current_tab = self.mode_tabs.currentIndex()

        if current_tab == 0:
            # 单图片转视频模式
            if not self.batch_tasks:
                QMessageBox.warning(self, "警告", "请先添加任务到列表")
                return
            self.execute_concurrent_tasks(self.batch_tasks)
        elif current_tab == 1:
            # 首尾帧图片转视频模式
            if not hasattr(self, 'batch_tasks_frames') or not self.batch_tasks_frames:
                QMessageBox.warning(self, "警告", "请先添加首尾帧任务到列表")
                return
            self.execute_concurrent_tasks(self.batch_tasks_frames)
        else:  # current_tab == 2
            # 视频换人物模式
            if not hasattr(self, 'batch_tasks_video') or not self.batch_tasks_video:
                QMessageBox.warning(self, "警告", "请先添加视频换人物任务到列表")
                return
            self.execute_concurrent_tasks(self.batch_tasks_video)

    def execute_concurrent_tasks(self, tasks):
        """真正并发执行任务 - 每个任务独立线程和API密钥"""
        if not tasks:
            return

        self.is_generating = True
        
        # 准备任务映射表 {task_id: task}
        task_map = {}
        for task in tasks:
            # 生成唯一任务ID: timestamp_random
            import random
            task_uid = f"{datetime.now().strftime('%H%M%S')}_{random.randint(100,999)}"
            task_id = f"task_{task_uid}"
            
            # 立即创建状态显示卡片
            # 确保传递完整参数
            card_task_info = task.copy()
            if 'name' not in card_task_info:
                card_task_info['name'] = f"任务_{task_uid}"
                
            self.create_task_status_card(task_id, card_task_info)
            task_map[task_id] = task

        # 提交到管理器
        self.concurrent_batch_manager.add_tasks(task_map, self.key_file_path)

    # ... (update_task_progress, on_task_finished, update_task_time, update_batch_progress, on_all_tasks_finished 方法不变) ...
    def update_task_progress(self, progress, message, task_id):
        """更新任务进度"""
        self.add_log(f"[{task_id}] {progress}% - {message}")
        
        # 自动启动计时器
        if task_id in self.task_status_cards:
            card = self.task_status_cards[task_id]
            card.update_progress(progress, message)
            if progress > 0 and progress < 100:
                card.start_timing()

    def on_task_finished(self, success, message, result_data, task_id):
        """单个任务完成的回调"""
        if success:
            self.add_log(f"✅ [{task_id}] 任务完成: {message}")
            self.complete_task_status_card(task_id, True, message)
            self.create_video_result_card(result_data, task_id)
        else:
            self.add_log(f"❌ [{task_id}] 任务失败: {message}")
            self.complete_task_status_card(task_id, False, message)

    def update_task_time(self, time_string, task_id):
        """更新任务时间显示"""
        self.update_task_time_card(task_id, time_string)

    def update_batch_progress(self, completed, total):
        """更新批量进度"""
        progress = int((completed / total) * 100) if total > 0 else 0
        self.batch_progress_bar.setValue(progress)
        self.batch_progress_label.setText(f"批量进度: {completed}/{total}")

    def on_all_tasks_finished(self):
        """所有任务完成"""
        self.is_generating = False
        self.add_log("🎉 所有并发任务已完成！")
        self.refresh_task_videos() # 刷新缩略图

    def create_video_result_card(self, result_data, task_id):
        """创建视频结果卡片"""
        try:
            # 在 VideoResultCard 自动下载后，VideoGenerationWidget 负责刷新缩略图
            card = VideoResultCard(result_data, task_id, self)
            self.video_scroll_layout.addWidget(card)
        except Exception as e:
            self.add_log(f"❌ 创建视频结果卡片失败: {e}")

    # ... (refresh_task_videos, create_video_thumbnail, open_output_folder, play_task_video, load_settings, save_settings, add_log, clear_log, save_log 方法不变) ...
    def refresh_task_videos(self):
        """刷新任务视频列表 (功能已禁用，界面元素已移除)"""
        pass

    def create_video_thumbnail(self, video_info):
        """创建视频缩略图"""
        try:
            widget = QWidget()
            # Widget大小将根据内容动态调整，这里设置最大高度限制
            widget.setFixedHeight(110)
            
            # ... (QWidget 样式代码，保持背景色等) ...
            widget.setStyleSheet("""
                QWidget {
                    background-color: #2a2a2a;
                    border: 1px solid #404040;
                    border-radius: 4px;
                }
                QWidget:hover {
                    border: 1px solid #4a90e2;
                    background-color: #333333;
                }
            """)

            layout = QVBoxLayout(widget)
            layout.setContentsMargins(5, 5, 5, 5)
            layout.setSpacing(2)

            thumbnail_label = QLabel()
            thumbnail_label.setAlignment(Qt.AlignCenter)
            
            target_height = 80 # 缩略图固定高度
            target_width = 142 # 默认 16:9 宽度
            
            if video_info.get('thumb_path') and os.path.exists(video_info['thumb_path']):
                try:
                    pixmap = QPixmap(video_info['thumb_path'])
                    if not pixmap.isNull():
                        # 计算自适应宽度
                        aspect_ratio = pixmap.width() / pixmap.height()
                        target_width = int(target_height * aspect_ratio)
                        
                        scaled_pixmap = pixmap.scaled(
                            target_width, target_height,
                            Qt.KeepAspectRatio,
                            Qt.SmoothTransformation
                        )
                        thumbnail_label.setPixmap(scaled_pixmap)
                    else:
                        thumbnail_label.setText("视频")
                        thumbnail_label.setStyleSheet("font-size: 14px; color: #666;")
                except:
                    thumbnail_label.setText("视频")
                    thumbnail_label.setStyleSheet("font-size: 14px; color: #666;")
            else:
                thumbnail_label.setText("视频")
                thumbnail_label.setStyleSheet("font-size: 14px; color: #666;")
            
            thumbnail_label.setFixedSize(target_width, target_height)
            layout.addWidget(thumbnail_label)
            
            # 根据计算出的缩略图宽度设置整个组件的固定宽度
            widget.setFixedWidth(target_width + 10) # 左右边距各5
            
            # ... (标签和点击事件) ...
            name_label = QLabel(video_info['name'][:15] + "..." if len(video_info['name']) > 15 else video_info['name'])
            name_label.setStyleSheet("color: #ffffff; font-size: 10px; background: transparent; border: none;")
            name_label.setAlignment(Qt.AlignCenter)
            layout.addWidget(name_label)

            widget.mousePressEvent = lambda event: self.play_task_video(video_info['path'], video_info['name'])

            return widget

        except Exception as e:
            self.add_log(f"⚠️ 创建视频缩略图失败: {e}")
            return None

    def open_output_folder(self):
        """打开output文件夹"""
        output_dir = "output"
        if Utils.open_folder(output_dir):
            self.add_log(f"📁 已打开output文件夹")
        else:
            self.add_log(f"❌ 打开文件夹失败")

    def play_task_video(self, file_path, file_name):
        """使用本地播放器播放视频"""
        try:
            if not os.path.exists(file_path):
                self.add_log(f"⚠️ 视频文件不存在: {file_path}")
                return

            QDesktopServices.openUrl(QUrl.fromLocalFile(file_path))
            self.add_log(f"🎬 使用本地播放器打开视频: {file_name}")

        except Exception as e:
            self.add_log(f"❌ 打开视频失败: {str(e)}")

    def load_settings(self):
        """加载设置 - 使用配置管理器"""
        try:
            video_params = self.settings_manager.get_video_params()
            api_settings = self.settings_manager.get_api_settings()

            self.width_spin.setValue(video_params.get('width', 480))
            self.height_spin.setValue(video_params.get('height', 854))
            self.duration_spin.setValue(video_params.get('duration', 5))
            self.frames_label.setText(str(video_params.get('num_frames', 81)))

            # 加载密钥配置
            key_source = api_settings.get('key_source', 'file')
            key_file = api_settings.get('key_file', '')
            key_text = api_settings.get('key_text', '')

            if key_source == 'text' and key_text:
                self.api_manager.load_keys_from_text(key_text)
                self.api_manager.set_key_source('text')
                self.key_file_path = None
            elif key_source == 'file' and key_file and os.path.exists(key_file):
                self.api_manager.load_keys_from_file(key_file)
                self.api_manager.set_key_source('file')
                self.key_file_path = key_file
            elif key_source == 'env':
                env_key = os.getenv('SiliconCloud_API_KEY')
                if env_key:
                    self.api_manager.set_key_source('env')
                    self.key_file_path = None
                else:
                    self.api_manager.set_key_source('file')
                    self.key_file_path = None
            else:
                self.api_manager.set_key_source('file')
                self.key_file_path = None

            # 加载 Web App ID
            self.api_manager.web_app_id_single = api_settings.get('web_app_id_single', 39386)
            self.api_manager.web_app_id_frames = api_settings.get('web_app_id_frames', 39388)
            self.api_manager.web_app_id_video = api_settings.get('web_app_id_video', 38808)

            self.update_key_status()
            self.update_current_params_display()
            self.refresh_task_videos()
            self.webapp_id_label.setText(f"单图:{self.api_manager.web_app_id_single} | 首尾帧:{self.api_manager.web_app_id_frames} | 换人物:{self.api_manager.web_app_id_video}")

            self.add_log(f"✅ 已加载视频设置配置")

        except Exception as e:
            self.add_log(f"❌ 加载设置失败: {e}")
            try:
                self.update_current_params_display()
            except AttributeError:
                if hasattr(self, 'current_params_top_label'):
                    self.current_params_top_label.setText("当前: 480×854, 5秒, 81帧")

    def save_settings(self):
        """保存设置 - 使用配置管理器"""
        try:
            width = self.width_spin.value() if hasattr(self, 'width_spin') and self.width_spin else 480
            height = self.height_spin.value() if hasattr(self, 'height_spin') and self.height_spin else 854
            duration = self.duration_spin.value() if hasattr(self, 'duration_spin') and self.duration_spin else 5

            success1 = self.settings_manager.set_video_params(width, height, duration)

            # 准备 API 设置参数
            key_source = self.api_manager.get_key_source()
            key_file_path = getattr(self, 'key_file_path', '') if key_source == 'file' else ''
            key_text = self.api_manager.key_text if key_source == 'text' else ''
            
            success2 = self.settings_manager.set_api_settings(
                key_file=key_file_path,
                web_app_id_single=self.api_manager.web_app_id_single,
                web_app_id_frames=self.api_manager.web_app_id_frames,
                web_app_id_video=self.api_manager.web_app_id_video,
                key_text=key_text,
                key_source=key_source
            )

            if success1 and success2:
                self.add_log(f"✅ 视频设置已保存")
            else:
                self.add_log(f"⚠️ 部分设置保存失败")

        except Exception as e:
            self.add_log(f"❌ 保存设置失败: {e}")

    def add_log(self, message):
        """添加日志到日志文本框"""
        try:
            timestamp = datetime.now().strftime("%H:%M:%S")
            log_entry = f"[{timestamp}] {message}"

            if hasattr(self, 'log_text'):
                self.log_text.append(log_entry)
                scrollbar = self.log_text.verticalScrollBar()
                scrollbar.setValue(scrollbar.maximum())

            print(log_entry)
        except Exception as e:
            print(f"添加日志失败: {e}, 原消息: {message}")

    def clear_log(self):
        """清空日志"""
        if hasattr(self, 'log_text'):
            self.log_text.clear()
            self.add_log("📋 日志已清空")

    def save_log(self):
        """保存日志到文件"""
        try:
            if hasattr(self, 'log_text'):
                log_content = self.log_text.toPlainText()
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                log_file = f"video_generation_log_{timestamp}.txt"

                with open(log_file, 'w', encoding='utf-8') as f:
                    f.write(log_content)

                QMessageBox.information(self, "成功", f"日志已保存到: {log_file}")
                self.add_log(f"📄 日志已保存到文件: {log_file}")
        except Exception as e:
            QMessageBox.warning(self, "错误", f"保存日志失败: {str(e)}")
            self.add_log(f"❌ 保存日志失败: {str(e)}")

# --- 12. 视频参数设置对话框 (VideoSettingsDialog) ---
class VideoSettingsDialog(QDialog):
    # ... (代码基本不变，仅修正了 frames_label 的文本更新) ...
    """视频参数设置对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("视频参数设置")
        self.setMinimumSize(550, 480)
        self.setStyleSheet("""
            QDialog { background-color: #1e1e1e; color: #ffffff; }
            QSpinBox {
                background-color: #333333;
                border: 1px solid #505050;
                border-radius: 4px;
                color: #ffffff;
                padding: 4px;
                min-height: 30px;
                font-size: 14px;
            }
            QSpinBox:hover {
                border: 1px solid #4a90e2;
            }
            QSpinBox::up-button, QSpinBox::down-button {
                width: 20px;
                background-color: #404040;
                border: none;
            }
            QLabel { font-size: 14px; }
            QGroupBox { 
                border: 1px solid #404040; 
                border-radius: 6px; 
                margin-top: 12px; 
                padding-top: 20px;
                font-size: 14px;
            }
            QGroupBox::title { subcontrol-origin: margin; left: 10px; padding: 0 5px; color: #aaaaaa; }
        """)
        self.init_ui()
        self.load_current_settings()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)
        layout.setContentsMargins(25, 25, 25, 25)

        title_label = QLabel("视频参数配置")
        title_label.setStyleSheet("font-size: 18px; font-weight: bold; color: #ffffff; margin-bottom: 10px;")
        layout.addWidget(title_label)

        resolution_group = QGroupBox("预设分辨率")
        # ... (resolution_group 样式代码) ...
        resolution_layout = QVBoxLayout(resolution_group)
        self.resolution_combo = ComboBox()
        self.resolution_combo.addItems([
            "自定义",
            "480p - 9:16 (480×854)", "480p - 16:9 (854×480)",
            "720p - 9:16 (720×1280)", "720p - 16:9 (1280×720)", 
            "1080p - 9:16 (1080×1920)", "1080p - 16:9 (1920×1080)"
        ])
        self.resolution_combo.setCurrentIndex(0)
        self.resolution_combo.setFixedHeight(34)
        self.resolution_combo.currentIndexChanged.connect(self.on_resolution_changed)
        preset_label = QLabel("选择预设:")
        # ... (preset_label 样式代码) ...
        resolution_layout.addWidget(preset_label)
        resolution_layout.addWidget(self.resolution_combo)
        layout.addWidget(resolution_group)

        size_group = QGroupBox("自定义尺寸")
        # ... (size_group 样式代码) ...
        size_layout = QGridLayout(size_group)

        # 宽度
        width_label = QLabel("宽度 (px):")
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 4096)
        self.width_spin.setSingleStep(64)
        self.width_spin.setValue(480)
        # ... (QSpinBox 样式代码) ...
        size_layout.addWidget(width_label, 0, 0)
        size_layout.addWidget(self.width_spin, 0, 1)

        # 互换按钮
        self.swap_btn = PushButton("🔄")
        self.swap_btn.setFixedSize(40, 36)
        self.swap_btn.clicked.connect(self.swap_dimensions)
        # ... (QPushButton 样式代码) ...
        size_layout.addWidget(self.swap_btn, 0, 2)

        # 高度
        height_label = QLabel("高度 (px):")
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 4096)
        self.height_spin.setSingleStep(64)
        self.height_spin.setValue(854)
        # ... (QSpinBox 样式代码) ...
        size_layout.addWidget(height_label, 1, 0)
        size_layout.addWidget(self.height_spin, 1, 1)
        layout.addWidget(size_group)

        # 视频时长
        duration_group = QGroupBox("视频时长")
        # ... (duration_group 样式代码) ...
        duration_layout = QHBoxLayout(duration_group)

        duration_label = QLabel("时长(秒):")
        self.duration_spin = QSpinBox()
        self.duration_spin.setRange(1, 30)
        self.duration_spin.setValue(5)
        self.duration_spin.setSingleStep(1)
        # ... (QSpinBox 样式代码) ...
        self.duration_spin.valueChanged.connect(lambda value: self.update_frames(value))
        duration_layout.addWidget(duration_label)
        duration_layout.addWidget(self.duration_spin)
        layout.addWidget(duration_group)

        # 帧数信息
        info_group = QGroupBox("帧数信息")
        # ... (info_group 样式代码) ...
        info_layout = QVBoxLayout(info_group)

        self.frames_label = QLabel("总帧数: 81")
        # ... (QLabel 样式代码) ...
        info_layout.addWidget(self.frames_label)

        frames_note = QLabel("注：16帧 = 1秒，总帧数 = (时长 × 16) + 1")
        frames_note.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(frames_note)
        layout.addWidget(info_group)

        # 按钮区域
        button_layout = QHBoxLayout()
        self.reset_btn = PushButton("重置默认")
        self.reset_btn.clicked.connect(self.reset_defaults)
        # ... (QPushButton 样式代码) ...
        button_layout.addWidget(self.reset_btn)

        button_layout.addStretch()

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        # ... (QPushButton 样式代码) ...
        button_layout.addWidget(cancel_btn)

        save_btn = PrimaryPushButton("确定")
        save_btn.clicked.connect(self.accept_settings)
        # ... (QPushButton 样式代码) ...
        button_layout.addWidget(save_btn)

        layout.addLayout(button_layout)

    def load_current_settings(self):
        """从配置文件加载当前设置"""
        try:
            if hasattr(self.parent(), 'settings_manager'):
                video_params = self.parent().settings_manager.get_video_params()
                self.width_spin.setValue(video_params.get('width', 480))
                self.height_spin.setValue(video_params.get('height', 854))
                self.duration_spin.setValue(video_params.get('duration', 5))
                self.update_frames(video_params.get('duration', 5))
            elif hasattr(self.parent(), 'width_spin'):
                self.width_spin.setValue(self.parent().width_spin.value())
                self.height_spin.setValue(self.parent().height_spin.value())
                self.duration_spin.setValue(self.parent().duration_spin.value())
                self.update_frames(self.duration_spin.value())
        except Exception as e:
            print(f"加载视频设置失败: {e}")
            self.reset_defaults()

    def on_resolution_changed(self, index):
        """预设分辨率改变"""
        resolutions = {
            1: (480, 854), 2: (854, 480), # 480p
            3: (720, 1280), 4: (1280, 720), # 720p
            5: (1080, 1920), 6: (1920, 1080) # 1080p
        }
        if index in resolutions:
            self.width_spin.setValue(resolutions[index][0])
            self.height_spin.setValue(resolutions[index][1])

    def update_frames(self, seconds):
        """根据秒数更新帧数"""
        total_frames = seconds * 16 + 1
        self.frames_label.setText(f"总帧数: {total_frames}") # 修正文本

    def swap_dimensions(self):
        """互换宽度和高度"""
        width, height = self.width_spin.value(), self.height_spin.value()
        self.width_spin.setValue(height)
        self.height_spin.setValue(width)

    def reset_defaults(self):
        """重置为默认值"""
        self.width_spin.setValue(480)
        self.height_spin.setValue(854)
        self.duration_spin.setValue(5)
        self.resolution_combo.setCurrentIndex(0)
        self.update_frames(5)

    def accept_settings(self):
        """应用设置并关闭"""
        try:
            if hasattr(self.parent(), 'width_spin'):
                self.parent().width_spin.setValue(self.width_spin.value())
                self.parent().height_spin.setValue(self.height_spin.value())
                self.parent().duration_spin.setValue(self.duration_spin.value())
                self.parent().update_frames(self.duration_spin.value())
                self.parent().update_current_params_display()
                
                if hasattr(self.parent(), 'settings_manager'):
                    self.parent().settings_manager.set_video_params(
                        self.width_spin.value(),
                        self.height_spin.value(),
                        self.duration_spin.value()
                    )
                    self.parent().add_log("✅ 视频参数设置已保存到JSON配置文件")

                self.parent().add_log("✅ 视频参数设置已应用")
        except Exception as e:
            if hasattr(self.parent(), 'add_log'):
                self.parent().add_log(f"❌ 应用设置失败: {str(e)}")
        self.accept()

# --- 13. API设置对话框 (APISettingsDialog) ---
class APISettingsDialog(QDialog):
    # ... (代码基本不变，仅修正了 save_settings 中对 key_file_path 的处理，确保在切换到 env 时设置为空) ...
    """API设置对话框"""

    def __init__(self, api_manager, parent=None):
        super().__init__(parent)
        self.api_manager = api_manager
        self.setWindowTitle("API密钥设置")
        self.setMinimumSize(500, 400)
        self.init_ui()
        self.load_current_settings()
        self.setStyleSheet("""
            QDialog { background-color: #1e1e1e; color: #ffffff; }
            QSpinBox {
                background-color: #333333;
                border: 1px solid #505050;
                border-radius: 4px;
                color: #ffffff;
                padding: 4px;
                min-height: 30px;
                font-size: 14px;
            }
            QSpinBox:hover {
                border: 1px solid #4a90e2;
            }
            QSpinBox::up-button, QSpinBox::down-button {
                width: 20px;
                background-color: #404040;
                border: none;
            }
            QLineEdit {
                background-color: #333333;
                border: 1px solid #505050;
                border-radius: 4px;
                color: #ffffff;
                padding: 4px;
                font-size: 14px;
            }
        """)

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        webapp_group = QGroupBox("Web App ID 配置")
        webapp_layout = QVBoxLayout(webapp_group)

        # 单图片转视频 Web App ID
        single_layout = QHBoxLayout()
        single_layout.addWidget(QLabel("单图片转视频 ID:"))
        self.webapp_id_single_spin = QSpinBox()
        self.webapp_id_single_spin.setRange(1, 99999)
        self.webapp_id_single_spin.setValue(getattr(self.api_manager, 'web_app_id_single', 39386))
        self.webapp_id_single_spin.setFixedWidth(150)
        single_layout.addWidget(self.webapp_id_single_spin)
        single_layout.addStretch()
        webapp_layout.addLayout(single_layout)

        # 首尾帧图片转视频 Web App ID
        frames_layout = QHBoxLayout()
        frames_layout.addWidget(QLabel("首尾帧转视频 ID:"))
        self.webapp_id_frames_spin = QSpinBox()
        self.webapp_id_frames_spin.setRange(1, 99999)
        self.webapp_id_frames_spin.setValue(getattr(self.api_manager, 'web_app_id_frames', 39388))
        self.webapp_id_frames_spin.setFixedWidth(150)
        frames_layout.addWidget(self.webapp_id_frames_spin)
        frames_layout.addStretch()
        webapp_layout.addLayout(frames_layout)

        # 视频换人物 Web App ID
        video_layout = QHBoxLayout()
        video_layout.addWidget(QLabel("视频换人物 ID:"))
        self.webapp_id_video_spin = QSpinBox()
        self.webapp_id_video_spin.setRange(1, 99999)
        self.webapp_id_video_spin.setValue(getattr(self.api_manager, 'web_app_id_video', 38808))
        self.webapp_id_video_spin.setFixedWidth(150)
        video_layout.addWidget(self.webapp_id_video_spin)
        video_layout.addStretch()
        webapp_layout.addLayout(video_layout)

        # API URL 设置
        api_url_layout = QHBoxLayout()
        api_url_layout.addWidget(QLabel("API 请求地址:"))
        self.api_url_edit = LineEdit()
        current_url = getattr(self.api_manager, 'api_url', "https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
        self.api_url_edit.setText(current_url)
        self.api_url_edit.setPlaceholderText("默认: https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
        api_url_layout.addWidget(self.api_url_edit)
        webapp_layout.addLayout(api_url_layout)

        layout.addWidget(webapp_group)

        key_group = QGroupBox("API密钥设置")
        key_layout = QVBoxLayout(key_group)

        # 密钥源选择
        source_layout = QHBoxLayout()
        source_label = QLabel("密钥来源：")
        source_layout.addWidget(source_label)

        from PyQt5.QtWidgets import QRadioButton, QButtonGroup
        self.key_source_group = QButtonGroup(self)

        self.file_radio = QRadioButton("文件密钥")
        self.file_radio.setChecked(True)
        self.key_source_group.addButton(self.file_radio, 0)
        source_layout.addWidget(self.file_radio)

        self.env_radio = QRadioButton("系统变量")
        self.key_source_group.addButton(self.env_radio, 1)
        source_layout.addWidget(self.env_radio)

        self.text_radio = QRadioButton("密钥文本")
        self.key_source_group.addButton(self.text_radio, 2)
        source_layout.addWidget(self.text_radio)

        self.file_radio.toggled.connect(self.on_key_source_changed)
        self.env_radio.toggled.connect(self.on_key_source_changed)
        self.text_radio.toggled.connect(self.on_key_source_changed)
        key_layout.addLayout(source_layout)

        line = QFrame()
        line.setFrameShape(QFrame.HLine)
        key_layout.addWidget(line)

        # 文件密钥设置
        file_layout = QHBoxLayout()
        self.key_file_edit = LineEdit()
        self.key_file_edit.setPlaceholderText("输入密钥文件路径...")
        self.key_file_edit.setText(getattr(self.parent(), 'key_file_path', ''))
        file_layout.addWidget(self.key_file_edit)

        self.browse_btn = PushButton("浏览")
        self.browse_btn.clicked.connect(self.browse_key_file)
        file_layout.addWidget(self.browse_btn)
        key_layout.addLayout(file_layout)

        # 密钥文本设置
        self.key_text_edit = QTextEdit()
        self.key_text_edit.setPlaceholderText("直接输入API密钥，每行一个密钥...")
        self.key_text_edit.setMaximumHeight(100)
        key_layout.addWidget(QLabel("密钥文本:"))
        key_layout.addWidget(self.key_text_edit)

        self.env_status_label = QLabel("系统变量状态：检查中...")
        key_layout.addWidget(self.env_status_label)
        self.update_env_status()

        info_label = QLabel("密钥格式：每行一个API密钥，建议至少18个密钥用于批量处理")
        info_label.setStyleSheet("color: #666; font-size: 12px; padding: 5px;")
        key_layout.addWidget(info_label)

        self.test_btn = PushButton("测试密钥")
        self.test_btn.clicked.connect(self.test_keys)
        key_layout.addWidget(self.test_btn)
        layout.addWidget(key_group)

        self.status_label = QLabel("准备就绪")
        self.status_label.setStyleSheet("padding: 10px; background: #333333; border-radius: 4px;")
        layout.addWidget(self.status_label)

        button_layout = QHBoxLayout()
        save_btn = PrimaryPushButton("保存")
        save_btn.clicked.connect(self.save_settings)
        button_layout.addWidget(save_btn)

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)
        layout.addLayout(button_layout)

        self.on_key_source_changed() # 初始状态更新

    def on_key_source_changed(self):
        """密钥源切换处理"""
        is_file = self.file_radio.isChecked()
        is_env = self.env_radio.isChecked()
        is_text = self.text_radio.isChecked()

        self.key_file_edit.setEnabled(is_file)
        self.browse_btn.setEnabled(is_file)
        self.key_text_edit.setEnabled(is_text)
        self.test_btn.setEnabled(is_file or is_text)
        self.update_env_status()
        self.status_label.setText("准备就绪")
        self.status_label.setStyleSheet("padding: 10px; background: #333333; border-radius: 4px; color: #ffffff;")

    def update_env_status(self):
        """更新系统变量状态显示"""
        env_key = os.getenv('SiliconCloud_API_KEY')
        if self.env_radio.isChecked():
            if env_key:
                masked_key = f"{env_key[:10]}...{env_key[-5:]}"
                self.env_status_label.setText(f"系统变量已设置: {masked_key}")
                self.env_status_label.setStyleSheet("color: #4CAF50; font-size: 12px; padding: 5px;")
            else:
                self.env_status_label.setText("系统变量 SiliconCloud_API_KEY 未设置")
                self.env_status_label.setStyleSheet("color: #f44336; font-size: 12px; padding: 5px;")
        else:
            self.env_status_label.setText("")

    def browse_key_file(self):
        """浏览密钥文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择API密钥文件", "", "文本文件 (*.txt);;所有文件 (*)"
        )
        if file_path:
            self.key_file_edit.setText(file_path)

    def test_keys(self):
        """测试密钥"""
        is_file = self.file_radio.isChecked()
        is_text = self.text_radio.isChecked()

        temp_api_manager = APIKeyManager()

        if is_file:
            file_path = self.key_file_edit.text().strip()
            if not file_path or not os.path.exists(file_path):
                QMessageBox.warning(self, "警告", "请选择有效的密钥文件")
                return

            if temp_api_manager.load_keys_from_file(file_path):
                count = len(temp_api_manager.api_keys)
                self.status_label.setText(f"✅ 成功加载 {count} 个API密钥")
                self.status_label.setStyleSheet("padding: 10px; background: #e8f5e8; border-radius: 4px; color: #4CAF50;")
            else:
                self.status_label.setText("❌ 密钥文件加载失败")
                self.status_label.setStyleSheet("padding: 10px; background: #ffebee; border-radius: 4px; color: #f44336;")

        elif is_text:
            key_text = self.key_text_edit.toPlainText().strip()
            if not key_text:
                QMessageBox.warning(self, "警告", "请输入密钥文本")
                return

            if temp_api_manager.load_keys_from_text(key_text):
                count = len(temp_api_manager.api_keys)
                self.status_label.setText(f"✅ 成功加载 {count} 个API密钥")
                self.status_label.setStyleSheet("padding: 10px; background: #e8f5e8; border-radius: 4px; color: #4CAF50;")
            else:
                self.status_label.setText("❌ 密钥文本解析失败")
                self.status_label.setStyleSheet("padding: 10px; background: #ffebee; border-radius: 4px; color: #f44336;")

    def save_settings(self):
        """保存设置"""
        # 保存三个 Web App ID
        webapp_id_single = self.webapp_id_single_spin.value()
        webapp_id_frames = self.webapp_id_frames_spin.value()
        webapp_id_video = self.webapp_id_video_spin.value()
        api_url = self.api_url_edit.text().strip()

        self.api_manager.web_app_id_single = webapp_id_single
        self.api_manager.web_app_id_frames = webapp_id_frames
        self.api_manager.web_app_id_video = webapp_id_video
        self.api_manager.api_url = api_url

        # 更新父级管理器
        self.parent().api_manager.web_app_id_single = webapp_id_single
        self.parent().api_manager.web_app_id_frames = webapp_id_frames
        self.parent().api_manager.web_app_id_video = webapp_id_video
        self.parent().api_manager.api_url = api_url

        # 处理密钥来源
        key_file_to_save = ""
        key_text_to_save = ""
        key_source = ""

        if self.file_radio.isChecked():
            # 文件密钥
            key_source = "file"
            file_path = self.key_file_edit.text().strip()

            if not file_path or not os.path.exists(file_path):
                QMessageBox.warning(self, "警告", "请选择有效的密钥文件")
                return

            if self.api_manager.load_keys_from_file(file_path):
                self.parent().key_file_path = file_path
                key_file_to_save = file_path
                self.api_manager.set_key_source("file")
            else:
                QMessageBox.warning(self, "警告", "密钥文件加载失败")
                return

        elif self.env_radio.isChecked():
            # 系统变量
            key_source = "env"
            env_key = os.getenv('SiliconCloud_API_KEY')
            if not env_key:
                QMessageBox.warning(self, "警告", "系统变量 SiliconCloud_API_KEY 未设置")
                return
            self.parent().key_file_path = None
            key_file_to_save = ""
            self.api_manager.set_key_source("env")

        elif self.text_radio.isChecked():
            # 文本密钥
            key_source = "text"
            key_text = self.key_text_edit.toPlainText().strip()
            if not key_text:
                QMessageBox.warning(self, "警告", "请输入密钥文本")
                return
            if self.api_manager.load_keys_from_text(key_text):
                key_text_to_save = key_text
                self.parent().key_file_path = None
                key_file_to_save = ""
                self.api_manager.set_key_source("text")
            else:
                QMessageBox.warning(self, "警告", "密钥文本解析失败")
                return

        # 保存到配置文件
        if hasattr(self.parent(), 'settings_manager'):
            self.parent().settings_manager.set_api_settings(
                key_file=key_file_to_save,
                web_app_id_single=webapp_id_single,
                web_app_id_frames=webapp_id_frames,
                web_app_id_video=webapp_id_video,
                api_url=api_url,
                key_text=key_text_to_save,
                key_source=key_source
            )
            if hasattr(self.parent(), 'add_log'):
                source_name = {
                    "file": "文件密钥",
                    "env": "系统变量",
                    "text": "密钥文本"
                }.get(key_source, "未知")
                self.parent().add_log(f"✅ API密钥设置已保存 ({source_name})")

        self.accept()

    def load_current_settings(self):
        """从配置文件加载当前设置"""
        try:
            if hasattr(self.parent(), 'settings_manager'):
                api_settings = self.parent().settings_manager.get_api_settings()

                key_file = api_settings.get('key_file', '')
                key_text = api_settings.get('key_text', '')
                key_source = api_settings.get('key_source', 'file')
                webapp_id_single = api_settings.get('web_app_id_single', 39386)
                webapp_id_frames = api_settings.get('web_app_id_frames', 39388)
                webapp_id_video = api_settings.get('web_app_id_video', 38808)
                api_url = api_settings.get('api_url', 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create')

                # 设置 Web App ID
                self.webapp_id_single_spin.setValue(webapp_id_single)
                self.webapp_id_frames_spin.setValue(webapp_id_frames)
                self.webapp_id_video_spin.setValue(webapp_id_video)
                self.api_url_edit.setText(api_url)

                # 更新管理器
                self.api_manager.web_app_id_single = webapp_id_single
                self.api_manager.web_app_id_frames = webapp_id_frames
                self.api_manager.web_app_id_video = webapp_id_video
                self.api_manager.api_url = api_url
                self.parent().api_manager.web_app_id_single = webapp_id_single
                self.parent().api_manager.web_app_id_frames = webapp_id_frames
                self.parent().api_manager.web_app_id_video = webapp_id_video
                self.parent().api_manager.api_url = api_url

                # 根据密钥来源设置界面
                env_key = os.getenv('SiliconCloud_API_KEY')
                is_file_config = key_source == "file" and key_file and os.path.exists(key_file)
                is_env_source = key_source == "env" and env_key
                is_text_source = key_source == "text" and key_text

                if is_file_config:
                    self.key_file_edit.setText(key_file)
                    self.file_radio.setChecked(True)
                    self.parent().key_file_path = key_file
                    self.api_manager.load_keys_from_file(key_file)
                    self.api_manager.set_key_source("file")
                elif is_env_source:
                    self.env_radio.setChecked(True)
                    self.parent().key_file_path = None
                    self.api_manager.set_key_source("env")
                elif is_text_source:
                    self.key_text_edit.setText(key_text)
                    self.text_radio.setChecked(True)
                    self.parent().key_file_path = None
                    self.api_manager.load_keys_from_text(key_text)
                    self.api_manager.set_key_source("text")
                else:
                    # 默认选中文件密钥
                    self.file_radio.setChecked(True)
                    if key_file and os.path.exists(key_file):
                        self.key_file_edit.setText(key_file)
                        self.parent().key_file_path = key_file
                        self.api_manager.load_keys_from_file(key_file)
                        self.api_manager.set_key_source("file")

                self.on_key_source_changed() # 确保界面状态正确

        except Exception as e:
            print(f"加载API设置失败: {e}")

# --- 14. 主程序入口（假设已集成到 PyQt 应用框架） ---
if __name__ == '__main__':
    from PyQt5.QtWidgets import QApplication, QMainWindow

    app = QApplication(sys.argv)
    
    # 强制设置深色主题
    app.setStyle('Fusion')
    palette = QPalette()
    palette.setColor(QPalette.Window, Qt.darkGray)
    palette.setColor(QPalette.WindowText, Qt.white)
    palette.setColor(QPalette.Base, Qt.black)
    palette.setColor(QPalette.AlternateBase, Qt.darkGray)
    palette.setColor(QPalette.ToolTipBase, Qt.white)
    palette.setColor(QPalette.ToolTipText, Qt.white)
    palette.setColor(QPalette.Text, Qt.white)
    palette.setColor(QPalette.Button, Qt.darkGray)
    palette.setColor(QPalette.ButtonText, Qt.white)
    palette.setColor(QPalette.BrightText, Qt.red)
    palette.setColor(QPalette.Link, Qt.cyan)
    palette.setColor(QPalette.Highlight, QColor(72, 166, 237))
    palette.setColor(QPalette.HighlightedText, Qt.black)
    app.setPalette(palette)


    main_window = QMainWindow()
    main_window.setWindowTitle("图片转视频生成工具 V2.0.1")
    main_window.setMinimumSize(1200, 800)

    video_widget = VideoGenerationWidget(main_window)
    main_window.setCentralWidget(video_widget)

    main_window.show()
    sys.exit(app.exec_())
