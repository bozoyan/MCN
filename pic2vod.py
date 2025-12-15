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
from PyQt5.QtCore import QThread, pyqtSignal, QTimer, Qt, QMimeData, QUrl, QObject
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QLineEdit, QTextEdit, QPushButton, QComboBox,
                            QSpinBox, QProgressBar, QMessageBox, QFileDialog,
                            QGroupBox, QTabWidget, QSplitter, QFrame,
                            QGridLayout, QScrollArea, QSlider, QCheckBox, QDialog)
from PyQt5.QtGui import QPixmap, QDragEnterEvent, QDropEvent, QPalette
import qfluentwidgets as qf
from qfluentwidgets import (FluentIcon, CardWidget, ElevatedCardWidget,
                          SmoothScrollArea, SubtitleLabel, BodyLabel,
                          PrimaryPushButton, PushButton, LineEdit, ComboBox,
                          ProgressBar, InfoBar, InfoBarPosition,
                          SwitchButton, InfoBadge, TeachingTip, TeachingTipTailPosition)

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
                self.image_dropped.emit(file_path, self.base64_data)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载图片失败: {str(e)}")

    def clear_image(self):
        self.image_label.clear()
        self.image_label.setText("🖼️\n拖拽图片到这里\n或点击选择文件")
        self.current_image_path = ""
        self.base64_data = ""

# API密钥管理器
class APIKeyManager:
    """API密钥管理器"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.current_key_index = 0
        self.web_app_id = 41082

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
        if self.api_keys:
            return self.api_keys
        env_key = os.getenv('SiliconCloud_API_KEY')
        return [env_key] if env_key else []

# 独立任务视频生成工作线程
class SingleVideoGenerationWorker(QThread):
    """单个视频生成工作线程 - 支持独立计时和并发执行"""
    progress_updated = pyqtSignal(int, str, str)  # progress, message, task_id
    task_finished = pyqtSignal(bool, str, dict, str)  # success, message, result_data, task_id
    time_updated = pyqtSignal(str, str)  # time_string, task_id
    log_updated = pyqtSignal(str)  # 日志更新信号

    def __init__(self, task, task_id, api_key):
        super().__init__()
        self.task = task
        self.task_id = task_id
        self.api_key = api_key
        self.start_time = None
        self.is_cancelled = False

        # 创建日志目录
        self.log_dir = "logs"
        if not os.path.exists(self.log_dir):
            os.makedirs(self.log_dir)

        # 计时器
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_timer)
        self.timer.setInterval(1000)  # 每秒更新一次

    def update_timer(self):
        """更新计时器显示"""
        if self.start_time:
            elapsed = time.time() - self.start_time
            hours = int(elapsed // 3600)
            minutes = int((elapsed % 3600) // 60)
            seconds = int(elapsed % 60)
            time_str = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            self.time_updated.emit(time_str, self.task_id)

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
            self.timer.start()  # 开始计时

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
                                self.task['image_input'] = f"data:{image_type};base64,{base64_data}"
                                self.log_message(f"📝 已转换图片为 {image_type} 格式")

                    except Exception as e:
                        self.task_finished.emit(False, f"图片处理失败: {str(e)}", {}, self.task_id)
                        return

            self.progress_updated.emit(20, "准备API请求...", self.task_id)

            # 构建请求数据
            request_data = {
                "input": {
                    "image": self.task['image_input'],
                    "prompt": prompt,
                    "width": width,
                    "height": height,
                    "num_frames": num_frames
                }
            }

            self.progress_updated.emit(30, "发送API请求...", self.task_id)

            # 发送API请求 - 使用正确的BizyAir API格式
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }

            # 构建BizyAir API请求数据格式 - 使用节点ID格式
            bizyair_request_data = {
                "web_app_id": 41082,  # 正确的Web App ID
                "suppress_preview_output": False,
                "input_values": {
                    "67:LoadImage.image": self.task['image_input'],
                    "68:ImageResizeKJv2.width": width,
                    "68:ImageResizeKJv2.height": height,
                    "16:WanVideoTextEncode.positive_prompt": prompt,
                    "89:WanVideoImageToVideoEncode.num_frames": num_frames
                }
            }

            self.log_message(f"📤 发送BizyAir API请求: {width}x{height}, {num_frames}帧 (AppID: 41082)")
            self.log_message(f"🔑 API密钥: {self.api_key[:10]}...")
            self.log_message(f"📝 请求URL: https://api.bizyair.cn/w/v1/webapp/task/openapi/create")

            # 注释掉API连接测试，避免404错误干扰
            # try:
            #     test_response = requests.get(
            #         "https://api.bizyair.cn/w/v1/webapp/app/list",
            #         headers=headers,
            #         timeout=10
            #     )
            #     self.log_message(f"🔍 API连接测试: {test_response.status_code}")
            # except Exception as e:
            #     self.log_message(f"⚠️ API连接测试失败: {str(e)}")

            response = requests.post(
                "https://api.bizyair.cn/w/v1/webapp/task/openapi/create",
                headers=headers,
                json=bizyair_request_data,
                timeout=600  # 10分钟超时
            )

            self.log_message(f"📡 API响应状态: {response.status_code}")

            if response.status_code == 200:
                result_data = response.json()
                self.log_message(f"✅ API请求成功，请求ID: {result_data.get('request_id', 'N/A')}")

                # 检查BizyAir的响应格式
                request_id = result_data.get('request_id')
                status = result_data.get('status', '')

                if request_id:
                    self.log_message(f"📋 任务ID: {request_id}, 状态: {status}")

                    # 如果任务立即完成且有输出
                    if status == 'Success' and 'outputs' in result_data:
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
                    else:
                        # 任务可能还在处理中，需要查询状态
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
            self.timer.stop()  # 停止计时

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
        self.timer.stop()


# 并发批量任务管理器
class ConcurrentBatchManager(QObject):
    """并发批量任务管理器"""
    all_tasks_finished = pyqtSignal()  # 所有任务完成信号
    task_progress = pyqtSignal(int, str, str)  # 进度更新
    task_finished = pyqtSignal(bool, str, dict, str)  # 任务完成
    task_time_updated = pyqtSignal(str, str)  # 任务时间更新
    log_updated = pyqtSignal(str)  # 日志更新
    batch_progress_updated = pyqtSignal(int, int)  # 批量进度更新

    def __init__(self):
        super().__init__()
        self.workers = {}  # task_id -> worker
        self.completed_tasks = 0
        self.total_tasks = 0
        self.api_manager = APIKeyManager()

    def execute_batch_tasks(self, tasks, key_file=None):
        """并发执行批量任务"""
        self.total_tasks = len(tasks)
        self.completed_tasks = 0

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
            worker = SingleVideoGenerationWorker(task, task_id, api_key)
            self.workers[task_id] = worker

            # 连接信号
            worker.progress_updated.connect(self.task_progress)
            worker.task_finished.connect(self.on_single_task_finished)
            worker.time_updated.connect(self.task_time_updated)
            worker.log_updated.connect(self.log_updated)

            # 启动任务（立即并发执行）
            worker.start()

            # 稍微错开启动时间，避免同时请求API
            time.sleep(0.1)

    def on_single_task_finished(self, success, message, result_data, task_id):
        """单个任务完成的回调"""
        self.completed_tasks += 1
        self.update_batch_progress()

        # 移除已完成的工作线程
        if task_id in self.workers:
            worker = self.workers.pop(task_id)
            worker.deleteLater()

        # 检查是否所有任务都已完成
        if self.completed_tasks >= self.total_tasks:
            self.log_updated.emit(f"✅ 所有任务完成！成功: {self.completed_tasks}/{self.total_tasks}")
            self.all_tasks_finished.emit()

    def update_batch_progress(self):
        """更新批量进度"""
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

    def cancel_all_tasks(self):
        """取消所有任务"""
        for worker in self.workers.values():
            worker.cancel()
            worker.wait()  # 等待线程结束
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
                background-color: #1e1e1e;
                color: #ffffff;
            }
            QScrollArea {
                background-color: #1e1e1e;
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
        self.settings_btn = PushButton("设置")  # 移除图标，添加文字
        self.settings_btn.setFixedSize(60, 32)  # 增加宽度以适应文字
        self.settings_btn.clicked.connect(self.show_settings_dialog)
        self.settings_btn.setStyleSheet("""
            QPushButton {
                border: none;
                background-color: transparent;
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
                border: 1px solid #404040;
                max-width: 200px;
            }
        """)
        layout.addWidget(self.current_params_top_label)

        return bar

    def create_control_panel(self):
        """创建控制面板（深色主题）"""
        panel = QWidget()
        panel.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(6)  # 减少模块间距
        layout.setContentsMargins(8, 8, 8, 8)  # 减少面板边距

        # 创建滚动区域
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("""
            QScrollArea {
                background-color: #1e1e1e;
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
        scroll_widget.setStyleSheet("QWidget { background-color: #1e1e1e; }")
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setSpacing(6)  # 减少滚动区域内间距

        # 图片输入组
        image_group = self.create_image_input_group()
        scroll_layout.addWidget(image_group)

        # 批量任务组
        batch_group = self.create_batch_group()
        scroll_layout.addWidget(batch_group)

        # 操作按钮组
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
        self.input_type_combo.addItems(["图片URL", "本地文件上传"])
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

        # 初始状态
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
        task_title.setStyleSheet("color: #ffffff; font-size: 18px; font-weight: bold; margin-top: -100px; padding: 2px 0;")
        layout.addWidget(task_title)
        layout.addWidget(self.task_scroll)

        # 添加任务按钮
        add_task_layout = QHBoxLayout()
        self.add_task_btn = PushButton("添加到任务列表")  # 移除图标
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

        self.clear_tasks_btn = PushButton("清空任务")  # 移除图标
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

    def create_actions_group(self):
        """创建操作按钮组（深色主题）"""
        group = QGroupBox("")  # 操作
        layout = QVBoxLayout(group)
        layout.setSpacing(0)  # 增加间距

        # 提示词输入（增高）
        self.prompt_edit = QTextEdit()
        self.prompt_edit.setPlaceholderText("输入视频生成的提示词，例如：美女跳舞、风景变化等...")
        self.prompt_edit.setFixedHeight(180)  # 减少高度让界面更紧凑
        self.prompt_edit.setStyleSheet("""
            QTextEdit {
                font-size: 18px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                border: 1px solid #404040;
                border-radius: 6px;
                margin-top:-120px;
                margin-bottom:20px;
                padding: 12px;
                background-color: #333333;
                color: #ffffff;
                selection-background-color: #4a90e2;
            }
            QTextEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        layout.addWidget(self.prompt_edit)

        # 添加弹性空间
        layout.addStretch()

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

        # 视频列表滚动区域（限制高度）
        self.video_scroll = SmoothScrollArea()
        self.video_scroll_widget = QWidget()
        self.video_scroll_layout = QVBoxLayout(self.video_scroll_widget)
        self.video_scroll_layout.setSpacing(10)
        self.video_scroll.setWidget(self.video_scroll_widget)
        self.video_scroll.setWidgetResizable(True)
        self.video_scroll.setFixedHeight(300)  # 限制高度，为播放器留空间
        video_list_layout.addWidget(self.video_scroll)

        # 下部分：视频播放区域
        # 分隔线
        separator = QFrame()
        separator.setFrameShape(QFrame.HLine)
        separator.setStyleSheet("color: #404040;")
        video_list_layout.addWidget(separator)

        # 视频播放区域标题
        player_title = QLabel("🎬 视频播放器")
        player_title.setStyleSheet("font-size: 14px; font-weight: bold; color: #ffffff; margin: 10px 0 5px 0;")
        video_list_layout.addWidget(player_title)

        # 视频播放器容器
        player_container = QFrame()
        player_container.setStyleSheet("""
            QFrame {
                background-color: #1a1a1a;
                border: 1px solid #404040;
                border-radius: 8px;
                padding: 10px;
            }
        """)
        player_layout = QVBoxLayout(player_container)
        player_layout.setSpacing(8)

        # 分割器：播放器和本地视频列表
        player_splitter = QSplitter(Qt.Horizontal)
        player_layout.addWidget(player_splitter)

        # 左侧：播放器区域
        player_left = QWidget()
        player_left_layout = QVBoxLayout(player_left)
        player_left_layout.setSpacing(8)

        # 视频播放器
        from PyQt5.QtMultimediaWidgets import QVideoWidget
        from PyQt5.QtMultimedia import QMediaPlayer, QMediaContent

        self.video_player = QVideoWidget()
        self.video_player.setStyleSheet("""
            QVideoWidget {
                background-color: #000000;
                border: 2px solid #404040;
                border-radius: 6px;
                min-height: 250px;
            }
        """)
        player_left_layout.addWidget(self.video_player)

        # 媒体播放器
        self.media_player = QMediaPlayer()
        self.media_player.setVideoOutput(self.video_player)

        # 播放控制区域
        playback_controls = QHBoxLayout()

        self.play_btn = PushButton("▶️ 播放")
        self.play_btn.setFixedHeight(30)
        self.play_btn.clicked.connect(self.toggle_playback)
        self.play_btn.setEnabled(False)
        playback_controls.addWidget(self.play_btn)

        self.stop_btn = PushButton("⏹️ 停止")
        self.stop_btn.setFixedHeight(30)
        self.stop_btn.clicked.connect(self.stop_playback)
        self.stop_btn.setEnabled(False)
        playback_controls.addWidget(self.stop_btn)

        # 刷新本地视频列表按钮
        self.refresh_videos_btn = PushButton("🔄")
        self.refresh_videos_btn.setFixedHeight(30)
        self.refresh_videos_btn.setFixedWidth(30)
        self.refresh_videos_btn.clicked.connect(self.refresh_local_videos)
        self.refresh_videos_btn.setToolTip("刷新本地视频列表")
        playback_controls.addWidget(self.refresh_videos_btn)

        # 当前播放信息
        self.current_video_label = QLabel("未选择视频")
        self.current_video_label.setStyleSheet("""
            QLabel {
                color: #cccccc;
                font-size: 11px;
                padding: 6px 10px;
                background-color: #333333;
                border-radius: 4px;
                border: 1px solid #404040;
            }
        """)
        playback_controls.addWidget(self.current_video_label)

        playback_controls.addStretch()

        player_left_layout.addLayout(playback_controls)
        player_splitter.addWidget(player_left)

        # 右侧：本地视频列表
        player_right = QWidget()
        player_right_layout = QVBoxLayout(player_right)
        player_right_layout.setSpacing(5)

        # 本地视频列表标题
        local_videos_title = QLabel("📁 本地视频")
        local_videos_title.setStyleSheet("font-size: 14px; font-weight: bold; color: #ffffff; margin-bottom: 5px;")
        player_right_layout.addWidget(local_videos_title)

        # 本地视频列表区域
        self.local_videos_scroll = QScrollArea()
        self.local_videos_scroll.setWidgetResizable(True)
        self.local_videos_scroll.setStyleSheet("""
            QScrollArea {
                background-color: #2a2a2a;
                border: 1px solid #404040;
                border-radius: 6px;
            }
            QScrollBar:vertical {
                background-color: #2a2a2a;
                width: 6px;
                border-radius: 3px;
            }
            QScrollBar::handle:vertical {
                background-color: #4a4a4a;
                border-radius: 3px;
                min-height: 15px;
            }
        """)

        self.local_videos_widget = QWidget()
        self.local_videos_layout = QVBoxLayout(self.local_videos_widget)
        self.local_videos_layout.setSpacing(3)
        self.local_videos_scroll.setWidget(self.local_videos_widget)
        player_right_layout.addWidget(self.local_videos_scroll)

        player_splitter.addWidget(player_right)

        # 设置分割比例（播放器:本地列表 = 3:1）
        player_splitter.setSizes([450, 150])

        video_list_layout.addWidget(player_container)

        self.result_tabs.addTab(self.video_list_widget, "视频列表")

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
        is_url = index == 0
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
            'image_path': self.drop_widget.current_image_path if self.input_type_combo.currentIndex() == 1 else '',
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
        card.setFixedHeight(60)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(10, 5, 10, 5)

        # 任务信息
        info_layout = QVBoxLayout()
        name_label = QLabel(task['name'])
        name_label.setStyleSheet("font-weight: bold;background-color:#292929;")
        info_layout.addWidget(name_label)

        prompt_label = QLabel(f"提示词: {task['prompt'][:60]}...")
        prompt_label.setStyleSheet("color: #666; font-size: 12px;background-color:#292929;")
        info_layout.addWidget(prompt_label)

        layout.addLayout(info_layout)

        layout.addStretch()

        # 删除按钮
        delete_btn = PushButton("删除")  # 移除图标，添加文字
        delete_btn.setFixedSize(30, 30)
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
        self.add_log("🗑️ 已清空所有任务")

    def get_current_image_input(self):
        """获取当前图片输入"""
        if self.input_type_combo.currentIndex() == 0:  # URL
            return self.image_url_edit.text().strip()
        else:  # 本地文件
            return self.drop_widget.base64_data

    def generate_single_video(self):
        """生成单个视频 - 支持并发执行"""
        # 检查是否已有任务在执行
        if self.concurrent_batch_manager and len(self.concurrent_batch_manager.workers) > 0:
            # 允许多个并发任务，但给出提示
            reply = QMessageBox.question(
                self, "确认",
                "当前有任务正在执行，是否要并发执行新的任务？\n(这样可以充分利用多个API密钥)",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes
            )
            if reply == QMessageBox.No:
                return

        image_input = self.get_current_image_input()
        prompt = self.prompt_edit.toPlainText().strip()

        if not image_input:
            QMessageBox.warning(self, "警告", "请先选择图片")
            return

        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频提示词")
            return

        # 创建单个任务，使用时间戳确保唯一性
        timestamp = datetime.now().strftime("%H%M%S")
        task = {
            'name': f"单个任务_{timestamp}",
            'image_input': image_input,
            'image_path': self.drop_widget.current_image_path if self.input_type_combo.currentIndex() == 1 else '',
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

        # 使用并发执行而非顺序执行
        self.execute_concurrent_tasks(self.batch_tasks)

    def execute_concurrent_tasks(self, tasks):
        """真正并发执行任务 - 每个任务独立线程和API密钥"""
        if not tasks:
            return

        # 为每个任务创建进度卡片
        self.task_cards = {}
        for i, task in enumerate(tasks):
            task_id = f"task_{i+1}"
            # 创建包含任务ID的视频数据
            video_data = {
                **task,
                'task_name': task.get('name', f'任务 {i+1}'),
                'timestamp': datetime.now().isoformat()
            }
            # 创建并添加卡片
            video_card = VideoResultCard(video_data, self)
            video_card.task_id = task_id  # 设置任务ID
            self.video_scroll_layout.addWidget(video_card)
            self.task_cards[task_id] = video_card
            # 开始进度显示
            video_card.start_progress()

        # 切换到视频列表Tab
        self.result_tabs.setCurrentIndex(0)

        # 如果已有管理器，复用或创建新的
        if not self.concurrent_batch_manager:
            self.concurrent_batch_manager = ConcurrentBatchManager()
            self.concurrent_batch_manager.task_progress.connect(self.update_task_progress)
            self.concurrent_batch_manager.task_finished.connect(self.on_task_finished)
            self.concurrent_batch_manager.task_time_updated.connect(self.update_task_time)
            self.concurrent_batch_manager.log_updated.connect(self.add_log)
            self.concurrent_batch_manager.batch_progress_updated.connect(self.update_batch_progress)
            self.concurrent_batch_manager.all_tasks_finished.connect(self.on_all_tasks_finished)

        # 获取密钥文件路径
        key_file_path = getattr(self, 'key_file_path', None)

        # 开始真正并发执行（所有任务同时启动）
        self.add_log(f"🚀 开始并发执行，共{len(tasks)}个任务，WebAppID: {self.api_manager.web_app_id}")
        self.concurrent_batch_manager.execute_batch_tasks(tasks, key_file_path)

    def update_task_progress(self, progress, message, task_id):
        """更新单个任务进度"""
        self.add_log(f"[{task_id}] {progress}% - {message}")

        # 更新对应卡片的进度
        if hasattr(self, 'task_cards') and task_id in self.task_cards:
            card = self.task_cards[task_id]
            card.update_progress(progress, message)

    def on_task_finished(self, success, message, result_data, task_id):
        """任务完成回调"""
        if success:
            self.add_log(f"✅ [{task_id}] {message}")
            # 更新对应卡片为完成状态
            if hasattr(self, 'task_cards') and task_id in self.task_cards:
                card = self.task_cards[task_id]
                video_url = result_data.get('url', '')  # 统一使用 'url' 字段
                if video_url:
                    card.complete_progress(video_url)
                    self.add_log(f"📹 [{task_id}] 视频链接: {video_url}")
                else:
                    card.error_progress("未获取到视频URL")
                # 更新卡片的video_data
                card.video_data.update(result_data)

                # 停止该任务的计时器更新
                if self.concurrent_batch_manager and task_id in self.concurrent_batch_manager.workers:
                    worker = self.concurrent_batch_manager.workers.get(task_id)
                    if worker and hasattr(worker, 'timer') and worker.timer:
                        worker.timer.stop()
        else:
            self.add_log(f"❌ [{task_id}] {message}")
            # 更新对应卡片为错误状态
            if hasattr(self, 'task_cards') and task_id in self.task_cards:
                card = self.task_cards[task_id]
                card.error_progress(message)

    def update_task_time(self, time_string, task_id):
        """更新任务计时显示"""
        # 更新对应卡片的时间显示
        if hasattr(self, 'task_cards') and task_id in self.task_cards:
            card = self.task_cards[task_id]
            # 检查任务是否已完成，如果已完成则不再更新时间
            if card.progress_bar.value() < 100:
                card.update_time(time_string)

    def on_all_tasks_finished(self):
        """所有任务完成的回调"""
        self.add_log("🎉 所有并发任务已完成！")
        # 可以在这里添加批量完成后的处理逻辑
        QMessageBox.information(self, "完成", "所有视频生成任务已完成！")

        # 清理管理器
        if self.concurrent_batch_manager:
            self.concurrent_batch_manager = None

    def update_batch_progress(self, current, total):
        """更新批量进度"""
        progress = int((current / total) * 100) if total > 0 else 0
        self.batch_progress_bar.setValue(progress)
        self.batch_progress_label.setText(f"批量进度: {current}/{total}")

    def add_video_result(self, video_data):
        """添加视频结果"""
        # 创建视频结果卡片
        video_card = VideoResultCard(video_data)
        self.video_scroll_layout.addWidget(video_card)

        # 切换到视频列表Tab
        self.result_tabs.setCurrentIndex(0)

    def show_settings_dialog(self):
        """显示设置对话框"""
        dialog = APISettingsDialog(self.api_manager, self)
        if dialog.exec_() == QDialog.Accepted:
            self.update_key_status()
            self.save_settings()

    def cancel_task(self, task_id):
        """取消指定任务"""
        if self.current_batch_worker and self.current_batch_worker.isRunning():
            self.current_batch_worker.cancel()
            self.add_log(f"⏹️ 用户请求取消任务 {task_id}")

    def update_key_status(self):
        """更新密钥状态显示（深色主题）"""
        count = self.api_manager.get_available_keys_count()
        if count > 0:
            self.key_status_label.setText(f"密钥: {count}个可用")
            self.key_status_label.setStyleSheet("""
                color: #4CAF50;
                padding: 6px 15px;
                background: #1e3a1e;
                border-radius: 6px;
                border: 1px solid #2e5a2e;
                font-size: 12px;
                min-width: 120px;
            """)
        else:
            self.key_status_label.setText("密钥: 未配置")
            self.key_status_label.setStyleSheet("""
                color: #ff6b6b;
                padding: 6px 15px;
                background: #3a1e1e;
                border-radius: 6px;
                border: 1px solid #5a2e2e;
                font-size: 12px;
                min-width: 120px;
            """)

    def add_log(self, message):
        """添加日志"""
        self.log_text.append(message)
        # 自动滚动到底部
        cursor = self.log_text.textCursor()
        cursor.movePosition(cursor.End)
        self.log_text.setTextCursor(cursor)

    def clear_log(self):
        """清空日志"""
        self.log_text.clear()
        self.add_log("📝 日志已清空")

    def save_log(self):
        """保存日志"""
        file_path, _ = QFileDialog.getSaveFileName(
            self, "保存日志", f"video_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt", "文本文件 (*.txt)"
        )
        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(self.log_text.toPlainText())
                QMessageBox.information(self, "成功", f"日志已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"保存失败: {str(e)}")

    def refresh_local_videos(self):
        """刷新本地视频列表"""
        try:
            # 清空现有列表
            while self.local_videos_layout.count():
                item = self.local_videos_layout.takeAt(0)
                if item.widget():
                    item.widget().deleteLater()

            # 检查output目录
            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)
                self.local_videos_layout.addWidget(QLabel("📁 output文件夹为空"))
                return

            # 支持的视频格式
            video_extensions = ['.mp4', '.avi', '.mov', '.mkv', '.flv', '.wmv', '.webm']
            video_files = []

            # 扫描视频文件
            for file in os.listdir(output_dir):
                if any(file.lower().endswith(ext) for ext in video_extensions):
                    file_path = os.path.join(output_dir, file)
                    if os.path.isfile(file_path):
                        # 获取文件信息
                        stat = os.stat(file_path)
                        size_mb = stat.st_size / (1024 * 1024)
                        mtime = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M")

                        video_files.append({
                            'name': file,
                            'path': file_path,
                            'size_mb': size_mb,
                            'mtime': mtime
                        })

            # 按修改时间排序（最新的在前）
            video_files.sort(key=lambda x: x['mtime'], reverse=True)

            if not video_files:
                self.local_videos_layout.addWidget(QLabel("📁 没有找到视频文件"))
                return

            # 添加视频文件到列表
            for video_info in video_files:
                video_item = self.create_local_video_item(video_info)
                self.local_videos_layout.addWidget(video_item)

            self.add_log(f"📁 已刷新本地视频列表，共{len(video_files)}个文件")

        except Exception as e:
            self.add_log(f"⚠️ 刷新本地视频列表失败: {str(e)}")
            self.local_videos_layout.addWidget(QLabel("❌ 加载失败"))

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
            from PyQt5.QtMultimedia import QMediaContent

            self.media_player.setMedia(QMediaContent(QUrl.fromLocalFile(file_path)))
            self.media_player.play()

            # 更新播放按钮文本
            self.play_btn.setText("⏸️ 暂停")

            self.add_log(f"🎬 正在播放本地视频: {file_name}")

        except Exception as e:
            self.add_log(f"⚠️ 播放本地视频失败: {str(e)}")
            QMessageBox.warning(self, "错误", f"播放失败: {str(e)}")

    def load_settings(self):
        """加载设置"""
        try:
            settings_file = "video_settings.json"
            if os.path.exists(settings_file):
                with open(settings_file, 'r', encoding='utf-8') as f:
                    settings = json.load(f)

                # 加载密钥文件路径
                if 'key_file' in settings:
                    self.api_manager.load_keys_from_file(settings['key_file'])
                    self.key_file_path = settings['key_file']

                self.update_key_status()

                # 初始化参数显示
                self.update_current_params_display()

                # 初始化本地视频列表
                self.refresh_local_videos()
        except Exception as e:
            self.add_log(f"加载设置失败: {e}")

            # 即使加载失败也要初始化参数显示
            try:
                self.update_current_params_display()
            except AttributeError as e:
                self.add_log(f"参数显示初始化失败: {str(e)}")
                # 手动设置默认参数显示
                if hasattr(self, 'current_params_top_label'):
                    self.current_params_top_label.setText("当前: 480×854, 5秒, 81帧")

    def save_settings(self):
        """保存设置"""
        try:
            settings = {}
            if hasattr(self, 'key_file_path') and self.key_file_path:
                settings['key_file'] = self.key_file_path

            settings_file = "video_settings.json"
            with open(settings_file, 'w', encoding='utf-8') as f:
                json.dump(settings, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.add_log(f"保存设置失败: {e}")

    def add_video_to_display(self, video_path, video_name):
        """添加视频到播放区域"""
        try:
            # 确保在视频列表Tab（索引0）
            self.result_tabs.setCurrentIndex(0)

            # 设置当前播放的视频
            self.current_video_path = video_path
            self.current_video_label.setText(f"当前: {os.path.basename(video_path)}")

            # 启用播放控制按钮
            self.play_btn.setEnabled(True)
            self.stop_btn.setEnabled(True)

            # 加载视频到播放器
            from PyQt5.QtCore import QUrl
            from PyQt5.QtMultimedia import QMediaContent

            self.media_player.setMedia(QMediaContent(QUrl.fromLocalFile(video_path)))
            self.add_log(f"🎬 已加载视频: {video_name}")

        except Exception as e:
            self.add_log(f"⚠️ 加载视频失败: {str(e)}")

    def play_video_in_display(self, video_path):
        """在显示区域播放视频"""
        try:
            # 确保在视频列表Tab（索引0）
            self.result_tabs.setCurrentIndex(0)

            # 设置并播放视频
            self.current_video_path = video_path
            self.current_video_label.setText(f"正在播放: {os.path.basename(video_path)}")

            # 启用播放控制按钮
            self.play_btn.setEnabled(True)
            self.stop_btn.setEnabled(True)

            # 加载并播放视频
            from PyQt5.QtCore import QUrl
            from PyQt5.QtMultimedia import QMediaContent

            self.media_player.setMedia(QMediaContent(QUrl.fromLocalFile(video_path)))
            self.media_player.play()

            # 更新播放按钮文本
            self.play_btn.setText("⏸️ 暂停")

        except Exception as e:
            self.add_log(f"⚠️ 播放视频失败: {str(e)}")

    def toggle_playback(self):
        """切换播放/暂停"""
        if self.media_player.state() == self.media_player.PlayingState:
            self.media_player.pause()
            self.play_btn.setText("▶️ 播放")
        else:
            self.media_player.play()
            self.play_btn.setText("⏸️ 暂停")

    def stop_playback(self):
        """停止播放"""
        self.media_player.stop()
        self.play_btn.setText("▶️ 播放")

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
                background-color: #1a1a1a;
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
                background-color: #222222;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
                background-color: #2a2a2a;
                border-top-right-radius: 6px;
                border-bottom-right-radius: 6px;
            }
            QComboBox::down-arrow {
                image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEFSURBVCiRldKxSgNBEMbxH0QZ0CuEF2CiEwJCgKESFuwBLhAT8AFyEO7wELsAC7AQX4CNxgU0cG6+dCZmZn8ZzYwXJJW8k8/fnOeOA8gw/r9fSEECGNFIAiCRZSROJIKJVmQygJMFQYGIFFsCgnhBaiBiOIEFEZgYhBRRGYGGYBFJp9uQRZZYcS1Lb5EA/ghggCVBJEARRyESOhKhszEMDQDdICB9ALRxZUeCcOPPMi5F+T8SX6FMaVvUIFxAIsgYgsI6IEHEhgUYEagIYRGAqPwiwAEYQmAqBQbY4QhBiBoZfn+/fXfjPMO4KdYvKEnKcTb1ncNcIrr8AyVcOlH9Zc1wAAAAASUVORK5CYII=);
                width: 12px;
                height: 12px;
            }
            QComboBox QAbstractItemView {
                background-color: #1a1a1a;
                border: 1px solid #404040;
                selection-background-color: #4a90e2;
                color: #ffffff;
                selection-color: #ffffff;
                padding: 4px 0px;
            }
            QComboBox QAbstractItemView::item {
                padding: 8px 12px;
                border-bottom: 1px solid #404040;
                background-color: #1a1a1a;
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
        self.duration_spin.valueChanged.connect(lambda: self.update_frames())
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
        """从主界面加载当前设置"""
        if hasattr(self.parent(), 'width_spin') and hasattr(self.parent(), 'height_spin'):
            self.width_spin.setValue(self.parent().width_spin.value())
            self.height_spin.setValue(self.parent().height_spin.value())
            self.duration_spin.setValue(self.parent().duration_spin.value())
            self.update_frames()

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

    def update_frames(self):
        """根据秒数更新帧数"""
        seconds = self.duration_spin.value()
        total_frames = seconds * 16 + 1
        self.frames_label.setText(f"总帧数: {total_frames}")

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
        self.update_frames()

    def accept_settings(self):
        """应用设置并关闭"""
        try:
            if hasattr(self.parent(), 'width_spin') and hasattr(self.parent(), 'height_spin'):
                # 更新父控件的参数值
                self.parent().width_spin.setValue(self.width_spin.value())
                self.parent().height_spin.setValue(self.height_spin.value())
                self.parent().duration_spin.setValue(self.duration_spin.value())
                self.parent().update_frames()

                # 更新参数显示
                self.parent().update_current_params_display()
        except Exception as e:
            print(f"应用设置时出错: {str(e)}")
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

        # API密钥文件设置
        key_group = QGroupBox("API密钥文件")
        key_layout = QVBoxLayout(key_group)

        file_layout = QHBoxLayout()
        self.key_file_edit = LineEdit()
        self.key_file_edit.setPlaceholderText("输入密钥文件路径...")
        self.key_file_edit.setText(getattr(self.parent(), 'key_file_path', ''))
        file_layout.addWidget(self.key_file_edit)

        self.browse_btn = PushButton("浏览")  # 移除图标
        self.browse_btn.clicked.connect(self.browse_key_file)
        file_layout.addWidget(self.browse_btn)

        key_layout.addLayout(file_layout)

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
        self.api_manager.web_app_id = self.webapp_id_spin.value()

        file_path = self.key_file_edit.text().strip()
        if file_path and os.path.exists(file_path):
            if self.api_manager.load_keys_from_file(file_path):
                self.parent().key_file_path = file_path
                self.accept()
            else:
                QMessageBox.warning(self, "警告", "密钥文件保存失败")
        else:
            self.accept()

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
        self.status_label = QLabel("准备中...")
        self.status_label.setStyleSheet("color: #4a90e2; font-size: 12px; font-weight: bold;")
        header_layout.addWidget(self.status_label)

        layout.addLayout(header_layout)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(12)  # 减小高度
        self.progress_bar.setValue(0)
        layout.addWidget(self.progress_bar)

        # 进度文字显示（百分比和时间）
        self.progress_info_label = QLabel("等待开始...")
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
        self.url_layout = QVBoxLayout(self.url_container)
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

        # 按钮区域
        button_layout = QHBoxLayout()

        self.view_btn = PushButton("播放")
        self.view_btn.clicked.connect(self.view_video)
        self.view_btn.hide()  # 初始隐藏
        button_layout.addWidget(self.view_btn)

        self.download_btn = PushButton("下载")
        self.download_btn.clicked.connect(self.download_video)
        self.download_btn.hide()  # 初始隐藏
        button_layout.addWidget(self.download_btn)

        self.copy_url_btn = PushButton("复制URL")
        self.copy_url_btn.clicked.connect(self.copy_url)
        self.copy_url_btn.hide()  # 初始隐藏
        button_layout.addWidget(self.copy_url_btn)

        layout.addLayout(button_layout)

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
            current_progress = self.progress_bar.value()
            self.progress_info_label.setText(f"进度: {current_progress}% - 已用时: {elapsed}秒")

    def update_time(self, time_string):
        """从外部更新计时器显示"""
        current_progress = self.progress_bar.value()
        self.progress_info_label.setText(f"进度: {current_progress}% - 用时: {time_string}")

    def complete_progress(self, video_url=""):
        """完成进度显示"""
        self.progress_bar.setValue(100)
        self.status_label.setText("生成完成")
        self.status_label.setStyleSheet("color: #28a745; font-size: 12px; font-weight: bold;")

        if self.progress_timer:
            self.progress_timer.stop()

        elapsed = int(time.time() - self.start_time) if self.start_time else 0
        self.progress_info_label.setText(f"完成! 总用时: {elapsed}秒")

        if video_url:
            self.url_edit.setText(video_url)
            self.url_container.show()
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
        video_url = self.video_data.get('video_url', '')
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