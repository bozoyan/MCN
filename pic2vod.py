#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图片转视频生成模块 (pic2vod) - 增强版
基于 BizyAir API 的图片转视频功能，支持批量生成和更美观的界面
"""

import os
import sys
import json
import time
import threading
import requests
import base64
from datetime import datetime

# 视频设置配置管理
class VideoSettingsManager:
    """视频设置配置管理器"""

    def __init__(self, config_file="video_settings.json"):
        self.config_file = config_file
        self.default_settings = {
            "video_params": {
                "width": 480,
                "height": 854,
                "duration": 5,
                "num_frames": 81
            },
            "api_settings": {
                "key_file": "",
                "web_app_id": 41082  # 正确的WebApp ID
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
                # 合并默认设置，确保所有必要的键都存在
                return self._merge_settings(self.default_settings, settings)
            else:
                return self.default_settings.copy()
        except Exception as e:
            print(f"加载视频设置失败: {e}")
            return self.default_settings.copy()

    def save_settings(self, settings):
        """保存配置文件"""
        try:
            # 创建备份
            if os.path.exists(self.config_file):
                backup_file = f"{self.config_file}.backup"
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    with open(backup_file, 'w', encoding='utf-8') as backup:
                        backup.write(f.read())

            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(settings, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"保存视频设置失败: {e}")
            return False

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

    def set_api_settings(self, key_file, web_app_id=41082):
        """设置API参数"""
        settings = self.load_settings()
        settings["api_settings"] = {
            "key_file": key_file,
            "web_app_id": web_app_id
        }
        return self.save_settings(settings)

    def get_ui_settings(self):
        """获取UI设置"""
        settings = self.load_settings()
        return settings.get("ui_settings", self.default_settings["ui_settings"])

    def set_ui_settings(self, last_export_dir=None):
        """设置UI参数"""
        settings = self.load_settings()
        if last_export_dir:
            settings["ui_settings"]["last_export_dir"] = last_export_dir
        return self.save_settings(settings)

    def _merge_settings(self, defaults, loaded):
        """合并配置，确保所有必要字段都存在"""
        result = defaults.copy()
        for key, value in loaded.items():
            if key in result:
                if isinstance(value, dict) and isinstance(result[key], dict):
                    result[key] = {**result[key], **value}
                else:
                    result[key] = value
            else:
                result[key] = value
        return result
from PyQt5.QtCore import QThread, pyqtSignal, QTimer, Qt, QMimeData, QUrl, QObject
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QLineEdit, QTextEdit, QPushButton, QComboBox,
                            QSpinBox, QProgressBar, QMessageBox, QFileDialog,
                            QGroupBox, QTabWidget, QSplitter, QFrame,
                            QGridLayout, QScrollArea, QSlider, QCheckBox, QDialog, QSizePolicy)
from PyQt5.QtGui import QPixmap, QDragEnterEvent, QDropEvent, QPalette

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
        def __init__(self):
            pass
    class QMediaPlayer:
        def __init__(self):
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
import qfluentwidgets as qf
from qfluentwidgets import (FluentIcon, CardWidget, ElevatedCardWidget,
                          SmoothScrollArea, SubtitleLabel, BodyLabel,
                          PrimaryPushButton, PushButton, LineEdit, ComboBox,
                          ProgressBar, InfoBar, InfoBarPosition,
                          SwitchButton, InfoBadge, TeachingTip, TeachingTipTailPosition,
                          StrongBodyLabel, CaptionLabel)

# 导入配置管理器
try:
    from storyboard_generator import config_manager, MODEL_API_KEY
except ImportError:
    # 如果无法导入，使用默认配置
    MODEL_API_KEY = os.getenv('SiliconCloud_API_KEY')
    class ConfigManager:
        def get(self, key, default=None):
            return default
        def set(self, key, value):
            pass
    config_manager = ConfigManager()

# 图片拖拽上传小部件
class ImageDropWidget(QFrame):
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
        self.image_label.setText("🖼️\n拖拽图片到这里\n或点击选择文件")
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
                    self.base64_data = base64.b64encode(image_data).decode('utf-8')

                self.current_image_path = file_path
                # 添加 current_image_data 属性以保持一致性
                self.current_image_data = self.base64_data
                self.image_dropped.emit(file_path, self.base64_data)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载图片失败: {str(e)}")

    def clear_image(self):
        self.image_label.clear()
        self.image_label.setText("🖼️\n拖拽图片到这里\n或点击选择文件")
        self.current_image_path = ""
        self.base64_data = ""
        self.current_image_data = ""

# API密钥管理器
class APIKeyManager:
    """API密钥管理器"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.current_key_index = 0
        self.web_app_id = 41082  # 正确的WebApp ID
        self.key_source = "file"  # "file" 或 "env"

    def load_keys_from_file(self, file_path):
        """从文件加载API密钥"""
        try:
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    keys = [line.strip() for line in f.readlines() if line.strip()]
                self.api_keys = [key for key in keys if len(key) > 10]  # 过滤掉无效密钥
                self.key_file = file_path
                return True
        except Exception as e:
            print(f"加载API密钥文件失败: {e}")
        return False

    def get_next_key(self):
        """获取下一个可用的API密钥"""
        if not self.api_keys:
            # 如果没有从文件加载，使用环境变量
            env_key = os.getenv('SiliconCloud_API_KEY')
            if env_key:
                return env_key
            return None

        if self.current_key_index >= len(self.api_keys):
            self.current_key_index = 0

        key = self.api_keys[self.current_key_index]
        self.current_key_index += 1
        return key

    def get_available_keys_count(self):
        """获取可用密钥数量"""
        if self.api_keys:
            return len(self.api_keys)
        env_key = os.getenv('SiliconCloud_API_KEY')
        return 1 if env_key else 0

    def get_all_keys(self):
        """获取所有可用的API密钥"""
        if self.key_source == "env":
            env_key = os.getenv('SiliconCloud_API_KEY')
            return [env_key] if env_key else []
        else:
            return self.api_keys if self.api_keys else []

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
        else:
            return "文件密钥"

# 独立任务视频生成工作线程
class SingleVideoGenerationWorker(QThread):
    """单个视频生成工作线程 - 支持独立计时和并发执行"""
    progress_updated = pyqtSignal(int, str, str)  # progress, message, task_id
    task_finished = pyqtSignal(bool, str, dict, str)  # success, message, result_data, task_id
    time_updated = pyqtSignal(str, str)  # time_string, task_id
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, task, task_id, api_key, api_manager):
        super().__init__()
        self.task = task
        self.task_id = task_id
        self.api_key = api_key
        self.api_manager = api_manager  # 添加API管理器引用
        self.start_time = None
        self.is_cancelled = False
        self.time_update_active = False

        # 创建日志目录
        self.log_dir = "logs"
        if not os.path.exists(self.log_dir):
            os.makedirs(self.log_dir)

        # 不再使用QTimer，改用时间信号机制
        # self.timer = QTimer()
        # self.timer.timeout.connect(self.update_timer)
        # self.timer.setInterval(1000)  # 每秒更新一次

    def start_time_updates(self):
        """开始时间更新"""
        self.time_update_active = True
        self.update_time_loop()

    def update_time_loop(self):
        """时间更新循环"""
        if self.time_update_active and not self.is_cancelled:
            self.update_timer()
            # 使用QTimer.singleShot在主线程中执行下一次更新
            QTimer.singleShot(1000, self.update_time_loop)

    def update_timer(self):
        """更新计时器显示"""
        if self.start_time and not self.is_cancelled:
            elapsed = time.time() - self.start_time
            hours = int(elapsed // 3600)
            minutes = int((elapsed % 3600) // 60)
            seconds = int(elapsed % 60)
            time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            self.time_updated.emit(time_str, self.task_id)
            
        # 确保时间更新循环持续执行
        if self.time_update_active and not self.is_cancelled:
            QTimer.singleShot(1000, self.update_timer)

    def log_message(self, message):
        """记录日志消息"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        task_name = self.task.get('name', f'任务 {self.task_id}')
        log_entry = f"[{timestamp}] [{task_name}] {message}"
        self.log_updated.emit(log_entry)

        # 写入日志文件
        log_file = os.path.join(self.log_dir, "batch_video_generation.log")
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"写入日志失败: {e}")

    def compress_image(self, image_data, original_path):
        """压缩图像数据"""
        try:
            # 尝试使用 PIL 进行图像压缩
            try:
                from PIL import Image
                import io

                # 将二进制数据转换为 PIL Image
                image = Image.open(io.BytesIO(image_data))

                # 转换为 RGB（如果是 RGBA 或其他格式）
                if image.mode in ('RGBA', 'LA', 'P'):
                    background = Image.new('RGB', image.size, (255, 255, 255))
                    if image.mode == 'P':
                        image = image.convert('RGBA')
                    background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                    image = background

                # 调整图片大小，保持宽高比
                max_dimension = 1024
                if max(image.size) > max_dimension:
                    ratio = max_dimension / max(image.size)
                    new_size = tuple(int(dim * ratio) for dim in image.size)
                    image = image.resize(new_size, Image.Resampling.LANCZOS)

                # 压缩图片质量
                output = io.BytesIO()
                image.save(output, format='JPEG', quality=85, optimize=True)
                compressed_data = output.getvalue()
                output.close()

                self.log_message(f"✅ 图片压缩成功: {len(image_data)} → {len(compressed_data)} 字节")
                return compressed_data

            except ImportError:
                self.log_message("⚠️ PIL未安装，跳过图片压缩")
                return image_data

        except Exception as e:
            self.log_message(f"❌ 图片压缩失败: {str(e)}")
            return image_data

    def run(self):
        """运行单个视频生成任务"""
        try:
            self.start_time = time.time()
            self.start_time_updates()  # 开始计时更新

            task_name = self.task.get('name', f'任务 {self.task_id}')
            self.log_message(f"🚀 开始生成视频: {task_name}")
            self.progress_updated.emit(5, "初始化任务...", self.task_id)

            # 准备请求数据
            image_input = self.task.get('image_input', '')
            prompt = self.task.get('prompt', '')
            width = self.task.get('width', 480)
            height = self.task.get('height', 854)
            num_frames = self.task.get('num_frames', 81)

            self.progress_updated.emit(10, "准备请求数据...", self.task_id)

            # 图像格式检查和转换
            if isinstance(image_input, str):
                if image_input.startswith('data:image/'):
                    self.log_message("🖼️ 检测到data URL格式的图片数据")
                elif image_input and not image_input.startswith('http') and not image_input.startswith('data:'):
                    try:
                        image_path = self.task.get('image_path', '')
                        if image_path and os.path.exists(image_path):
                            with open(image_path, 'rb') as f:
                                image_data = f.read()

                                max_size = 500 * 1024  # 500KB 限制
                                original_size = len(image_data)

                                if len(image_data) > max_size:
                                    self.log_message(f"⚠️ 图片过大({original_size}字节)，开始压缩...")
                                    image_data = self.compress_image(image_data, image_path)
                                    compressed_size = len(image_data)
                                    compression_ratio = (1 - compressed_size / original_size) * 100
                                    self.log_message(f"✅ 图片压缩完成: {original_size}→{compressed_size}字节 (压缩{compression_ratio:.1f}%)")

                                import imghdr
                                detected_type = imghdr.what(None, image_data)

                                mime_types = {
                                    'jpeg': 'image/jpeg',
                                    'jpg': 'image/jpeg',
                                    'png': 'image/png',
                                    'webp': 'image/webp'
                                }
                                image_type = mime_types.get(detected_type, 'image/jpeg')

                                base64_data = base64.b64encode(image_data).decode('utf-8')
                                # BizyAir API 可能期望纯 base64 字符串，而不是 data URL 格式
                                self.task['image_input'] = base64_data
                                self.log_message(f"📝 已转换图片为纯 base64 格式 ({image_type})")

                    except Exception as e:
                        self.task_finished.emit(False, f"图片处理失败: {str(e)}", {}, self.task_id)
                        return

            self.progress_updated.emit(20, "准备API请求...", self.task_id)


            self.progress_updated.emit(30, "发送API请求...", self.task_id)

            # 发送API请求 - 使用正确的BizyAir API格式
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }

            # 构建BizyAir API请求数据格式 - 参考老版本，支持本地上传
            image_input = self.task['image_input']

            # 处理图片输入格式 - 支持本地上传（参考老版本）
            if image_input.startswith('http'):
                # 网络URL，直接使用
                image_value = image_input
                self.log_message(f"🌐 使用网络图片URL: {image_input}")
            else:
                # 本地文件，转换为data URL格式（参考老版本）
                image_value = f"data:image/jpeg;base64,{image_input}"
                self.log_message(f"📁 使用本地图片文件 (data URL格式)")

            bizyair_request_data = {
                "web_app_id": self.api_manager.web_app_id,  # 41082
                "suppress_preview_output": False,  # 参考老版本使用False
                "input_values": {
                    "67:LoadImage.image": image_value,
                    "68:ImageResizeKJv2.width": width,
                    "68:ImageResizeKJv2.height": height,
                    "16:WanVideoTextEncode.positive_prompt": prompt,
                    "89:WanVideoImageToVideoEncode.num_frames": num_frames
                }
            }

            self.log_message(f"📤 发送BizyAir API请求: {width}x{height}, {num_frames}帧 (AppID: {self.api_manager.web_app_id})")
            self.log_message(f"🔑 API密钥: {self.api_key[:10]}... (长度: {len(self.api_key)})")

            # 简化的API密钥检查
            if not self.api_key:
                self.task_finished.emit(False, "API密钥未配置", {}, self.task_id)
                return

            if self.api_key:
                self.log_message(f"🔑 当前API密钥: {self.api_key[:15]}...{self.api_key[-5:]} (长度: {len(self.api_key)})")
                self.log_message(f"🔑 API密钥格式: {'正确(sk-开头)' if self.api_key.startswith('sk-') else '错误格式'}")

                # 检查是否有隐藏字符或换行符
                clean_key = self.api_key.strip()
                if clean_key != self.api_key:
                    self.log_message(f"⚠️ API密钥包含空白字符，已清理")
                    self.api_key = clean_key

                # 验证API密钥字符
                allowed_chars = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_')
                invalid_chars = [c for c in self.api_key if c not in allowed_chars]
                if invalid_chars:
                    self.log_message(f"⚠️ API密钥包含无效字符: {set(invalid_chars)}")
                else:
                    self.log_message(f"✅ API密钥字符格式正确")
            else:
                self.log_message(f"❌ API密钥为空或未设置！")
                self.task_finished.emit(False, "API密钥未配置", {}, self.task_id)
                return

            # 检查API管理器状态
            available_keys = self.api_manager.get_all_keys()
            self.log_message(f"🔧 API管理器状态: 总密钥数={len(available_keys)}")
            if available_keys:
                self.log_message(f"🔧 第一个密钥示例: {available_keys[0][:15]}...{available_keys[0][-5:]} (长度: {len(available_keys[0])})")

            # 直接发送API请求 - 参考老版本简化格式
            self.log_message(f"📝 请求URL: https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
            self.log_message(f"✅ 使用WebApp ID: {self.api_manager.web_app_id}")

            # 参考老版本的超时设置：(连接超时, 读取超时)
            response = requests.post(
                "https://api.bizyair.cn/w/v1/webapp/task/openapi/create",
                headers=headers,
                json=bizyair_request_data,
                timeout=(300, 600)  # 5分钟连接超时，10分钟读取超时
            )

            self.log_message(f"📡 API响应状态: {response.status_code}")

            # 详细记录API响应内容，帮助调试
            try:
                response_data = response.json()
                self.log_message(f"📋 API响应内容: {json.dumps(response_data, ensure_ascii=False, indent=2)}")
            except:
                self.log_message(f"📋 API响应文本: {response.text[:500]}")

            if response.status_code == 200:
                result_data = response.json()
                self.log_message(f"✅ API请求成功，请求ID: {result_data.get('request_id', 'N/A')}")

                # 检查BizyAir的响应格式
                request_id = result_data.get('request_id')
                status = result_data.get('status', '')

                if request_id:
                    self.log_message(f"📋 任务ID: {request_id}, 状态: {status}")

                    # 处理立即失败的情况
                    if status == 'Failed' or status == 'failed':
                        error_info = result_data.get('error', result_data.get('message', '任务执行失败'))
                        self.task_finished.emit(False, f"视频生成失败: {error_info}", {}, self.task_id)
                        return

                    # 如果任务立即完成且有输出
                    elif status == 'Success' and 'outputs' in result_data:
                        outputs = result_data['outputs']
                        if outputs and len(outputs) > 0:
                            video_url = outputs[0].get('object_url', '')
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
                                    'timestamp': datetime.now().isoformat()
                                }

                                self.progress_updated.emit(100, "任务完成！", self.task_id)
                                self.task_finished.emit(True, "视频生成成功", result, self.task_id)
                                return
                            else:
                                self.task_finished.emit(False, "视频生成成功但未获取到URL", {}, self.task_id)
                                return
                        else:
                            self.task_finished.emit(False, "视频生成成功但无输出结果", {}, self.task_id)
                            return

                    # 如果任务还在处理中（Running, Pending等状态）
                    elif status in ['Running', 'Pending', 'submitted', 'processing']:
                        self.progress_updated.emit(50, "查询任务状态...", self.task_id)
                        video_url = self.check_video_status_bizyair(request_id)

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
                                'timestamp': datetime.now().isoformat()
                            }

                            self.progress_updated.emit(100, "任务完成！", self.task_id)
                            self.task_finished.emit(True, "视频生成成功", result, self.task_id)
                        else:
                            self.task_finished.emit(False, "视频生成失败或超时", {}, self.task_id)

                    # 其他未知状态
                    else:
                        self.log_message(f"⚠️ 未知任务状态: {status}")
                        # 尝试查询一次状态
                        self.progress_updated.emit(50, "查询任务状态...", self.task_id)
                        video_url = self.check_video_status_bizyair(request_id)

                        if video_url:
                            result = {
                                'id': request_id,
                                'url': video_url,
                                'width': width,
                                'height': height,
                                'num_frames': num_frames,
                                'prompt': prompt,
                                'task_name': task_name,
                                'timestamp': datetime.now().isoformat()
                            }
                            self.progress_updated.emit(100, "任务完成！", self.task_id)
                            self.task_finished.emit(True, "视频生成成功", result, self.task_id)
                        else:
                            self.task_finished.emit(False, f"任务状态异常: {status}", {}, self.task_id)
                else:
                    self.task_finished.emit(False, "API响应格式错误：缺少request_id", {}, self.task_id)
                    return
            else:
                error_msg = f"API请求失败: HTTP {response.status_code}"
                try:
                    error_detail = response.json()
                    error_msg += f" - {error_detail.get('message', '未知错误')}"
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
            self.log_message(f"❌ 任务执行异常: {str(e)}")
            self.task_finished.emit(False, f"任务执行异常: {str(e)}", {}, self.task_id)
        finally:
            self.time_update_active = False  # 停止计时更新

    def check_video_status_bizyair(self, request_id):
        """查询BizyAir任务状态"""
        max_attempts = 120  # 最大尝试次数（10分钟）
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
                    timeout=30
                )

                if response.status_code == 200:
                    data = response.json()
                    status = data.get('status', '')

                    self.progress_updated.emit(
                        min(80, 50 + (attempt * 30 // max_attempts)),
                        f"检查进度... ({status})",
                        self.task_id
                    )
                    
                    if status == 'Success' and 'outputs' in data:
                        outputs = data['outputs']
                        if outputs and len(outputs) > 0:
                            video_url = outputs[0].get('object_url', '')
                            if video_url:
                                self.log_message(f"🎉 视频生成完成: {video_url}")
                                return video_url

                    elif status == 'Failed' or status == 'failed':
                        error_info = data.get('error', '生成失败')
                        self.log_message(f"❌ 视频生成失败: {error_info}")
                        return None

                    else:
                        self.log_message(f"⏳ 视频生成中... ({status}) - 第{attempt+1}次检查")

                else:
                    self.log_message(f"⚠️ 状态查询失败: HTTP {response.status_code}")

            except Exception as e:
                self.log_message(f"⚠️ 状态查询异常: {str(e)}")

            # 如果不是最后一次尝试，等待后继续
            if attempt < max_attempts - 1:
                time.sleep(check_interval)

        self.log_message(f"⏰ 视频生成超时 ({max_attempts * check_interval}秒)")
        return None

    def check_video_status(self, video_id):
        """检查视频生成状态"""
        max_attempts = 120  # 最大尝试次数（10分钟）
        check_interval = 5  # 检查间隔5秒

        for attempt in range(max_attempts):
            if self.is_cancelled:
                self.log_message("⏹️ 任务已取消")
                return None

            try:
                headers = {
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                }

                response = requests.get(
                    f"https://api.bizyair.com/v1/inferences/{video_id}",
                    headers=headers,
                    timeout=30
                )

                if response.status_code == 200:
                    data = response.json()
                    status = data.get('status', '')

                    self.progress_updated.emit(
                        min(80, 50 + (attempt * 30 // max_attempts)),
                        f"检查进度... ({status})",
                        self.task_id
                    )

                    if status == 'succeeded':
                        video_url = data.get('output', {}).get('videos', [{}])[0].get('url', '')
                        if video_url:
                            self.log_message(f"🎉 视频生成完成: {video_url}")
                            return video_url

                    elif status == 'failed':
                        error_info = data.get('error', '生成失败')
                        self.log_message(f"❌ 视频生成失败: {error_info}")
                        return None

                    else:
                        self.log_message(f"⏳ 视频生成中... ({status}) - 第{attempt+1}次检查")

                else:
                    self.log_message(f"⚠️ 状态查询失败: HTTP {response.status_code}")

            except Exception as e:
                self.log_message(f"⚠️ 状态查询异常: {str(e)}")

            # 如果不是最后一次尝试，等待后继续
            if attempt < max_attempts - 1:
                time.sleep(check_interval)

        self.log_message(f"⏰ 视频生成超时 ({max_attempts * check_interval}秒)")
        return None

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True
        self.time_update_active = False


# 并发批量任务管理器
class ConcurrentBatchManager(QObject):
    """并发批量任务管理器"""
    all_tasks_finished = pyqtSignal()  # 所有任务完成信号
    task_progress = pyqtSignal(int, str, str)  # 进度更新
    task_finished = pyqtSignal(bool, str, dict, str)  # 任务完成
    task_time_updated = pyqtSignal(str, str)  # 任务时间更新
    log_updated = pyqtSignal(str)  # 日志更新
    batch_progress_updated = pyqtSignal(int, int)  # 批量进度更新

    def __init__(self, api_manager=None):
        super().__init__()
        self.workers = {}  # task_id -> worker
        self.completed_tasks = 0
        self.total_tasks = 0
        # 使用传入的API管理器或创建新的
        self.api_manager = api_manager if api_manager is not None else APIKeyManager()

    def execute_batch_tasks(self, tasks, key_file=None):
        """并发执行批量任务"""
        # --- 修复点1：每次执行前重置状态 ---
        self.workers.clear()
        self.completed_tasks = 0
        self.total_tasks = len(tasks)

        # 加载API密钥
        if key_file:
            self.api_manager.load_keys_from_file(key_file)

        available_keys = self.api_manager.get_all_keys()
        if len(available_keys) < len(tasks):
            self.log_updated.emit(f"⚠️ 警告: 只有{len(available_keys)}个密钥，但有{len(tasks)}个任务")

        self.log_updated.emit(f"🚀 开始并发批量生成，共{len(tasks)}个任务 (AppID: {self.api_manager.web_app_id})")

        # 为每个任务创建独立的工作线程
        for i, task in enumerate(tasks):
            task_id = f"task_{i+1}"

            # 循环分配API密钥
            api_key = available_keys[i % len(available_keys)] if available_keys else None

            if not api_key:
                self.task_finished.emit(False, "没有可用的API密钥", {}, task_id)
                self.completed_tasks += 1
                self.update_batch_progress()
                continue

            # 创建工作线程
            worker = SingleVideoGenerationWorker(task, task_id, api_key, self.api_manager)
            self.workers[task_id] = worker

            # 连接信号
            worker.progress_updated.connect(self.task_progress)
            worker.task_finished.connect(self.on_single_task_finished)
            worker.time_updated.connect(self.task_time_updated)
            worker.log_updated.connect(self.log_updated)

            # 启动任务（错开并发执行，避免API限流）
            worker.start()
            self.log_updated.emit(f"🚀 已启动任务 {task_id}，使用密钥 {api_key[:10]}...")

            # 增加错开启动时间，避免同时请求API导致限流
            time.sleep(0.5)  # 增加到0.5秒，给API足够的缓冲时间

    def on_single_task_finished(self, success, message, result_data, task_id):
        """单个任务完成的回调"""
        self.completed_tasks += 1
        self.update_batch_progress()

        # 将任务完成信号传递给主界面
        self.task_finished.emit(success, message, result_data, task_id)

        # 移除已完成的工作线程
        if task_id in self.workers:
            worker = self.workers.pop(task_id)
            # 等待线程完全结束
            if worker.isRunning():
                worker.quit()
                worker.wait(3000)  # 等待最多3秒
            worker.deleteLater()

        # 检查是否所有任务都已完成
        if self.completed_tasks >= self.total_tasks:
            self.log_updated.emit(f"✅ 所有任务完成！成功: {self.completed_tasks}/{self.total_tasks}")
            self.all_tasks_finished.emit()
            # --- 修复点2：任务完成后重置状态 ---
            self.completed_tasks = 0
            self.total_tasks = 0
            self.workers.clear()

    def update_batch_progress(self):
        """更新批量进度"""
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

    def cancel_all_tasks(self):
        """取消所有任务"""
        # 先取消所有任务
        for worker in self.workers.values():
            worker.cancel()

        # 等待所有线程结束
        for worker in self.workers.values():
            if worker.isRunning():
                worker.quit()
                worker.wait(5000)  # 等待最多5秒

        # 清空工作线程列表
        self.workers.clear()


# 保留原有的批量视频生成工作线程（向后兼容）
class BatchVideoGenerationWorker(QThread):
    """批量视频生成工作线程"""
    progress_updated = pyqtSignal(int, str, str)  # progress, message, task_id
    task_finished = pyqtSignal(bool, str, dict, str)  # success, message, result_data, task_id
    batch_progress = pyqtSignal(int, int)  # current, total
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, task_list):
        super().__init__()
        self.task_list = task_list
        self.api_manager = APIKeyManager()
        self.start_time = None
        # 移除QTimer，在工作线程中使用会导致跨线程问题
        self.is_cancelled = False

        # 创建日志目录
        self.log_dir = "logs"
        if not os.path.exists(self.log_dir):
            os.makedirs(self.log_dir)

    
    def log_message(self, message):
        """记录日志消息"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}"
        self.log_updated.emit(log_entry)

        # 写入日志文件
        log_file = os.path.join(self.log_dir, "batch_video_generation.log")
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"写入日志失败: {e}")

    def compress_image(self, image_data, original_path):
        """压缩图像数据"""
        try:
            # 尝试使用 PIL 进行图像压缩
            try:
                from PIL import Image
                import io

                # 将二进制数据转换为 PIL Image
                image = Image.open(io.BytesIO(image_data))

                # 转换为 RGB（如果是 RGBA 或其他格式）
                if image.mode in ('RGBA', 'LA', 'P'):
                    background = Image.new('RGB', image.size, (255, 255, 255))
                    if image.mode == 'P':
                        image = image.convert('RGBA')
                    background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                    image = background

                # 计算新的尺寸，保持宽高比
                max_dimension = 1024  # 最大尺寸
                width, height = image.size

                if width > max_dimension or height > max_dimension:
                    ratio = min(max_dimension / width, max_dimension / height)
                    new_width = int(width * ratio)
                    new_height = int(height * ratio)
                    image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
                    self.log_message(f"🖼️ 图片尺寸调整: {width}×{height} → {new_width}×{new_height}")

                # 压缩图像
                output = io.BytesIO()
                # 使用 JPEG 格式压缩，质量 85%
                image.save(output, format='JPEG', quality=85, optimize=True)
                compressed_data = output.getvalue()
                output.close()

                self.log_message(f"🔧 使用PIL压缩完成")
                return compressed_data

            except ImportError:
                self.log_message("⚠️ PIL库未安装，使用简单压缩方法")
                return self.simple_image_compress(image_data, original_path)

        except Exception as e:
            self.log_message(f"⚠️ 图像压缩失败，使用原始数据: {str(e)}")
            return image_data

    def simple_image_compress(self, image_data, original_path):
        """简单图像压缩方法（当 PIL 不可用时）"""
        try:
            # 检查是否为 PNG，如果是，尝试转换为 JPEG
            import imghdr
            detected_type = imghdr.what(None, image_data)

            if detected_type == 'png':
                self.log_message("🔄 尝试将 PNG 转换为 JPEG 以减小文件大小")
                # 这里只能进行简单处理，PIL 不可用时功能有限
                # 返回原始数据，但记录日志
                self.log_message("⚠️ 无法进行格式转换，保持原始 PNG 格式")

            return image_data

        except Exception as e:
            self.log_message(f"⚠️ 简单压缩失败: {str(e)}")
            return image_data

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True
        self.log_message("⏹️ 批量任务已取消")

    def run(self):
        """运行批量视频生成"""
        try:
            self.start_time = time.time()

            self.log_message(f"🚀 开始批量生成视频，共 {len(self.task_list)} 个任务 (AppID: {self.api_manager.web_app_id})")
            self.batch_progress.emit(0, len(self.task_list))

            # 加载API密钥
            if hasattr(self.task_list[0], 'key_file') and self.task_list[0].key_file:
                self.api_manager.load_keys_from_file(self.task_list[0].key_file)
                self.log_message(f"📋 已加载 {self.api_manager.get_available_keys_count()} 个API密钥")

            for i, task in enumerate(self.task_list):
                if self.is_cancelled:
                    break

                # 计算并显示运行时间
                if self.start_time:
                    elapsed = time.time() - self.start_time
                    hours = int(elapsed // 3600)
                    minutes = int((elapsed % 3600) // 60)
                    seconds = int(elapsed % 60)
                    time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
                    self.log_message(f"⏱️ 运行时间: {time_str}")

                self.log_message(f"📝 处理任务 {i+1}/{len(self.task_list)}: {task.get('name', '未命名')}")
                self.batch_progress.emit(i, len(self.task_list))

                # 处理单个任务
                success = self.process_single_task(task, f"task_{i+1}")

                if not success and self.is_cancelled:
                    break

            if not self.is_cancelled:
                self.batch_progress.emit(len(self.task_list), len(self.task_list))
                self.log_message("✅ 批量生成完成!")

        except Exception as e:
            self.log_message(f"❌ 批量生成失败: {str(e)}")

    def process_single_task(self, task, task_id):
        """处理单个视频生成任务"""
        try:
            api_key = self.api_manager.get_next_key()
            if not api_key:
                self.task_finished.emit(False, "没有可用的API密钥", {}, task_id)
                return False

            self.progress_updated.emit(5, "获取API密钥...", task_id)

            # 准备请求数据
            image_input = task.get('image_input', '')
            prompt = task.get('prompt', '')
            width = task.get('width', 480)
            height = task.get('height', 854)
            num_frames = task.get('num_frames', 81)

            self.progress_updated.emit(10, "准备请求数据...", task_id)

            # 图像格式检查和转换 - 针对BizyAir API优化
            if isinstance(image_input, str):
                if image_input.startswith('data:image/'):
                    self.log_message("🖼️ 检测到data URL格式的图片数据")
                    # 对于已有的data URL格式，保持不变
                elif image_input and not image_input.startswith('http') and not image_input.startswith('data:'):
                    # 纯base64数据或本地文件路径，需要转换为正确格式
                    try:
                        image_path = task.get('image_path', '')
                        if image_path and os.path.exists(image_path):
                            # 从文件路径重新读取并转换
                            with open(image_path, 'rb') as f:
                                image_data = f.read()

                                # 检查图片大小，如果过大则压缩
                                max_size = 500 * 1024  # 500KB 限制
                                original_size = len(image_data)

                                if len(image_data) > max_size:
                                    self.log_message(f"⚠️ 图片过大({original_size}字节)，开始压缩...")
                                    image_data = self.compress_image(image_data, image_path)
                                    compressed_size = len(image_data)
                                    compression_ratio = (1 - compressed_size / original_size) * 100
                                    self.log_message(f"✅ 图片压缩完成: {original_size}→{compressed_size}字节 (压缩{compression_ratio:.1f}%)")

                                # 尝试确定图片类型
                                import imghdr
                                detected_type = imghdr.what(None, image_data)

                                # 根据图片类型设置MIME类型
                                mime_types = {
                                    'jpeg': 'image/jpeg',
                                    'jpg': 'image/jpeg',
                                    'png': 'image/png',
                                    'webp': 'image/webp'
                                }
                                image_type = mime_types.get(detected_type, 'image/jpeg')

                                # 转换为 data URL 格式（BizyAir API可能需要这种格式）
                                base64_data = base64.b64encode(image_data).decode('utf-8')
                                image_input = f"data:{image_type};base64,{base64_data}"
                                self.log_message(f"✅ 图片已转换为data URL格式，类型: {image_type}, 大小: {len(image_input)}字符")
                                self.log_message(f"💡 提示: 将使用data URL格式提交API（包含MIME类型前缀）")
                        else:
                            # 尝试将纯base64转换为data URL
                            import imghdr
                            try:
                                decoded_data = base64.b64decode(image_input)
                                detected_type = imghdr.what(None, decoded_data)
                                mime_types = {
                                    'jpeg': 'image/jpeg',
                                    'jpg': 'image/jpeg',
                                    'png': 'image/png',
                                    'webp': 'image/webp'
                                }
                                image_type = mime_types.get(detected_type, 'image/jpeg')
                                # 转换为 data URL 格式
                                image_input = f"data:{image_type};base64,{image_input}"
                                self.log_message(f"✅ 已转换为data URL格式，检测到类型: {image_type}")
                            except:
                                # 如果解码失败，默认使用JPEG格式的data URL
                                image_input = f"data:image/jpeg;base64,{image_input}"
                                self.log_message(f"⚠️ 无法检测图片类型，使用默认JPEG格式的data URL")
                    except Exception as e:
                        self.log_message(f"⚠️ 图片转换失败: {str(e)}")
                        return False
                elif image_input.startswith('http'):
                    self.log_message("🌐 使用网络图片URL")
                else:
                    self.log_message(f"📷 图片输入类型: {type(image_input)}")
            else:
                self.log_message(f"⚠️ 图片输入不是字符串格式: {type(image_input)}")

            # API验证和参数优化
            self.log_message(f"🔑 API密钥验证: {api_key[:20]}...{api_key[-10:] if len(api_key) > 30 else api_key}")
            self.log_message(f"🆔 Web App ID: {self.api_manager.web_app_id}")

            # 优化参数：如果图片过大或帧数过多，给出警告
            if isinstance(image_input, str) and len(image_input) > 5000000:  # 5MB base64 限制降低
                self.log_message(f"⚠️ 警告: 图片较大({len(image_input)}字符)，可能影响API处理")
                # 如果仍然过大，尝试进一步压缩
                if len(image_input) > 8000000:  # 8MB 硬限制
                    self.log_message(f"❌ 错误: 图片过大({len(image_input)}字符)，超过API限制")
                    self.task_finished.emit(False, f"图片过大，请使用更小的图片({len(image_input)}字符 > 8MB限制)", {}, task_id)
                    return False

            if num_frames > 481:  # 超过30秒
                self.log_message(f"⚠️ 警告: 帧数较多({num_frames}帧)，可能增加处理时间")

            base_url = 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create'
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }

            # 准备图像数据 - 根据BizyAir API文档使用简单字符串格式
            if image_input.startswith('http'):
                # 对于URL，直接使用
                image_value = image_input
                self.log_message("🔧 使用图像URL格式")
            else:
                # 对于data URL或base64，直接使用字符串格式
                image_value = image_input
                if image_input.startswith('data:image/'):
                    self.log_message("🔧 使用data URL字符串格式")
                else:
                    self.log_message("🔧 使用base64字符串格式")

            input_values = {
                "67:LoadImage.image": image_value,
                "68:ImageResizeKJv2.width": width,
                "68:ImageResizeKJv2.height": height,
                "16:WanVideoTextEncode.positive_prompt": prompt,
                "89:WanVideoImageToVideoEncode.num_frames": num_frames
            }

            request_data = {
                "web_app_id": self.api_manager.web_app_id,
                "suppress_preview_output": False,  # 修复：改为False，与标准API一致
                "input_values": input_values
            }

            self.progress_updated.emit(20, "连接API服务器...", task_id)

            # 开始请求计时
            request_start_time = time.time()

            # 优化超时设置：改为300秒，给足够时间但不会太长
            self.log_message(f"📤 发送API请求: {prompt[:100]}...")

            # 记录请求数据信息（不影响实际发送的数据）
            image_info = ""
            if "input_values" in request_data and "67:LoadImage.image" in request_data["input_values"]:
                image_data = request_data["input_values"]["67:LoadImage.image"]
                if isinstance(image_data, dict):
                    # 对象格式
                    data_type = image_data.get("type", "unknown")
                    if "data" in image_data:
                        data_length = len(image_data["data"])
                        image_info = f"图像格式: [对象格式，类型: {data_type}, 数据长度: {data_length}字符]"
                    else:
                        image_info = f"图像格式: [对象格式，类型: {data_type}]"
                elif isinstance(image_data, str):
                    if image_data.startswith('data:'):
                        # data URL格式
                        image_info = f"图像格式: [Data URL格式，长度: {len(image_data)}字符]"
                    elif image_data.startswith('http'):
                        # URL格式
                        image_info = f"图像格式: [URL格式: {image_data[:80]}...]"
                    else:
                        # 纯base64或其他格式
                        image_info = f"图像格式: [字符串格式，长度: {len(image_data)}字符]"
                else:
                    image_info = f"图像格式: [数据类型: {type(image_data)}]"

            # 创建用于日志的请求数据副本（隐藏敏感信息）
            log_request_data = {
                "web_app_id": request_data["web_app_id"],
                "suppress_preview_output": request_data["suppress_preview_output"],
                "input_values": {
                    "67:LoadImage.image": image_info,
                    "68:ImageResizeKJv2.width": request_data["input_values"]["68:ImageResizeKJv2.width"],
                    "68:ImageResizeKJv2.height": request_data["input_values"]["68:ImageResizeKJv2.height"],
                    "16:WanVideoTextEncode.positive_prompt": request_data["input_values"]["16:WanVideoTextEncode.positive_prompt"],
                    "89:WanVideoImageToVideoEncode.num_frames": request_data["input_values"]["89:WanVideoImageToVideoEncode.num_frames"]
                }
            }

            self.log_message(f"📋 请求数据: {json.dumps(log_request_data, ensure_ascii=False, indent=2)}")

            # 使用更短的超时设置，避免长时间等待
            # (连接超时, 读取超时) - 优化超时设置
            self.log_message(f"🌐 连接服务器，超时设置: 连接300s，读取600s")

            response = requests.post(
                base_url,
                headers=headers,
                json=request_data,
                timeout=(300, 600)  # 连接300秒超时，读取600秒超时
            )

            if self.is_cancelled:
                return False

            # 计算请求用时
            request_time = time.time() - request_start_time
            self.progress_updated.emit(60, f"API请求完成({request_time:.1f}s)，处理响应...", task_id)

            # 详细记录响应信息
            self.log_message(f"📥 响应状态码: {response.status_code}")
            self.log_message(f"📄 响应头: {dict(response.headers)}")

            if response.status_code == 200:
                self.progress_updated.emit(80, "解析API响应...", task_id)
                result = response.json()

                # 创建日志友好的响应数据（隐藏过长的base64数据）
                log_result = result.copy()
                if "outputs" in log_result and isinstance(log_result["outputs"], list):
                    for output in log_result["outputs"]:
                        if isinstance(output, dict) and "object_url" in output:
                            url = output["object_url"]
                            if len(url) > 200:  # 如果URL很长，可能是base64数据
                                output["object_url"] = f"[数据URL，长度: {len(url)}字符]"

                self.log_message(f"📋 API响应: {json.dumps(log_result, ensure_ascii=False, indent=2)}")

                if result.get("status") == "Success" and result.get("outputs"):
                    self.progress_updated.emit(90, "提取视频URL...", task_id)
                    outputs = result["outputs"]
                    if outputs and len(outputs) > 0:
                        video_output = outputs[0]
                        video_url = video_output.get("object_url", "")

                        if video_url:
                            self.log_message(f"✅ 视频生成成功: {video_url}")

                            result_data = {
                                "url": video_url,  # 统一使用 'url' 字段
                                "input_image": image_input,
                                "prompt": prompt,
                                "width": width,
                                "height": height,
                                "num_frames": num_frames,
                                "task_name": task.get('name', '未命名'),
                                "timestamp": datetime.now().isoformat()
                            }

                            self.progress_updated.emit(100, "视频生成完成!", task_id)
                            self.task_finished.emit(True, "视频生成成功!", result_data, task_id)
                            return True
                        else:
                            error_msg = "响应中未找到视频URL"
                            self.log_message(f"❌ {error_msg}")
                    else:
                        error_msg = "响应中outputs为空"
                        self.log_message(f"❌ {error_msg}")
                else:
                    status = result.get("status", "未知")
                    error_msg = f"API返回状态: {status}"
                    self.log_message(f"❌ {error_msg}")
            else:
                error_msg = f"HTTP错误 {response.status_code}: {response.text}"
                self.log_message(f"❌ {error_msg}")

            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False

        except requests.exceptions.Timeout as e:
            error_msg = f"API请求超时(连接300s/读取600s): {str(e)}"
            self.log_message(f"⏰ {error_msg}")
            self.log_message(f"💡 建议: 1) 检查网络连接 2) 尝试更小的图片 3) 缩短视频时长 4) 稍后重试")
            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False
        except requests.exceptions.ConnectionError as e:
            error_msg = f"网络连接错误: {str(e)}"
            self.log_message(f"🔌 {error_msg}")
            self.log_message(f"💡 建议: 1) 检查网络连接 2) 确认API服务器可访问 3) 检查防火墙设置")
            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False
        except json.JSONDecodeError as e:
            error_msg = f"响应解析错误: {str(e)}"
            self.log_message(f"📄 {error_msg}")
            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False
        except Exception as e:
            error_msg = f"生成异常: {str(e)}"
            self.log_message(f"💥 {error_msg}")
            import traceback
            self.log_message(f"📋 详细错误堆栈: {traceback.format_exc()}")
            self.progress_updated.emit(0, error_msg, task_id)
            self.task_finished.emit(False, error_msg, {}, task_id)
            return False

# 主要的视频生成界面
class VideoGenerationWidget(QWidget):
    """视频生成主界面 - 增强版"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_batch_worker = None
        self.concurrent_batch_manager = None  # 新增并发管理器
        self.batch_tasks = []
        self.api_manager = APIKeyManager()

        # 任务状态卡片管理器
        self.task_status_cards = {}  # task_id -> TaskStatusCard

        # 初始化配置管理器
        self.settings_manager = VideoSettingsManager()

        # 先初始化隐藏的参数控件
        self.init_hidden_params_controls()

        self.init_ui()
        self.load_settings()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(8, 8, 8, 8)

        # 设置深色主题整体样式
        self.setStyleSheet("""
            VideoGenerationWidget {
                background-color: #2A2A2A;
                color: #ffffff;
            }
            QScrollArea {
                background-color: #2A2A2A;
                border: none;
            }
            QSplitter::handle {
                background-color: #3a3a3a;
                width: 2px;
            }
            QSplitter::handle:hover {
                background-color: #4a4a4a;
            }
            QLabel {
                color: #ffffff;
                font-size: 13px;
            }
            QGroupBox {
                color: #ffffff;
            }
            QPushButton {
                color: #ffffff;
            }
            QTextEdit {
                color: #ffffff;
            }
            QLineEdit {
                color: #ffffff;
            }
            QComboBox {
                color: #ffffff;
            }
            QSpinBox {
                color: #ffffff;
            }
        """)

        # 顶部控制栏 - 密钥设置（深色主题）
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

    def create_top_bar(self):
        """创建顶部控制栏（深色主题）"""
        bar = QFrame()
        bar.setFixedHeight(60)  # 增加高度
        bar.setStyleSheet("""
            QFrame {
                background-color: #2a2a2a;
                border-radius: 8px;
                margin: 2px;
            }
        """)
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(12, 12, 12, 12)  # 增加上下边距

        # 标题
        title = QLabel("🎬 图片转视频生成")
        title.setStyleSheet("font-size: 18px; font-weight: bold; color: #ffffff;")
        layout.addWidget(title)

        layout.addStretch()

        # 当前密钥状态显示（深色主题）
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

        # 显示 Web App ID（避免混淆）
        self.webapp_id_label = QLabel(f"AppID: {self.api_manager.web_app_id}")
        self.webapp_id_label.setStyleSheet("""
            color: #4a90e2;
            padding: 6px 15px;
            background: #2a3a4a;
            border-radius: 6px;
            border: 1px solid #4a90e2;
            font-size: 12px;
            font-weight: bold;
            min-width: 100px;
        """)
        layout.addWidget(self.webapp_id_label)

        # 密钥设置按钮
        self.settings_btn = PushButton("API 密钥设置")  # 移除图标，添加文字
        self.settings_btn.setFixedSize(130, 32)  # 增加宽度以显示完整文字
        # 修复: 将 show_settings_dialog 更正为正确的 APISettingsDialog 调用方式
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

        # 分隔线
        separator = QLabel("|")
        separator.setStyleSheet("color: #666666; font-size: 14px; margin: 0 8px;")
        layout.addWidget(separator)

        # 视频参数设置按钮（顶部版本）
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

        # 当前参数显示（顶部版本）
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
            # 更新密钥状态显示
            self.update_key_status()
            
            # 更新WebApp ID显示
            self.webapp_id_label.setText(f"AppID: {self.api_manager.web_app_id}")
            
            # 保存设置
            self.save_settings()

    def update_key_status(self):
        """更新密钥状态显示"""
        try:
            available_keys = self.api_manager.get_available_keys_count()
            key_source_display = self.api_manager.get_key_source_display()

            if available_keys > 0:
                if self.api_manager.get_key_source() == "env":
                    self.key_status_label.setText(f"系统变量: 1个可用")
                    self.key_status_label.setStyleSheet("""
                        color: #17a2b8;
                        padding: 6px 15px;
                        background: #e6f7ff;
                        border-radius: 6px;
                        border: 1px solid #17a2b8;
                        font-size: 12px;
                        min-width: 120px;
                    """)
                else:
                    self.key_status_label.setText(f"{key_source_display}: {available_keys}个可用")
                    self.key_status_label.setStyleSheet("""
                        color: #28a745;
                        padding: 6px 15px;
                        background: #e8f5e8;
                        border-radius: 6px;
                        border: 1px solid #28a745;
                        font-size: 12px;
                        min-width: 120px;
                    """)
            else:
                if self.api_manager.get_key_source() == "env":
                    self.key_status_label.setText("系统变量: 未设置")
                    self.key_status_label.setStyleSheet("""
                        color: #dc3545;
                        padding: 6px 15px;
                        background: #ffebee;
                        border-radius: 6px;
                        border: 1px solid #dc3545;
                        font-size: 12px;
                        min-width: 120px;
                    """)
                else:
                    self.key_status_label.setText("文件密钥: 未配置")
                    self.key_status_label.setStyleSheet("""
                        color: #cccccc;
                        padding: 6px 15px;
                        background: #333333;
                        border-radius: 6px;
                        border: 1px solid #404040;
                        font-size: 12px;
                        min-width: 120px;
                    """)
        except Exception as e:
            self.add_log(f"更新密钥状态显示失败: {e}")

    def create_control_panel(self):
        """创建控制面板（深色主题）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(6)  # 减少模块间距
        layout.setContentsMargins(8, 8, 8, 8)  # 减少面板边距

        # 创建滚动区域
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("""
            QScrollArea {
                background-color: #2A2A2A;
                border: none;
            }
            QScrollBar:vertical {
                background-color: #2a2a2a;
                width: 8px;
                border-radius: 4px;
            }
            QScrollBar::handle:vertical {
                background-color: #4a4a4a;
                border-radius: 4px;
                min-height: 20px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #5a5a5a;
            }
        """)

        scroll_widget = QWidget()
        scroll_widget.setStyleSheet("QWidget { background-color: #2A2A2A; }")
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setSpacing(6)  # 减少滚动区域内间距

        # 图片输入组
        image_group = self.create_image_input_group()
        scroll_layout.addWidget(image_group)
        
        # 提示词输入区域（移到图片上传区域下方）
        prompt_group = self.create_prompt_group()
        scroll_layout.addWidget(prompt_group)

        # 批量任务组（移到按钮上方）
        batch_group = self.create_batch_group()
        scroll_layout.addWidget(batch_group)

        # 操作按钮组（放在最下方）
        actions_group = self.create_actions_group()
        scroll_layout.addWidget(actions_group)

        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        return panel

    def create_image_input_group(self):
        """创建图片输入组（深色主题）"""
        group = QGroupBox("") #图片输入
        layout = QVBoxLayout(group)
        layout.setSpacing(0)

        # 输入方式选择（简化，一行显示）
        self.input_type_combo = ComboBox()
        self.input_type_combo.addItems(["本地文件上传", "图片URL"])
        self.input_type_combo.setFixedHeight(32)
        self.input_type_combo.setStyleSheet("""
            QComboBox {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 13px;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
            }
            QComboBox::down-arrow {
                image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEFSURBVCiRldKxSgNBEMbxH0QZ0CuEF2CiEwJCgKESFuwBLhAT8AFyEO7wELsAC7AQX4CNxgU0cG6+dCZmZn8ZzYwXJJW8k8/fnOeOA8gw/r9fSEECGNFIAiCRZSROJIKJVmQygJMFQYGIFFsCgnhBaiBiOIEFEZgYhBRRGYGGYBFJp9uQRZZYcS1Lb5EA/ghggCVBJEARRyESOhKhszEMDQDdICB9ALRxZUeCcOPPMi5F+T8SX6FMaVvUIFxAIsgYgsI6IEHEhgUYEagIYRGAqPwiwAEYQmAqBQbY4QhBiBoZfn+/fXfjPMO4KdYvKEnKcTb1ncNcIrr8AyVcOlH9Zc1wAAAAASUVORK5CYII=);
                width: 12px;
                height: 12px;
            }
            QComboBox QAbstractItemView {
                background-color: #333333;
                border: 1px solid #404040;
                selection-background-color: #4a90e2;
                color: #ffffff;
            }
        """)
        self.input_type_combo.currentIndexChanged.connect(self.on_input_type_changed)
        layout.addWidget(self.input_type_combo)

        # URL输入框
        self.url_widget = QWidget()
        url_layout = QVBoxLayout(self.url_widget)
        url_layout.setContentsMargins(0, 0, 0, 0)

        self.image_url_edit = LineEdit()
        self.image_url_edit.setFixedHeight(32)
        self.image_url_edit.setPlaceholderText("输入图片URL地址...")
        self.image_url_edit.setStyleSheet("""
            QLineEdit {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 6px 12px;
                color: #ffffff;
                font-size: 13px;
            }
            QLineEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        url_layout.addWidget(self.image_url_edit)

        layout.addWidget(self.url_widget)

        # 本地文件上传区域
        self.upload_widget = QWidget()
        upload_layout = QVBoxLayout(self.upload_widget)
        upload_layout.setContentsMargins(0, 0, 0, 0)

        # 拖拽上传区域
        self.drop_widget = ImageDropWidget()
        self.drop_widget.image_dropped.connect(self.on_image_dropped)
        upload_layout.addWidget(self.drop_widget)

        layout.addWidget(self.upload_widget)

        # 初始状态 - 默认选择本地文件上传（索引0）
        self.input_type_combo.setCurrentIndex(0)
        self.on_input_type_changed(0)

        return group

    def create_batch_group(self):
        """创建批量任务组（深色主题）"""
        group = QGroupBox("") #批量任务管理
        layout = QVBoxLayout(group)
        layout.setSpacing(0)

        # 任务列表
        self.task_list_widget = QWidget()
        self.task_list_layout = QVBoxLayout(self.task_list_widget)
        self.task_list_layout.setSpacing(0)
        # 注意：QVBoxLayout 没有 setStyleSheet 方法，移除这个调用

        # 创建滚动区域用于任务列表
        self.task_scroll = QScrollArea()
        self.task_scroll.setWidgetResizable(True)
        self.task_scroll.setFixedHeight(130)  # 减少高度，让界面更紧凑
        self.task_scroll.setWidget(self.task_list_widget)

        # 任务标题 - 使用更紧凑的显示
        task_title = QLabel("待处理任务:")
        task_title.setStyleSheet("color: #ffffff; font-size: 18px; font-weight: bold; padding: 2px 0;")
        layout.addWidget(task_title)
        layout.addWidget(self.task_scroll)

        # 添加任务按钮
        add_task_layout = QHBoxLayout()
        self.add_task_btn = PushButton("+ 添加到任务列表 +")  # 移除图标
        self.add_task_btn.setFixedSize(240, 36)
        self.add_task_btn.setStyleSheet("""
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
        self.add_task_btn.clicked.connect(self.add_to_batch_tasks)
        add_task_layout.addWidget(self.add_task_btn)

        self.clear_tasks_btn = PushButton("X 清空任务 X")  # 移除图标
        self.clear_tasks_btn.setFixedSize(240, 36)
        self.clear_tasks_btn.setStyleSheet("""
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
                border: 1px solid #dc3545;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.clear_tasks_btn.clicked.connect(self.clear_batch_tasks)
        add_task_layout.addWidget(self.clear_tasks_btn)

        layout.addLayout(add_task_layout)

        return group

    def create_params_group(self):
        """创建空的视频参数组（隐藏，只保留控件初始化）"""
        # 初始化隐藏的控件（供对话框使用）
        self.init_hidden_params_controls()

        # 返回空的QWidget，不显示任何内容
        empty_widget = QWidget()
        empty_widget.setFixedHeight(0)  # 高度为0，完全隐藏
        return empty_widget

    def init_hidden_params_controls(self):
        """初始化隐藏的参数控件（供对话框使用）"""
        # 预设分辨率（隐藏）
        self.resolution_combo = ComboBox()
        self.resolution_combo.addItems([
            "自定义",
            "480p - 16:9 (854×480)",
            "480p - 9:16 (480×854)",
            "720p - 16:9 (1280×720)",
            "720p - 9:16 (720×1280)",
            "1080p - 16:9 (1920×1080)",
            "1080p - 9:16 (1080×1920)"
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

        # BizyAir API的帧数计算：16帧/秒 + 1帧封面
        frames = seconds * 16 + 1
        self.frames_label.setText(str(frames))

        # 同时更新对话框中的显示（如果存在）
        if hasattr(self, 'video_settings_dialog') and self.video_settings_dialog:
            if hasattr(self.video_settings_dialog, 'frames_label'):
                self.video_settings_dialog.frames_label.setText(str(frames))

    def show_video_settings_dialog(self):
        """显示视频参数设置对话框"""
        dialog = VideoSettingsDialog(self)
        if dialog.exec_() == QDialog.Accepted:
            self.update_current_params_display()

    def update_current_params_display(self):
        """更新当前参数显示"""
        try:
            width = self.width_spin.value()
            height = self.height_spin.value()
            duration = self.duration_spin.value()
            frames = self.frames_label.text()

            # 更新两个位置的显示
            params_text = f"当前: {width}×{height}, {duration}秒, {frames}帧"

            # 更新左侧面板中的显示
            if hasattr(self, 'current_params_label'):
                self.current_params_label.setText(params_text)

            # 更新顶部导航栏中的显示
            if hasattr(self, 'current_params_top_label'):
                self.current_params_top_label.setText(params_text)
        except AttributeError as e:
            # 如果控件不存在，使用默认值
            default_params = "当前: 480×854, 5秒, 81帧"
            if hasattr(self, 'current_params_top_label'):
                self.current_params_top_label.setText(default_params)
            if hasattr(self, 'current_params_label'):
                self.current_params_label.setText(default_params)

    def create_prompt_group(self):
        """创建提示词输入组（无标题无边框）"""
        # 提示词输入框（自适应高度）
        self.prompt_edit = QTextEdit()
        self.prompt_edit.setPlaceholderText("输入视频生成的提示词，例如：美女跳舞、风景变化等...")
        self.prompt_edit.setMinimumHeight(40)  # 设置最小高度，但允许自适应
        self.prompt_edit.setMaximumHeight(280)  # 设置最大高度，防止过大
        self.prompt_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.prompt_edit.setStyleSheet("""
            QTextEdit {
                font-size: 18px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                border: 1px solid #404040;
                border-radius: 6px;
                padding: 12px;
                background-color: #333333;
                color: #ffffff;
                selection-background-color: #4a90e2;
            }
            QTextEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        
        return self.prompt_edit
        
    def create_actions_group(self):
        """创建操作按钮组（深色主题）"""
        group = QGroupBox("") #操作
        layout = QVBoxLayout(group)
        layout.setContentsMargins(10, 15, 10, 10)

        # 生成按钮放在底部左对齐
        button_layout = QHBoxLayout()
        button_layout.setSpacing(10)

        self.single_generate_btn = PrimaryPushButton("单个生成")
        self.single_generate_btn.setFixedSize(120, 36)
        self.single_generate_btn.setStyleSheet("""
            QPushButton {
                background-color: #4a90e2;
                border: none;
                border-radius: 6px;
                color: #ffffff;
                font-size: 18px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #5ba0f2;
            }
            QPushButton:pressed {
                background-color: #3a80d2;
            }
        """)
        self.single_generate_btn.clicked.connect(self.generate_single_video)
        button_layout.addWidget(self.single_generate_btn)

        self.batch_generate_btn = PrimaryPushButton("批量生成")
        self.batch_generate_btn.setFixedSize(120, 36)
        self.batch_generate_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                border: none;
                border-radius: 6px;
                color: #ffffff;
                font-size: 18px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #38b755;
            }
            QPushButton:pressed {
                background-color: #1a9735;
            }
        """)
        self.batch_generate_btn.clicked.connect(self.generate_batch_videos)
        button_layout.addWidget(self.batch_generate_btn)

        # 添加弹性空间到右侧
        button_layout.addStretch()

        layout.addLayout(button_layout)

        return group

    def create_result_panel(self):
        """创建结果展示面板（深色主题）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(10)
        layout.setContentsMargins(5, 0, 0, 0)

        # 创建Tab Widget
        self.result_tabs = QTabWidget()
        self.result_tabs.setStyleSheet("""
            QTabWidget::pane {
                background: #2a2a2a;
                border-radius: 8px;
            }
            QTabBar::tab {
                background: #333333;
                color: #cccccc;
                padding: 10px 20px;
                margin-right: 2px;
                border-top-left-radius: 8px;
                border-top-right-radius: 8px;
                border: 1px solid #404040;
                border-bottom: none;
                font-weight: 500;
                font-size: 13px;
            }
            QTabBar::tab:selected {
                background: #4a90e2;
                color: #ffffff;
                border-bottom: 1px solid #4a90e2;
            }
            QTabBar::tab:hover:!selected {
                background: #3a3a3a;
                color: #ffffff;
            }
        """)

        # 视频列表Tab（整合播放功能）
        self.video_list_widget = QWidget()
        video_list_layout = QVBoxLayout(self.video_list_widget)
        video_list_layout.setContentsMargins(10, 10, 10, 10)
        video_list_layout.setSpacing(10)

        # 上部分：批量进度和生成结果
        # 批量进度
        self.batch_progress_bar = ProgressBar()
        self.batch_progress_bar.setFixedHeight(15)
        self.batch_progress_label = QLabel("准备就绪")
        video_list_layout.addWidget(self.batch_progress_label)
        video_list_layout.addWidget(self.batch_progress_bar)

        # 视频列表标题
        list_title = QLabel("📋 生成结果:")
        list_title.setStyleSheet("font-size: 16px; font-weight: bold; color: #ffffff; margin-bottom: 5px;")
        video_list_layout.addWidget(list_title)

        # 视频列表滚动区域（增加高度）
        self.video_scroll = SmoothScrollArea()
        self.video_scroll_widget = QWidget()
        self.video_scroll_layout = QVBoxLayout(self.video_scroll_widget)
        self.video_scroll_layout.setSpacing(10)
        self.video_scroll.setWidget(self.video_scroll_widget)
        self.video_scroll.setWidgetResizable(True)
        self.video_scroll.setFixedHeight(450)  # 增加高度，为生成结果留更多空间
        video_list_layout.addWidget(self.video_scroll)

        # 下部分：任务视频播放区域 - 分两行显示，无间距
        # 视频播放器容器 - 简洁大气设计
        player_container = QWidget()
        player_container.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        player_layout = QVBoxLayout(player_container)
        player_layout.setContentsMargins(0, 0, 0, 0)
        player_layout.setSpacing(0)

        # 第一行：简洁的控制栏
        control_bar = QWidget()
        control_bar.setFixedHeight(50)
        control_bar.setStyleSheet("""
            QWidget {
                background-color: #2a2a2a;
                border-top: 1px solid #404040;
            }
        """)
        control_layout = QHBoxLayout(control_bar)
        control_layout.setContentsMargins(15, 8, 15, 8)

        # 刷新按钮
        self.refresh_videos_btn = PushButton("刷新")
        self.refresh_videos_btn.setFixedSize(80, 34)
        self.refresh_videos_btn.clicked.connect(self.refresh_task_videos)
        self.refresh_videos_btn.setStyleSheet("""
            QPushButton {
                background-color: #444444;
                border: none;
                border-radius: 4px;
                color: white;
                font-size: 13px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #555555;
            }
        """)
        control_layout.addWidget(self.refresh_videos_btn)

        # 打开output文件夹按钮
        self.open_output_btn = PushButton("打开文件夹")
        self.open_output_btn.setFixedSize(100, 34)
        self.open_output_btn.clicked.connect(self.open_output_folder)
        self.open_output_btn.setStyleSheet("""
            QPushButton {
                background-color: #17a2b8;
                border: none;
                border-radius: 4px;
                color: white;
                font-size: 13px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #138496;
            }
        """)
        control_layout.addWidget(self.open_output_btn)

        # 当前播放信息
        self.current_video_label = QLabel("点击下方视频缩略图使用本地播放器打开")
        self.current_video_label.setStyleSheet("""
            QLabel {
                color: #cccccc;
                font-size: 12px;
                padding: 6px 12px;
                background-color: #333333;
                border-radius: 4px;
                margin-left: 10px;
            }
        """)
        control_layout.addWidget(self.current_video_label)

        control_layout.addStretch()

        player_layout.addWidget(control_bar)

        # 第二行：任务视频缩略图区域 - 无间距
        thumbnail_container = QWidget()
        thumbnail_container.setFixedHeight(120)
        thumbnail_container.setStyleSheet("""
            QWidget {
                background-color: #1a1a1a;
                border-top: 0px;
            }
        """)
        thumbnail_layout = QHBoxLayout(thumbnail_container)
        thumbnail_layout.setContentsMargins(10, 8, 10, 8)
        thumbnail_layout.setSpacing(10)

        # 缩略图滚动区域
        self.task_thumbnail_scroll = QScrollArea()
        self.task_thumbnail_scroll.setWidgetResizable(True)
        self.task_thumbnail_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.task_thumbnail_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.task_thumbnail_scroll.setStyleSheet("""
            QScrollArea {
                background-color: transparent;
                border: none;
            }
            QScrollBar:horizontal {
                background-color: #2a2a2a;
                height: 6px;
                border-radius: 3px;
            }
            QScrollBar::handle:horizontal {
                background-color: #4a4a4a;
                border-radius: 3px;
                min-width: 20px;
            }
        """)

        self.task_thumbnails_widget = QWidget()
        self.task_thumbnails_layout = QHBoxLayout(self.task_thumbnails_widget)
        self.task_thumbnails_layout.setSpacing(10)
        self.task_thumbnails_layout.setContentsMargins(0, 0, 0, 0)
        self.task_thumbnail_scroll.setWidget(self.task_thumbnails_widget)
        thumbnail_layout.addWidget(self.task_thumbnail_scroll)

        player_layout.addWidget(thumbnail_container)

        video_list_layout.addWidget(player_container)

        self.result_tabs.addTab(self.video_list_widget, "视频列表-任务")

        # 日志Tab
        self.log_widget = QWidget()
        log_layout = QVBoxLayout(self.log_widget)
        log_layout.setContentsMargins(10, 10, 10, 10)

        # 日志文本框
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setStyleSheet("""
            QTextEdit {
                font-family: 'Consolas', 'Monaco', monospace;
                font-size: 12px;
                background-color: #1a1a1a;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                selection-background-color: #4a90e2;
            }
        """)
        log_layout.addWidget(QLabel("")) #操作日志:
        log_layout.addWidget(self.log_text)

        # 日志控制按钮
        log_controls = QHBoxLayout()
        clear_log_btn = PushButton("清空日志")  # 移除图标
        clear_log_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 16px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #dc3545;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        clear_log_btn.clicked.connect(self.clear_log)
        log_controls.addWidget(clear_log_btn)

        save_log_btn = PushButton("保存日志")  # 移除图标
        save_log_btn.setStyleSheet("""
            QPushButton {
                background-color: #333333;
                border: 1px solid #404040;
                border-radius: 6px;
                color: #ffffff;
                font-size: 16px;
                padding: 6px 12px;
            }
            QPushButton:hover {
                background-color: #3a3a3a;
                border: 1px solid #28a745;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        save_log_btn.clicked.connect(self.save_log)
        log_controls.addWidget(save_log_btn)

        log_controls.addStretch()
        log_layout.addLayout(log_controls)

        self.result_tabs.addTab(self.log_widget, "操作日志")

        layout.addWidget(self.result_tabs)

        return panel

    def on_input_type_changed(self, index):
        """输入方式改变"""
        is_url = index == 1  # 现在索引1是图片URL，索引0是本地文件上传
        self.url_widget.setVisible(is_url)
        self.upload_widget.setVisible(not is_url)

    def on_resolution_changed(self, index):
        """预设分辨率改变"""
        resolutions = {
            1: (854, 480),   # 480p - 16:9
            2: (480, 854),   # 480p - 9:16
            3: (1280, 720),  # 720p - 16:9
            4: (720, 1280)   # 720p - 9:16
        }

        if index in resolutions:
            width, height = resolutions[index]
            self.width_spin.setValue(width)
            self.height_spin.setValue(height)

    def update_frames(self, seconds):
        """根据秒数更新帧数"""
        total_frames = seconds * 16 + 1
        self.frames_label.setText(str(total_frames))

    def on_image_dropped(self, file_path, base64_data):
        """处理图片拖拽事件"""
        self.add_log(f"📁 已加载图片: {os.path.basename(file_path)}")

    def add_to_batch_tasks(self):
        """添加到批量任务列表"""
        # 获取当前设置
        image_input = self.get_current_image_input()
        prompt = self.prompt_edit.toPlainText().strip()

        if not image_input:
            QMessageBox.warning(self, "警告", "请先选择图片")
            return

        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        # 创建任务数据
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
        # 清空现有显示
        while self.task_list_layout.count():
            item = self.task_list_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        # 添加任务卡片
        for i, task in enumerate(self.batch_tasks):
            task_card = self.create_task_card(task, i)
            self.task_list_layout.addWidget(task_card)

    def create_task_card(self, task, index):
        """创建任务卡片"""
        card = CardWidget()
        card.setFixedHeight(36)
        card.setStyleSheet("""
            CardWidget {
                background-color: #2a2a2a;
                border: 1px solid #404040;
                border-radius: 8px;
                margin: 2px;
            }
            CardWidget:hover {
                border: 1px solid #4a90e2;
            }
        """)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(10, 5, 10, 5)

        # 任务信息
        info_layout = QVBoxLayout()
        name_label = QLabel(task['name'])
        name_label.setStyleSheet("font-weight: bold; color: #ffffff; font-size: 13px;")
        info_layout.addWidget(name_label)

        prompt_label = QLabel(f"提示词: {task['prompt'][:140]}...")
        prompt_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(prompt_label)

        layout.addLayout(info_layout)

        layout.addStretch()

        # 删除按钮
        delete_btn = PushButton("删除")  # 移除图标，添加文字
        delete_btn.setFixedSize(30, 30)
        delete_btn.setStyleSheet("""
            QPushButton {
                background-color: #dc3545;
                border: none;
                border-radius: 4px;
                color: white;
                font-size: 12px;
            }
            QPushButton:hover {
                background-color: #e74c3c;
            }
        """)
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
        # 清空任务状态卡片
        self.clear_task_status_cards()
        self.add_log("🗑️ 已清空所有任务")

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

        # 创建任务参数
        task_params = {
            'width': task.get('width', 480),
            'height': task.get('height', 854),
            'num_frames': task.get('num_frames', 81),
            'prompt': task.get('prompt', '')
        }

        # 创建新的状态卡片
        card = TaskStatusCard(
            task_id=task_id,
            task_name=task.get('name', f'任务 {task_id}'),
            task_params=task_params,
            parent=self
        )

        # 设置密钥源类型
        key_source = self.api_manager.get_key_source_display()
        card.set_key_source(key_source)

        # 添加到视频列表
        self.video_scroll_layout.insertWidget(0, card)  # 插入到最前面

        # 保存引用
        self.task_status_cards[task_id] = card

    def update_task_status_card(self, task_id, progress, message):
        """更新任务状态卡片"""
        if task_id in self.task_status_cards:
            card = self.task_status_cards[task_id]
            if card:
                card.update_progress(progress, message)

    def update_task_time_card(self, task_id, time_string):
        """更新任务时间显示"""
        if task_id in self.task_status_cards:
            card = self.task_status_cards[task_id]
            if card:
                card.update_time(time_string)

    def complete_task_status_card(self, task_id, success, message=""):
        """完成任务状态卡片"""
        if task_id in self.task_status_cards:
            card = self.task_status_cards[task_id]
            if card:
                card.set_completed(success, message)

    def get_current_image_input(self):
        """获取当前图片输入"""
        if self.input_type_combo.currentIndex() == 1:  # URL (现在索引1是URL)
            return self.image_url_edit.text().strip()
        else:  # 本地文件 (索引0)
            return self.drop_widget.base64_data

    def generate_single_video(self):
        """生成单个视频 - 并发方式"""
        # 检查是否正在生成任务
        if getattr(self, 'is_generating', False):
            reply = QMessageBox.question(
                self, "任务进行中", 
                "当前有任务正在执行，是否要并发执行新任务？",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No
            )
            if reply == QMessageBox.No:
                return

        # 获取输入参数
        input_type = self.input_type_combo.currentIndex()
        prompt = self.prompt_edit.toPlainText().strip()

        if input_type == 1:  # URL输入 (现在索引1是URL)
            image_input = self.image_url_edit.text().strip()
            if not image_input:
                QMessageBox.warning(self, "警告", "请输入图片URL")
                return
        else:  # 本地文件上传 (索引0)
            if not hasattr(self.drop_widget, 'base64_data') or not self.drop_widget.base64_data:
                QMessageBox.warning(self, "警告", "请先上传图片文件")
                return
            image_input = self.drop_widget.base64_data

        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        # 创建单个任务，使用时间戳确保唯一性
        timestamp = datetime.now().strftime("%H%M%S")
        task = {
            'name': f"单个任务_{timestamp}",
            'image_input': image_input,
            'image_path': self.drop_widget.current_image_path if self.input_type_combo.currentIndex() == 0 else '',
            'prompt': prompt,
            'width': self.width_spin.value(),
            'height': self.height_spin.value(),
            'num_frames': self.duration_spin.value() * 16 + 1
        }

        # 执行单个任务（并发方式）
        self.execute_concurrent_tasks([task])

    def generate_batch_videos(self):
        """生成批量视频 - 真正的并发执行"""
        if not self.batch_tasks:
            QMessageBox.warning(self, "警告", "请先添加任务到列表")
            return

        # 检查是否正在生成任务
        if getattr(self, 'is_generating', False):
            reply = QMessageBox.question(
                self, "任务进行中", 
                "当前有任务正在执行，是否要并发执行新任务？",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No
            )
            if reply == QMessageBox.No:
                return

        # 使用并发执行而非顺序执行
        self.execute_concurrent_tasks(self.batch_tasks)

    def execute_concurrent_tasks(self, tasks):
        """真正并发执行任务 - 每个任务独立线程和API密钥"""
        if not tasks:
            return

        # 修复：每次执行都新建管理器，确保清理旧状态与断开旧信号，避免无法再次执行
        if getattr(self, 'concurrent_batch_manager', None):
            try:
                self.concurrent_batch_manager.cancel_all_tasks()
                # 断开旧信号，防止重复触发
                try:
                    self.concurrent_batch_manager.task_progress.disconnect(self.update_task_progress)
                except:
                    pass
                try:
                    self.concurrent_batch_manager.task_finished.disconnect(self.on_task_finished)
                except:
                    pass
                try:
                    self.concurrent_batch_manager.task_time_updated.disconnect(self.update_task_time)
                except:
                    pass
                try:
                    self.concurrent_batch_manager.log_updated.disconnect(self.add_log)
                except:
                    pass
                try:
                    self.concurrent_batch_manager.batch_progress_updated.disconnect(self.update_batch_progress)
                except:
                    pass
                try:
                    self.concurrent_batch_manager.all_tasks_finished.disconnect(self.on_all_tasks_finished)
                except:
                    pass
            except Exception:
                pass
            self.concurrent_batch_manager = None

        # 新建管理器并连接信号
        self.concurrent_batch_manager = ConcurrentBatchManager(self.api_manager)
        self.concurrent_batch_manager.task_progress.connect(self.update_task_progress)
        self.concurrent_batch_manager.task_finished.connect(self.on_task_finished)
        self.concurrent_batch_manager.task_time_updated.connect(self.update_task_time)
        self.concurrent_batch_manager.log_updated.connect(self.add_log)
        self.concurrent_batch_manager.batch_progress_updated.connect(self.update_batch_progress)
        self.concurrent_batch_manager.all_tasks_finished.connect(self.on_all_tasks_finished)

        # 获取密钥文件路径
        key_file_path = getattr(self, 'key_file_path', None)

        # 标记生成状态，便于后续逻辑判断
        self.is_generating = True

        # 为每个任务创建状态卡片
        for i, task in enumerate(tasks):
            task_id = f"task_{i+1}"
            # 创建任务状态卡片
            self.create_task_status_card(task_id, task)

        # 开始真正并发执行（所有任务同时启动）
        self.add_log(f"🚀 开始并发执行，共{len(tasks)}个任务，WebAppID: {self.api_manager.web_app_id}")
        self.concurrent_batch_manager.execute_batch_tasks(tasks, key_file_path)

    def update_task_progress(self, progress, message, task_id):
        """更新任务进度"""
        # 更新日志
        self.add_log(f"[{task_id}] {progress}% - {message}")

        # 更新任务状态卡片
        self.update_task_status_card(task_id, progress, message)

    def on_task_finished(self, success, message, result_data, task_id):
        """单个任务完成的回调"""
        if success:
            self.add_log(f"✅ [{task_id}] 任务完成: {message}")
            # 完成任务状态卡片
            self.complete_task_status_card(task_id, True, message)
            # 创建视频结果卡片
            self.create_video_result_card(result_data, task_id)
        else:
            self.add_log(f"❌ [{task_id}] 任务失败: {message}")
            # 完成任务状态卡片（失败状态）
            self.complete_task_status_card(task_id, False, message)

    def update_task_time(self, time_string, task_id):
        """更新任务时间显示"""
        # 更新任务状态卡片时间
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
        # 移除自动弹窗，让用户可以继续执行新任务
        # QMessageBox.information(self, "完成", "所有视频生成任务已完成")

    def create_video_result_card(self, result_data, task_id):
        """创建视频结果卡片"""
        try:
            card = VideoResultCard(result_data, task_id, self)
            self.video_scroll_layout.addWidget(card)
        except Exception as e:
            self.add_log(f"❌ 创建视频结果卡片失败: {e}")

    def refresh_task_videos(self):
        """刷新任务视频列表"""
        try:
            # 清空现有缩略图
            while self.task_thumbnails_layout.count():
                item = self.task_thumbnails_layout.takeAt(0)
                if item.widget():
                    item.widget().deleteLater()

            # 扫描output目录中的视频文件
            output_dir = "output"
            if os.path.exists(output_dir):
                video_files = []
                for file_name in os.listdir(output_dir):
                    if file_name.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.flv', '.webm')):
                        file_path = os.path.join(output_dir, file_name)
                        try:
                            # 获取文件信息
                            stat_info = os.stat(file_path)
                            video_info = {
                                'name': file_name,
                                'path': file_path,
                                'size_mb': stat_info.st_size / (1024 * 1024),
                                'create_time': stat_info.st_ctime
                            }
                            video_files.append(video_info)
                        except:
                            pass

                # 按创建时间排序（最新的在前）
                video_files.sort(key=lambda x: x['create_time'], reverse=True)

                # 创建缩略图
                for video_info in video_files[:10]:  # 只显示最新的10个
                    thumbnail = self.create_video_thumbnail(video_info)
                    if thumbnail:
                        self.task_thumbnails_layout.addWidget(thumbnail)

        except Exception as e:
            self.add_log(f"⚠️ 刷新任务视频失败: {e}")

    def create_video_thumbnail(self, video_info):
        """创建视频缩略图"""
        try:
            widget = QWidget()
            widget.setFixedSize(160, 90)
            widget.setStyleSheet("""
                QWidget {
                    background-color: #2a2a2a;
                    border: 1px solid #404040;
                    border-radius: 4px;
                }
                QWidget:hover {
                    border: 1px solid #4a90e2;
                }
            """)

            layout = QVBoxLayout(widget)
            layout.setContentsMargins(5, 5, 5, 5)
            layout.setSpacing(2)

            # 缩略图（暂时用文件名代替）
            thumbnail_label = QLabel("🎬")
            thumbnail_label.setAlignment(Qt.AlignCenter)
            thumbnail_label.setStyleSheet("font-size: 24px; color: #666;")
            layout.addWidget(thumbnail_label)

            # 文件名
            name_label = QLabel(video_info['name'][:15] + "..." if len(video_info['name']) > 15 else video_info['name'])
            name_label.setStyleSheet("color: #ffffff; font-size: 10px;")
            name_label.setAlignment(Qt.AlignCenter)
            layout.addWidget(name_label)

            # 文件大小和时间
            info_label = QLabel(f"{video_info['size_mb']:.1f}MB")
            info_label.setStyleSheet("color: #888888; font-size: 8px;")
            info_label.setAlignment(Qt.AlignCenter)
            layout.addWidget(info_label)

            # 点击播放
            widget.mousePressEvent = lambda event: self.play_task_video(video_info['path'], video_info['name'])

            return widget

        except Exception as e:
            self.add_log(f"⚠️ 创建视频缩略图失败: {e}")
            return None

    def open_output_folder(self):
        """打开output文件夹"""
        try:
            import subprocess
            import platform

            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)

            # 根据操作系统打开文件夹
            system = platform.system()
            if system == "Windows":
                os.startfile(output_dir)
            elif system == "Darwin":  # macOS
                subprocess.run(["open", output_dir])
            else:  # Linux
                subprocess.run(["xdg-open", output_dir])

            self.add_log(f"📁 已打开output文件夹")

        except Exception as e:
            self.add_log(f"❌ 打开文件夹失败: {str(e)}")

    def play_task_video(self, file_path, file_name):
        """使用本地播放器播放视频"""
        try:
            if not os.path.exists(file_path):
                self.add_log(f"⚠️ 视频文件不存在: {file_path}")
                return

            # 直接使用系统默认播放器打开视频文件
            from PyQt5.QtGui import QDesktopServices
            from PyQt5.QtCore import QUrl
            QDesktopServices.openUrl(QUrl.fromLocalFile(file_path))

            # 更新状态显示
            self.current_video_label.setText(f"已使用本地播放器打开: {file_name}")
            self.add_log(f"🎬 使用本地播放器打开视频: {file_name}")

        except Exception as e:
            self.add_log(f"❌ 打开视频失败: {str(e)}")

    def create_local_video_item(self, video_info):
        """创建本地视频列表项"""
        item = QFrame()
        item.setStyleSheet("""
            QFrame {
                background-color: #2a2a2a;
                border: 1px solid #404040;
                border-radius: 4px;
                margin: 1px;
                padding: 5px;
            }
            QFrame:hover {
                background-color: #333333;
                border: 1px solid #4a90e2;
            }
        """)

        layout = QVBoxLayout(item)
        layout.setSpacing(2)
        layout.setContentsMargins(5, 3, 5, 3)

        # 文件名
        name_label = QLabel(video_info['name'][:30] + "..." if len(video_info['name']) > 30 else video_info['name'])
        name_label.setStyleSheet("color: #ffffff; font-size: 12px; font-weight: bold;")
        layout.addWidget(name_label)

        # 文件信息
        info_layout = QHBoxLayout()

        size_label = QLabel(f"{video_info['size_mb']:.1f}MB")
        size_label.setStyleSheet("color: #cccccc; font-size: 10px;")
        info_layout.addWidget(size_label)

        info_layout.addStretch()

        time_label = QLabel(video_info['mtime'])
        time_label.setStyleSheet("color: #888888; font-size: 10px;")
        info_layout.addWidget(time_label)

        layout.addLayout(info_layout)

        # 双击播放
        item.mouseDoubleClickEvent = lambda event: self.play_local_video(video_info['path'], video_info['name'])
        item.setCursor(Qt.PointingHandCursor)

        # 右键菜单
        item.setContextMenuPolicy(3)  # Qt.CustomContextMenu
        item.customContextMenuRequested.connect(lambda pos: self.show_video_context_menu(pos, video_info))

        return item

    def show_video_context_menu(self, pos, video_info):
        """显示视频右键菜单"""
        from PyQt5.QtWidgets import QMenu
        menu = QMenu()

        play_action = menu.addAction("▶️ 播放")
        play_action.triggered.connect(lambda: self.play_local_video(video_info['path'], video_info['name']))

        menu.addSeparator()

        open_folder_action = menu.addAction("📁 在文件夹中显示")
        open_folder_action.triggered.connect(lambda: self.open_in_folder(video_info['path']))

        delete_action = menu.addAction("🗑️ 删除")
        delete_action.triggered.connect(lambda: self.delete_video_file(video_info['path'], video_info['name']))

        menu.exec_(self.local_videos_widget.mapToGlobal(pos))

    def open_in_folder(self, file_path):
        """在文件夹中显示文件"""
        import platform
        import subprocess

        try:
            if platform.system() == "Windows":
                subprocess.Popen(['explorer', '/select,', file_path])
            elif platform.system() == "Darwin":  # macOS
                subprocess.Popen(['open', '-R', file_path])
            else:  # Linux
                subprocess.Popen(['xdg-open', os.path.dirname(file_path)])
        except Exception as e:
            self.add_log(f"⚠️ 无法打开文件夹: {str(e)}")

    def delete_video_file(self, file_path, file_name):
        """删除视频文件"""
        reply = QMessageBox.question(
            self, "确认删除",
            f"确定要删除视频文件 '{file_name}' 吗？\n\n此操作不可撤销。",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            try:
                os.remove(file_path)
                self.add_log(f"🗑️ 已删除视频文件: {file_name}")
                self.refresh_local_videos()  # 刷新列表
            except Exception as e:
                self.add_log(f"❌ 删除失败: {str(e)}")
                QMessageBox.warning(self, "错误", f"删除失败: {str(e)}")

    def play_local_video(self, file_path, file_name):
        """播放本地视频文件"""
        try:
            # 切换到视频列表Tab
            self.result_tabs.setCurrentIndex(0)

            # 设置当前播放的视频
            self.current_video_path = file_path
            self.current_video_label.setText(f"正在播放: {file_name}")

            # 启用播放控制按钮
            self.play_btn.setEnabled(True)
            self.stop_btn.setEnabled(True)

            # 加载视频到播放器
            from PyQt5.QtCore import QUrl
            self.media_player.setMedia(QMediaContent(QUrl.fromLocalFile(file_path)))
            self.media_player.play()

            # 更新播放按钮文本
            self.play_btn.setText("⏸️ 暂停")

            self.add_log(f"🎬 正在播放本地视频: {file_name}")

        except Exception as e:
            self.add_log(f"⚠️ 播放本地视频失败: {str(e)}")
            QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")

    def load_settings(self):
        """加载设置 - 使用配置管理器"""
        try:
            # 加载所有设置
            video_params = self.settings_manager.get_video_params()
            api_settings = self.settings_manager.get_api_settings()

            # 应用视频参数到控件
            if hasattr(self, 'width_spin'):
                self.width_spin.setValue(video_params.get('width', 480))
            if hasattr(self, 'height_spin'):
                self.height_spin.setValue(video_params.get('height', 854))
            if hasattr(self, 'duration_spin'):
                self.duration_spin.setValue(video_params.get('duration', 5))
            if hasattr(self, 'frames_label'):
                self.frames_label.setText(str(video_params.get('num_frames', 81)))

            # 加载API密钥设置
            key_file = api_settings.get('key_file', '')
            if key_file and os.path.exists(key_file):
                self.api_manager.load_keys_from_file(key_file)
                self.api_manager.set_key_source("file")  # 设置为文件密钥
                self.key_file_path = key_file
            else:
                # 检查是否有系统变量密钥可用
                env_key = os.getenv('SiliconCloud_API_KEY')
                if env_key:
                    self.api_manager.set_key_source("env")  # 设置为系统变量
                else:
                    self.api_manager.set_key_source("file")  # 默认文件密钥

            self.update_key_status()

            # 初始化参数显示
            self.update_current_params_display()

            # 初始化任务视频列表
            self.refresh_task_videos()

            self.add_log(f"✅ 已加载视频设置配置")

        except Exception as e:
            self.add_log(f"❌ 加载设置失败: {e}")

            # 即使加载失败也要初始化参数显示
            try:
                self.update_current_params_display()
            except AttributeError as e:
                self.add_log(f"参数显示初始化失败: {str(e)}")
                # 手动设置默认参数显示
                if hasattr(self, 'current_params_top_label'):
                    self.current_params_top_label.setText("当前: 480×854, 5秒, 81帧")

    def save_settings(self):
        """保存设置 - 使用配置管理器"""
        try:
            # 获取当前参数值
            if hasattr(self, 'width_spin') and self.width_spin:
                width = self.width_spin.value()
            else:
                width = 480

            if hasattr(self, 'height_spin') and self.height_spin:
                height = self.height_spin.value()
            else:
                height = 854

            if hasattr(self, 'duration_spin') and self.duration_spin:
                duration = self.duration_spin.value()
            else:
                duration = 5

            # 保存视频参数
            success1 = self.settings_manager.set_video_params(width, height, duration)

            # 保存API密钥文件路径
            key_file_path = getattr(self, 'key_file_path', '')
            if key_file_path:
                success2 = self.settings_manager.set_api_settings(key_file_path, self.api_manager.web_app_id)
            else:
                success2 = True  # 没有密钥文件也算成功

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

            # 在主线程中更新UI
            if hasattr(self, 'log_text'):
                self.log_text.append(log_entry)
                # 滚动到底部
                scrollbar = self.log_text.verticalScrollBar()
                scrollbar.setValue(scrollbar.maximum())

            # 同时输出到控制台
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

# 视频参数设置对话框
class VideoSettingsDialog(QDialog):
    """视频参数设置对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("视频参数设置")
        self.setMinimumSize(500, 400)

        # 设置深色主题样式
        self.setStyleSheet("""
            QDialog {
                background-color: #1e1e1e;
                color: #ffffff;
            }
        """)

        self.init_ui()
        self.load_current_settings()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)
        layout.setContentsMargins(25, 25, 25, 25)

        # 标题
        title_label = QLabel("视频参数配置")
        title_label.setStyleSheet("font-size: 18px; font-weight: bold; color: #ffffff; margin-bottom: 10px;")
        layout.addWidget(title_label)

        # 预设分辨率
        resolution_group = QGroupBox("预设分辨率")
        resolution_group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        resolution_layout = QVBoxLayout(resolution_group)

        self.resolution_combo = ComboBox()
        self.resolution_combo.addItems([
            "自定义",
            "480p - 16:9 (854×480)",
            "480p - 9:16 (480×854)",
            "720p - 16:9 (1280×720)",
            "720p - 9:16 (720×1280)",
            "1080p - 16:9 (1920×1080)",
            "1080p - 9:16 (1080×1920)"
        ])
        self.resolution_combo.setFixedHeight(36)
        self.resolution_combo.setStyleSheet("""
            QComboBox {
                background-color: #000000;
                border: 2px solid #404040;
                border-radius: 8px;
                padding: 8px 12px;
                font-size: 14px;
                color: #ffffff;
            }
            QComboBox:focus {
                border: 2px solid #4a90e2;
            }
            QComboBox:hover {
                border: 2px solid #5a5a5a;
                background-color: #1a1a1a;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
                background-color: #000000;
                border-top-right-radius: 6px;
                border-bottom-right-radius: 6px;
            }
            QComboBox::down-arrow {
                image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEFSURBVCiRldKxSgNBEMbxH0QZ0CuEF2CiEwJCgKESFuwBLhAT8AFyEO7wELsAC7AQX4CNxgU0cG6+dCZmZn8ZzYwXJJW8k8/fnOeOA8gw/r9fSEECGNFIAiCRZSROJIKJVmQygJMFQYGIFFsCgnhBaiBiOIEFEZgYhBRRGYGGYBFJp9uQRZZYcS1Lb5EA/ghggCVBJEARRyESOhKhszEMDQDdICB9ALRxZUeCcOPPMi5F+T8SX6FMaVvUIFxAIsgYgsI6IEHEhgUYEagIYRGAqPwiwAEYQmAqBQbY4QhBiBoZfn+/fXfjPMO4KdYvKEnKcTb1ncNcIrr8AyVcOlH9Zc1wAAAAASUVORK5CYII=);
                width: 12px;
                height: 12px;
            }
            QComboBox QAbstractItemView {
                background-color: #000000;
                border: 1px solid #404040;
                selection-background-color: #4a90e2;
                color: #ffffff;
                selection-color: #ffffff;
                padding: 4px 0px;
            }
            QComboBox QAbstractItemView::item {
                padding: 8px 12px;
                border-bottom: 1px solid #404040;
                background-color: #000000;
            }
            QComboBox QAbstractItemView::item:selected {
                background-color: #4a90e2;
                color: #ffffff;
            }
            QComboBox QAbstractItemView::item:hover {
                background-color: #2a2a2a;
            }
        """)
        self.resolution_combo.currentIndexChanged.connect(self.on_resolution_changed)
        # 选择预设标签
        preset_label = QLabel("选择预设:")
        preset_label.setStyleSheet("""
            QLabel {
                color: #ffffff;
                font-size: 14px;
                font-weight: 500;
                margin-bottom: 5px;
            }
        """)
        resolution_layout.addWidget(preset_label)
        resolution_layout.addWidget(self.resolution_combo)
        layout.addWidget(resolution_group)

        # 自定义尺寸
        size_group = QGroupBox("自定义尺寸")
        size_group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        size_layout = QGridLayout(size_group)

        # 宽度
        width_label = QLabel("宽度 (px):")
        width_label.setStyleSheet("color: #ffffff; font-size: 14px;")
        size_layout.addWidget(width_label, 0, 0)
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 4096)
        self.width_spin.setSingleStep(64)
        self.width_spin.setValue(480)
        self.width_spin.setFixedHeight(36)
        self.width_spin.setStyleSheet("""
            QSpinBox {
                background-color: #1a1a1a;
                border: 2px solid #404040;
                border-radius: 8px;
                padding: 8px;
                font-size: 14px;
                color: #ffffff;
            }
            QSpinBox:focus {
                border: 2px solid #4a90e2;
            }
            QSpinBox:hover {
                border: 2px solid #5a5a5a;
            }
        """)
        size_layout.addWidget(self.width_spin, 0, 1)

        # 互换按钮
        self.swap_btn = PushButton("🔄")
        self.swap_btn.setFixedSize(40, 36)
        self.swap_btn.clicked.connect(self.swap_dimensions)
        self.swap_btn.setStyleSheet("""
            QPushButton {
                background-color: #3a3a3a;
                border: 1px solid #404040;
                border-radius: 8px;
                font-size: 16px;
                color: #ffffff;
            }
            QPushButton:hover {
                background-color: #4a4a4a;
                border: 1px solid #5a5a5a;
            }
            QPushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        size_layout.addWidget(self.swap_btn, 0, 2)

        # 高度
        height_label = QLabel("高度 (px):")
        height_label.setStyleSheet("color: #ffffff; font-size: 14px;")
        size_layout.addWidget(height_label, 1, 0)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 4096)
        self.height_spin.setSingleStep(64)
        self.height_spin.setValue(854)
        self.height_spin.setFixedHeight(36)
        self.height_spin.setStyleSheet("""
            QSpinBox {
                background-color: #1a1a1a;
                border: 2px solid #404040;
                border-radius: 8px;
                padding: 8px;
                font-size: 14px;
                color: #ffffff;
            }
            QSpinBox:focus {
                border: 2px solid #4a90e2;
            }
            QSpinBox:hover {
                border: 2px solid #5a5a5a;
            }
        """)
        size_layout.addWidget(self.height_spin, 1, 1)

        layout.addWidget(size_group)

        # 视频时长
        duration_group = QGroupBox("视频时长")
        duration_group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        duration_layout = QHBoxLayout(duration_group)

        duration_label = QLabel("时长(秒):")
        duration_label.setStyleSheet("color: #ffffff; font-size: 14px;")
        duration_layout.addWidget(duration_label)
        self.duration_spin = QSpinBox()
        self.duration_spin.setRange(1, 30)
        self.duration_spin.setValue(5)
        self.duration_spin.setSingleStep(1)
        self.duration_spin.setFixedHeight(36)
        self.duration_spin.setStyleSheet("""
            QSpinBox {
                background-color: #1a1a1a;
                border: 2px solid #404040;
                border-radius: 8px;
                padding: 8px;
                font-size: 14px;
                color: #ffffff;
            }
            QSpinBox:focus {
                border: 2px solid #4a90e2;
            }
            QSpinBox:hover {
                border: 2px solid #5a5a5a;
            }
        """)
        self.duration_spin.valueChanged.connect(lambda value: self.update_frames(value))
        duration_layout.addWidget(self.duration_spin)

        layout.addWidget(duration_group)

        # 帧数信息
        info_group = QGroupBox("帧数信息")
        info_group.setStyleSheet("""
            QGroupBox {
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 8px;
                margin-top: 8px;
                padding-top: 8px;
                background-color: #2a2a2a;
                color: #ffffff;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px 0 8px;
                color: #ffffff;
                font-size: 14px;
            }
        """)
        info_layout = QVBoxLayout(info_group)

        self.frames_label = QLabel("总帧数: 81")
        self.frames_label.setStyleSheet("""
            QLabel {
                font-weight: bold;
                color: #4a90e2;
                font-size: 16px;
                padding: 10px;
                background-color: #1a3a4e;
                border-radius: 8px;
                border: 1px solid #4a90e2;
            }
        """)
        info_layout.addWidget(self.frames_label)

        frames_note = QLabel("📝 注：16帧 = 1秒，总帧数 = (时长 × 16) + 1")
        frames_note.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(frames_note)

        layout.addWidget(info_group)

        # 按钮区域
        button_layout = QHBoxLayout()

        self.reset_btn = PushButton("重置默认")
        self.reset_btn.clicked.connect(self.reset_defaults)
        self.reset_btn.setStyleSheet("""
            QPushButton {
                background-color: #6c757d;
                color: white;
                border: none;
                border-radius: 8px;
                padding: 10px 20px;
                font-size: 14px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #5a6268;
            }
        """)
        button_layout.addWidget(self.reset_btn)

        button_layout.addStretch()

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        cancel_btn.setStyleSheet("""
            QPushButton {
                background-color: #dc3545;
                color: white;
                border: none;
                border-radius: 8px;
                padding: 10px 20px;
                font-size: 14px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #c82333;
            }
        """)
        button_layout.addWidget(cancel_btn)

        save_btn = PrimaryPushButton("确定")
        save_btn.clicked.connect(self.accept_settings)
        save_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                color: white;
                border: none;
                border-radius: 8px;
                padding: 10px 20px;
                font-size: 14px;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #218838;
            }
        """)
        button_layout.addWidget(save_btn)

        layout.addLayout(button_layout)

    def load_current_settings(self):
        """从配置文件加载当前设置，优先使用JSON配置"""
        try:
            # 优先从配置文件加载
            if hasattr(self.parent(), 'settings_manager'):
                video_params = self.parent().settings_manager.get_video_params()

                self.width_spin.setValue(video_params.get('width', 480))
                self.height_spin.setValue(video_params.get('height', 854))
                self.duration_spin.setValue(video_params.get('duration', 5))
                self.update_frames(video_params.get('duration', 5))

                # 更新父控件的值（如果存在）
                if hasattr(self.parent(), 'width_spin'):
                    self.parent().width_spin.setValue(video_params.get('width', 480))
                if hasattr(self.parent(), 'height_spin'):
                    self.parent().height_spin.setValue(video_params.get('height', 854))
                if hasattr(self.parent(), 'duration_spin'):
                    self.parent().duration_spin.setValue(video_params.get('duration', 5))

            # 如果没有配置管理器，则从父控件加载
            elif hasattr(self.parent(), 'width_spin') and hasattr(self.parent(), 'height_spin'):
                self.width_spin.setValue(self.parent().width_spin.value())
                self.height_spin.setValue(self.parent().height_spin.value())
                self.duration_spin.setValue(self.parent().duration_spin.value())
                self.update_frames(self.duration_spin.value())

        except Exception as e:
            print(f"加载视频设置失败: {e}")
            # 使用默认值
            self.width_spin.setValue(480)
            self.height_spin.setValue(854)
            self.duration_spin.setValue(5)
            self.update_frames(5)

    def on_resolution_changed(self, index):
        """预设分辨率改变"""
        resolutions = {
            1: (854, 480),   # 480p - 16:9
            2: (480, 854),   # 480p - 9:16
            3: (1280, 720),  # 720p - 16:9
            4: (720, 1280),  # 720p - 9:16
            5: (1920, 1080), # 1080p - 16:9
            6: (1080, 1920)  # 1080p - 9:16
        }

        if index in resolutions:
            width, height = resolutions[index]
            self.width_spin.setValue(width)
            self.height_spin.setValue(height)

    def update_frames(self, seconds=None):
        """根据秒数更新帧数"""
        # 修复：统一为 seconds 可选；同时更新对话框显示，避免重复定义导致功能丢失
        if seconds is None:
            seconds = self.duration_spin.value()

        total_frames = seconds * 16 + 1
        self.frames_label.setText(str(total_frames))

        # 同步更新设置对话框中的帧数显示（如果存在）
        if hasattr(self, 'video_settings_dialog') and self.video_settings_dialog:
            if hasattr(self.video_settings_dialog, 'frames_label'):
                self.video_settings_dialog.frames_label.setText(f"总帧数: {total_frames}")

    def swap_dimensions(self):
        """互换宽度和高度"""
        width = self.width_spin.value()
        height = self.height_spin.value()
        self.width_spin.setValue(height)
        self.height_spin.setValue(width)

    def reset_defaults(self):
        """重置为默认值"""
        self.width_spin.setValue(480)
        self.height_spin.setValue(854)
        self.duration_spin.setValue(5)
        self.resolution_combo.setCurrentIndex(0)  # 自定义
        self.update_frames(5)

    def accept_settings(self):
        """应用设置并关闭"""
        try:
            if hasattr(self.parent(), 'width_spin') and hasattr(self.parent(), 'height_spin'):
                # 更新父控件的参数值
                self.parent().width_spin.setValue(self.width_spin.value())
                self.parent().height_spin.setValue(self.height_spin.value())
                self.parent().duration_spin.setValue(self.duration_spin.value())
                # 传递当前时长参数给update_frames方法
                self.parent().update_frames(self.duration_spin.value())

                # 更新参数显示
                self.parent().update_current_params_display()

                # 直接保存到JSON配置文件
                if hasattr(self.parent(), 'settings_manager'):
                    width = self.width_spin.value()
                    height = self.height_spin.value()
                    duration = self.duration_spin.value()
                    success = self.parent().settings_manager.set_video_params(width, height, duration)
                    if success:
                        self.parent().add_log(f"✅ 视频参数设置已保存到JSON配置文件")
                    else:
                        self.parent().add_log(f"⚠️ 视频参数保存到JSON文件失败")

                # 显示成功提示
                self.parent().add_log(f"✅ 视频参数设置已应用")
        except Exception as e:
            print(f"应用设置时出错: {str(e)}")
            if hasattr(self.parent(), 'add_log'):
                self.parent().add_log(f"❌ 应用设置失败: {str(e)}")
        self.accept()

# API设置对话框
class APISettingsDialog(QDialog):
    """API设置对话框"""

    def __init__(self, api_manager, parent=None):
        super().__init__(parent)
        self.api_manager = api_manager
        self.setWindowTitle("API密钥设置")
        self.setMinimumSize(500, 400)
        self.init_ui()
        self.load_current_settings()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # Web App ID设置
        webapp_group = QGroupBox("Web App ID")
        webapp_layout = QVBoxLayout(webapp_group)

        self.webapp_id_spin = QSpinBox()
        self.webapp_id_spin.setRange(1, 99999)
        self.webapp_id_spin.setValue(self.api_manager.web_app_id)
        webapp_layout.addWidget(QLabel("Web App ID:"))
        webapp_layout.addWidget(self.webapp_id_spin)

        layout.addWidget(webapp_group)

        # API密钥源选择
        key_group = QGroupBox("API密钥设置")
        key_layout = QVBoxLayout(key_group)

        # 密钥源选择
        source_layout = QHBoxLayout()
        source_label = QLabel("密钥来源：")
        source_label.setStyleSheet("font-weight: bold;")
        source_layout.addWidget(source_label)

        from PyQt5.QtWidgets import QRadioButton, QButtonGroup
        self.key_source_group = QButtonGroup(self)

        self.file_radio = QRadioButton("文件密钥")
        self.file_radio.setChecked(True)  # 默认选择文件密钥
        self.file_radio.setStyleSheet("QRadioButton { color: #ffffff; }")
        self.key_source_group.addButton(self.file_radio, 0)
        source_layout.addWidget(self.file_radio)

        self.env_radio = QRadioButton("系统变量 (SiliconCloud_API_KEY)")
        self.env_radio.setStyleSheet("QRadioButton { color: #ffffff; }")
        self.key_source_group.addButton(self.env_radio, 1)
        source_layout.addWidget(self.env_radio)

        # 连接信号
        self.file_radio.toggled.connect(self.on_key_source_changed)
        self.env_radio.toggled.connect(self.on_key_source_changed)

        key_layout.addLayout(source_layout)

        # 分隔线
        line = QFrame()
        line.setFrameShape(QFrame.HLine)
        line.setStyleSheet("color: #444444;")
        key_layout.addWidget(line)

        # 文件密钥设置
        file_layout = QHBoxLayout()
        self.key_file_edit = LineEdit()
        self.key_file_edit.setPlaceholderText("输入密钥文件路径...")
        self.key_file_edit.setText(getattr(self.parent(), 'key_file_path', ''))
        file_layout.addWidget(self.key_file_edit)

        self.browse_btn = PushButton("浏览")  # 移除图标
        self.browse_btn.clicked.connect(self.browse_key_file)
        file_layout.addWidget(self.browse_btn)

        key_layout.addLayout(file_layout)

        # 系统变量状态显示
        self.env_status_label = QLabel("系统变量状态：检查中...")
        self.env_status_label.setStyleSheet("color: #cccccc; font-size: 12px; padding: 5px;")
        key_layout.addWidget(self.env_status_label)

        # 更新系统变量状态
        self.update_env_status()

        # 密钥说明
        info_label = QLabel("密钥文件格式：每行一个API密钥，建议至少18个密钥用于批量处理")
        info_label.setStyleSheet("color: #666; font-size: 12px; padding: 5px;")
        key_layout.addWidget(info_label)

        # 测试按钮
        self.test_btn = PushButton("测试密钥")  # 移除图标
        self.test_btn.clicked.connect(self.test_keys)
        key_layout.addWidget(self.test_btn)

        layout.addWidget(key_group)

        # 状态显示
        self.status_label = QLabel("准备就绪")
        self.status_label.setStyleSheet("padding: 10px; background: #333333; border-radius: 4px;")
        layout.addWidget(self.status_label)

        # 按钮
        button_layout = QHBoxLayout()
        save_btn = PrimaryPushButton("保存")
        save_btn.clicked.connect(self.save_settings)
        button_layout.addWidget(save_btn)

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)

        layout.addLayout(button_layout)

    def on_key_source_changed(self):
        """密钥源切换处理"""
        is_file = self.file_radio.isChecked()

        if is_file:
            # 选择文件密钥
            self.key_file_edit.setEnabled(True)
            self.browse_btn.setEnabled(True)
            self.test_btn.setEnabled(True)
        else:
            # 选择系统变量
            self.key_file_edit.setEnabled(False)
            self.browse_btn.setEnabled(False)
            self.test_btn.setEnabled(False)

        self.update_env_status()

    def update_env_status(self):
        """更新系统变量状态显示"""
        env_key = os.getenv('SiliconCloud_API_KEY')
        if self.env_radio.isChecked():
            if env_key:
                masked_key = f"{env_key[:10]}...{env_key[-5:]}"
                self.env_status_label.setText(f"✅ 系统变量已设置: {masked_key}")
                self.env_status_label.setStyleSheet("color: #4CAF50; font-size: 12px; padding: 5px;")
            else:
                self.env_status_label.setText("❌ 系统变量 SiliconCloud_API_KEY 未设置")
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
        file_path = self.key_file_edit.text().strip()
        if not file_path or not os.path.exists(file_path):
            QMessageBox.warning(self, "警告", "请选择有效的密钥文件")
            return

        if self.api_manager.load_keys_from_file(file_path):
            count = len(self.api_manager.api_keys)
            self.status_label.setText(f"✅ 成功加载 {count} 个API密钥")
            self.status_label.setStyleSheet("padding: 10px; background: #e8f5e8; border-radius: 4px; color: #4CAF50;")
        else:
            self.status_label.setText("❌ 密钥文件加载失败")
            self.status_label.setStyleSheet("padding: 10px; background: #ffebee; border-radius: 4px; color: #f44336;")

    def save_settings(self):
        """保存设置"""
        # 保存WebApp ID
        self.api_manager.web_app_id = self.webapp_id_spin.value()

        # 保存密钥源选择
        is_file_source = self.file_radio.isChecked()
        if is_file_source:
            self.api_manager.set_key_source("file")

            file_path = self.key_file_edit.text().strip()
            if file_path and os.path.exists(file_path):
                if self.api_manager.load_keys_from_file(file_path):
                    self.parent().key_file_path = file_path

                    # 保存API设置到JSON配置文件
                    if hasattr(self.parent(), 'settings_manager'):
                        self.parent().settings_manager.set_api_settings(file_path, self.webapp_id_spin.value())
                        if hasattr(self.parent(), 'add_log'):
                            self.parent().add_log(f"✅ API密钥设置已保存 (文件密钥)")

                    self.accept()
                else:
                    QMessageBox.warning(self, "警告", "密钥文件加载失败")
            else:
                QMessageBox.warning(self, "警告", "请选择有效的密钥文件")
        else:
            # 选择系统变量
            self.api_manager.set_key_source("env")
            env_key = os.getenv('SiliconCloud_API_KEY')
            if not env_key:
                QMessageBox.warning(self, "警告", "系统变量 SiliconCloud_API_KEY 未设置")
                return

            # 保存WebApp ID设置（使用空字符串表示系统变量）
            if hasattr(self.parent(), 'settings_manager'):
                self.parent().settings_manager.set_api_settings("", self.webapp_id_spin.value())
                if hasattr(self.parent(), 'add_log'):
                    self.parent().add_log(f"✅ API密钥设置已保存 (系统变量)")

            self.accept()

    def load_current_settings(self):
        """从配置文件加载当前设置"""
        try:
            if hasattr(self.parent(), 'settings_manager'):
                api_settings = self.parent().settings_manager.get_api_settings()

                # 加载密钥文件路径
                key_file = api_settings.get('key_file', '')
                if key_file:
                    self.key_file_edit.setText(key_file)

                # 加载WebApp ID
                webapp_id = api_settings.get('web_app_id', 41082)
                self.webapp_id_spin.setValue(webapp_id)
                self.api_manager.web_app_id = webapp_id
        except Exception as e:
            print(f"加载API设置失败: {e}")

# 视频下载工作线程
class VideoDownloadWorker(QThread):
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
            import os
            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)

            local_path = os.path.join(output_dir, self.filename)

            self.progress_updated.emit(10, "开始下载视频...")
            self.log_updated.emit(f"🎬 开始下载视频: {self.filename}")
            self.log_updated.emit(f"📥 远程URL: {self.video_url}")

            # 使用requests下载文件
            response = requests.get(self.video_url, stream=True, timeout=300)
            response.raise_for_status()

            total_size = int(response.headers.get('content-length', 0))
            downloaded_size = 0

            self.progress_updated.emit(20, f"准备写入本地文件: {local_path}")

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

            self.progress_updated.emit(95, "下载完成，验证文件...")

            # 验证文件是否下载成功
            if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                file_size = os.path.getsize(local_path)
                self.progress_updated.emit(100, "下载完成！")
                self.log_updated.emit(f"✅ 视频下载完成: {local_path} ({file_size} 字节)")
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

# 任务状态卡片
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
        self.init_ui()

    def init_ui(self):
        """初始化UI"""
        self.setFixedHeight(120)  # 设置固定高度
        self.setStyleSheet("""
            CardWidget {
                background-color: #2a2a2a;
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
            # 限制提示词长度，避免显示过长
            if len(prompt) > 50:
                prompt_display = prompt[:47] + "..."
            else:
                prompt_display = prompt

            self.prompt_label = CaptionLabel(prompt_display)
            self.prompt_label.setStyleSheet("color: #aaaaaa; font-size: 11px;")
            self.prompt_label.setWordWrap(False)
            layout.addWidget(self.prompt_label)

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
        self.status = message
        self.progress_bar.setValue(progress)

        # 根据进度更新状态标签颜色
        if progress >= 100:
            self.status_label.setStyleSheet("color: #28a745; font-size: 11px; padding: 4px 8px; background: #e8f5e8; border-radius: 4px;")
        elif progress >= 50:
            self.status_label.setStyleSheet("color: #ffc107; font-size: 11px; padding: 4px 8px; background: #fff3cd; border-radius: 4px;")
        else:
            self.status_label.setStyleSheet("color: #17a2b8; font-size: 11px; padding: 4px 8px; background: #e6f7ff; border-radius: 4px;")

    def update_time(self, time_string):
        """更新时间显示"""
        self.time_string = time_string
        self.time_label.setText(time_string)

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
        if success:
            self.progress = 100
            self.status = "已完成" if not message else message
            self.progress_bar.setValue(100)
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
            self.status = f"失败: {message}" if message else "生成失败"
            self.status_label.setStyleSheet("color: #dc3545; font-size: 11px; padding: 4px 8px; background: #ffebee; border-radius: 4px;")
            self.setStyleSheet("""
                CardWidget {
                    background-color: #3a2a2a;
                    border: 1px solid #dc3545;
                    border-radius: 8px;
                    margin: 2px;
                }
            """)

# 视频结果卡片
class VideoResultCard(QWidget):
    """视频结果展示卡片（支持进度显示）"""

    def __init__(self, video_data, parent=None):
        super().__init__(parent)
        self.video_data = video_data
        self.start_time = None
        self.progress_timer = None
        self.task_id = None  # 用于标识任务
        self.local_video_path = None  # 本地视频文件路径
        self.download_worker = None  # 下载工作线程
        self.init_ui()

    def init_ui(self):
        # 去掉底色背景，使用透明背景
        self.setStyleSheet("QWidget { background-color: transparent; }")

        layout = QVBoxLayout(self)
        layout.setSpacing(6)  # 减小间距
        layout.setContentsMargins(10, 8, 10, 8)  # 减小边距

        # 标题和状态行
        header_layout = QHBoxLayout()

        # 标题
        title = self.video_data.get('task_name', '未命名视频')
        if 'timestamp' in self.video_data:
            try:
                dt = datetime.fromisoformat(self.video_data['timestamp'])
                title += f" ({dt.strftime('%H:%M:%S')})"
            except:
                pass

        self.title_label = QLabel(title)
        self.title_label.setStyleSheet("font-weight: bold; color: #ffffff; font-size: 14px;")
        header_layout.addWidget(self.title_label)

        header_layout.addStretch()

        # 状态显示
        self.status_label = QLabel("等待开始...")
        self.status_label.setStyleSheet("color: #4a90e2; font-size: 12px; font-weight: bold;")
        header_layout.addWidget(self.status_label)

        layout.addLayout(header_layout)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(12)  # 减小高度
        self.progress_bar.setValue(0)
        layout.addWidget(self.progress_bar)

        # 进度文字显示（百分比和时间）
        self.progress_info_label = QLabel("等待开始... 00:00:00")
        self.progress_info_label.setStyleSheet("color: #cccccc; font-size: 11px;")
        layout.addWidget(self.progress_info_label)

        # 视频信息 - 单行显示，更紧凑
        info_layout = QHBoxLayout()

        info_text = f"尺寸: {self.video_data.get('width', 'N/A')}×{self.video_data.get('height', 'N/A')}"
        self.info_label = QLabel(info_text)
        self.info_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(self.info_label)

        info_layout.addSpacing(15)

        frames_text = f"帧数: {self.video_data.get('num_frames', 'N/A')}"
        self.frames_label = QLabel(frames_text)
        self.frames_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(self.frames_label)

        info_layout.addStretch()
        layout.addLayout(info_layout)

        # 提示词预览 - 去掉多余背景色
        prompt = self.video_data.get('prompt', '')
        if prompt:
            prompt_preview = prompt[:300] + "..." if len(prompt) > 300 else prompt  # 增加字符数
            self.prompt_label = QLabel(f"提示词: {prompt_preview}")
            self.prompt_label.setStyleSheet("color: #888888; font-size: 12px; margin: 2px 0;")
            self.prompt_label.setWordWrap(True)
            layout.addWidget(self.prompt_label)

        # 视频URL显示（初始隐藏）
        self.url_container = QWidget()
        self.url_layout = QHBoxLayout(self.url_container)
        self.url_layout.setContentsMargins(0, 0, 0, 0)

        url_label = QLabel("视频URL:")
        url_label.setStyleSheet("color: #ffffff; font-size: 12px; font-weight: bold;")
        self.url_layout.addWidget(url_label)

        self.url_edit = LineEdit()
        self.url_edit.setReadOnly(True)
        self.url_edit.setStyleSheet("""
            LineEdit {
                font-size: 11px;
                padding: 4px;
                background-color: #333333;
                border: 1px solid #404040;
                color: #ffffff;
            }
        """)
        self.url_layout.addWidget(self.url_edit)

        self.url_container.hide()  # 初始隐藏
        layout.addWidget(self.url_container)

        # URL显示和按钮区域
        url_button_layout = QHBoxLayout()
        
        self.copy_url_btn = PushButton("复制URL")
        self.copy_url_btn.clicked.connect(self.copy_url)
        self.copy_url_btn.hide()  # 初始隐藏
        url_button_layout.addWidget(self.copy_url_btn)
        
        # URL文本展示区域 - 在复制URL按钮右侧
        self.url_text_label = QLabel()
        self.url_text_label.setWordWrap(True)
        self.url_text_label.setMaximumWidth(400)  # 设置最大宽度
        self.url_text_label.setMinimumHeight(60)  # 设置最小高度
        self.url_text_label.setAlignment(Qt.AlignTop | Qt.AlignLeft)  # 左上对齐
        self.url_text_label.setStyleSheet("""
            QLabel {
                background-color: #2a2a2a;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 6px 8px;
                color: #e0e0e0;
                font-size: 11px;
                font-family: 'Consolas', 'Monaco', monospace;
            }
        """)
        self.url_text_label.hide()  # 初始隐藏
        url_button_layout.addWidget(self.url_text_label)

        self.view_btn = PushButton("播放")
        self.view_btn.clicked.connect(self.view_video)
        self.view_btn.hide()  # 初始隐藏
        url_button_layout.addWidget(self.view_btn)

        self.download_btn = PushButton("下载")
        self.download_btn.clicked.connect(self.download_video)
        self.download_btn.hide()  # 初始隐藏
        url_button_layout.addWidget(self.download_btn)

        layout.addLayout(url_button_layout)

        # 取消按钮单独放在最下方
        self.cancel_btn = PushButton("取消")
        self.cancel_btn.setFixedHeight(28)  # 固定较小高度
        self.cancel_btn.setStyleSheet("""
            QPushButton {
                background-color: #dc3545;
                color: #ffffff;
                border: none;
                border-radius: 6px;
                padding: 4px 12px;
                font-size: 12px;
            }
            QPushButton:hover {
                background-color: #e74c3c;
            }
        """)
        self.cancel_btn.hide()  # 初始隐藏
        self.cancel_btn.clicked.connect(self.cancel_clicked)
        layout.addWidget(self.cancel_btn)

    def start_progress(self):
        """开始进度显示"""
        self.status_label.setText("正在生成...")
        self.status_label.setStyleSheet("color: #f39c12; font-size: 12px; font-weight: bold;")
        self.progress_bar.setValue(0)
        self.start_time = time.time()

        # 显示取消按钮，隐藏URL相关按钮
        self.cancel_btn.show()
        self.view_btn.hide()
        self.download_btn.hide()
        self.copy_url_btn.hide()
        self.url_container.hide()
        self.url_text_label.hide()

        # 启动计时器
        if self.progress_timer:
            self.progress_timer.stop()

        self.progress_timer = QTimer()
        self.progress_timer.timeout.connect(self.update_timer)
        self.progress_timer.start(1000)  # 每秒更新一次

    def update_progress(self, value, status_text=""):
        """更新进度"""
        self.progress_bar.setValue(value)
        if status_text:
            self.progress_info_label.setText(f"{status_text} - {value}%")
        else:
            elapsed = int(time.time() - self.start_time) if self.start_time else 0
            self.progress_info_label.setText(f"进度: {value}% - 已用时: {elapsed}秒")

    def update_timer(self):
        """更新计时器显示"""
        if self.start_time:
            elapsed = int(time.time() - self.start_time)
            hours = elapsed // 3600
            minutes = (elapsed % 3600) // 60
            seconds = elapsed % 60
            time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            current_progress = self.progress_bar.value()
            
            # 添加滚动信息
            if current_progress < 100:
                scroll_text = "· 正在生成视频...请耐心等待 ·"
                self.progress_info_label.setText(f"进度: {current_progress}% - 已用时: {time_str} {scroll_text}")
            else:
                self.progress_info_label.setText(f"进度: {current_progress}% - 已用时: {time_str}")

    def update_time(self, time_string):
        """从外部更新计时器显示"""
        current_progress = self.progress_bar.value()
        self.progress_info_label.setText(f"进度: {current_progress}% - 用时: {time_string}")

    def complete_progress(self, video_url=""):
        """完成进度显示"""
        self.progress_bar.setValue(100)
        self.status_label.setText("任务完成")  # 修改为"任务完成"而不是"完成"
        self.status_label.setStyleSheet("color: #28a745; font-size: 12px; font-weight: bold;")

        # 不停止计时器，让它继续计时显示总用时
        elapsed = int(time.time() - self.start_time) if self.start_time else 0
        hours = elapsed // 3600
        minutes = (elapsed % 3600) // 60
        seconds = elapsed % 60
        time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        self.progress_info_label.setText(f"任务完成! 总用时: {time_str}")

        if video_url:
            self.url_edit.setText(video_url)
            self.url_text_label.setText(video_url)
            self.url_container.show()
            self.url_text_label.show()  # 确保URL文本标签显示
            self.view_btn.show()
            self.download_btn.show()
            self.copy_url_btn.show()

            # 自动下载视频到本地
            self.auto_download_video(video_url)

        # 隐藏取消按钮
        self.cancel_btn.hide()

    def auto_download_video(self, video_url):
        """自动下载视频到output文件夹"""
        try:
            # 生成文件名
            task_name = self.video_data.get('task_name', 'video')
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{task_name}_{timestamp}.mp4"

            # 清理文件名中的特殊字符
            import re
            filename = re.sub(r'[^\w\-_.]', '_', filename)

            self.status_label.setText("正在下载...")
            self.status_label.setStyleSheet("color: #f39c12; font-size: 12px; font-weight: bold;")

            # 创建下载工作线程
            self.download_worker = VideoDownloadWorker(video_url, filename)
            self.download_worker.progress_updated.connect(self.on_download_progress)
            self.download_worker.download_finished.connect(self.on_download_finished)
            self.download_worker.log_updated.connect(self.on_download_log)

            # 如果父组件有日志功能，连接它
            if hasattr(self.parent(), 'add_log'):
                self.download_worker.log_updated.connect(self.parent().add_log)

            self.download_worker.start()

        except Exception as e:
            self.status_label.setText("下载失败")
            self.status_label.setStyleSheet("color: #dc3545; font-size: 12px; font-weight: bold;")
            print(f"自动下载启动失败: {str(e)}")

    def on_download_progress(self, progress, message):
        """下载进度更新"""
        self.progress_info_label.setText(f"下载: {message}")

    def on_download_finished(self, success, message, local_path):
        """下载完成回调"""
        if success and local_path:
            self.local_video_path = local_path
            self.status_label.setText("下载完成")
            self.status_label.setStyleSheet("color: #28a745; font-size: 12px; font-weight: bold;")

            # 更新按钮文本
            self.view_btn.setText("本地播放")

            # 通知父组件添加到视频展示区域
            if hasattr(self.parent(), 'add_video_to_display'):
                self.parent().add_video_to_display(local_path, self.video_data.get('task_name', '未命名'))

            self.progress_info_label.setText(f"✅ 已保存到: {os.path.basename(local_path)}")
        else:
            self.status_label.setText("下载失败")
            self.status_label.setStyleSheet("color: #dc3545; font-size: 12px; font-weight: bold;")
            self.progress_info_label.setText(f"❌ {message}")

    def on_download_log(self, message):
        """下载日志"""
        # 这个方法会被父组件的add_log方法处理
        pass

    def error_progress(self, error_msg=""):
        """显示错误状态"""
        self.status_label.setText("生成失败")
        self.status_label.setStyleSheet("color: #dc3545; font-size: 12px; font-weight: bold;")

        if self.progress_timer:
            self.progress_timer.stop()

        self.progress_info_label.setText(f"错误: {error_msg}")

        # 隐藏取消按钮
        self.cancel_btn.hide()

    def cancel_clicked(self):
        """取消按钮被点击"""
        # 通知父组件取消对应任务
        if self.parent() and hasattr(self.parent(), 'cancel_task'):
            self.parent().cancel_task(self.task_id)

        self.cancel_generation()

    def cancel_generation(self):
        """取消生成"""
        if self.progress_timer:
            self.progress_timer.stop()

        self.status_label.setText("已取消")
        self.status_label.setStyleSheet("color: #666666; font-size: 12px; font-weight: bold;")
        self.progress_info_label.setText("用户取消操作")

        # 隐藏取消按钮
        self.cancel_btn.hide()

    def view_video(self):
        """查看视频"""
        # 优先播放本地文件
        if self.local_video_path and os.path.exists(self.local_video_path):
            self.play_local_video(self.local_video_path)
        else:
            # 如果没有本地文件，播放远程URL
            video_url = self.video_data.get('url', '')  # 统一使用 'url' 字段
            if video_url:
                self.play_remote_video(video_url)
            else:
                QMessageBox.warning(self, "警告", "视频不可用")

    def play_local_video(self, local_path):
        """播放本地视频文件"""
        try:
            # 通知父组件播放本地视频
            if hasattr(self.parent(), 'play_video_in_display'):
                self.parent().play_video_in_display(local_path)
            else:
                # 如果父组件没有播放功能，使用系统默认播放器
                from PyQt5.QtCore import QUrl
                from PyQt5.QtGui import QDesktopServices
                QDesktopServices.openUrl(QUrl.fromLocalFile(local_path))
        except Exception as e:
            QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")

    def play_remote_video(self, video_url):
        """播放远程视频URL - 先下载到本地再播放"""
        try:
            # 生成文件名
            task_name = self.video_data.get('task_name', 'video')
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{task_name}_{timestamp}_play.mp4"

            # 清理文件名中的特殊字符
            import re
            filename = re.sub(r'[^\w\-_.]', '_', filename)

            # 禁用播放按钮并显示状态
            if hasattr(self, 'view_btn'):
                self.view_btn.setEnabled(False)
                self.view_btn.setText("下载中...")

            # 创建下载工作线程用于播放
            self.play_download_worker = VideoDownloadWorker(video_url, filename)
            self.play_download_worker.download_finished.connect(self.on_play_download_finished)

            # 如果父组件有日志功能，连接它
            if hasattr(self.parent(), 'add_log'):
                self.play_download_worker.log_updated.connect(self.parent().add_log)

            self.play_download_worker.start()

        except Exception as e:
            QMessageBox.warning(self, "错误", f"启动播放失败: {str(e)}")
            # 恢复按钮状态
            if hasattr(self, 'view_btn'):
                self.view_btn.setEnabled(True)
                self.view_btn.setText("播放")

    def on_play_download_finished(self, success, message, local_path):
        """播放下载完成回调"""
        # 恢复播放按钮状态
        if hasattr(self, 'view_btn'):
            self.view_btn.setEnabled(True)
            self.view_btn.setText("本地播放")

        if success and local_path:
            try:
                # 下载成功，播放本地视频
                self.play_local_video(local_path)
            except Exception as e:
                QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")
        else:
            # 下载失败，回退到系统播放器
            if hasattr(self, 'view_btn'):
                self.view_btn.setText("播放")
            video_url = self.video_data.get('url', '')
            if video_url:
                try:
                    from PyQt5.QtCore import QUrl
                    from PyQt5.QtGui import QDesktopServices
                    QDesktopServices.openUrl(QUrl(video_url))
                except Exception as e:
                    QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")

    def download_video(self):
        """下载视频"""
        video_url = self.video_data.get('url', '')  # 统一使用 'url' 字段
        if not video_url:
            QMessageBox.warning(self, "警告", "视频URL不可用")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self,
            f"保存视频 {self.video_data.get('task_name', 'video')}",
            f"{self.video_data.get('task_name', 'video')}.mp4",
            "MP4 Files (*.mp4)"
        )

        if file_path:
            try:
                self.download_btn.setEnabled(False)
                self.download_btn.setText("下载中...")

                response = requests.get(video_url, stream=True, timeout=300)
                response.raise_for_status()

                with open(file_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)

                QMessageBox.information(self, "成功", f"视频已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"下载失败: {str(e)}")
            finally:
                self.download_btn.setEnabled(True)
                self.download_btn.setText("下载")

    def copy_url(self):
        """复制视频URL"""
        video_url = self.video_data.get('url', '')
        if not video_url:
            video_url = self.url_edit.text()
        
        if video_url:
            from PyQt5.QtWidgets import QApplication
            clipboard = QApplication.clipboard()
            clipboard.setText(video_url)

            # 显示提示
            from qfluentwidgets import InfoBar
            InfoBar.success(
                title="成功",
                content="视频URL已复制到剪贴板",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=2000,
                parent=self
            )

# 视频结果卡片类
class VideoResultCard(CardWidget):
    """视频结果展示卡片"""

    def __init__(self, video_data, task_id, parent=None):
        super().__init__(parent)
        self.video_data = video_data
        self.task_id = task_id
        self.parent = parent
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 15, 15, 15)
        layout.setSpacing(10)

        # 任务标题
        title_label = QLabel(f"📋 {self.video_data.get('task_name', f'任务_{self.task_id}')}")
        title_label.setStyleSheet("font-size: 14px; font-weight: bold; color: #ffffff; margin-bottom: 5px;")
        layout.addWidget(title_label)

        # 视频信息
        info_layout = QHBoxLayout()

        # 分辨率
        size_label = QLabel(f"{self.video_data.get('width', 480)}×{self.video_data.get('height', 854)}")
        size_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(size_label)

        info_layout.addStretch()

        # 帧数
        frames_label = QLabel(f"{self.video_data.get('num_frames', 81)}帧")
        frames_label.setStyleSheet("color: #cccccc; font-size: 12px;")
        info_layout.addWidget(frames_label)

        layout.addLayout(info_layout)

        # 提示词
        prompt_text = self.video_data.get('prompt', '')
        if prompt_text:
            prompt_label = QLabel(f"提示词: {prompt_text[:60]}...")
            prompt_label.setStyleSheet("color: #888888; font-size: 11px;")
            prompt_label.setWordWrap(True)
            layout.addWidget(prompt_label)

        # 操作按钮
        button_layout = QHBoxLayout()

        self.view_btn = PushButton("本地播放")
        self.view_btn.setFixedSize(80, 30)
        self.view_btn.clicked.connect(self.view_video)
        button_layout.addWidget(self.view_btn)

        self.download_btn = PushButton("下载")
        self.download_btn.setFixedSize(60, 30)
        self.download_btn.clicked.connect(self.download_video)
        button_layout.addWidget(self.download_btn)

        self.copy_url_btn = PushButton("复制URL")
        self.copy_url_btn.setFixedSize(80, 30)
        self.copy_url_btn.clicked.connect(self.copy_url)
        button_layout.addWidget(self.copy_url_btn)

        button_layout.addStretch()
        layout.addLayout(button_layout)

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

    def view_video(self):
        """播放视频"""
        try:
            video_url = self.video_data.get('url', '')
            if video_url:
                # 先尝试下载到本地然后播放
                self.view_btn.setEnabled(False)
                self.view_btn.setText("下载中...")

                # 创建下载工作线程
                self.download_worker = VideoDownloadWorker(video_url, f"video_{self.task_id}.mp4")
                self.download_worker.download_finished.connect(self.on_play_download_finished)
                self.download_worker.start()
            else:
                QMessageBox.warning(self, "警告", "视频URL不可用")
        except Exception as e:
            QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")

    def on_play_download_finished(self, success, message, local_path):
        """播放下载完成回调"""
        # 恢复播放按钮状态
        if hasattr(self, 'view_btn'):
            self.view_btn.setEnabled(True)
            self.view_btn.setText("本地播放")

        if success and local_path:
            try:
                # 下载成功，播放本地视频
                self.parent.play_task_video(local_path, f"视频_{self.task_id}")
            except Exception as e:
                QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")
        else:
            # 下载失败，回退到系统播放器
            if hasattr(self, 'view_btn'):
                self.view_btn.setText("播放")
            video_url = self.video_data.get('url', '')
            if video_url:
                try:
                    from PyQt5.QtCore import QUrl
                    from PyQt5.QtGui import QDesktopServices
                    QDesktopServices.openUrl(QUrl(video_url))
                except Exception as e:
                    QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")

    def download_video(self):
        """下载视频"""
        video_url = self.video_data.get('url', '')
        if not video_url:
            QMessageBox.warning(self, "警告", "视频URL不可用")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self,
            f"保存视频 {self.video_data.get('task_name', f'video_{self.task_id}')}",
            f"{self.video_data.get('task_name', f'video_{self.task_id}')}.mp4",
            "MP4 Files (*.mp4)"
        )

        if file_path:
            try:
                self.download_btn.setEnabled(False)
                self.download_btn.setText("下载中...")

                response = requests.get(video_url, stream=True, timeout=300)
                response.raise_for_status()

                with open(file_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)

                QMessageBox.information(self, "成功", f"视频已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"下载失败: {str(e)}")
            finally:
                self.download_btn.setEnabled(True)
                self.download_btn.setText("下载")

    def copy_url(self):
        """复制视频URL"""
        video_url = self.video_data.get('url', '')
        if video_url:
            from PyQt5.QtWidgets import QApplication
            clipboard = QApplication.clipboard()
            clipboard.setText(video_url)

            # 显示提示
            from qfluentwidgets import InfoBar
            InfoBar.success(
                title="成功",
                content="视频URL已复制到剪贴板",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=2000,
                parent=self
            )