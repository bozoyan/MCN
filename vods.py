#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
视频生成模块（vods）——基于BizyAir API
支持文本转视频和图像转视频两种模式
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
                            QScrollArea, QDialog, QSizePolicy, QTabWidget,
                            QTableWidgetItem, QApplication)
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

        log_file = os.path.join(Utils.LOG_DIR, "vods_generation.log")
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

# ==================== Video Utils ====================
class VideoUtils:
    """视频处理工具类"""

    @staticmethod
    def extract_filename_from_url(url):
        """从视频 URL 中提取文件名"""
        import re
        from datetime import datetime

        filename_match = re.search(r'/([^/]+\.mp4)', url)
        if filename_match:
            return filename_match.group(1)
        else:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            return f"vods_video_{timestamp}.mp4"

    @staticmethod
    def get_local_video_path(url, output_dir="output"):
        """获取视频本地存储路径"""
        import os

        # 确保 output 目录存在
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        filename = VideoUtils.extract_filename_from_url(url)
        return os.path.join(output_dir, filename)

    @staticmethod
    def open_video_file(local_path):
        """跨平台打开视频文件"""
        import platform
        import subprocess

        try:
            if platform.system() == 'Darwin':  # macOS
                subprocess.run(['open', local_path])
            elif platform.system() == 'Windows':
                os.startfile(local_path)
            else:  # Linux
                subprocess.run(['xdg-open', local_path])
            return True, None
        except Exception as e:
            return False, str(e)

    @staticmethod
    def check_local_file_exists(local_path):
        """检查本地文件是否存在且有效"""
        import os

        return os.path.exists(local_path) and os.path.getsize(local_path) > 0

# ==================== BizyAir Upload Utils ====================
class BizyAirUploadUtils:
    """BizyAir 文件上传工具类，支持本地图片上传获取远程 URL"""

    @staticmethod
    def upload_local_file(file_path, api_key, log_signal=None):
        """上传本地文件到 BizyAir OSS，返回远程 URL

        步骤：
        1. 获取上传凭证 (GET /x/v1/upload/token)
        2. 使用凭证上传到阿里云 OSS
        3. 提交输入资源 (POST /x/v1/input_resource/commit)
        4. 返回可用的远程 URL
        """
        try:
            file_name = os.path.basename(file_path)

            # 步骤1：获取上传凭证
            if log_signal:
                log_signal.emit(f"[上传] 获取上传凭证: {file_name}")

            token_url = "https://api.bizyair.cn/x/v1/upload/token"
            params = {
                "file_name": file_name,
                "file_type": "inputs"
            }
            headers = {
                "Authorization": f"Bearer {api_key}"
            }

            proxies = {"http": None, "https": None}
            resp = requests.get(token_url, params=params, headers=headers,
                               timeout=30, proxies=proxies)
            resp.raise_for_status()
            token_data = resp.json()

            # 兼容新旧 API 响应格式
            # 旧格式: {"endpoint": "...", "bucket": "...", "credential": {...}, "object_key": "..."}
            # 新格式: {"data": {"file": {...}, "storage": {"endpoint": "...", "bucket": "...", "region": "..."}}}
            data = token_data.get("data", {})

            if data:
                # 新格式
                file_info = data.get("file", {})
                storage_info = data.get("storage", {})

                object_key = file_info.get("object_key", token_data.get("object_key", ""))
                access_key_id = file_info.get("access_key_id", "")
                access_key_secret = file_info.get("access_key_secret", "")
                security_token = file_info.get("security_token", "")

                endpoint = storage_info.get("endpoint", token_data.get("endpoint", ""))
                bucket = storage_info.get("bucket", token_data.get("bucket", ""))
                region = storage_info.get("region", token_data.get("region", ""))
            else:
                # 旧格式
                credential = token_data.get("credential", {})
                endpoint = token_data.get("endpoint", "")
                bucket = token_data.get("bucket", "")
                region = token_data.get("region", "")
                object_key = token_data.get("object_key", "")

                access_key_id = credential.get("access_key_id", "")
                access_key_secret = credential.get("access_key_secret", "")
                security_token = credential.get("security_token", "")

            if not all([endpoint, bucket, object_key, access_key_id, access_key_secret]):
                raise Exception(f"上传凭证不完整: {token_data}")

            if log_signal:
                log_signal.emit(f"[上传] 凭证获取成功, object_key: {object_key}")

            # 步骤2：上传文件到阿里云 OSS
            BizyAirUploadUtils._upload_to_oss(
                endpoint, bucket, region, object_key, file_path,
                access_key_id, access_key_secret, security_token,
                log_signal
            )

            # 步骤3：提交输入资源
            if log_signal:
                log_signal.emit(f"[上传] 提交输入资源...")

            commit_url = "https://api.bizyair.cn/x/v1/input_resource/commit"
            commit_payload = {
                "name": file_name,
                "object_key": object_key
            }
            commit_headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }

            resp = requests.post(commit_url, json=commit_payload, headers=commit_headers,
                                timeout=30, proxies=proxies)
            resp.raise_for_status()
            commit_data = resp.json()

            # 构建可用的远程 URL
            remote_url = f"https://{bucket}.{endpoint}/{object_key}"

            if log_signal:
                log_signal.emit(f"[上传] 上传完成: {remote_url}")

            return remote_url

        except Exception as e:
            if log_signal:
                log_signal.emit(f"[上传] 上传失败: {str(e)}")
            raise

    @staticmethod
    def _upload_to_oss(endpoint, bucket, region, object_key, file_path,
                       access_key_id, access_key_secret, security_token,
                       log_signal=None):
        """使用 requests PUT 上传文件到阿里云 OSS（使用 V1 签名）"""
        import hmac
        import hashlib
        import base64
        from datetime import datetime

        url = f"https://{bucket}.{endpoint}/{object_key}"

        # 读取文件内容
        with open(file_path, 'rb') as f:
            file_data = f.read()

        # 猜测 Content-Type
        import mimetypes
        content_type = mimetypes.guess_type(file_path)[0] or 'application/octet-stream'

        # GMT 时间（使用 email.utils 确保输出英文，避免中文 locale 导致编码错误）
        from email.utils import formatdate
        date_str = formatdate(usegmt=True)

        # 构造 V1 签名
        # StringToSign = VERB + "\n" + Content-MD5 + "\n" + Content-Type + "\n" + Date + "\n"
        #                + CanonicalizedOSSHeaders + CanonicalizedResource
        md5 = base64.b64encode(hashlib.md5(file_data).digest()).decode()
        canonicalized_headers = f"x-oss-security-token:{security_token}\n"
        canonicalized_resource = f"/{bucket}/{object_key}"

        string_to_sign = f"PUT\n{md5}\n{content_type}\n{date_str}\n{canonicalized_headers}{canonicalized_resource}"

        signature = base64.b64encode(
            hmac.new(access_key_secret.encode(), string_to_sign.encode(), hashlib.sha1).digest()
        ).decode()

        upload_headers = {
            'Authorization': f'OSS {access_key_id}:{signature}',
            'Content-Type': content_type,
            'Content-MD5': md5,
            'Date': date_str,
            'x-oss-security-token': security_token
        }

        if log_signal:
            log_signal.emit(f"[上传] PUT 上传到 OSS: {url[:80]}...")

        resp = requests.put(url, data=file_data, headers=upload_headers,
                           timeout=120, proxies={"http": None, "https": None})
        resp.raise_for_status()

        if log_signal:
            log_signal.emit(f"[上传] OSS 上传成功 (HTTP {resp.status_code})")

    @staticmethod
    def get_image_url(image_input, api_key, log_signal=None):
        """将图片输入转换为远程 URL

        支持的输入格式：
        - 远程 URL（http/https 开头）：直接返回
        - 本地文件路径：上传到 BizyAir OSS 后返回 URL
        - URL 列表：逐个处理
        """
        if isinstance(image_input, list):
            urls = []
            for item in image_input:
                url = BizyAirUploadUtils.get_image_url(item, api_key, log_signal)
                if url:
                    urls.append(url)
            return urls

        if isinstance(image_input, str):
            if image_input.startswith('http://') or image_input.startswith('https://'):
                return image_input
            # 本地文件路径，需要上传
            if os.path.exists(image_input):
                return BizyAirUploadUtils.upload_local_file(image_input, api_key, log_signal)
            else:
                raise Exception(f"图片文件不存在: {image_input}")

        raise Exception(f"不支持的图片输入格式: {type(image_input)}")

# ==================== Play Video Mixin ====================
class PlayVideoMixin:
    """视频播放功能混入类，提供统一的播放逻辑

    使用方式：
        class MyWidget(QWidget, PlayVideoMixin):
            def __init__(self):
                super().__init__()
                # 可以直接使用 self.play_video(url)

    子类需要实现的方法：
        - show_success_message(title, content): 显示成功消息
        - show_info_message(title, content): 显示信息消息
        - show_error_message(title, content): 显示错误消息
        - get_video_download_finished_callback(): 返回下载完成的回调函数
    """

    def play_video(self, url):
        """播放视频（优先使用本地已下载的文件）

        Args:
            url: 视频 URL
        """
        local_path = VideoUtils.get_local_video_path(url)

        # 检查本地是否已有该文件
        if VideoUtils.check_local_file_exists(local_path):
            filename = VideoUtils.extract_filename_from_url(url)
            # 直接播放本地文件
            success, error = VideoUtils.open_video_file(local_path)
            if success:
                self.show_play_success_message(filename)
            else:
                self.show_play_error_message(error)
        else:
            # 创建下载线程
            from PyQt5.QtCore import QTimer
            filename = VideoUtils.extract_filename_from_url(url)

            download_thread = VideoDownloadThread(url, local_path, self)
            download_thread.finished.connect(
                lambda success, path, fn=filename: self._on_download_finished(success, path, fn)
            )
            download_thread.start()
            self.show_download_start_message(local_path)

    def _on_download_finished(self, success, local_path, filename):
        """视频下载完成回调

        Args:
            success: 下载是否成功
            local_path: 本地文件路径
            filename: 文件名
        """
        if success:
            # 下载完成后自动播放
            success, error = VideoUtils.open_video_file(local_path)
            if success:
                self.show_download_success_message(filename)
            else:
                self.show_play_error_message(f"下载成功但无法播放: {error}")
        else:
            self.show_download_error_message()

    # 子类需要实现的接口方法（提供默认实现）
    def show_play_success_message(self, filename):
        """播放成功消息"""
        pass

    def show_play_error_message(self, error):
        """播放错误消息"""
        pass

    def show_download_start_message(self, local_path):
        """下载开始消息"""
        pass

    def show_download_success_message(self, filename):
        """下载成功消息"""
        pass

    def show_download_error_message(self):
        """下载失败消息"""
        pass

# ==================== Settings Manager ====================
class Sora2SettingsManager:
    """Sora2 视频设置管理器"""

    def __init__(self, config_file="vods_settings.json"):
        self.config_file = config_file
        self.default_settings = {
            "video_params": {
                "display": "vertical",
                "duration": 5
            },
            "api_settings": {
                "key_file": "",
                "key_text": "",
                "key_source": "file",
                "api_url_t2v": "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/text-to-video",
                "api_url_i2v": "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/image-to-video",
                "query_url": "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi",
                "upload_token_url": "https://api.bizyair.cn/x/v1/upload/token",
                "upload_commit_url": "https://api.bizyair.cn/x/v1/input_resource/commit"
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

    def set_video_params(self, display="vertical", duration=5):
        """设置视频参数"""
        settings = self.load_settings()
        settings["video_params"] = {
            "display": display,
            "duration": duration
        }
        return self.save_settings(settings)

    def get_api_settings(self):
        """获取 API 设置"""
        settings = self.load_settings()
        return settings.get("api_settings", self.default_settings["api_settings"])

    def set_api_settings(self, key_file="", key_text="", key_source="file",
                        api_url_t2v=None, api_url_i2v=None, query_url=None):
        """设置 API 参数"""
        settings = self.load_settings()

        current_api = settings.get("api_settings", {})
        settings["api_settings"] = {
            "key_file": key_file,
            "key_text": key_text,
            "key_source": key_source,
            "api_url_t2v": api_url_t2v or current_api.get("api_url_t2v",
                "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/text-to-video"),
            "api_url_i2v": api_url_i2v or current_api.get("api_url_i2v",
                "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/image-to-video"),
            "query_url": query_url or current_api.get("query_url",
                "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi"),
            "upload_token_url": current_api.get("upload_token_url",
                "https://api.bizyair.cn/x/v1/upload/token"),
            "upload_commit_url": current_api.get("upload_commit_url",
                "https://api.bizyair.cn/x/v1/input_resource/commit")
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

# ==================== API Key Manager ====================
class Sora2APIKeyManager:
    """Sora2 API 密钥管理器"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.key_text = ""
        self.current_key_index = 0
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

    def __init__(self, history_file="vods_tasks_history.json"):
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
            "display": task_data.get('display', 'vertical'),
            "duration": task_data.get('duration', 5),
            "api_key_used": self._mask_api_key(api_key_used),
            "timestamps": {
                "created_at": datetime.now().isoformat(),
                "submitted_at": datetime.now().isoformat(),
                "completed_at": None
            },
            "result": {
                "video_url": None,
                "error_message": None
            }
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
        print(f"[Download] 开始下载: {self.url}")

        # 临时清除系统代理环境变量，确保不使用任何代理
        old_env = {}
        proxy_vars = ['http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY',
                      'all_proxy', 'ALL_PROXY', 'socks_proxy', 'SOCKS_PROXY',
                      'no_proxy', 'NO_PROXY']
        for var in proxy_vars:
            if var in os.environ:
                old_env[var] = os.environ[var]
                del os.environ[var]

        try:
            # 优先使用 urllib（不受 PySocks 库影响，更可靠）
            # 因为此项目依赖中包含 pysocks，requests 库会被自动配置使用 SOCKS 代理
            # 即使设置 trust_env=False 和 proxies=None 也无法完全禁用
            # urllib 不受 PySocks 影响，更适合国内 API 直连
            print(f"[Download] 使用 urllib 下载（不受 PySocks 影响）")
            self._download_with_urllib()

        except Exception as e:
            print(f"[Download] urllib 下载失败: {e}")
            import traceback
            print(f"[Download] traceback: {traceback.format_exc()}")
            self.finished.emit(False, "")
        finally:
            # 恢复环境变量
            for var, val in old_env.items():
                os.environ[var] = val
            print(f"[Download] 下载任务结束")

    def _download_with_requests(self):
        """使用 requests 下载（已增强代理禁用）"""
        import urllib3
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        session = requests.Session()
        session.trust_env = False
        session.proxies.clear()
        session.proxies.update({
            "http": None,
            "https": None,
            "ftp": None,
            "socks4": None,
            "socks5": None
        })
        session.verify = False

        response = session.get(
            self.url,
            stream=True,
            timeout=120,
            headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            }
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

    def _download_with_urllib(self):
        """使用 urllib 下载（不受 PySocks 影响）"""
        import urllib.request
        import ssl

        # 创建不验证 SSL 的上下文
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE

        # 创建请求
        req = urllib.request.Request(
            self.url,
            headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            }
        )

        # 下载文件
        with urllib.request.urlopen(req, timeout=120, context=ssl_context) as response:
            with open(self.local_path, 'wb') as f:
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)

        self.finished.emit(True, self.local_path)

# ==================== Video Generation Worker ====================
class Sora2VideoGenerationWorker(QThread):
    """Sora2 单个视频生成工作线程"""
    progress_updated = pyqtSignal(int, str, str)
    task_finished = pyqtSignal(bool, str, dict, str)
    time_updated = pyqtSignal(str, str)
    log_updated = pyqtSignal(str)
    request_id_updated = pyqtSignal(str, str)  # (request_id, task_id)

    def __init__(self, task, task_id, api_key, api_manager):
        super().__init__()
        self.task = task
        self.task_id = task_id
        self.api_key = api_key
        self.api_manager = api_manager
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

            if not self.api_key:
                self.log_message("API key not configured or empty")
                self.task_finished.emit(False, "API key not configured", {}, self.task_id)
                return

            prompt = self.task.get('prompt', '')
            video_mode = self.task.get('video_mode', 't2v')
            display = self.task.get('display', 'vertical')
            image_input = self.task.get('image_input', '')

            self.log_message(f"Mode: {'文生视频' if video_mode == 't2v' else '图生视频'}")
            self.log_message(f"Display: {display}")

            output_dir = "output"
            if not os.path.exists(output_dir):
                os.makedirs(output_dir)

            timestamp_str = datetime.now().strftime("%H%M%S")
            base_filename = f"vods_{video_mode}_{timestamp_str}"

            if video_mode == "i2v":
                if not image_input:
                    self.task_finished.emit(False, "图生视频模式需要上传图片", {}, self.task_id)
                    return

                # LTX2.3 I2V 需要图片 URL，本地文件需先上传
                self.progress_updated.emit(20, "处理图片中...", self.task_id)
                try:
                    image_input = BizyAirUploadUtils.get_image_url(
                        image_input, self.api_key, self.log_updated
                    )
                    self.log_message(f"图片URL准备完成")
                except Exception as upload_err:
                    self.log_message(f"图片上传失败: {str(upload_err)}")
                    self.task_finished.emit(False, f"图片上传失败: {str(upload_err)}", {}, self.task_id)
                    return

                self.progress_updated.emit(30, "准备图生视频请求...", self.task_id)

            else:
                self.progress_updated.emit(30, "准备文生视频请求...", self.task_id)
                self.log_message("使用文生视频模式")

            # 更新 task 中的 image_input 为已上传的 URL
            self.task['image_input'] = image_input

            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }

            # 构建 LTX2.3 请求数据
            bizyair_request_data = self._build_request_data()

            # 根据视频模式选择 LTX2.3 API URL
            settings_manager = Sora2SettingsManager()
            api_settings = settings_manager.get_api_settings()
            if video_mode == "i2v":
                api_url = api_settings.get("api_url_i2v",
                    "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/image-to-video")
            else:
                api_url = api_settings.get("api_url_t2v",
                    "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/text-to-video")

            self.log_message(f"发送 LTX2.3 API 请求: {api_url}")
            self.log_message(f"请求数据: {json.dumps(bizyair_request_data, ensure_ascii=False, indent=2)}")
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

                request_id = result_data.get('request_id') or result_data.get('data', {}).get('request_id')

                if not request_id:
                    error_msg = result_data.get('message', 'API response format error: missing request_id')
                    self.task_finished.emit(False, error_msg, {}, self.task_id)
                    return

                # LTX2.3 始终是异步，需要轮询查询结果
                # 在任务状态卡片上显示 request_id
                self.request_id_updated.emit(request_id, self.task_id)
                self.progress_updated.emit(60, "查询任务状态...", self.task_id)
                video_url = self.check_video_status(request_id)

                if video_url:
                    self.progress_updated.emit(90, "视频URL获取成功", self.task_id)

                    result = {
                        'id': request_id,
                        'request_id': request_id,
                        'url': video_url,
                        'prompt': prompt,
                        'display': display,
                        'video_mode': video_mode,
                        'task_name': task_name,
                        'timestamp': datetime.now().isoformat(),
                        'base_filename': base_filename
                    }

                    self.progress_updated.emit(100, "任务完成!", self.task_id)
                    self.task_finished.emit(True, "LTX2 视频生成成功", result, self.task_id)
                else:
                    # 轮询超时，传递 request_id 以便用户手动查询
                    fail_result = {
                        'request_id': request_id,
                        'id': request_id,
                        'url': '',
                        'prompt': prompt,
                        'video_mode': video_mode,
                        'task_name': task_name
                    }
                    self.task_finished.emit(False, "LTX2 视频生成超时，可点击查询按钮手动查询", fail_result, self.task_id)

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
        """查询 LTX2.3 任务状态

        提交后等待 120 秒再开始轮询，然后每 1 分钟查询一次
        """
        initial_delay = 120  # 120 秒后开始轮询
        check_interval = 30  # 每 30 秒轮询一次
        max_attempts = 90

        settings_manager = Sora2SettingsManager()
        api_settings = settings_manager.get_api_settings()
        query_base_url = api_settings.get("query_url",
            "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi")

        # 初始等待阶段（5 分钟）
        self.log_message(f"任务已提交，等待 {initial_delay // 60} 分钟后开始轮询...")
        elapsed = 0
        while elapsed < initial_delay:
            if self.is_cancelled:
                self.log_message("Task cancelled during initial wait")
                return None
            sleep_time = min(10, initial_delay - elapsed)
            time.sleep(sleep_time)
            elapsed += sleep_time
            self.progress_updated.emit(
                min(59, 50 + (elapsed * 10 // initial_delay)),
                f"等待轮询... ({elapsed // 60}/{initial_delay // 60} 分钟)",
                self.task_id
            )

        self.log_message("开始轮询任务状态...")

        for attempt in range(max_attempts):
            if self.is_cancelled:
                self.log_message("Task cancelled")
                return None

            try:
                headers = {
                    "Authorization": f"Bearer {self.api_key}"
                }

                response = requests.get(
                    f"{query_base_url}/{request_id}",
                    headers=headers,
                    timeout=30,
                    proxies={"http": None, "https": None}
                )

                response.raise_for_status()

                data = response.json()

                # 查询响应格式：{"code": 20000, "status": true, "data": {"status": "Success", "outputs": {...}}}
                # 顶层 status 是布尔值，真正的任务状态在 data.status 中
                data_inner = data.get('data', {})
                if isinstance(data_inner, dict) and 'status' in data_inner:
                    status = data_inner.get('status', '')
                    outputs = data_inner.get('outputs', {})
                else:
                    status = data.get('status', '')
                    outputs = data.get('outputs', {})

                self.log_message(f"轮询结果: status={status}, has_videos={bool(outputs.get('videos', []))}")

                self.progress_updated.emit(
                    min(90, 60 + (attempt * 30 // max_attempts)),
                    f"查询中... ({status}) 第 {attempt+1} 次",
                    self.task_id
                )

                if status == 'Success':
                    videos = outputs.get('videos', []) if outputs else []
                    if videos:
                        video_url = videos[0]
                        self.log_message(f"Video generation completed: {video_url}")
                        return video_url
                    self.log_message(f"status=Success 但无视频输出")
                    return None

                elif status == 'Failed':
                    error_info = data.get('message', '') or (data.get('data', {}) or {}).get('message', '') or 'Generation failed'
                    self.log_message(f"Video generation failed: {error_info}")
                    return None

                else:
                    self.log_message(f"Video generating... ({status}) - Check {attempt+1}")

            except Exception as e:
                self.log_message(f"Status query exception: {str(e)}")

            if attempt < max_attempts - 1:
                time.sleep(check_interval)

        self.log_message(f"Video generation timeout ({initial_delay // 60 + max_attempts * check_interval // 60} minutes)")
        return None

    def _build_request_data(self):
        """构建 LTX2.3 API 请求数据"""
        video_mode = self.task.get('video_mode', 't2v')
        prompt = self.task.get('prompt', '')
        display = self.task.get('display', 'vertical')
        image_input = self.task.get('image_input', '')

        if video_mode == "i2v":
            # 图生视频 - image_input 已在上传阶段转换为 URL
            image_urls = image_input if isinstance(image_input, list) else [image_input]
            return {
                "prompt": prompt,
                "image": image_urls,
                "duration": 5,
                "resolution": "1080P",
                "display": display,
                "seed": -1
            }
        else:
            # 文生视频
            return {
                "seed": -1,
                "display": display,
                "resolution": "1080P",
                "duration": 5,
                "prompt": prompt
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
    request_id_updated = pyqtSignal(str, str)  # (request_id, task_id)

    def __init__(self, api_manager=None):
        super().__init__()
        self.workers = {}
        self.completed_tasks = 0
        self.total_tasks = 0
        self.api_manager = api_manager if api_manager is not None else Sora2APIKeyManager()

    def log_message(self, message):
        Utils.log_message(message, self.log_updated, "Sora2 Batch Manager")

    def start_task(self, task_id, task, api_key):
        """立即启动单个任务"""
        worker = Sora2VideoGenerationWorker(
            task, task_id, api_key, self.api_manager
        )
        self.workers[task_id] = worker

        worker.progress_updated.connect(self.task_progress)
        worker.task_finished.connect(self.on_single_task_finished)
        worker.time_updated.connect(self.task_time_updated)
        worker.log_updated.connect(self.log_updated)
        worker.request_id_updated.connect(self.request_id_updated)

        worker.start()
        self.log_message(f"Started task {task_id}")

    def add_tasks(self, task_map, key_file=None):
        """添加任务并立即启动（并发执行）"""
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

        # 立即启动所有任务（并发执行）
        for i, (task_id, task) in enumerate(task_map.items()):
            key_index = i % len(available_keys)
            api_key = available_keys[key_index]
            self.start_task(task_id, task, api_key)

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

        # 检查是否所有任务都已完成
        if self.completed_tasks >= self.total_tasks:
            self.log_message(f"当前批次任务完成! 成功: {self.completed_tasks}/{self.total_tasks}")
            self.all_tasks_finished.emit()
            # 不再重置计数器，改为累积统计，用于全局任务跟踪
            # self.completed_tasks = 0
            # self.total_tasks = 0
            # self.workers.clear()

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
    """图片拖拽上传组件，支持本地文件和远程 URL"""
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

        # URL 输入按钮
        self.url_btn = PushButton("🔗 输入URL")
        self.url_btn.setFixedHeight(32)
        self.url_btn.setStyleSheet("""
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
        self.url_btn.clicked.connect(self.input_url)
        container_layout.addWidget(self.url_btn)

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
        """加载本地图片并显示"""
        try:
            pixmap = QPixmap(file_path)
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    250, 130,
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                self.image_label.setPixmap(scaled_pixmap)

                self.current_image_path = file_path
                self.current_image_data = file_path
                self.image_dropped.emit(file_path, file_path)

        except Exception as e:
            QMessageBox.warning(self, "错误", f"加载图片失败: {str(e)}")

    def input_url(self):
        """输入远程图片 URL"""
        from PyQt5.QtWidgets import QInputDialog
        url, ok = QInputDialog.getText(
            self, "输入图片URL", "请输入图片的远程URL地址:",
            text=self.current_image_path if self.current_image_path.startswith('http') else ""
        )
        if ok and url.strip():
            url = url.strip()
            if url.startswith('http://') or url.startswith('https://'):
                self.current_image_path = url
                self.current_image_data = url
                self.image_label.setText(f"🌐\n\n已设置远程URL\n{url[:50]}...")
                self.image_dropped.emit(url, url)
            else:
                QMessageBox.warning(self, "警告", "请输入有效的HTTP/HTTPS URL地址")

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
        self.status = "等待开始"
        self.key_source = "文件密钥"
        self.request_id = ""  # request_id
        self.is_expanded = True  # 卡片展开/收缩状态

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

        # Row 1: Task name (left) and Status + Mode + Key type (right)
        top_layout = QHBoxLayout()

        # 左侧：任务名称和 request_id
        left_container = QWidget()
        left_layout = QHBoxLayout(left_container)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(8)

        self.name_label = StrongBodyLabel(self.task_name)
        self.name_label.setStyleSheet("color: #ffffff; font-size: 14px; font-weight: 600;")
        left_layout.addWidget(self.name_label)

        # request_id 标签（初始隐藏）
        self.request_id_label = CaptionLabel("")
        self.request_id_label.setStyleSheet("color: #ff9800; font-size: 11px; font-weight: 500; padding: 4px 8px; background: #3a2a1a; border-radius: 4px;")
        self.request_id_label.setVisible(False)
        left_layout.addWidget(self.request_id_label)

        top_layout.addWidget(left_container)
        top_layout.addStretch()

        # 右上角容器：状态、模式、密钥类型和缩小/展开按钮在同一行
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

        # 缩小/展开按钮
        self.toggle_btn = PushButton("👁")
        self.toggle_btn.setFixedSize(28, 24)
        self.toggle_btn.setToolTip("缩小任务卡片")
        self.toggle_btn.setStyleSheet("""
            PushButton {
                background-color: #3a3a3a;
                color: #888888;
                border: 1px solid #505050;
                border-radius: 4px;
                font-size: 12px;
            }
            PushButton:hover {
                background-color: #4a4a4a;
                color: #ffffff;
            }
        """)
        self.toggle_btn.clicked.connect(self.toggle_visibility)
        right_layout.addWidget(self.toggle_btn)

        top_layout.addWidget(right_container)
        layout.addLayout(top_layout)

        # Row 2: Task parameters
        params_layout = QHBoxLayout()

        video_mode = self.task_params.get('video_mode', 't2v')
        display = self.task_params.get('display', 'vertical')
        duration = self.task_params.get('duration', 5)

        display_text = "竖屏" if display == "vertical" else "横屏"
        params_text = f"{'图生视频' if video_mode == 'i2v' else '文生视频'} - {display_text} - {duration}秒"
        self.params_label = CaptionLabel(params_text)
        self.params_label.setStyleSheet("color: #888888; font-size: 12px; background: #353535;")
        params_layout.addWidget(self.params_label)

        params_layout.addStretch()
        layout.addLayout(params_layout)

        # Row 3: Prompt
        prompt = self.task_params.get('prompt', '')
        if prompt:
            if len(prompt) > 70:
                prompt_display = prompt[:67] + "..."
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

    def set_request_id(self, request_id):
        """设置 request_id 并显示"""
        self.request_id = request_id
        if request_id:
            # 显示前 48 个字符，太长则截断
            display_id = request_id[:48] if len(request_id) > 48 else request_id
            self.request_id_label.setText(f"ID: {display_id}")
            self.request_id_label.setVisible(True)
        else:
            self.request_id_label.setVisible(False)

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

    def toggle_visibility(self):
        """切换卡片展开/收缩状态"""
        self.is_expanded = not self.is_expanded

        if self.is_expanded:
            # 展开卡片：恢复完整显示
            self.toggle_btn.setText("👁")
            self.toggle_btn.setToolTip("缩小任务卡片")
            self.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
            self.setMinimumHeight(145)
            self.setMaximumHeight(16777215)  # 清除最大高度限制

            # 显示所有内容
            for i in range(self.layout().count()):
                item = self.layout().itemAt(i)
                if item and item.widget():
                    item.widget().show()
                elif item.layout():
                    # 显示布局中的所有子项
                    for j in range(item.layout().count()):
                        sub_item = item.layout().itemAt(j)
                        if sub_item and sub_item.widget():
                            sub_item.widget().show()

        else:
            # 收缩卡片：只显示标题行和按钮
            self.toggle_btn.setText("👁‍🗨")
            self.toggle_btn.setToolTip("展开任务卡片")
            # 设置固定高度
            self.setFixedHeight(45)

            # 隐藏除了第一行（top_layout）外的所有内容
            for i in range(1, self.layout().count()):
                item = self.layout().itemAt(i)
                if item and item.widget():
                    item.widget().hide()
                elif item.layout():
                    # 隐藏布局中的所有子项
                    for j in range(item.layout().count()):
                        sub_item = item.layout().itemAt(j)
                        if sub_item and sub_item.widget():
                            sub_item.widget().hide()

# ==================== Main Widget ====================
class Sora2VideoGenerationWidget(QWidget, PlayVideoMixin):
    """Sora2 视频生成主组件"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.batch_manager = None
        self.api_manager = Sora2APIKeyManager()
        self.settings_manager = Sora2SettingsManager()

        api_settings = self.settings_manager.get_api_settings()

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
        # self.add_log("=== Sora2 视频生成系统已启动 ===")
        # self.add_log(f"初始化时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
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
        self.batch_manager.request_id_updated.connect(self.update_task_request_id)

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

        title = QLabel("LTX2 AI 视频生成")
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

        self.display_vertical = QRadioButton("竖屏")
        self.display_vertical.setChecked(True)
        self.display_vertical.setStyleSheet("QRadioButton { color: #ffffff; font-size: 13px; }")

        self.display_horizontal = QRadioButton("横屏")
        self.display_horizontal.setStyleSheet("QRadioButton { color: #ffffff; font-size: 13px; }")

        ratio_layout.addWidget(self.display_vertical)
        ratio_layout.addWidget(self.display_horizontal)

        mode_ratio_layout.addWidget(ratio_widget, 1)

        # 视频时长（LTX2.3 固定 5 秒）
        duration_label = QLabel("5秒")
        duration_label.setStyleSheet("color: #888888; font-size: 13px;")
        mode_ratio_layout.addWidget(duration_label, 1)

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

        # Tab 1: Task Status (进行中的任务)
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

        # Tab 2: Response Results (响应结果 - 成功完成的任务)
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
        self.tab_widget.addTab(results_tab, "响应结果")

        # Tab 3: Operation Logs (操作日志)
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

        self.tab_widget.addTab(logs_tab, "操作日志")

        layout.addWidget(self.tab_widget, 1)

        return panel

    def on_video_mode_changed(self, index):
        """视频模式切换事件"""
        if index == 1:
            self.image_container.setVisible(True)
        else:
            self.image_container.setVisible(False)

    def set_display(self, display):
        """Set display mode"""
        if display == "vertical":
            self.display_vertical.setChecked(True)
            self.display_horizontal.setChecked(False)
        else:
            self.display_vertical.setChecked(False)
            self.display_horizontal.setChecked(True)

    def get_display(self):
        """Get current display mode"""
        return "vertical" if self.display_vertical.isChecked() else "horizontal"

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

        if video_mode == "i2v" and not self.image_drop_widget.current_image_path:
            QMessageBox.warning(self, "警告", "图生视频模式需要上传图片")
            return

        display = self.get_display()

        task = {
            'name': f'LTX2_{"图生视频" if video_mode == "i2v" else "文生视频"}_{datetime.now().strftime("%H%M%S")}',
            'prompt': prompt,
            'video_mode': video_mode,
            'display': display,
            'duration': 5
        }

        if video_mode == "i2v":
            # LTX2.3 I2V 需要文件路径或 URL，Worker 会自动上传本地文件
            task['image_input'] = self.image_drop_widget.current_image_path

        task_map = {f"task_{int(time.time())}": task}
        self.start_generation(task_map)

    def generate_batch_videos(self):
        """批量生成视频"""
        batch_text = self.batch_list.toPlainText().strip()
        if not batch_text:
            QMessageBox.warning(self, "警告", "请输入批量任务列表")
            return

        video_mode = "i2v" if self.video_mode_combo.currentIndex() == 1 else "t2v"
        display = self.get_display()

        lines = [line.strip() for line in batch_text.split('\n') if line.strip()]
        task_map = {}

        for i, line in enumerate(lines):
            if video_mode == "i2v" and '|' in line:
                parts = line.split('|', 1)
                if len(parts) == 2:
                    image_path, prompt = parts
                    task = {
                        'name': f'LTX2 图生视频_{i+1:03d}',
                        'prompt': prompt.strip(),
                        'video_mode': 'i2v',
                        'display': display,
                        'duration': 5,
                        'image_input': image_path.strip()
                    }
            else:
                task = {
                    'name': f'LTX2_{"图生视频" if video_mode == "i2v" else "文生视频"}_{i+1:03d}',
                    'prompt': line,
                    'video_mode': video_mode,
                    'display': display,
                    'duration': 5
                }

                if video_mode == "i2v":
                    task['image_input'] = self.image_drop_widget.current_image_path

            task_map[f"task_{int(time.time())}_{i}"] = task

        if task_map:
            self.start_generation(task_map)

    def start_generation(self, task_map):
        """Start generation - 不再清除之前的任务，保留所有任务历史"""
        # 不再清除之前的任务卡片和结果卡片，保留所有任务历史
        # self.clear_task_cards()  # 注释掉，不清除之前的任务
        # self.clear_result_cards()  # 注释掉，不清除之前的结果

        for task_id, task in task_map.items():
            # 检查任务是否已存在，避免重复添加
            if task_id not in self.task_status_cards:
                self.add_task_status_card(task_id, task)
            else:
                # 任务已存在，重新启动计时器
                self.task_status_cards[task_id].start_timing()

        self.batch_manager.add_tasks(task_map, self.key_file_path)

    def add_task_status_card(self, task_id, task):
        """Add task status card"""
        task_params = {
            'video_mode': task.get('video_mode', 't2v'),
            'display': task.get('display', 'vertical'),
            'prompt': task.get('prompt', ''),
            'duration': task.get('duration', 5)
        }

        card = Sora2TaskStatusCard(task_id, task.get('name', f'Task_{task_id}'), task_params, self)
        self.tasks_layout.insertWidget(0, card)  # 插入到最上方，最新的任务在最前面
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
            # 同时刷新整体进度统计
            self.update_batch_progress(0, 0)

    def update_task_time(self, time_string, task_id):
        """Update task time - 同时更新任务状态卡片和结果卡片"""
        # 更新任务状态卡片的时间
        if task_id in self.task_status_cards:
            self.task_status_cards[task_id].update_time(time_string)

        # 同时更新对应结果卡片的标题时间
        for result_card in self.video_result_cards:
            if hasattr(result_card, 'task_id') and result_card.task_id == task_id:
                if hasattr(result_card, 'title_label') and hasattr(result_card, 'task_name'):
                    task_name = result_card.task_name
                    request_id = result_card.request_id if hasattr(result_card, 'request_id') else ''

                    # 重新构建标题，使用新的时间
                    if time_string and request_id:
                        new_title = f"Task: {task_name} | 用时: {time_string} | ID: {request_id[:48]}"
                    elif time_string:
                        new_title = f"Task: {task_name} | 用时: {time_string}"
                    elif request_id:
                        new_title = f"Task: {task_name} | ID: {request_id[:48]}"
                    else:
                        new_title = f"Task: {task_name}"

                    result_card.title_label.setText(new_title)
                break

    def update_task_request_id(self, request_id, task_id):
        """Update task request_id"""
        if task_id in self.task_status_cards:
            if request_id:
                self.task_status_cards[task_id].set_request_id(request_id)

    def play_completion_sound(self):
        """播放任务完成提示音"""
        try:
            sound_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ok.mp3")
            if os.path.exists(sound_file):
                if platform.system() == 'Darwin':  # macOS
                    subprocess.Popen(['afplay', sound_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                elif platform.system() == 'Windows':
                    import winsound
                    winsound.PlaySound(sound_file, winsound.SND_FILENAME | winsound.SND_ASYNC)
                else:  # Linux
                    subprocess.Popen(['aplay', sound_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            self.add_log(f"[提示音] 播放失败: {str(e)}")

    def on_task_finished(self, success, message, result_data, task_id):
        """Task finished callback"""
        # 成功时播放提示音
        if success:
            self.play_completion_sound()

        if task_id in self.task_status_cards:
            # 停止计时器
            self.task_status_cards[task_id].stop_timing()
            self.task_status_cards[task_id].set_completed(success, message)
            # 任务卡片保留在"任务状态"选项卡中，不再自动移除
            # 用户可以手动点击缩小/展开按钮来管理卡片显示

        if success and result_data:
            self.add_simple_result_card(result_data, task_id)
            # 自动下载视频到 output 目录
            video_url = result_data.get('url', '')
            if video_url:
                self.download_video_to_output(video_url)
        elif not success and result_data and result_data.get('request_id'):
            # 失败但有 request_id，创建结果卡片以便用户手动查询
            self.add_simple_result_card(result_data, task_id)

        # 刷新进度统计
        self.update_batch_progress(0, 0)

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
            title = QLabel(f"Task: {task_name} | 用时: {time_str} | ID: {request_id[:48]}")
        elif time_str:
            title = QLabel(f"Task: {task_name} | 用时: {time_str}")
        elif request_id:
            title = QLabel(f"Task: {task_name} | ID: {request_id[:48]}")
        else:
            title = QLabel(f"Task: {task_name}")

        title.setStyleSheet("font-size: 13px; font-weight: bold; color: #ffffff;")
        layout.addWidget(title)

        url = video_data.get('url', '')

        # 使用 LineEdit 显示完整 URL（只读）
        url_input = qf.LineEdit()
        url_input.setText(url)
        url_input.setReadOnly(True)  # 始终只读
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

        # 存储卡片引用以便后续更新
        result_card.url_input = url_input
        result_card.request_id = request_id
        result_card.task_id = task_id
        result_card.task_name = task_name
        result_card.title_label = title  # 保存标题 label 引用，用于实时更新用时

        btn_layout = QHBoxLayout()

        # 有 request_id 时添加查询按钮
        if request_id:
            query_btn = PushButton("🔄 查询")
            query_btn.clicked.connect(lambda: self.query_task_result(request_id, url_input, result_card))
            btn_layout.addWidget(query_btn)

        play_btn = PushButton("▶ 播放")
        play_btn.clicked.connect(lambda: self.play_video(url_input.text()))  # 使用输入框中的 URL
        btn_layout.addWidget(play_btn)

        copy_btn = PushButton("复制URL")
        copy_btn.clicked.connect(lambda: self.copy_url(url_input.text()))
        btn_layout.addWidget(copy_btn)

        open_btn = PushButton("浏览器打开")
        open_btn.clicked.connect(lambda: QDesktopServices.openUrl(QUrl(url_input.text())))
        btn_layout.addWidget(open_btn)

        btn_layout.addStretch()
        layout.addLayout(btn_layout)

        self.results_layout.insertWidget(0, result_card)  # 插入到最上方，最新的结果在最前面
        self.video_result_cards.append(result_card)

    def copy_url(self, url):
        """Copy URL to clipboard"""
        # 添加调试日志，帮助排查URL显示问题
        print(f"[DEBUG] copy_url 被调用，URL内容: {url}")
        self.add_log(f"[复制URL] 复制内容: {url[:100] if url else '(空)'}")

        # 使用 QApplication.clipboard() 而不是 QCoreApplication.clipboard()
        clipboard = QApplication.clipboard()
        clipboard.setText(url)
        InfoBar.success(
            title="成功",
            content=f"URL已复制到剪贴板: {url[:60]}..." if len(url) > 60 else "URL已复制到剪贴板",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=2000,
            parent=self
        )

    def query_task_result(self, request_id, url_input, result_card):
        """查询任务结果"""
        api_key = self.api_manager.get_next_key()
        if not api_key:
            InfoBar.error(
                title="错误",
                content="未配置 API 密钥",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )
            return

        self.add_log(f"[查询] 查询任务 {request_id[:48]}")

        settings_manager = Sora2SettingsManager()
        api_settings = settings_manager.get_api_settings()
        query_url = api_settings.get("query_url", "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi")

        try:
            headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
            response = requests.get(f"{query_url}/{request_id}", headers=headers, timeout=30, proxies={"http": None, "https": None})
            response.raise_for_status()
            data = response.json()

            self.add_log(f"[查询] 响应: {json.dumps(data, ensure_ascii=False, indent=2)}")

            status = data.get('status', '')
            if status == 'Success':
                outputs = data.get('outputs', {})
                videos = outputs.get('videos', [])
                if videos:
                    video_url = videos[0]
                    url_input.setText(video_url)
                    url_input.setStyleSheet("LineEdit { background-color: #1e2a1e; color: #6bcb77; font-size: 11px; border: 1px solid #28a745; border-radius: 4px; padding: 6px; }")
                    task_id = result_card.task_id
                    if task_id in self.task_status_cards:
                        self.task_status_cards[task_id].stop_timing()
                        self.task_status_cards[task_id].set_completed(True, "查询成功")
                    self.play_completion_sound()
                    InfoBar.success(
                        title="查询成功",
                        content="视频已生成",
                        orient=Qt.Horizontal,
                        isClosable=True,
                        position=InfoBarPosition.TOP,
                        duration=3000,
                        parent=self
                    )
                    self.download_video_to_output(video_url)
                    return
            elif status == 'Failed':
                InfoBar.warning(
                    title="查询失败",
                    content="任务执行失败",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=3000,
                    parent=self
                )
                return

            InfoBar.info(
                title="任务执行中",
                content=f"当前状态: {status}",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )
        except Exception as e:
            self.add_log(f"[查询] 异常: {str(e)}")
            InfoBar.error(
                title="查询失败",
                content=str(e),
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )

    def download_video_to_output(self, url):
        """下载视频到 output 目录"""
        try:
            # 使用 VideoUtils 获取本地路径
            local_path = VideoUtils.get_local_video_path(url)
            filename = VideoUtils.extract_filename_from_url(url)

            # 创建下载线程
            download_thread = VideoDownloadThread(url, local_path, self)
            download_thread.finished.connect(lambda success, path: self.on_download_finished(success, path, filename))
            download_thread.start()

            self.add_log(f"[下载] 开始下载视频到: {local_path}")

        except Exception as e:
            self.add_log(f"[下载] 下载准备失败: {str(e)}")

    def on_download_finished(self, success, local_path, filename):
        """视频下载完成回调"""
        if success:
            self.add_log(f"[下载] 视频已保存: {local_path}")
            InfoBar.success(
                title="下载完成",
                content=f"视频已保存到: {filename}",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )
        else:
            InfoBar.error(
                title="下载失败",
                content="视频下载失败，请稍后重试",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )

    # ==================== Play Video Mixin 接口实现 ====================
    def show_play_success_message(self, filename):
        """播放成功消息"""
        InfoBar.success(
            title="播放中",
            content=f"已打开本地视频：{filename}",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=2000,
            parent=self
        )

    def show_play_error_message(self, error):
        """播放错误消息"""
        InfoBar.error(
            title="错误",
            content=f"无法打开视频：{error}",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=3000,
            parent=self
        )

    def show_download_start_message(self, local_path):
        """下载开始消息"""
        InfoBar.info(
            title="下载中",
            content=f"正在下载视频到：{local_path}",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=3000,
            parent=self
        )

    def show_download_success_message(self, filename):
        """下载成功消息"""
        InfoBar.success(
            title="播放中",
            content=f"已打开视频：{filename}",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=3000,
            parent=self
        )

    def show_download_error_message(self):
        """下载失败消息"""
        InfoBar.error(
            title="下载失败",
            content="视频下载失败，请重试",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=5000,
            parent=self
        )

    def update_batch_progress(self, completed, total):
        """Update batch progress - 显示所有任务的整体统计"""
        # 统计所有任务的状态
        total_tasks = len(self.task_status_cards)
        if total_tasks == 0:
            self.batch_progress_label.setText("暂无任务")
            self.batch_progress_bar.setValue(0)
            return

        # 详细统计各种状态的任务数量
        not_started_count = 0  # 未开始（还在队列中）
        submitted_count = 0      # 已提交（已获取到 request_id）
        polling_count = 0       # 轮询中（已提交但在等待回调）
        completed_count = 0     # 已完成（已获取到视频 URL）
        failed_count = 0        # 失败

        for task_id, card in self.task_status_cards.items():
            status_text = card.status_label.text()

            # 判断任务状态
            if "等待开始" in status_text:
                not_started_count += 1
            elif "生成中" in status_text:
                # 检查是否已获取 request_id
                if card.request_id:
                    polling_count += 1
                else:
                    submitted_count += 1
            elif "已完成" in status_text:
                # 检查是否有视频 URL（通过检查结果卡片）
                has_video_url = False
                for result_card in self.video_result_cards:
                    if hasattr(result_card, 'task_id') and result_card.task_id == task_id:
                        if hasattr(result_card, 'url_input') and result_card.url_input.text() and result_card.url_input.text() != '':
                            has_video_url = True
                            break

                if has_video_url:
                    completed_count += 1
                else:
                    polling_count += 1  # 已提交但还在等待结果
            elif "生成失败" in status_text:
                failed_count += 1

        # 构建详细的统计信息文本
        stats_parts = []
        stats_parts.append(f"总计: {total_tasks}")

        if not_started_count > 0:
            stats_parts.append(f"未开始: {not_started_count}")
        if submitted_count > 0:
            stats_parts.append(f"已提交(轮询): {submitted_count}")
        if polling_count > 0:
            stats_parts.append(f"轮询中: {polling_count}")
        if completed_count > 0:
            stats_parts.append(f"已完成: {completed_count}")
        if failed_count > 0:
            stats_parts.append(f"失败: {failed_count}")

        self.batch_progress_label.setText(" | ".join(stats_parts))

        # 计算总体进度（基于已完成的任务）
        if total_tasks > 0:
            progress = int((completed_count / total_tasks) * 100)
            self.batch_progress_bar.setValue(progress)

    def on_all_tasks_finished(self):
        """任务ID 获取已完成，开始加载轮询中"""
        InfoBar.success(
            title="完成",
            content="任务ID 获取已完成，开始加载轮询中",
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

        # 加载视频参数
        video_params = self.settings_manager.get_video_params()
        display = video_params.get("display", "vertical")
        self.set_display(display)

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
        print(f"[LTX2] {message}")
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
            f"vods_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
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
        self.settings_manager.set_video_params(
            display=self.get_display(),
            duration=5
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
        self.setWindowTitle("LTX2 API 设置")
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

        api_layout.addWidget(QLabel("文生视频 API URL："))
        self.t2v_url_edit = LineEdit()
        self.t2v_url_edit.setFixedHeight(35)
        api_layout.addWidget(self.t2v_url_edit)

        api_layout.addWidget(QLabel("图生视频 API URL："))
        self.i2v_url_edit = LineEdit()
        self.i2v_url_edit.setFixedHeight(35)
        api_layout.addWidget(self.i2v_url_edit)

        api_layout.addWidget(QLabel("查询接口 URL："))
        self.query_url_edit_api = LineEdit()
        self.query_url_edit_api.setFixedHeight(35)
        api_layout.addWidget(self.query_url_edit_api)

        api_group.setLayout(api_layout)
        scroll_layout.addWidget(api_group)

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
        self.t2v_url_edit.setText(api_settings.get("api_url_t2v",
            "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/text-to-video"))
        self.i2v_url_edit.setText(api_settings.get("api_url_i2v",
            "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/image-to-video"))
        self.query_url_edit_api.setText(api_settings.get("query_url",
            "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi"))

    def save_settings(self):
        """保存设置"""
        key_source_map = {0: "file", 1: "env", 2: "text"}
        key_source = key_source_map.get(self.key_source_combo.currentIndex(), "file")

        success = self.settings_manager.set_api_settings(
            key_file=self.key_file_edit.text().strip(),
            key_text=self.key_text_edit.toPlainText().strip(),
            key_source=key_source,
            api_url_t2v=self.t2v_url_edit.text().strip(),
            api_url_i2v=self.i2v_url_edit.text().strip(),
            query_url=self.query_url_edit_api.text().strip()
        )

        if success:
            QMessageBox.information(self, "成功", "LTX2 API设置已保存")
            self.accept()
        else:
            QMessageBox.critical(self, "错误", "设置保存失败")

# ==================== Task History Dialog ====================
class Sora2TaskHistoryDialog(QDialog, PlayVideoMixin):
    """Sora2 任务历史查看对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("任务历史记录")
        self.setMinimumSize(900, 600)
        self.history_manager = Sora2TaskHistoryManager()

        # 获取父组件的管理器
        self.api_manager = parent.api_manager if parent else Sora2APIKeyManager()
        self.settings_manager = parent.settings_manager if parent else Sora2SettingsManager()

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

        query_pending_btn = PushButton("查询待处理")
        query_pending_btn.clicked.connect(self.query_all_pending)
        toolbar.addWidget(query_pending_btn)

        query_selected_btn = PushButton("查询选中")
        query_selected_btn.clicked.connect(self.query_selected_tasks)
        toolbar.addWidget(query_selected_btn)

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
        self.details_text.setStyleSheet("background-color: #1e1e1e; color: #aaaaaa; font-size: 18px;")
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

        # 添加播放按钮（使用不同颜色）
        self.play_btn = PushButton("▶ 播放视频")
        self.play_btn.clicked.connect(self.play_selected_task)
        self.play_btn.setStyleSheet("""
            PushButton {
                background-color: #28a745;
                color: #ffffff;
                border: none;
                border-radius: 4px;
                padding: 6px 16px;
                font-weight: 600;
            }
            PushButton:hover {
                background-color: #218838;
            }
        """)
        self.play_btn.setEnabled(False)  # 初始禁用，选中任务后启用
        button_layout.addWidget(self.play_btn)

        # 添加浏览器打开按钮（使用不同颜色）
        self.browser_btn = PushButton("浏览器打开")
        self.browser_btn.clicked.connect(self.open_in_browser)
        self.browser_btn.setStyleSheet("""
            PushButton {
                background-color: #007bff;
                color: #ffffff;
                border: none;
                border-radius: 4px;
                padding: 6px 16px;
                font-weight: 600;
            }
            PushButton:hover {
                background-color: #0056b3;
            }
        """)
        self.browser_btn.setEnabled(False)  # 初始禁用，选中任务后启用
        button_layout.addWidget(self.browser_btn)

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
            self.task_table.setItem(row, 0, QTableWidgetItem(task["task_id"]))
            self.task_table.setItem(row, 1, QTableWidgetItem(task["name"]))
            self.task_table.setItem(row, 2, QTableWidgetItem(task.get("request_id", "")))
            self.task_table.setItem(row, 3, QTableWidgetItem(task["status"]))
            self.task_table.setItem(row, 4, QTableWidgetItem("轮询"))
            self.task_table.setItem(row, 5, QTableWidgetItem(task["timestamps"]["created_at"]))
            self.task_table.setItem(row, 6, QTableWidgetItem(task["result"].get("video_url", "")))

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

            # 保存当前选择任务的 video_url，用于播放和浏览器打开
            self.current_video_url = task.get("result", {}).get("video_url", "")

            # 如果有视频 URL，启用播放和浏览器打开按钮
            if self.current_video_url:
                self.play_btn.setEnabled(True)
                self.browser_btn.setEnabled(True)
            else:
                self.play_btn.setEnabled(False)
                self.browser_btn.setEnabled(False)

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
            f"vods_tasks_history_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json",
            "JSON 文件 (*.json)"
        )
        if file_path:
            try:
                import shutil
                shutil.copy(self.history_manager.history_file, file_path)
                QMessageBox.information(self, "成功", f"任务历史已导出到: {file_path}")
            except Exception as e:
                QMessageBox.warning(self, "失败", f"导出失败: {str(e)}")

    def play_selected_task(self):
        """播放选中任务的视频"""
        if not hasattr(self, 'current_video_url') or not self.current_video_url:
            QMessageBox.warning(self, "提示", "请先选择一个有视频 URL 的任务")
            return

        # 使用 PlayVideoMixin 的 play_video 方法
        self.play_video(self.current_video_url)

    # ==================== Play Video Mixin 接口实现 ====================
    def show_play_success_message(self, filename):
        """播放成功消息"""
        QMessageBox.information(self, "播放", f"正在播放本地视频:\n{filename}")

    def show_play_error_message(self, error):
        """播放错误消息"""
        QMessageBox.warning(self, "播放失败", f"无法播放视频: {error}")

    def show_download_start_message(self, local_path):
        """下载开始消息"""
        QMessageBox.information(self, "下载", f"视频不存在，开始下载:\n{os.path.basename(local_path)}")

    def show_download_success_message(self, filename):
        """下载成功消息（下载完成后自动播放，不显示消息）"""
        pass

    def show_download_error_message(self):
        """下载失败消息"""
        QMessageBox.warning(self, "下载失败", "视频下载失败，请稍后重试")

    def open_in_browser(self):
        """在浏览器中打开选中任务的视频 URL"""
        if not hasattr(self, 'current_video_url') or not self.current_video_url:
            QMessageBox.warning(self, "提示", "请先选择一个有视频 URL 的任务")
            return

        try:
            QDesktopServices.openUrl(QUrl(self.current_video_url))
        except Exception as e:
            QMessageBox.warning(self, "打开失败", f"无法在浏览器中打开 URL:\n{str(e)}")

    def query_all_pending(self):
        """查询所有待处理任务"""
        history = self.history_manager.load_history()
        pending_tasks = [
            task for task in history["tasks"].values()
            if task.get("status") == "pending" and task.get("request_id")
        ]

        if not pending_tasks:
            QMessageBox.information(self, "提示", "没有待处理的任务")
            return

        reply = QMessageBox.question(
            self, "确认查询",
            f"发现 {len(pending_tasks)} 个待处理任务，是否全部查询？",
            QMessageBox.Yes | QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            self._batch_query_tasks(pending_tasks)

    def query_selected_tasks(self):
        """查询选中的任务"""
        selected_items = self.task_table.selectedItems()
        if not selected_items:
            QMessageBox.warning(self, "提示", "请先选择要查询的任务")
            return

        # 获取选中行的 request_id
        request_ids = set()
        for item in selected_items:
            row = item.row()
            request_id_item = self.task_table.item(row, 2)
            if request_id_item:
                request_id = request_id_item.text()
                if request_id:
                    request_ids.add(request_id)

        if not request_ids:
            QMessageBox.warning(self, "提示", "选中的任务没有 Request ID")
            return

        # 获取任务列表
        history = self.history_manager.load_history()
        tasks_to_query = [
            task for task in history["tasks"].values()
            if task.get("request_id") in request_ids
        ]

        self._batch_query_tasks(tasks_to_query)

    def _batch_query_tasks(self, tasks):
        """批量查询任务"""
        if not tasks:
            return

        # 获取 API 设置
        api_settings = self.settings_manager.get_api_settings()
        query_url = api_settings.get("query_url", "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi")

        # 查询每个任务
        success_count = 0
        for task in tasks:
            request_id = task.get("request_id")
            if not request_id:
                continue

            api_key = self.api_manager.get_next_key()
            if not api_key:
                print(f"查询任务 {request_id[:48]} 失败: 未配置 API 密钥")
                continue

            try:
                headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
                response = requests.get(f"{query_url}/{request_id}", headers=headers, timeout=30, proxies={"http": None, "https": None})
                response.raise_for_status()
                data = response.json()

                # 解析 LTX2.3 响应
                status = data.get('status', '')

                if status == 'Success':
                    outputs = data.get('outputs', {})
                    videos = outputs.get('videos', [])
                    if videos:
                        video_url = videos[0]
                        # 更新任务历史
                        task_id = task.get('task_id')
                        if task_id:
                            self.history_manager.update_task_status(
                                task_id, 'success', video_url=video_url
                            )
                        success_count += 1
                elif status == 'Failed':
                    task_id = task.get('task_id')
                    if task_id:
                        self.history_manager.update_task_status(
                            task_id, 'failed', error_message='任务执行失败'
                        )

            except Exception as e:
                print(f"查询任务 {request_id[:48]} 失败: {str(e)}")

        # 刷新任务列表
        self.load_tasks()

        QMessageBox.information(
            self, "查询完成",
            f"查询完成！\n成功: {success_count}/{len(tasks)}\n请查看任务列表中的状态更新"
        )

# ==================== Main Entry Point ====================
if __name__ == "__main__":
    from PyQt5.QtWidgets import QApplication

    app = QApplication(sys.argv)

    # Set dark theme
    qf.setTheme(Theme.DARK)

    window = Sora2VideoGenerationWidget()
    window.setWindowTitle("LTX2 AI 视频生成器")
    window.resize(1200, 800)
    window.show()

    sys.exit(app.exec_())
