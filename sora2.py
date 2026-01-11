#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sora2 Video Generation Module (sora2) - Based on BizyAir API
Supports both text-to-video and image-to-video modes
"""

import os
import sys
import json
import time
import requests
import base64
import traceback
import re
import subprocess
import platform
import threading
from datetime import datetime, timedelta
from PyQt5.QtCore import QObject, QTimer

try:
    from PIL import Image
    import io
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

from PyQt5.QtCore import QThread, pyqtSignal, Qt, QUrl, QCoreApplication
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QTextEdit, QPushButton, QComboBox,
                            QProgressBar, QMessageBox, QFileDialog,
                            QGroupBox, QSplitter, QFrame, QRadioButton,
                            QScrollArea, QDialog, QSizePolicy, QTabWidget)
from PyQt5.QtGui import QPixmap, QDragEnterEvent, QDropEvent, QDesktopServices

import qfluentwidgets as qf
from qfluentwidgets import (FluentIcon, CardWidget,
                          PrimaryPushButton, PushButton, LineEdit, ComboBox,
                          ProgressBar, InfoBar, InfoBarPosition,
                          StrongBodyLabel, CaptionLabel, Theme)

# ==================== Utils ====================
class Utils:
    """工具方法集合"""

    LOG_DIR = "logs"

    @staticmethod
    def log_message(message, log_updated_signal=None, task_name=None):
        """记录日志消息"""
        if not os.path.exists(Utils.LOG_DIR):
            os.makedirs(Utils.LOG_DIR)

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        task_prefix = f"[{task_name}] " if task_name else ""
        log_entry = f"[{timestamp}] {task_prefix}{message}"

        if log_updated_signal:
            log_updated_signal.emit(log_entry)

        log_file = os.path.join(Utils.LOG_DIR, "sora2_generation.log")
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"Failed to write log: {e}")

    @staticmethod
    def compress_image(image_data, log_updated_signal=None):
        """压缩图片数据"""
        if not HAS_PIL:
            Utils.log_message("PIL not installed, skip compression", log_updated_signal)
            return image_data

        try:
            image = Image.open(io.BytesIO(image_data))

            if image.mode in ('RGBA', 'LA', 'P'):
                background = Image.new('RGB', image.size, (255, 255, 255))
                if image.mode == 'P':
                    image = image.convert('RGBA')
                background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                image = background.convert('RGB')

            max_dimension = 1280
            width, height = image.size

            if max(width, height) > max_dimension:
                ratio = max_dimension / max(width, height)
                new_size = tuple(int(dim * ratio) for dim in image.size)
                image = image.resize(new_size, Image.Resampling.LANCZOS)
                Utils.log_message(f"Image resized: {width}x{height} -> {new_size[0]}x{new_size[1]}", log_updated_signal)

            output = io.BytesIO()
            image.save(output, format='JPEG', quality=85, optimize=True)
            compressed_data = output.getvalue()
            output.close()

            Utils.log_message(f"Image compressed: {len(image_data)} -> {len(compressed_data)} bytes", log_updated_signal)
            return compressed_data

        except Exception as e:
            Utils.log_message(f"Compression failed, using original: {str(e)}", log_updated_signal)
            return image_data

# ==================== Settings Manager ====================
class Sora2SettingsManager:
    """Sora2 视频设置管理器"""

    def __init__(self, config_file="sora2_settings.json"):
        self.config_file = config_file
        self.default_settings = {
            "video_params": {
                "aspect_ratio": "9:16",
                "duration": 10,
                "duration_t2v": 10,
                "duration_i2v": 10
            },
            "api_settings": {
                "key_file": "",
                "key_text": "",
                "key_source": "file",
                "web_app_id_t2v": 42921,
                "web_app_id_i2v": 42936,
                "api_url": "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
            },
            "ui_settings": {
                "last_export_dir": "output",
                "video_mode": "t2v"
            }
        }

    def load_settings(self):
        """加载设置"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                return self._merge_settings(self.default_settings, settings)
            else:
                return self.default_settings.copy()
        except Exception as e:
            print(f"Failed to load Sora2 settings: {e}")
            return self.default_settings.copy()

    def save_settings(self, settings):
        """保存设置"""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(settings, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"Failed to save Sora2 settings: {e}")
            return False

    def get_video_params(self):
        """获取视频参数"""
        settings = self.load_settings()
        return settings.get("video_params", self.default_settings["video_params"])

    def set_video_params(self, aspect_ratio="9:16", duration=10, duration_t2v=10, duration_i2v=10):
        """设置视频参数"""
        settings = self.load_settings()
        settings["video_params"] = {
            "aspect_ratio": aspect_ratio,
            "duration": duration,
            "duration_t2v": duration_t2v,
            "duration_i2v": duration_i2v
        }
        return self.save_settings(settings)

    def get_api_settings(self):
        """获取 API 设置"""
        settings = self.load_settings()
        return settings.get("api_settings", self.default_settings["api_settings"])

    def set_api_settings(self, key_file="", web_app_id_t2v=42921, web_app_id_i2v=42936,
                        api_url=None, key_text="", key_source="file"):
        """设置 API 参数"""
        settings = self.load_settings()

        current_api_url = settings.get("api_settings", {}).get("api_url",
            "https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
        if api_url is None:
            api_url = current_api_url

        settings["api_settings"] = {
            "key_file": key_file,
            "key_text": key_text,
            "key_source": key_source,
            "web_app_id_t2v": web_app_id_t2v,
            "web_app_id_i2v": web_app_id_i2v,
            "api_url": api_url
        }
        return self.save_settings(settings)

    def _merge_settings(self, defaults, loaded):
        """合并设置"""
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

    def get_webhook_settings(self):
        """获取 WebHook 配置"""
        settings = self.load_settings()
        return {
            "enabled": settings.get("api_settings", {}).get("webhook_enabled", False),
            "url": settings.get("api_settings", {}).get("webhook_url", ""),
            "token": settings.get("api_settings", {}).get("webhook_token", ""),
            "query_url": settings.get("api_settings", {}).get("query_url",
                "https://api.bizyair.cn/w/v1/webapp/task/openapi/outputs"),
            "delay_minutes": settings.get("api_settings", {}).get("query_delay_minutes", 10),
            "fallback_to_polling": settings.get("api_settings", {}).get("fallback_to_polling", False)
        }

    def set_webhook_settings(self, enabled=False, url="", token="",
                             query_url=None, delay_minutes=10, fallback_to_polling=False):
        """设置 WebHook 配置"""
        settings = self.load_settings()
        if "api_settings" not in settings:
            settings["api_settings"] = {}

        settings["api_settings"]["webhook_enabled"] = enabled
        settings["api_settings"]["webhook_url"] = url
        settings["api_settings"]["webhook_token"] = token
        settings["api_settings"]["query_url"] = query_url or \
            "https://api.bizyair.cn/w/v1/webapp/task/openapi/outputs"
        settings["api_settings"]["query_delay_minutes"] = delay_minutes
        settings["api_settings"]["fallback_to_polling"] = fallback_to_polling

        return self.save_settings(settings)

# ==================== API Key Manager ====================
class Sora2APIKeyManager:
    """Sora2 API 密钥管理器"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.key_text = ""
        self.current_key_index = 0
        self.web_app_id_t2v = 42921
        self.web_app_id_i2v = 42936
        self.key_source = "file"

    def load_keys_from_file(self, file_path):
        """从文件加载 API 密钥"""
        try:
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    keys = [line.strip() for line in f.readlines()
                           if line.strip() and not line.strip().startswith('#')]
                self.api_keys = [key for key in keys if len(key) > 10]
                self.key_file = file_path
                return True
        except Exception as e:
            print(f"Failed to load API key file: {e}")
        return False

    def load_keys_from_text(self, key_text):
        """从文本加载 API 密钥"""
        try:
            if key_text:
                keys = [line.strip() for line in key_text.split('\n')
                       if line.strip() and not line.strip().startswith('#')]
                self.api_keys = [key for key in keys if len(key) > 10]
                self.key_text = key_text
                return True
        except Exception as e:
            print(f"Failed to load API key text: {e}")
        return False

    def get_next_key(self):
        """获取下一个可用的 API 密钥"""
        if self.key_source == "env":
            return os.getenv('SiliconCloud_API_KEY')
        elif self.key_source == "text":
            if not self.api_keys:
                return None
            if self.current_key_index >= len(self.api_keys):
                self.current_key_index = 0
            key = self.api_keys[self.current_key_index]
            self.current_key_index += 1
            return key
        else:
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
        """获取所有可用的 API 密钥"""
        if self.key_source == "env":
            env_key = os.getenv('SiliconCloud_API_KEY')
            return [env_key] if env_key else []
        elif self.key_source == "text":
            return self.api_keys
        else:
            return self.api_keys

    def set_key_source(self, source):
        """设置密钥来源"""
        self.key_source = source
        self.current_key_index = 0

    def get_key_source(self):
        """获取当前密钥来源"""
        return self.key_source

    def get_key_source_display(self):
        """获取密钥来源显示文本"""
        if self.key_source == "env":
            return "系统变量"
        elif self.key_source == "text":
            return "密钥文本"
        else:
            return "文件密钥"

# ==================== Task History Manager ====================
class Sora2TaskHistoryManager:
    """Sora2 任务历史记录管理器"""

    def __init__(self, history_file="sora2_tasks_history.json"):
        self.history_file = history_file
        self.lock = threading.Lock()

    def load_history(self):
        """加载任务历史"""
        try:
            if os.path.exists(self.history_file):
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            else:
                return self._get_empty_history()
        except Exception as e:
            print(f"加载任务历史失败: {e}")
            return self._get_empty_history()

    def save_history(self, history):
        """保存任务历史"""
        try:
            with self.lock:
                history["last_updated"] = datetime.now().isoformat()
                self._update_statistics(history)
                with open(self.history_file, 'w', encoding='utf-8') as f:
                    json.dump(history, f, ensure_ascii=False, indent=2)
                return True
        except Exception as e:
            print(f"保存任务历史失败: {e}")
            return False

    def add_task(self, task_id, task_data, request_id, api_key_used):
        """添加新任务记录"""
        history = self.load_history()

        history["tasks"][task_id] = {
            "task_id": task_id,
            "name": task_data.get('name', ''),
            "request_id": request_id,
            "status": "pending",
            "video_mode": task_data.get('video_mode', 't2v'),
            "prompt": task_data.get('prompt', ''),
            "aspect_ratio": task_data.get('aspect_ratio', '9:16'),
            "duration": task_data.get('duration', 10),
            "api_key_used": self._mask_api_key(api_key_used),
            "web_app_id": task_data.get('web_app_id', 0),
            "timestamps": {
                "created_at": datetime.now().isoformat(),
                "submitted_at": datetime.now().isoformat(),
                "completed_at": None
            },
            "result": {
                "video_url": None,
                "error_message": None
            },
            "webhook_mode": True
        }

        return self.save_history(history)

    def update_task_status(self, task_id, status, video_url=None, error_message=None):
        """更新任务状态"""
        history = self.load_history()

        if task_id in history["tasks"]:
            task = history["tasks"][task_id]
            task["status"] = status

            if status in ("success", "failed"):
                task["timestamps"]["completed_at"] = datetime.now().isoformat()
                if status == "success" and video_url:
                    task["result"]["video_url"] = video_url
                elif status == "failed":
                    task["result"]["error_message"] = error_message

            return self.save_history(history)
        return False

    def get_task_by_request_id(self, request_id):
        """通过 request_id 查询任务"""
        history = self.load_history()
        for task_id, task in history["tasks"].items():
            if task.get("request_id") == request_id:
                return task
        return None

    def get_pending_tasks(self, older_than_minutes=10):
        """获取待查询的任务(超过指定分钟数)"""
        history = self.load_history()
        pending_tasks = []
        cutoff_time = datetime.now() - timedelta(minutes=older_than_minutes)

        for task_id, task in history["tasks"].items():
            if task.get("status") == "pending":
                submitted_at = datetime.fromisoformat(task["timestamps"]["submitted_at"])
                if submitted_at < cutoff_time:
                    pending_tasks.append(task)

        return pending_tasks

    def delete_task(self, task_id):
        """删除任务记录"""
        history = self.load_history()
        if task_id in history["tasks"]:
            del history["tasks"][task_id]
            return self.save_history(history)
        return False

    def clear_completed_tasks(self, days=7):
        """清理已完成的旧任务"""
        history = self.load_history()
        cutoff_time = datetime.now() - timedelta(days=days)
        tasks_to_delete = []

        for task_id, task in history["tasks"].items():
            if task.get("status") in ("success", "failed"):
                completed_at = task["timestamps"].get("completed_at")
                if completed_at:
                    completed_time = datetime.fromisoformat(completed_at)
                    if completed_time < cutoff_time:
                        tasks_to_delete.append(task_id)

        for task_id in tasks_to_delete:
            del history["tasks"][task_id]

        return self.save_history(history), len(tasks_to_delete)

    def _mask_api_key(self, api_key):
        """脱敏 API 密钥"""
        if len(api_key) > 10:
            return api_key[:4] + "****" + api_key[-4:]
        return "****"

    def _update_statistics(self, history):
        """更新统计信息"""
        tasks = list(history["tasks"].values())
        history["statistics"] = {
            "total_tasks": len(tasks),
            "completed_tasks": sum(1 for t in tasks if t["status"] == "success"),
            "pending_tasks": sum(1 for t in tasks if t["status"] == "pending"),
            "failed_tasks": sum(1 for t in tasks if t["status"] == "failed")
        }

    def _get_empty_history(self):
        """获取空历史记录结构"""
        return {
            "version": "2.0.0",
            "last_updated": datetime.now().isoformat(),
            "statistics": {
                "total_tasks": 0,
                "completed_tasks": 0,
                "pending_tasks": 0,
                "failed_tasks": 0
            },
            "tasks": {}
        }

# ==================== Video Download Thread ====================
class VideoDownloadThread(QThread):
    """视频下载线程"""
    finished = pyqtSignal(bool, str)

    def __init__(self, url, local_path, parent=None):
        super().__init__(parent)
        self.url = url
        self.local_path = local_path

    def run(self):
        """下载视频"""
        try:
            proxies = {"http": None, "https": None}

            response = requests.get(
                self.url,
                stream=True,
                timeout=60,
                proxies=proxies
            )
            response.raise_for_status()

            total_size = int(response.headers.get('content-length', 0))

            with open(self.local_path, 'wb') as f:
                if total_size > 0:
                    downloaded = 0
                    chunk_size = 8192
                    for chunk in response.iter_content(chunk_size=chunk_size):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                else:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)

            self.finished.emit(True, self.local_path)

        except Exception as e:
            print(f"Download error: {e}")
            self.finished.emit(False, "")

# ==================== Video Generation Worker ====================
class Sora2VideoGenerationWorker(QThread):
    """Sora2 单个视频生成工作线程"""
    progress_updated = pyqtSignal(int, str, str)
    task_finished = pyqtSignal(bool, str, dict, str)
    time_updated = pyqtSignal(str, str)
    log_updated = pyqtSignal(str)

    def __init__(self, task, task_id, api_key, api_manager, webhook_enabled=False, webhook_settings=None):
        super().__init__()
        self.task = task
        self.task_id = task_id
        self.api_key = api_key
        self.api_manager = api_manager
        self.webhook_enabled = webhook_enabled
        self.webhook_settings = webhook_settings or {}
        self.history_manager = Sora2TaskHistoryManager()
        self.start_time = None
        self.is_cancelled = False

    def log_message(self, message):
        """记录日志消息"""
        task_name = self.task.get('name', f'Task {self.task_id}')
        Utils.log_message(message, self.log_updated, task_name)

    def run(self):
        """运行 Sora2 视频生成任务"""
        self.start_time = time.time()
        task_name = self.task.get('name', f'Task {self.task_id}')

        try:
            self.log_message(f"Starting Sora2 video generation: {task_name}")
            self.progress_updated.emit(5, "Initializing task...", self.task_id)

            # 检查是否使用 WebHook 模式
            if self.webhook_enabled and self.webhook_settings.get("enabled", False):
                self.log_message("使用 WebHook 模式提交任务")
                self._run_webhook_mode()
                return

            if not self.api_key:
                self.log_message("API key not configured or empty")
                self.task_finished.emit(False, "API key not configured", {}, self.task_id)
                return

            prompt = self.task.get('prompt', '')
            video_mode = self.task.get('video_mode', 't2v')
            aspect_ratio = self.task.get('aspect_ratio', '9:16')
            duration = self.task.get('duration', 10)
            image_input = self.task.get('image_input', '')

            self.log_message(f"Mode: {'文生视频' if video_mode == 't2v' else '图生视频'}")
            self.log_message(f"Aspect Ratio: {aspect_ratio}")
            self.log_message(f"Duration: {duration}s")

            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)

            timestamp_str = datetime.now().strftime("%H%M%S")
            base_filename = f"sora2_{video_mode}_{timestamp_str}"

            if video_mode == "i2v":
                if not image_input:
                    self.log_message("图生视频 mode requires an image")
                    self.task_finished.emit(False, "图生视频 mode requires an image", {}, self.task_id)
                    return

                image_value = image_input
                if isinstance(image_input, str) and not image_input.startswith('http') and not image_input.startswith('data:'):
                    image_path = self.task.get('image_path', '')
                    if image_path and os.path.exists(image_path):
                        with open(image_path, 'rb') as f:
                            image_data = f.read()

                        max_size = 8 * 1024 * 1024
                        if len(image_data) > max_size:
                            self.log_message(f"Image too large ({len(image_data)} bytes), compressing...")
                            image_data = Utils.compress_image(image_data, self.log_updated)

                        import imghdr
                        detected_type = imghdr.what(None, image_data)
                        image_type = f'image/{detected_type}' if detected_type else 'image/jpeg'

                        base64_data = base64.b64encode(image_data).decode('utf-8')
                        image_value = f"data:{image_type};base64,{base64_data}"
                        self.log_message(f"Converted to data URL format ({image_type})")
                    else:
                        self.log_message("Cannot read image file")
                        self.task_finished.emit(False, "Cannot read image file", {}, self.task_id)
                        return

                self.progress_updated.emit(30, "Preparing image-to-video request...", self.task_id)

                bizyair_request_data = {
                    "web_app_id": self.api_manager.web_app_id_i2v,
                    "suppress_preview_output": True,
                    "input_values": {
                        "18:LoadImage.image": image_value,
                        "6:CR Prompt Text.prompt": prompt,
                        "54:BizyAir_Sora_V2_I2V_API.aspect_ratio": aspect_ratio,
                        "54:BizyAir_Sora_V2_I2V_API.duration": duration
                    }
                }
                self.log_message(f"Using 图生视频 mode, Web App ID: {self.api_manager.web_app_id_i2v}")

            else:
                self.progress_updated.emit(30, "Preparing text-to-video request...", self.task_id)

                bizyair_request_data = {
                    "web_app_id": self.api_manager.web_app_id_t2v,
                    "suppress_preview_output": True,
                    "input_values": {
                        "57:BizyAir_Sora_V2_T2V_API.prompt": prompt,
                        "57:BizyAir_Sora_V2_T2V_API.aspect_ratio": aspect_ratio,
                        "57:BizyAir_Sora_V2_T2V_API.duration": duration
                    }
                }
                self.log_message(f"Using 文生视频 mode, Web App ID: {self.api_manager.web_app_id_t2v}")

            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }

            api_url = "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
            if hasattr(self.api_manager, 'api_url') and self.api_manager.api_url:
                api_url = self.api_manager.api_url

            self.log_message(f"Sending BizyAir API request: {api_url}")
            self.log_message(f"Request data: {json.dumps(bizyair_request_data, ensure_ascii=False, indent=2)}")
            self.progress_updated.emit(40, "Sending API request...", self.task_id)

            try:
                proxies = {"http": None, "https": None}

                response = requests.post(
                    api_url,
                    headers=headers,
                    json=bizyair_request_data,
                    timeout=(10, 1800),  # 连接超时10秒，读取超时30分钟
                    proxies=proxies
                )

                self.log_message(f"API response status: {response.status_code}")
                response.raise_for_status()

                result_data = response.json()
                self.log_message(f"API response: {json.dumps(result_data, ensure_ascii=False, indent=2)}")

                request_id = result_data.get('request_id')
                status = result_data.get('status', '').lower()

                if not request_id:
                    error_msg = result_data.get('message', 'API response format error: missing request_id')
                    self.task_finished.emit(False, error_msg, {}, self.task_id)
                    return

                if status == 'failed':
                    error_info = result_data.get('error', result_data.get('message', 'Task execution failed'))
                    self.task_finished.emit(False, f"Video generation failed: {error_info}", {}, self.task_id)
                    return

                video_url = None

                if status == 'success' and 'outputs' in result_data:
                    outputs = result_data['outputs']
                    if outputs and len(outputs) > 0:
                        video_url = outputs[0].get('object_url', '')

                if not video_url:
                    self.progress_updated.emit(60, "Querying task status...", self.task_id)
                    video_url = self.check_video_status(request_id)

                if video_url:
                    self.progress_updated.emit(90, "Video URL obtained successfully", self.task_id)

                    result = {
                        'id': request_id,
                        'url': video_url,
                        'prompt': prompt,
                        'aspect_ratio': aspect_ratio,
                        'video_mode': video_mode,
                        'task_name': task_name,
                        'timestamp': datetime.now().isoformat(),
                        'base_filename': base_filename
                    }

                    self.progress_updated.emit(100, "Task completed!", self.task_id)
                    self.task_finished.emit(True, "Sora2 video generation successful", result, self.task_id)
                else:
                    self.task_finished.emit(False, "Sora2 video generation failed or timeout", {}, self.task_id)

            except requests.exceptions.HTTPError as http_err:
                error_msg = f"API request failed: HTTP {response.status_code}"
                try:
                    error_detail = response.json()
                    detail_msg = error_detail.get('message', 'Unknown error')
                    error_msg += f" - {detail_msg}"
                    self.log_message(f"Error response: {json.dumps(error_detail, ensure_ascii=False, indent=2)}")
                except:
                    error_msg += f" - {response.text[:200]}"
                    self.log_message(f"Error response text: {response.text[:500]}")
                self.log_message(f"HTTP Error: {error_msg}")
                self.task_finished.emit(False, error_msg, {}, self.task_id)

            except requests.exceptions.Timeout:
                self.log_message("API request timeout")
                self.task_finished.emit(False, "API request timeout", {}, self.task_id)

            except requests.exceptions.RequestException as e:
                self.log_message(f"Network error: {str(e)}")
                self.task_finished.emit(False, f"Network error: {str(e)}", {}, self.task_id)

            except Exception as e:
                self.log_message(f"Task execution exception: {str(e)} - {traceback.format_exc()}")
                self.task_finished.emit(False, f"Task execution exception: {str(e)}", {}, self.task_id)

        except Exception as e:
            self.log_message(f"Task initialization exception: {str(e)} - {traceback.format_exc()}")
            self.task_finished.emit(False, f"Task initialization exception: {str(e)}", {}, self.task_id)

    def check_video_status(self, request_id):
        """查询 BizyAir 任务状态"""
        max_attempts = 90  #最多轮询 90次
        check_interval = 20  #每次间隔 20秒

        for attempt in range(max_attempts):
            if self.is_cancelled:
                self.log_message("Task cancelled")
                return None

            try:
                headers = {
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}"
                }

                response = requests.get(
                    f"https://api.bizyair.cn/w/v1/webapp/task/openapi/query?request_id={request_id}",
                    headers=headers,
                    timeout=30,
                    proxies={"http": None, "https": None}
                )

                response.raise_for_status()

                data = response.json()
                status = data.get('status', '').lower()

                self.progress_updated.emit(
                    min(90, 60 + (attempt * 30 // max_attempts)),
                    f"Checking progress... ({status.capitalize()})",
                    self.task_id
                )

                if status == 'success' and 'outputs' in data:
                    outputs = data['outputs']
                    if outputs and len(outputs) > 0:
                        video_url = outputs[0].get('object_url', '')
                        if video_url:
                            self.log_message(f"Video generation completed: {video_url}")
                            return video_url

                elif status == 'failed':
                    error_info = data.get('error', 'Generation failed')
                    self.log_message(f"Video generation failed: {error_info}")
                    return None

                else:
                    self.log_message(f"Video generating... ({status.capitalize()}) - Check {attempt+1}")

            except requests.exceptions.RequestException as e:
                self.log_message(f"Status query exception: {str(e)}")

            if attempt < max_attempts - 1:
                time.sleep(check_interval)

        self.log_message(f"Video generation timeout ({max_attempts * check_interval // 60} minutes)")
        return None

    def _run_webhook_mode(self):
        """WebHook 模式处理"""
        try:
            task_name = self.task.get('name', f'Task {self.task_id}')
            video_mode = self.task.get('video_mode', 't2v')

            # 构建 API 请求数据
            request_data = self._build_request_data()

            # 构建请求头(包含 WebHook 配置)
            headers = self._build_headers_with_webhook()

            # 发送请求
            api_url = "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
            if hasattr(self.api_manager, 'api_url') and self.api_manager.api_url:
                api_url = self.api_manager.api_url

            self.log_message(f"[WebHook] 发送请求到: {api_url}")
            self.progress_updated.emit(20, "WebHook 模式: 提交中...", self.task_id)

            proxies = {"http": None, "https": None}
            response = requests.post(
                api_url,
                headers=headers,
                json=request_data,
                timeout=(10, 30),
                proxies=proxies
            )

            self.log_message(f"[WebHook] 响应状态码: {response.status_code}")
            response.raise_for_status()

            result_data = response.json()
            self.log_message(f"[WebHook] API 响应: {json.dumps(result_data, ensure_ascii=False, indent=2)}")

            request_id = result_data.get('request_id')

            if not request_id:
                error_msg = result_data.get('message', 'API response format error: missing request_id')
                self.task_finished.emit(False, error_msg, {}, self.task_id)
                return

            # 保存到任务历史
            web_app_id = self.api_manager.web_app_id_t2v if video_mode == 't2v' else self.api_manager.web_app_id_i2v
            self.task['web_app_id'] = web_app_id
            self.history_manager.add_task(self.task_id, self.task, request_id, self.api_key)

            self.progress_updated.emit(100, "WebHook 模式: 任务已提交", self.task_id)

            result = {
                'id': request_id,
                'url': None,
                'prompt': self.task.get('prompt', ''),
                'aspect_ratio': self.task.get('aspect_ratio', '9:16'),
                'video_mode': video_mode,
                'task_name': task_name,
                'timestamp': datetime.now().isoformat(),
                'webhook_mode': True,
                'request_id': request_id
            }

            self.task_finished.emit(True, "WebHook 任务已提交，等待回调", result, self.task_id)

        except requests.exceptions.HTTPError as http_err:
            error_msg = f"API request failed: HTTP {response.status_code}"
            try:
                error_detail = response.json()
                detail_msg = error_detail.get('message', 'Unknown error')
                error_msg += f" - {detail_msg}"
            except:
                error_msg += f" - {response.text[:200]}"
            self.log_message(f"[WebHook] HTTP Error: {error_msg}")

            # 检查是否回退到轮询模式
            if self.webhook_settings.get("fallback_to_polling", False):
                self.log_message(f"[WebHook] 回退到轮询模式")
                self._run_polling_fallback()
            else:
                self.task_finished.emit(False, error_msg, {}, self.task_id)

        except Exception as e:
            self.log_message(f"[WebHook] 异常: {str(e)}")

            # 检查是否回退到轮询模式
            if self.webhook_settings.get("fallback_to_polling", False):
                self.log_message(f"[WebHook] 回退到轮询模式")
                self._run_polling_fallback()
            else:
                self.task_finished.emit(False, f"WebHook 提交失败: {str(e)}", {}, self.task_id)

    def _run_polling_fallback(self):
        """回退到轮询模式"""
        try:
            self.log_message("[轮询模式] 启动轮询查询...")
            self.progress_updated.emit(10, "轮询模式: 准备查询...", self.task_id)

            # 重新执行原有的轮询逻辑
            # 这里需要重新构建请求数据并获取 request_id
            request_data = self._build_request_data()
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }

            api_url = "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
            if hasattr(self.api_manager, 'api_url') and self.api_manager.api_url:
                api_url = self.api_manager.api_url

            proxies = {"http": None, "https": None}
            response = requests.post(
                api_url,
                headers=headers,
                json=request_data,
                timeout=(10, 1800),
                proxies=proxies
            )

            response.raise_for_status()
            result_data = response.json()
            request_id = result_data.get('request_id')

            if not request_id:
                self.task_finished.emit(False, "轮询模式: 缺少 request_id", {}, self.task_id)
                return

            video_url = self.check_video_status(request_id)

            if video_url:
                self.progress_updated.emit(100, "轮询模式: 任务完成", self.task_id)
                result = {
                    'id': request_id,
                    'url': video_url,
                    'prompt': self.task.get('prompt', ''),
                    'aspect_ratio': self.task.get('aspect_ratio', '9:16'),
                    'video_mode': self.task.get('video_mode', 't2v'),
                    'task_name': self.task.get('name', f'Task {self.task_id}'),
                    'timestamp': datetime.now().isoformat(),
                    'webhook_mode': False
                }
                self.task_finished.emit(True, "轮询模式: 视频生成成功", result, self.task_id)
            else:
                self.task_finished.emit(False, "轮询模式: 视频生成失败或超时", {}, self.task_id)

        except Exception as e:
            self.log_message(f"[轮询模式] 异常: {str(e)}")
            self.task_finished.emit(False, f"轮询模式: {str(e)}", {}, self.task_id)

    def _build_headers_with_webhook(self):
        """构建请求头(包含 WebHook 配置)"""
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}"
        }

        if self.webhook_settings.get("enabled", False):
            webhook_url = self.webhook_settings.get("url", "")
            webhook_token = self.webhook_settings.get("token", "")

            if webhook_url:
                headers["X-BizyAir-Task-WebHook-Url"] = webhook_url
            if webhook_token:
                headers["X-BizyAir-Task-Authorization"] = f"Bearer {webhook_token}"

        return headers

    def _build_request_data(self):
        """构建 API 请求数据"""
        video_mode = self.task.get('video_mode', 't2v')
        prompt = self.task.get('prompt', '')
        aspect_ratio = self.task.get('aspect_ratio', '9:16')
        duration = self.task.get('duration', 10)
        image_input = self.task.get('image_input', '')

        if video_mode == "i2v":
            return {
                "web_app_id": self.api_manager.web_app_id_i2v,
                "suppress_preview_output": True,
                "input_values": {
                    "18:LoadImage.image": image_input,
                    "6:CR Prompt Text.prompt": prompt,
                    "54:BizyAir_Sora_V2_I2V_API.aspect_ratio": aspect_ratio,
                    "54:BizyAir_Sora_V2_I2V_API.duration": duration
                }
            }
        else:
            return {
                "web_app_id": self.api_manager.web_app_id_t2v,
                "suppress_preview_output": True,
                "input_values": {
                    "57:BizyAir_Sora_V2_T2V_API.prompt": prompt,
                    "57:BizyAir_Sora_V2_T2V_API.aspect_ratio": aspect_ratio,
                    "57:BizyAir_Sora_V2_T2V_API.duration": duration
                }
            }

    def cancel(self):
        """取消 task"""
        self.is_cancelled = True

# ==================== Simple Batch Manager ====================
class Sora2BatchManager(QObject):
    """Sora2 简单批量任务管理器"""
    all_tasks_finished = pyqtSignal()
    task_progress = pyqtSignal(int, str, str)
    task_finished = pyqtSignal(bool, str, dict, str)
    task_time_updated = pyqtSignal(str, str)
    log_updated = pyqtSignal(str)
    batch_progress_updated = pyqtSignal(int, int)

    def __init__(self, api_manager=None):
        super().__init__()
        self.workers = {}
        self.completed_tasks = 0
        self.total_tasks = 0
        self.api_manager = api_manager if api_manager is not None else Sora2APIKeyManager()
        self.pending_tasks = []  # 待启动的任务队列
        self.task_timer = QTimer(self)  # 任务启动定时器
        self.task_timer.timeout.connect(self.start_next_task)

    def log_message(self, message):
        Utils.log_message(message, self.log_updated, "Sora2 Batch Manager")

    def start_next_task(self):
        """启动下一个任务（定时器回调）"""
        if not self.pending_tasks:
            self.task_timer.stop()
            return

        task_id, task, api_key = self.pending_tasks.pop(0)

        worker = Sora2VideoGenerationWorker(task, task_id, api_key, self.api_manager)
        self.workers[task_id] = worker

        worker.progress_updated.connect(self.task_progress)
        worker.task_finished.connect(self.on_single_task_finished)
        worker.time_updated.connect(self.task_time_updated)
        worker.log_updated.connect(self.log_updated)

        worker.start()
        self.log_message(f"Started task {task_id}")

        # 如果还有待启动的任务，继续定时器
        if self.pending_tasks:
            self.task_timer.start(300000)  # 300秒后启动下一个

    def add_tasks(self, task_map, key_file=None):
        """添加任务"""
        new_tasks_count = len(task_map)
        if new_tasks_count == 0:
            return

        self.total_tasks += new_tasks_count

        if key_file:
            self.api_manager.load_keys_from_file(key_file)

        available_keys = self.api_manager.get_all_keys()
        if not available_keys:
            self.log_message("Error: No available API keys")
            for task_id in task_map.keys():
                self.task_finished.emit(False, "No available API keys", {}, task_id)
            if not self.workers:
                self.all_tasks_finished.emit()
            return

        self.log_message(f"Adding {new_tasks_count} new tasks")
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

        # 将所有任务加入队列
        for i, (task_id, task) in enumerate(task_map.items()):
            key_index = i % len(available_keys)
            api_key = available_keys[key_index]
            self.pending_tasks.append((task_id, task, api_key))

        # 启动第一个任务
        if self.pending_tasks:
            self.start_next_task()

    def on_single_task_finished(self, success, message, result_data, task_id):
        """单个任务完成回调"""
        self.completed_tasks += 1
        self.update_batch_progress()

        self.task_finished.emit(success, message, result_data, task_id)

        if task_id in self.workers:
            worker = self.workers.pop(task_id)
            if worker is not None:
                if worker.isRunning():
                    worker.quit()
                    worker.wait(3000)
                worker.deleteLater()

        if self.completed_tasks >= self.total_tasks:
            self.log_message(f"All tasks completed! 成功: {self.completed_tasks}/{self.total_tasks}")
            self.all_tasks_finished.emit()
            self.completed_tasks = 0
            self.total_tasks = 0
            self.workers.clear()

    def update_batch_progress(self):
        """Update batch progress"""
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

    def cancel_all_tasks(self):
        """取消 all tasks"""
        self.log_message("取消ling all tasks...")

        for worker in self.workers.values():
            if worker is not None:
                worker.cancel()

        for task_id, worker in list(self.workers.items()):
            if worker is not None and worker.isRunning():
                self.log_message(f"Waiting for task {task_id} to end...")
                worker.quit()
                worker.wait(2000)
            if worker is not None:
                worker.deleteLater()
            self.workers.pop(task_id, None)

        self.log_message("All tasks cleaned up.")
        self.completed_tasks = self.total_tasks
        self.batch_progress_updated.emit(self.total_tasks, self.total_tasks)
        self.all_tasks_finished.emit()

# ==================== Image Drop Widget ====================
class Sora2ImageDropWidget(QFrame):
    """Sora2 image drag and drop widget"""
    image_dropped = pyqtSignal(str, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.current_image_path = ""
        self.base64_data = ""
        self.current_image_data = ""
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 15, 15, 15)
        layout.setSpacing(10)

        # 创建一个容器来整合拖拽区域和按钮
        container = QFrame()
        container.setFixedSize(280, 200)
        container.setStyleSheet("""
            QFrame {
                border: 2px dashed #606060;
                border-radius: 10px;
                background-color: #252525;
            }
            QFrame:hover {
                border: 2px dashed #4a90e2;
                background-color: #2a2a3a;
            }
        """)

        container_layout = QVBoxLayout(container)
        container_layout.setContentsMargins(10, 10, 10, 10)
        container_layout.setSpacing(10)

        # 图片预览标签
        self.image_label = QLabel()
        self.image_label.setFixedSize(260, 140)
        self.image_label.setStyleSheet("""
            QLabel {
                border: none;
                border-radius: 6px;
                background-color: #1e1e1e;
                color: #888888;
                font-size: 12px;
            }
        """)
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setText("📁\n\n拖拽图片到这里\n或点击下方按钮选择")
        self.image_label.setCursor(Qt.PointingHandCursor)
        self.image_label.mousePressEvent = self.select_file

        container_layout.addWidget(self.image_label, alignment=Qt.AlignCenter)

        # 选择按钮
        self.select_btn = PushButton("📷 选择图片")
        self.select_btn.setFixedHeight(32)
        self.select_btn.setStyleSheet("""
            PushButton {
                background-color: #3a3a3a;
                color: #ffffff;
                border: 1px solid #505050;
                border-radius: 6px;
                font-size: 12px;
            }
            PushButton:hover {
                background-color: #4a4a4a;
                border: 1px solid #606060;
            }
            PushButton:pressed {
                background-color: #2a2a2a;
            }
        """)
        self.select_btn.clicked.connect(self.select_file)
        container_layout.addWidget(self.select_btn)

        # 使容器可点击
        container.mousePressEvent = self.on_container_clicked

        layout.addWidget(container, alignment=Qt.AlignCenter)

    def on_container_clicked(self, event):
        """容器点击事件"""
        # 如果点击的不是按钮，则触发选择文件
        self.select_file()

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dragLeaveEvent(self, event):
        pass

    def dropEvent(self, event: QDropEvent):
        files = [u.toLocalFile() for u in event.mimeData().urls()]
        for file_path in files:
            if file_path.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp')):
                self.load_image(file_path)
                break

    def select_file(self, event=None):
        """选择图片文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择图片文件",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"
        )
        if file_path:
            self.load_image(file_path)

    def load_image(self, file_path):
        """加载图片并显示"""
        try:
            pixmap = QPixmap(file_path)
            if not pixmap.isNull():
                # 缩放图片以适应标签大小
                scaled_pixmap = pixmap.scaled(
                    250, 130,
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                self.image_label.setPixmap(scaled_pixmap)

                with open(file_path, 'rb') as f:
                    image_data = f.read()
                    compressed_data = Utils.compress_image(image_data)
                    self.base64_data = base64.b64encode(compressed_data).decode('utf-8')

                self.current_image_path = file_path
                self.current_image_data = self.base64_data
                self.image_dropped.emit(file_path, self.base64_data)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载图片失败: {str(e)}")

    def clear_image(self):
        """清除图片"""
        self.image_label.clear()
        self.image_label.setText("📁\n\n拖拽图片到这里\n或点击下方按钮选择")
        self.current_image_path = ""
        self.base64_data = ""
        self.current_image_data = ""

# ==================== Task Status Card ====================
class Sora2TaskStatusCard(CardWidget):
    """Sora2 task status display card"""

    def __init__(self, task_id, task_name, task_params, parent=None):
        super().__init__(parent)
        self.task_id = task_id
        self.task_name = task_name
        self.task_params = task_params
        self.progress = 0
        self.time_string = "00:00:00"
        self.status = "Waiting to start"
        self.key_source = "文件密钥"

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_timer)
        self.start_ts = None
        self.is_timing = False

        self.init_ui()

    def init_ui(self):
        """初始化界面"""
        self.setMinimumHeight(145)
        self.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
        self.setStyleSheet("""
            CardWidget {
                background-color: #2A2A2A;
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

        # Row 1: Task name (left) and Status + Key type (right)
        top_layout = QHBoxLayout()

        self.name_label = StrongBodyLabel(self.task_name)
        self.name_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: 600;")
        top_layout.addWidget(self.name_label)

        top_layout.addStretch()

        # 右上角容器：状态和密钥类型在同一行
        right_container = QWidget()
        right_layout = QHBoxLayout(right_container)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(8)

        self.status_label = CaptionLabel(self.status)
        self.status_label.setStyleSheet("color: #ffffff; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #333333; border-radius: 4px;")
        right_layout.addWidget(self.status_label)

        self.key_type_label = CaptionLabel(self.key_source)
        self.key_type_label.setStyleSheet("color: #4a90e2; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #2a3a4a; border-radius: 4px;")
        right_layout.addWidget(self.key_type_label)

        top_layout.addWidget(right_container)
        layout.addLayout(top_layout)

        # Row 2: Task parameters
        params_layout = QHBoxLayout()

        video_mode = self.task_params.get('video_mode', 't2v')
        aspect_ratio = self.task_params.get('aspect_ratio', '9:16')
        duration = self.task_params.get('duration', 10)

        params_text = f"{'图生视频' if video_mode == 'i2v' else '文生视频'} - {aspect_ratio} - {duration}秒"
        self.params_label = CaptionLabel(params_text)
        self.params_label.setStyleSheet("color: #888888; font-size: 12px; background: #353535;")
        params_layout.addWidget(self.params_label)

        params_layout.addStretch()
        layout.addLayout(params_layout)

        # Row 3: Prompt
        prompt = self.task_params.get('prompt', '')
        if prompt:
            if len(prompt) > 85:
                prompt_display = prompt[:80] + "..."
            else:
                prompt_display = prompt

            self.prompt_label = CaptionLabel(prompt_display)
            self.prompt_label.setStyleSheet("color: #aaaaaa; font-size: 11px; background: #353535;")
            self.prompt_label.setWordWrap(False)
            layout.addWidget(self.prompt_label)

        self.progress_msg_label = CaptionLabel("")
        self.progress_msg_label.setStyleSheet("color: #999999; font-size: 11px; min-height: 14px; background: #353535;")
        layout.addWidget(self.progress_msg_label)

        # Row 4: Progress bar and time
        progress_layout = QHBoxLayout()

        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(4)
        progress_layout.addWidget(self.progress_bar)

        self.time_label = CaptionLabel(self.time_string)
        self.time_label.setStyleSheet("color: #666666; font-size: 11px; min-width: 70px;")
        self.time_label.setAlignment(Qt.AlignRight)
        progress_layout.addWidget(self.time_label)

        layout.addLayout(progress_layout)

    def update_progress(self, progress, message):
        """Update progress"""
        self.progress = progress
        self.progress_bar.setValue(progress)

        if progress < 100:
            self.status = "生成中"
            if progress >= 50:
                self.status_label.setStyleSheet("color: #ffffff; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #ffc107; border-radius: 4px;height: 40px;")
            else:
                self.status_label.setStyleSheet("color: #ffffff; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #17a2b8; border-radius: 4px;height: 40px;")

            self.progress_msg_label.setText(message)

        self.status_label.setText(self.status)

    def start_timing(self):
        """Start timing"""
        if not self.is_timing:
            self.is_timing = True
            self.start_ts = time.time()
            self.timer.start(1000)

    def stop_timing(self):
        """Stop timing"""
        if self.is_timing:
            self.is_timing = False
            self.timer.stop()
            self.update_timer()

    def update_timer(self):
        """Update time display"""
        if self.start_ts:
            elapsed = time.time() - self.start_ts
            hours = int(elapsed // 3600)
            minutes = int((elapsed % 3600) // 60)
            seconds = int(elapsed % 60)
            self.time_string = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            self.time_label.setText(self.time_string)

    def update_time(self, time_string):
        """Update time display"""
        self.time_string = time_string
        self.time_label.setText(time_string)

    def set_key_source(self, key_source):
        """Set key source type"""
        self.key_source = key_source
        self.key_type_label.setText(key_source)

        if key_source == "系统变量":
            self.key_type_label.setStyleSheet("color: #17a2b8; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #e6f7ff; border-radius: 4px;height: 40px;")
        else:
            self.key_type_label.setStyleSheet("color: #28a745; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #e8f5e8; border-radius: 4px;height: 40px;")

    def set_completed(self, success=True, message=""):
        """Set task completed status"""
        self.progress = 100
        self.progress_bar.setValue(100)
        self.progress_msg_label.setText(message)

        if success:
            self.status = "已完成"
            self.status_label.setStyleSheet("color: #ffffff; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #28a745; border-radius: 4px;")
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
            self.status_label.setStyleSheet("color: #ffffff; font-size: 11px; font-weight: 600; padding: 4px 8px; background: #dc3545; border-radius: 6px;")
            self.setStyleSheet("""
                CardWidget {
                    background-color: #3a2a2a;
                    border: 1px solid #dc3545;
                    border-radius: 8px;
                    margin: 2px;
                }
            """)
        self.status_label.setText(self.status)

# ==================== Main Widget ====================
class Sora2VideoGenerationWidget(QWidget):
    """Sora2 视频生成主组件"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.batch_manager = None
        self.api_manager = Sora2APIKeyManager()
        self.settings_manager = Sora2SettingsManager()

        api_settings = self.settings_manager.get_api_settings()
        self.api_manager.api_url = api_settings.get("api_url",
            "https://api.bizyair.cn/w/v1/webapp/task/openapi/create")

        self.key_file_path = None

        self.task_status_cards = {}
        self.video_result_cards = []

        self.init_ui()
        self.load_settings()
        self.init_batch_manager()

        # 添加初始化日志（延迟到 UI 完全初始化后）
        from PyQt5.QtCore import QTimer
        QTimer.singleShot(100, self.init_log_display)

    def init_log_display(self):
        """初始化日志显示"""
        self.add_log("=== Sora2 视频生成系统已启动 ===")
        self.add_log(f"初始化时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.add_log(f"文生视频 Web App ID: {self.api_manager.web_app_id_t2v}")
        self.add_log(f"图生视频 Web App ID: {self.api_manager.web_app_id_i2v}")
        self.add_log(f"API URL: {self.api_manager.api_url}")
        self.add_log("系统就绪，请输入提示词开始生成视频")
        self.add_log("")

    def init_batch_manager(self):
        """Initialize batch manager"""
        self.batch_manager = Sora2BatchManager(self.api_manager)
        self.batch_manager.task_progress.connect(self.update_task_progress)
        self.batch_manager.task_finished.connect(self.on_task_finished)
        self.batch_manager.task_time_updated.connect(self.update_task_time)
        self.batch_manager.log_updated.connect(self.add_log)
        self.batch_manager.batch_progress_updated.connect(self.update_batch_progress)
        self.batch_manager.all_tasks_finished.connect(self.on_all_tasks_finished)

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(8, 8, 8, 8)

        # Top bar
        top_bar = self.create_top_bar()
        layout.addWidget(top_bar)

        # Main splitter
        splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(splitter)

        # Left control panel
        left_panel = self.create_control_panel()
        splitter.addWidget(left_panel)

        # Right result panel
        right_panel = self.create_result_panel()
        splitter.addWidget(right_panel)

        splitter.setSizes([450, 750])

    def create_top_bar(self):
        """Create top control bar"""
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

        title = QLabel("Sora2 AI 视频生成")
        title.setStyleSheet("font-size: 18px; font-weight: bold; color: #ffffff;")
        layout.addWidget(title)

        layout.addSpacing(20)

        self.single_generate_btn = PrimaryPushButton("单个生成")
        self.single_generate_btn.setFixedSize(100, 32)
        self.single_generate_btn.clicked.connect(self.generate_single_video)
        layout.addWidget(self.single_generate_btn)

        self.batch_generate_btn = PushButton("批量生成")
        self.batch_generate_btn.setFixedSize(100, 32)
        self.batch_generate_btn.clicked.connect(self.generate_batch_videos)
        layout.addWidget(self.batch_generate_btn)

        self.api_settings_btn = PushButton(FluentIcon.SETTING, "API设置")
        self.api_settings_btn.setFixedSize(100, 32)
        self.api_settings_btn.clicked.connect(self.show_api_settings_dialog)
        layout.addWidget(self.api_settings_btn)

        self.history_btn = PushButton(FluentIcon.HISTORY, "任务历史")
        self.history_btn.setFixedSize(110, 32)
        self.history_btn.clicked.connect(self.show_task_history)
        layout.addWidget(self.history_btn)

        self.key_status_label = QLabel("密钥未配置")
        self.key_status_label.setStyleSheet("color: #dc3545; font-size: 12px; padding: 6px 12px; background: #fff3cd; border-radius: 4px;")
        layout.addWidget(self.key_status_label)

        layout.addStretch()

        return bar

    def create_control_panel(self):
        """创建左侧控制面板"""
        panel = QFrame()
        panel.setStyleSheet("""
            QFrame {
                background-color: #2A2A2A;
                border-radius: 8px;
                margin: 2px;
            }
        """)
        layout = QVBoxLayout(panel)
        layout.setSpacing(15)
        layout.setContentsMargins(15, 15, 15, 15)

        # 视频模式和宽高比选择（同一行）
        mode_ratio_widget = QWidget()
        mode_ratio_layout = QHBoxLayout(mode_ratio_widget)
        mode_ratio_layout.setContentsMargins(0, 0, 0, 0)
        mode_ratio_layout.setSpacing(15)

        # 视频模式选择
        self.video_mode_combo = ComboBox()
        self.video_mode_combo.addItems(["文生视频", "图生视频"])
        self.video_mode_combo.setFixedHeight(35)
        self.video_mode_combo.currentIndexChanged.connect(self.on_video_mode_changed)
        mode_ratio_layout.addWidget(self.video_mode_combo, 1)

        # 宽高比选择
        ratio_widget = QWidget()
        ratio_layout = QHBoxLayout(ratio_widget)
        ratio_layout.setContentsMargins(0, 0, 0, 0)
        ratio_layout.setSpacing(20)

        self.aspect_ratio_9_16 = QRadioButton("9:16 (竖屏)")
        self.aspect_ratio_9_16.setChecked(True)
        self.aspect_ratio_9_16.setStyleSheet("QRadioButton { color: #ffffff; font-size: 13px; }")

        self.aspect_ratio_16_9 = QRadioButton("16:9 (横屏)")
        self.aspect_ratio_16_9.setStyleSheet("QRadioButton { color: #ffffff; font-size: 13px; }")

        ratio_layout.addWidget(self.aspect_ratio_9_16)
        ratio_layout.addWidget(self.aspect_ratio_16_9)

        mode_ratio_layout.addWidget(ratio_widget, 1)

        # 视频时长选择
        self.duration_combo = ComboBox()
        self.duration_combo.addItems(["10秒", "15秒"])
        self.duration_combo.setCurrentIndex(0)
        self.duration_combo.setFixedHeight(35)
        mode_ratio_layout.addWidget(self.duration_combo, 1)

        layout.addWidget(mode_ratio_widget)

        # 图片上传区域（仅图生视频模式显示）
        # 使用容器以便控制显示/隐藏
        self.image_container = QWidget()
        image_layout = QVBoxLayout(self.image_container)
        image_layout.setContentsMargins(0, 0, 0, 0)
        image_layout.setSpacing(10)

        self.image_drop_widget = Sora2ImageDropWidget()
        image_layout.addWidget(self.image_drop_widget)

        clear_image_btn = PushButton("清除图片")
        clear_image_btn.clicked.connect(self.clear_image)
        image_layout.addWidget(clear_image_btn)

        self.image_container.setVisible(False)
        layout.addWidget(self.image_container)

        # 视频提示词输入
        self.prompt_edit = QTextEdit()
        self.prompt_edit.setPlaceholderText("请输入视频生成提示词，例如：\n- 美丽的日落场景，海浪轻轻拍打着沙滩\n- 可爱的猫咪在阳光下玩耍\n- 科幻风格未来城市，霓虹灯闪烁")
        self.prompt_edit.setFixedHeight(120)
        self.prompt_edit.setStyleSheet("""
            QTextEdit {
                margin-top:-130px;
                margin-bottom:20px;
                font-size: 18px;
                line-height: 1.5;
                padding: 8px;
                background: #1e1e1e;
                border-radius: 4px;
            }
        """)
        layout.addWidget(self.prompt_edit)

        # 批量任务
        batch_label = QLabel("批量任务")
        batch_label.setStyleSheet("QLabel { color: #ffffff; font-size: 14px; font-weight: bold; }")
        layout.addWidget(batch_label)

        self.batch_list = QTextEdit()
        self.batch_list.setPlaceholderText("批量任务格式（每行一个任务）：\n提示词1\n提示词2\n提示词3\n\n注：图生视频模式格式：图片路径|提示词")
        self.batch_list.setMinimumHeight(150)
        self.batch_list.setStyleSheet("""
            QTextEdit {
                font-size: 18px;
                line-height: 1.5;
                padding: 8px;
                background: #1e1e1e;
                border-radius: 4px;
            }
        """)
        layout.addWidget(self.batch_list)

        load_batch_file_btn = PushButton("从文件加载")
        load_batch_file_btn.clicked.connect(self.load_batch_from_file)
        layout.addWidget(load_batch_file_btn)

        layout.addStretch()

        return panel

    def create_result_panel(self):
        """Create right result panel"""
        panel = QFrame()
        panel.setStyleSheet("""
            QFrame {
                background-color: #1e1e1e;
                border-radius: 8px;
                margin: 2px;
            }
        """)
        layout = QVBoxLayout(panel)
        layout.setSpacing(15)
        layout.setContentsMargins(15, 15, 15, 15)

        # Progress
        progress_group = QGroupBox("生成进度")
        progress_group.setStyleSheet("""
            QGroupBox {
                color: #ffffff;
                font-size: 14px;
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 6px;
                margin-top: 10px;
                padding-top: 10px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px;
            }
        """)
        progress_layout = QVBoxLayout()

        self.batch_progress_label = QLabel("批量进度：0/0")
        self.batch_progress_label.setStyleSheet("color: #ffffff; font-size: 13px;")
        progress_layout.addWidget(self.batch_progress_label)

        self.batch_progress_bar = ProgressBar()
        self.batch_progress_bar.setFixedHeight(8)
        progress_layout.addWidget(self.batch_progress_bar)

        progress_group.setLayout(progress_layout)
        layout.addWidget(progress_group)

        # Tab Widget for Tasks, Results and Logs
        self.tab_widget = QTabWidget()
        self.tab_widget.setStyleSheet("""
            QTabWidget::pane {
                border: 1px solid #404040;
                border-radius: 6px;
                background-color: #1e1e1e;
            }
            QTabBar::tab {
                background-color: #2a2a2a;
                color: #888888;
                padding: 8px 16px;
                border: 1px solid #404040;
                border-bottom: none;
                border-top-left-radius: 4px;
                border-top-right-radius: 4px;
                margin-right: 2px;
                font-size: 13px;
            }
            QTabBar::tab:selected {
                background-color: #1e1e1e;
                color: #ffffff;
                font-weight: bold;
            }
            QTabBar::tab:hover {
                background-color: #333333;
                color: #ffffff;
            }
        """)

        # Tab 1: Task Status
        tasks_tab = QWidget()
        tasks_tab_layout = QVBoxLayout(tasks_tab)
        tasks_tab_layout.setContentsMargins(10, 10, 10, 10)
        tasks_tab_layout.setSpacing(10)

        self.tasks_scroll = QScrollArea()
        self.tasks_scroll.setWidgetResizable(True)
        self.tasks_scroll.setStyleSheet("""
            QScrollArea {
                border: none;
                background-color: transparent;
            }
        """)

        self.tasks_widget = QWidget()
        self.tasks_layout = QVBoxLayout(self.tasks_widget)
        self.tasks_layout.setSpacing(10)
        self.tasks_layout.addStretch()
        self.tasks_scroll.setWidget(self.tasks_widget)

        tasks_tab_layout.addWidget(self.tasks_scroll)
        self.tab_widget.addTab(tasks_tab, "任务状态")

        # Tab 2: Video Results
        results_tab = QWidget()
        results_tab_layout = QVBoxLayout(results_tab)
        results_tab_layout.setContentsMargins(10, 10, 10, 10)
        results_tab_layout.setSpacing(10)

        self.results_scroll = QScrollArea()
        self.results_scroll.setWidgetResizable(True)
        self.results_scroll.setStyleSheet("""
            QScrollArea {
                border: none;
                background-color: transparent;
            }
        """)

        self.results_widget = QWidget()
        self.results_layout = QVBoxLayout(self.results_widget)
        self.results_layout.setSpacing(10)
        self.results_layout.addStretch()
        self.results_scroll.setWidget(self.results_widget)

        results_tab_layout.addWidget(self.results_scroll)
        self.tab_widget.addTab(results_tab, "生成结果")

        # Tab 3: Logs
        logs_tab = QWidget()
        logs_tab_layout = QVBoxLayout(logs_tab)
        logs_tab_layout.setContentsMargins(10, 10, 10, 10)
        logs_tab_layout.setSpacing(10)

        # Log controls
        log_controls_layout = QHBoxLayout()
        log_controls_layout.setSpacing(10)

        clear_log_btn = PushButton("清空日志")
        clear_log_btn.setFixedHeight(28)
        clear_log_btn.clicked.connect(self.clear_log)
        log_controls_layout.addWidget(clear_log_btn)

        export_log_btn = PushButton("导出日志")
        export_log_btn.setFixedHeight(28)
        export_log_btn.clicked.connect(self.export_log)
        log_controls_layout.addWidget(export_log_btn)

        log_controls_layout.addStretch()
        logs_tab_layout.addLayout(log_controls_layout)

        # Log text area
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setHtml("<!DOCTYPE html><html><body style='background-color: #0d0d0d; margin: 0; padding: 0;'>")
        self.log_text.setStyleSheet("""
            QTextEdit {
                background-color: #0d0d0d;
                font-family: 'Monaco', 'Menlo', 'Consolas', monospace;
                font-size: 12px;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 10px;
            }
            QScrollBar:vertical {
                background-color: #1e1e1e;
                width: 12px;
                border-radius: 6px;
            }
            QScrollBar::handle:vertical {
                background-color: #404040;
                border-radius: 6px;
                min-height: 30px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #505050;
            }
        """)
        logs_tab_layout.addWidget(self.log_text)

        # 日志颜色说明
        legend_label = QLabel(
            "<span style='color: #ff6b6b;'>● 响应</span> | "
            "<span style='color: #ffd93d;'>● 警告</span> | "
            "<span style='color: #4d96ff;'>● API</span> | "
            "<span style='color: #6bcb77;'>● 成功</span> | "
            "<span style='color: #9b59b6;'>● 完成</span>"
        )
        legend_label.setStyleSheet("font-size: 11px; padding: 5px 0;")
        logs_tab_layout.addWidget(legend_label)

        self.tab_widget.addTab(logs_tab, "日志")

        layout.addWidget(self.tab_widget, 1)

        return panel

    def on_video_mode_changed(self, index):
        """视频模式切换事件"""
        if index == 1:
            self.image_container.setVisible(True)
        else:
            self.image_container.setVisible(False)

    def set_aspect_ratio(self, ratio):
        """Set aspect ratio"""
        if ratio == "9:16":
            self.aspect_ratio_9_16.setChecked(True)
            self.aspect_ratio_16_9.setChecked(False)
        else:
            self.aspect_ratio_9_16.setChecked(False)
            self.aspect_ratio_16_9.setChecked(True)

    def get_aspect_ratio(self):
        """Get current aspect ratio"""
        return "9:16" if self.aspect_ratio_9_16.isChecked() else "16:9"

    def get_duration(self):
        """Get current duration"""
        return 10 if self.duration_combo.currentIndex() == 0 else 15

    def clear_image(self):
        """Clear uploaded image"""
        self.image_drop_widget.clear_image()

    def load_batch_from_file(self):
        """Load batch tasks from file"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择批量任务文件",
            "",
            "文本文件 (*.txt);;所有文件 (*)"
        )
        if file_path:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.batch_list.setPlainText(content)
                InfoBar.success(
                    title="成功",
                    content=f"已加载 0 个任务",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=2000,
                    parent=self
                )
            except Exception as e:
                QMessageBox.warning(self, "错误", f"加载文件失败: {str(e)}")

    def generate_single_video(self):
        """生成单个视频"""
        prompt = self.prompt_edit.toPlainText().strip()
        if not prompt:
            QMessageBox.warning(self, "警告", "请输入视频生成提示词")
            return

        video_mode = "i2v" if self.video_mode_combo.currentIndex() == 1 else "t2v"

        if video_mode == "i2v" and not self.image_drop_widget.current_image_data:
            QMessageBox.warning(self, "警告", "图生视频模式需要上传图片")
            return

        aspect_ratio = self.get_aspect_ratio()
        duration = self.get_duration()

        task = {
            'name': f'Sora2_{"图生视频" if video_mode == "i2v" else "文生视频"}_{datetime.now().strftime("%H%M%S")}',
            'prompt': prompt,
            'video_mode': video_mode,
            'aspect_ratio': aspect_ratio,
            'duration': duration
        }

        if video_mode == "i2v":
            task['image_input'] = self.image_drop_widget.current_image_data
            task['image_path'] = self.image_drop_widget.current_image_path

        task_map = {f"task_{int(time.time())}": task}
        self.start_generation(task_map)

    def generate_batch_videos(self):
        """批量生成视频"""
        batch_text = self.batch_list.toPlainText().strip()
        if not batch_text:
            QMessageBox.warning(self, "警告", "请输入批量任务列表")
            return

        video_mode = "i2v" if self.video_mode_combo.currentIndex() == 1 else "t2v"
        aspect_ratio = self.get_aspect_ratio()
        duration = self.get_duration()

        lines = [line.strip() for line in batch_text.split('\n') if line.strip()]
        task_map = {}

        for i, line in enumerate(lines):
            if video_mode == "i2v" and '|' in line:
                parts = line.split('|', 1)
                if len(parts) == 2:
                    image_path, prompt = parts
                    task = {
                        'name': f'Sora2 图生视频_{i+1:03d}',
                        'prompt': prompt.strip(),
                        'video_mode': 'i2v',
                        'aspect_ratio': aspect_ratio,
                        'duration': duration,
                        'image_input': image_path.strip(),
                        'image_path': image_path.strip()
                    }
            else:
                task = {
                    'name': f'Sora2_{"图生视频" if video_mode == "i2v" else "文生视频"}_{i+1:03d}',
                    'prompt': line,
                    'video_mode': video_mode,
                    'aspect_ratio': aspect_ratio,
                    'duration': duration
                }

                if video_mode == "i2v":
                    task['image_input'] = self.image_drop_widget.current_image_data
                    task['image_path'] = self.image_drop_widget.current_image_path

            task_map[f"task_{int(time.time())}_{i}"] = task

        if task_map:
            self.start_generation(task_map)

    def start_generation(self, task_map):
        """Start generation"""
        self.clear_task_cards()
        self.clear_result_cards()

        for task_id, task in task_map.items():
            self.add_task_status_card(task_id, task)

        self.batch_manager.add_tasks(task_map, self.key_file_path)

    def add_task_status_card(self, task_id, task):
        """Add task status card"""
        task_params = {
            'video_mode': task.get('video_mode', 't2v'),
            'aspect_ratio': task.get('aspect_ratio', '9:16'),
            'prompt': task.get('prompt', ''),
            'duration': task.get('duration', 10)
        }

        card = Sora2TaskStatusCard(task_id, task.get('name', f'Task_{task_id}'), task_params, self)
        self.tasks_layout.insertWidget(self.tasks_layout.count() - 1, card)
        self.task_status_cards[task_id] = card

        # 立即启动计时器
        card.start_timing()

    def clear_task_cards(self):
        """Clear task status cards"""
        for task_id, card in self.task_status_cards.items():
            card.deleteLater()
        self.task_status_cards.clear()

    def clear_result_cards(self):
        """Clear video result cards"""
        for card in self.video_result_cards:
            card.deleteLater()
        self.video_result_cards.clear()

    def update_task_progress(self, progress, message, task_id):
        """Update task progress"""
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].update_progress(progress, message)

    def update_task_time(self, time_string, task_id):
        """Update task time"""
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].update_time(time_string)

    def on_task_finished(self, success, message, result_data, task_id):
        """Task finished callback"""
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].stop_timing()  # 停止计时器
            self.task_status_cards[task_id].set_completed(success, message)

        if success and result_data:
            self.add_simple_result_card(result_data, task_id)

    def add_simple_result_card(self, video_data, task_id):
        """Add simple result card"""
        result_card = QFrame()
        result_card.setStyleSheet("""
            QFrame {
                background-color: #2e3a2e;
                border: 1px solid #28a745;
                border-radius: 8px;
                margin: 5px;
                padding: 10px;
            }
        """)

        layout = QVBoxLayout(result_card)

        # 获取计时时间和 request_id
        time_str = ""
        if task_id in self.task_status_cards:
            time_str = self.task_status_cards[task_id].time_string

        request_id = video_data.get('request_id') or video_data.get('id', '')

        # 构建标题行：任务名称 | 用时 | request_id
        task_name = video_data.get('task_name', f'Task_{task_id}')
        if time_str and request_id:
            title = QLabel(f"Task: {task_name} | 用时: {time_str} | ID: {request_id[:48]}...")
        elif time_str:
            title = QLabel(f"Task: {task_name} | 用时: {time_str}")
        elif request_id:
            title = QLabel(f"Task: {task_name} | ID: {request_id[:48]}...")
        else:
            title = QLabel(f"Task: {task_name}")

        title.setStyleSheet("font-size: 13px; font-weight: bold; color: #ffffff;")
        layout.addWidget(title)

        url = video_data.get('url', '')

        # 使用 LineEdit 显示完整 URL
        url_input = qf.LineEdit()
        url_input.setText(url)
        url_input.setReadOnly(True)
        url_input.setStyleSheet("""
            LineEdit {
                background-color: #1e1e1e;
                color: #888888;
                font-size: 11px;
                border: 1px solid #404040;
                border-radius: 4px;
                padding: 6px;
            }
        """)
        url_input.setTextMargins(0, 0, 0, 0)
        layout.addWidget(url_input)

        btn_layout = QHBoxLayout()

        play_btn = PushButton("▶ 播放")
        play_btn.clicked.connect(lambda: self.play_video(url))
        btn_layout.addWidget(play_btn)

        copy_btn = PushButton("复制URL")
        copy_btn.clicked.connect(lambda: self.copy_url(url))
        btn_layout.addWidget(copy_btn)

        open_btn = PushButton("浏览器打开")
        open_btn.clicked.connect(lambda: QDesktopServices.openUrl(QUrl(url)))
        btn_layout.addWidget(open_btn)

        btn_layout.addStretch()
        layout.addLayout(btn_layout)

        self.results_layout.insertWidget(self.results_layout.count() - 1, result_card)
        self.video_result_cards.append(result_card)

    def copy_url(self, url):
        """Copy URL to clipboard"""
        clipboard = QCoreApplication.clipboard()
        clipboard.setText(url)
        InfoBar.success(
            title="成功",
            content="URL已复制到剪贴板",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=2000,
            parent=self
        )

    def play_video(self, url):
        """下载并播放视频"""
        # 创建 output 目录
        output_dir = "output"
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        # 从 URL 提取文件名
        filename_match = re.search(r'/([^/]+\.mp4)', url)
        if filename_match:
            filename = filename_match.group(1)
        else:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"sora2_video_{timestamp}.mp4"

        local_path = os.path.join(output_dir, filename)

        # 创建下载线程
        download_thread = VideoDownloadThread(url, local_path, self)
        download_thread.finished.connect(lambda success, path: self.on_download_finished(success, path, filename))
        download_thread.start()

        InfoBar.info(
            title="下载中",
            content=f"正在下载视频到：{local_path}",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=3000,
            parent=self
        )

    def on_download_finished(self, success, local_path, filename):
        """下载完成回调"""
        if success:
            # 在不同平台上打开视频文件
            try:
                if platform.system() == 'Darwin':  # macOS
                    subprocess.run(['open', local_path])
                elif platform.system() == 'Windows':
                    os.startfile(local_path)
                else:  # Linux
                    subprocess.run(['xdg-open', local_path])

                InfoBar.success(
                    title="播放中",
                    content=f"已打开视频：{filename}",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=3000,
                    parent=self
                )
            except Exception as e:
                InfoBar.error(
                    title="错误",
                    content=f"无法打开视频：{str(e)}",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=5000,
                    parent=self
                )
        else:
            InfoBar.error(
                title="下载失败",
                content=f"视频下载失败，请重试",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=5000,
                parent=self
            )

    def update_batch_progress(self, completed, total):
        """Update batch progress"""
        self.batch_progress_label.setText(f"批量进度： {completed}/{total}")
        if total > 0:
            progress = int((completed / total) * 100)
            self.batch_progress_bar.setValue(progress)

    def on_all_tasks_finished(self):
        """所有任务已完成"""
        InfoBar.success(
            title="完成",
            content="所有任务已完成",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=3000,
            parent=self
        )

    def update_generate_buttons_state(self):
        """更新生成按钮状态（已移除限制，允许多批次同时提交）"""
        self.single_generate_btn.setEnabled(True)
        self.batch_generate_btn.setEnabled(True)

    def show_api_settings_dialog(self):
        """Show API settings dialog"""
        dialog = Sora2APISettingsDialog(self)
        if dialog.exec_() == QDialog.Accepted:
            self.load_settings()
            self.update_key_status()

    def load_settings(self):
        """加载设置"""
        api_settings = self.settings_manager.get_api_settings()
        self.api_manager.api_url = api_settings.get("api_url",
            "https://api.bizyair.cn/w/v1/webapp/task/openapi/create")
        self.api_manager.web_app_id_t2v = api_settings.get("web_app_id_t2v", 42921)
        self.api_manager.web_app_id_i2v = api_settings.get("web_app_id_i2v", 42936)

        # 加载视频参数
        video_params = self.settings_manager.get_video_params()
        aspect_ratio = video_params.get("aspect_ratio", "9:16")
        self.set_aspect_ratio(aspect_ratio)

        # 加载时长设置
        duration = video_params.get("duration", 10)
        self.duration_combo.setCurrentIndex(0 if duration == 10 else 1)
        self.duration_combo.currentIndexChanged.connect(self.save_current_settings)

        # 加载UI设置
        ui_settings = self.settings_manager.load_settings().get("ui_settings", {})
        video_mode = ui_settings.get("video_mode", "t2v")
        self.video_mode_combo.setCurrentIndex(0 if video_mode == "t2v" else 1)

        key_source = api_settings.get("key_source", "file")
        self.api_manager.set_key_source(key_source)

        key_file = api_settings.get("key_file", "")
        if key_source == "file" and key_file:
            self.api_manager.load_keys_from_file(key_file)
            self.key_file_path = key_file
        elif key_source == "text":
            key_text = api_settings.get("key_text", "")
            self.api_manager.load_keys_from_text(key_text)

        self.update_key_status()

    def update_key_status(self):
        """Update key status"""
        available_keys = self.api_manager.get_available_keys_count()
        key_source = self.api_manager.get_key_source_display()

        if available_keys > 0:
            self.key_status_label.setText(f"OK {key_source} ({available_keys} keys)")
            self.key_status_label.setStyleSheet("color: #28a745; font-size: 12px; padding: 6px 12px; background: #e8f5e8; border-radius: 4px;")
        else:
            self.key_status_label.setText("Key not configured")
            self.key_status_label.setStyleSheet("color: #dc3545; font-size: 12px; padding: 6px 12px; background: #fff3cd; border-radius: 4px;")

    def add_log(self, message):
        """Add log"""
        print(f"[Sora2] {message}")
        # 同时显示到界面上
        if hasattr(self, 'log_text'):
            # 获取当前时间
            timestamp = datetime.now().strftime("%H:%M:%S")

            # 根据消息类型设置颜色
            color = "#00ff00"  # 默认绿色
            if "Error" in message or "error" in message or "失败" in message or "Failed" in message:
                color = "#ff6b6b"  # 红色
            elif "Warning" in message or "warning" in message or "警告" in message:
                color = "#ffd93d"  # 黄色
            elif "Starting" in message or "开始" in message or "Success" in message or "成功" in message:
                color = "#6bcb77"  # 浅绿色
            elif "API" in message or "Request" in message or "请求" in message:
                color = "#4d96ff"  # 蓝色
            elif "Completed" in message or "完成" in message:
                color = "#9b59b6"  # 紫色

            # 使用 HTML 格式设置颜色
            log_line = f'<span style="color: #888888;">[{timestamp}]</span> <span style="color: {color};">{message}</span>'
            self.log_text.append(log_line)
            # 自动滚动到底部
            cursor = self.log_text.textCursor()
            cursor.movePosition(cursor.End)
            self.log_text.setTextCursor(cursor)

    def clear_log(self):
        """清空日志"""
        self.log_text.clear()
        InfoBar.success(
            title="成功",
            content="日志已清空",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=2000,
            parent=self
        )

    def export_log(self):
        """导出日志"""
        file_path, _ = QFileDialog.getSaveFileName(
            self,
            "导出日志",
            f"sora2_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
            "文本文件 (*.txt);;所有文件 (*)"
        )
        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(self.log_text.toPlainText())
                InfoBar.success(
                    title="成功",
                    content=f"日志已导出到：{file_path}",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=2000,
                    parent=self
                )
            except Exception as e:
                QMessageBox.warning(self, "错误", f"导出日志失败：{str(e)}")

    def save_current_settings(self):
        """保存当前设置"""
        current_duration = self.get_duration()
        self.settings_manager.set_video_params(
            aspect_ratio=self.get_aspect_ratio(),
            duration=current_duration,
            duration_t2v=current_duration,
            duration_i2v=current_duration
        )

    def show_task_history(self):
        """显示任务历史"""
        dialog = Sora2TaskHistoryDialog(self)
        dialog.exec_()

# ==================== API Settings Dialog ====================
class Sora2APISettingsDialog(QDialog):
    """Sora2 API settings dialog"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Sora2 API Settings")
        self.setMinimumSize(600, 500)
        self.settings_manager = Sora2SettingsManager()
        self.init_ui()
        self.load_settings()

    def init_ui(self):
        main_layout = QVBoxLayout(self)
        main_layout.setSpacing(15)

        # 创建滚动区域
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll_area.setFrameShape(QFrame.NoFrame)

        # 滚动区域的内容容器
        scroll_content = QWidget()
        scroll_layout = QVBoxLayout(scroll_content)
        scroll_layout.setSpacing(15)
        scroll_layout.setContentsMargins(0, 0, 0, 10)

        # Key source selection
        source_group = QGroupBox("API Key 来源")
        source_group.setStyleSheet("""
            QGroupBox {
                color: #ffffff;
                font-size: 14px;
                font-weight: bold;
                border: 1px solid #404040;
                border-radius: 6px;
                margin-top: 10px;
                padding-top: 10px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px;
            }
        """)
        source_layout = QVBoxLayout()

        self.key_source_combo = ComboBox()
        self.key_source_combo.addItems(["文件密钥", "系统变量", "密钥文本"])
        self.key_source_combo.setFixedHeight(35)
        self.key_source_combo.currentIndexChanged.connect(self.on_key_source_changed)
        source_layout.addWidget(QLabel("密钥来源:"))
        source_layout.addWidget(self.key_source_combo)

        source_group.setLayout(source_layout)
        scroll_layout.addWidget(source_group)

        # File key settings
        self.file_group = QGroupBox("文件密钥配置")
        self.file_group.setStyleSheet(source_group.styleSheet())
        file_layout = QVBoxLayout()

        file_select_layout = QHBoxLayout()
        self.key_file_edit = LineEdit()
        self.key_file_edit.setPlaceholderText("选择文件密钥文件（每行一个密钥）")
        self.key_file_edit.setFixedHeight(35)
        file_select_layout.addWidget(self.key_file_edit)

        browse_btn = PushButton("浏览文件密钥...")
        browse_btn.setFixedHeight(35)
        browse_btn.clicked.connect(self.browse_key_file)
        file_select_layout.addWidget(browse_btn)

        file_layout.addLayout(file_select_layout)

        help_label = QLabel("文件格式：每行一个密钥，#开头的行会被忽略")
        help_label.setStyleSheet("color: #888888; font-size: 11px;")
        file_layout.addWidget(help_label)

        self.file_group.setLayout(file_layout)
        scroll_layout.addWidget(self.file_group)

        # Key text settings
        self.text_group = QGroupBox("密钥文本配置")
        self.text_group.setStyleSheet(source_group.styleSheet())
        text_layout = QVBoxLayout()

        self.key_text_edit = QTextEdit()
        self.key_text_edit.setPlaceholderText("输入API密钥（每行一个密钥）")
        self.key_text_edit.setMinimumHeight(100)
        text_layout.addWidget(QLabel("密钥文本:"))
        text_layout.addWidget(self.key_text_edit)

        self.text_group.setLayout(text_layout)
        self.text_group.setVisible(False)
        scroll_layout.addWidget(self.text_group)

        # API parameters
        api_group = QGroupBox("API 参数配置")
        api_group.setStyleSheet(source_group.styleSheet())
        api_layout = QVBoxLayout()

        api_layout.addWidget(QLabel("文生视频 Web App ID："))
        self.t2v_app_id_edit = LineEdit()
        self.t2v_app_id_edit.setFixedHeight(35)
        api_layout.addWidget(self.t2v_app_id_edit)

        api_layout.addWidget(QLabel("图生视频 Web App ID："))
        self.i2v_app_id_edit = LineEdit()
        self.i2v_app_id_edit.setFixedHeight(35)
        api_layout.addWidget(self.i2v_app_id_edit)

        api_layout.addWidget(QLabel("API URL:"))
        self.api_url_edit = LineEdit()
        self.api_url_edit.setFixedHeight(35)
        api_layout.addWidget(self.api_url_edit)

        api_group.setLayout(api_layout)
        scroll_layout.addWidget(api_group)

        # WebHook 设置
        webhook_group = QGroupBox("WebHook 设置")
        webhook_group.setStyleSheet(source_group.styleSheet())
        webhook_layout = QVBoxLayout()

        # WebHook 启用开关
        webhook_enable_layout = QHBoxLayout()
        self.webhook_enable_check = qf.SwitchButton()
        self.webhook_enable_check.setChecked(False)
        webhook_enable_layout.addWidget(QLabel("启用 WebHook 模式:"))
        webhook_enable_layout.addWidget(self.webhook_enable_check)
        webhook_enable_layout.addStretch()
        webhook_layout.addLayout(webhook_enable_layout)

        # WebHook URL
        webhook_layout.addWidget(QLabel("回调服务器 URL:"))
        self.webhook_url_edit = LineEdit()
        self.webhook_url_edit.setPlaceholderText("https://bizyair.bozoyan.cn/api/callback")
        self.webhook_url_edit.setFixedHeight(35)
        webhook_layout.addWidget(self.webhook_url_edit)

        # WebHook Token
        webhook_layout.addWidget(QLabel("回调验证令牌:"))
        self.webhook_token_edit = LineEdit()
        self.webhook_token_edit.setPlaceholderText("输入回调验证令牌")
        self.webhook_token_edit.setFixedHeight(35)
        webhook_layout.addWidget(self.webhook_token_edit)

        # 查询 URL
        webhook_layout.addWidget(QLabel("查询接口 URL:"))
        self.query_url_edit = LineEdit()
        self.query_url_edit.setPlaceholderText("https://api.bizyair.cn/w/v1/webapp/task/openapi/outputs")
        self.query_url_edit.setFixedHeight(35)
        webhook_layout.addWidget(self.query_url_edit)

        # 延迟查询时间
        delay_layout = QHBoxLayout()
        delay_layout.addWidget(QLabel("延迟查询时间(分钟):"))
        self.delay_minutes_spin = qf.SpinBox()
        self.delay_minutes_spin.setRange(1, 60)
        self.delay_minutes_spin.setValue(10)
        self.delay_minutes_spin.setFixedWidth(180)
        delay_layout.addWidget(self.delay_minutes_spin)
        delay_layout.addStretch()
        webhook_layout.addLayout(delay_layout)

        # 回退到轮询
        fallback_layout = QHBoxLayout()
        self.fallback_check = qf.SwitchButton()
        self.fallback_check.setChecked(False)
        fallback_layout.addWidget(QLabel("WebHook 失败时回退到轮询:"))
        fallback_layout.addWidget(self.fallback_check)
        fallback_layout.addStretch()
        webhook_layout.addLayout(fallback_layout)

        webhook_group.setLayout(webhook_layout)
        scroll_layout.addWidget(webhook_group)

        # 添加弹性空间，将内容推到顶部
        scroll_layout.addStretch()

        # 设置滚动区域的内容
        scroll_area.setWidget(scroll_content)
        main_layout.addWidget(scroll_area)

        # Bottom buttons
        button_layout = QHBoxLayout()
        save_btn = PrimaryPushButton("保存设置")
        save_btn.clicked.connect(self.save_settings)
        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)

        button_layout.addStretch()
        button_layout.addWidget(save_btn)
        button_layout.addWidget(cancel_btn)
        main_layout.addLayout(button_layout)

    def on_key_source_changed(self, index):
        """Key source changed event"""
        if index == 0:
            self.file_group.setVisible(True)
            self.text_group.setVisible(False)
        elif index == 1:
            self.file_group.setVisible(False)
            self.text_group.setVisible(False)
        else:
            self.file_group.setVisible(False)
            self.text_group.setVisible(True)

    def browse_key_file(self):
        """浏览 key file"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Select API Key File",
            "",
            "文本文件 (*.txt);;所有文件 (*)"
        )
        if file_path:
            self.key_file_edit.setText(file_path)

    def load_settings(self):
        """加载设置"""
        api_settings = self.settings_manager.get_api_settings()

        key_source = api_settings.get("key_source", "file")
        if key_source == "env":
            self.key_source_combo.setCurrentIndex(1)
        elif key_source == "text":
            self.key_source_combo.setCurrentIndex(2)
        else:
            self.key_source_combo.setCurrentIndex(0)

        self.key_file_edit.setText(api_settings.get("key_file", ""))
        self.key_text_edit.setPlainText(api_settings.get("key_text", ""))
        self.t2v_app_id_edit.setText(str(api_settings.get("web_app_id_t2v", 42921)))
        self.i2v_app_id_edit.setText(str(api_settings.get("web_app_id_i2v", 42936)))
        self.api_url_edit.setText(api_settings.get("api_url",
            "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"))

        # 加载 WebHook 设置
        webhook_settings = self.settings_manager.get_webhook_settings()
        self.webhook_enable_check.setChecked(webhook_settings.get("enabled", False))
        self.webhook_url_edit.setText(webhook_settings.get("url", ""))
        self.webhook_token_edit.setText(webhook_settings.get("token", ""))
        self.query_url_edit.setText(webhook_settings.get("query_url", ""))
        self.delay_minutes_spin.setValue(webhook_settings.get("delay_minutes", 10))
        self.fallback_check.setChecked(webhook_settings.get("fallback_to_polling", False))

    def save_settings(self):
        """保存设置"""
        key_source_map = {0: "file", 1: "env", 2: "text"}
        key_source = key_source_map.get(self.key_source_combo.currentIndex(), "file")

        try:
            t2v_app_id = int(self.t2v_app_id_edit.text().strip())
            i2v_app_id = int(self.i2v_app_id_edit.text().strip())
        except ValueError:
            QMessageBox.warning(self, "错误", "Web App ID 必须是数字")
            return

        success = self.settings_manager.set_api_settings(
            key_file=self.key_file_edit.text().strip(),
            web_app_id_t2v=t2v_app_id,
            web_app_id_i2v=i2v_app_id,
            api_url=self.api_url_edit.text().strip(),
            key_text=self.key_text_edit.toPlainText().strip(),
            key_source=key_source
        )

        # 保存 WebHook 设置
        webhook_success = self.settings_manager.set_webhook_settings(
            enabled=self.webhook_enable_check.isChecked(),
            url=self.webhook_url_edit.text().strip(),
            token=self.webhook_token_edit.text().strip(),
            query_url=self.query_url_edit.text().strip(),
            delay_minutes=self.delay_minutes_spin.value(),
            fallback_to_polling=self.fallback_check.isChecked()
        )

        if success and webhook_success:
            QMessageBox.information(self, "成功", "Sora2 API设置已保存")
            self.accept()
        else:
            QMessageBox.critical(self, "错误", "设置保存失败")

# ==================== Task Query Scheduler ====================
class Sora2TaskQueryScheduler(QObject):
    """Sora2 任务查询调度器"""

    task_status_updated = pyqtSignal(str, str, str)  # task_id, status, video_url
    log_updated = pyqtSignal(str)

    def __init__(self, api_manager, parent=None):
        super().__init__(parent)
        self.api_manager = api_manager
        self.history_manager = Sora2TaskHistoryManager()
        self.settings_manager = Sora2SettingsManager()
        self.query_timer = QTimer(self)
        self.query_timer.timeout.connect(self.query_pending_tasks)
        self.is_running = False

    def start_scheduler(self, interval_minutes=1):
        """启动调度器"""
        if not self.is_running:
            self.is_running = True
            interval_ms = interval_minutes * 60 * 1000
            self.query_timer.start(interval_ms)
            Utils.log_message("任务查询调度器已启动", self.log_updated)

    def stop_scheduler(self):
        """停止调度器"""
        if self.is_running:
            self.is_running = False
            self.query_timer.stop()
            Utils.log_message("任务查询调度器已停止", self.log_updated)

    def query_pending_tasks(self):
        """查询待处理任务"""
        try:
            webhook_settings = self.settings_manager.get_webhook_settings()
            delay_minutes = webhook_settings.get("delay_minutes", 10)

            # 获取需要查询的任务
            pending_tasks = self.history_manager.get_pending_tasks(delay_minutes)

            if not pending_tasks:
                return

            Utils.log_message(f"发现 {len(pending_tasks)} 个待查询任务", self.log_updated)

            for task in pending_tasks:
                self._query_single_task(task)

        except Exception as e:
            Utils.log_message(f"查询任务失败: {str(e)}", self.log_updated)

    def _query_single_task(self, task):
        """查询单个任务状态"""
        task_id = task.get("task_id")
        request_id = task.get("request_id")
        api_key_masked = task.get("api_key_used", "")

        try:
            webhook_settings = self.settings_manager.get_webhook_settings()
            query_url = webhook_settings.get("query_url",
                "https://api.bizyair.cn/w/v1/webapp/task/openapi/outputs")

            # 从原始 API 密钥存储中获取完整密钥
            api_key = self._get_full_api_key(api_key_masked)
            if not api_key:
                Utils.log_message(f"无法获取任务 {task_id} 的 API 密钥", self.log_updated)
                return

            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}"
            }

            response = requests.get(
                f"{query_url}?requestId={request_id}",
                headers=headers,
                timeout=30,
                proxies={"http": None, "https": None}
            )

            response.raise_for_status()
            data = response.json()

            # 解析响应
            if data.get("code") == 20000:
                task_data = data.get("data", {})
                status = task_data.get("status", "")

                if status == "Success":
                    outputs = task_data.get("outputs", [])
                    if outputs:
                        video_url = outputs[0].get("object_url", "")
                        self.history_manager.update_task_status(
                            task_id, "success", video_url=video_url
                        )
                        self.task_status_updated.emit(task_id, "success", video_url)
                        Utils.log_message(f"任务 {task_id} 完成: {video_url}", self.log_updated)

                elif status == "Failed":
                    self.history_manager.update_task_status(
                        task_id, "failed", error_message="任务执行失败"
                    )
                    self.task_status_updated.emit(task_id, "failed", "")
                    Utils.log_message(f"任务 {task_id} 失败", self.log_updated)

                else:
                    # 仍在运行中
                    Utils.log_message(f"任务 {task_id} 仍在运行中 ({status})", self.log_updated)

        except Exception as e:
            Utils.log_message(f"查询任务 {task_id} 失败: {str(e)}", self.log_updated)

    def _get_full_api_key(self, masked_key):
        """根据脱敏密钥获取完整密钥"""
        # 从 API 管理器中获取匹配的密钥
        all_keys = self.api_manager.get_all_keys()
        for key in all_keys:
            if len(key) >= 8:
                if key[:4] == masked_key[:4] and key[-4:] == masked_key[-4:]:
                    return key
        return None

# ==================== Task History Dialog ====================
class Sora2TaskHistoryDialog(QDialog):
    """Sora2 任务历史查看对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("任务历史记录")
        self.setMinimumSize(900, 600)
        self.history_manager = Sora2TaskHistoryManager()
        self.init_ui()
        self.load_tasks()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # 顶部工具栏
        toolbar = QHBoxLayout()

        refresh_btn = PushButton("刷新")
        refresh_btn.clicked.connect(self.load_tasks)
        toolbar.addWidget(refresh_btn)

        clear_btn = PushButton("清理已完成(7天前)")
        clear_btn.clicked.connect(self.clear_old_tasks)
        toolbar.addWidget(clear_btn)

        toolbar.addStretch()
        layout.addLayout(toolbar)

        # 统计信息
        self.stats_label = QLabel()
        self.stats_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(self.stats_label)

        # 任务列表
        self.task_table = qf.TableWidget()
        self.task_table.setColumnCount(7)
        self.task_table.setHorizontalHeaderLabels([
            "任务ID", "名称", "Request ID", "状态",
            "模式", "提交时间", "视频URL"
        ])
        self.task_table.setStyleSheet("""
            QTableWidget {
                background-color: #1e1e1e;
                gridline-color: #404040;
                color: #ffffff;
                font-size: 12px;
            }
            QHeaderView::section {
                background-color: #2a2a2a;
                color: #ffffff;
                padding: 8px;
                border: 1px solid #404040;
            }
        """)
        layout.addWidget(self.task_table)

        # 详情区域
        details_group = QGroupBox("任务详情")
        details_layout = QVBoxLayout()
        self.details_text = QTextEdit()
        self.details_text.setReadOnly(True)
        self.details_text.setMaximumHeight(150)
        self.details_text.setStyleSheet("background-color: #1e1e1e; color: #aaaaaa; font-size: 11px;")
        details_layout.addWidget(self.details_text)
        details_group.setLayout(details_layout)
        layout.addWidget(details_group)

        # 底部按钮
        button_layout = QHBoxLayout()
        delete_btn = PushButton("删除选中")
        delete_btn.clicked.connect(self.delete_selected)
        button_layout.addWidget(delete_btn)

        export_btn = PushButton("导出记录")
        export_btn.clicked.connect(self.export_history)
        button_layout.addWidget(export_btn)

        button_layout.addStretch()
        close_btn = PushButton("关闭")
        close_btn.clicked.connect(self.accept)
        button_layout.addWidget(close_btn)
        layout.addLayout(button_layout)

        # 表格点击事件
        self.task_table.itemClicked.connect(self.show_task_details)

    def load_tasks(self):
        """加载任务列表"""
        history = self.history_manager.load_history()
        tasks = list(history["tasks"].values())
        tasks.sort(key=lambda x: x["timestamps"]["created_at"], reverse=True)

        self.task_table.setRowCount(len(tasks))

        for row, task in enumerate(tasks):
            self.task_table.setItem(row, 0, qf.TableItem(task["task_id"]))
            self.task_table.setItem(row, 1, qf.TableItem(task["name"]))
            self.task_table.setItem(row, 2, qf.TableItem(task.get("request_id", "")))
            self.task_table.setItem(row, 3, qf.TableItem(task["status"]))
            self.task_table.setItem(row, 4, qf.TableItem("WebHook" if task.get("webhook_mode") else "轮询"))
            self.task_table.setItem(row, 5, qf.TableItem(task["timestamps"]["created_at"]))
            self.task_table.setItem(row, 6, qf.TableItem(task["result"].get("video_url", "")))

        # 更新统计信息
        stats = history["statistics"]
        self.stats_label.setText(
            f"总计: {stats['total_tasks']} | "
            f"已完成: {stats['completed_tasks']} | "
            f"待处理: {stats['pending_tasks']} | "
            f"失败: {stats['failed_tasks']}"
        )

    def show_task_details(self, item):
        """显示任务详情"""
        row = item.row()
        task_id = self.task_table.item(row, 0).text()

        history = self.history_manager.load_history()
        if task_id in history["tasks"]:
            task = history["tasks"][task_id]
            details = json.dumps(task, ensure_ascii=False, indent=2)
            self.details_text.setPlainText(details)

    def clear_old_tasks(self):
        """清理旧任务"""
        success, count = self.history_manager.clear_completed_tasks(days=7)
        if success:
            QMessageBox.information(self, "成功", f"已清理 {count} 个已完成任务")
            self.load_tasks()
        else:
            QMessageBox.warning(self, "失败", "清理任务失败")

    def delete_selected(self):
        """删除选中的任务"""
        current_row = self.task_table.currentRow()
        if current_row >= 0:
            task_id = self.task_table.item(current_row, 0).text()
            reply = QMessageBox.question(
                self, "确认删除",
                f"确定要删除任务 {task_id} 吗?",
                QMessageBox.Yes | QMessageBox.No
            )
            if reply == QMessageBox.Yes:
                if self.history_manager.delete_task(task_id):
                    self.load_tasks()
                    QMessageBox.information(self, "成功", "任务已删除")
                else:
                    QMessageBox.warning(self, "失败", "删除任务失败")

    def export_history(self):
        """导出任务历史"""
        file_path, _ = QFileDialog.getSaveFileName(
            self, "导出任务历史",
            f"sora2_tasks_history_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json",
            "JSON 文件 (*.json)"
        )
        if file_path:
            try:
                import shutil
                shutil.copy(self.history_manager.history_file, file_path)
                QMessageBox.information(self, "成功", f"任务历史已导出到: {file_path}")
            except Exception as e:
                QMessageBox.warning(self, "失败", f"导出失败: {str(e)}")

# ==================== Main Entry Point ====================
if __name__ == "__main__":
    from PyQt5.QtWidgets import QApplication

    app = QApplication(sys.argv)

    # Set dark theme
    qf.setTheme(Theme.DARK)

    window = Sora2VideoGenerationWidget()
    window.setWindowTitle("Sora2 AI Video Generator")
    window.resize(1200, 800)
    window.show()

    sys.exit(app.exec_())
