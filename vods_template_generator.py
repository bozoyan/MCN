#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
模板化视频生成模块
基于 BizyAir API 的异步查询模式
支持通过 JSON 配置文件动态生成视频
"""

import os
import json
import time
import requests
import threading
from datetime import datetime
from typing import Dict, List, Optional, Any
from PyQt5.QtCore import QThread, pyqtSignal, Qt, QUrl, QObject, QTimer
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                            QTextEdit, QSpinBox, QMessageBox, QFileDialog,
                            QGroupBox, QSplitter, QFrame,
                            QScrollArea, QDialog, QGridLayout, QTabWidget,
                            QTableWidgetItem, QTableWidget)
from PyQt5.QtGui import QDesktopServices
from qfluentwidgets import (FluentIcon, PrimaryPushButton, PushButton,
                          LineEdit, ComboBox, ProgressBar, TableWidget, InfoBar, InfoBarPosition)

# ==================== 历史记录管理器 ====================
class TaskHistoryManager:
    """任务历史记录管理器"""

    def __init__(self, history_file="vods_log.json"):
        self.history_file = history_file
        self.history = []
        self.load_history()

    def load_history(self):
        """加载历史记录"""
        if os.path.exists(self.history_file):
            try:
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    self.history = json.load(f)
                print(f"已加载 {len(self.history)} 条历史记录")
            except Exception as e:
                print(f"加载历史记录失败: {e}")
                self.history = []
        else:
            self.history = []

    def save_history(self):
        """保存历史记录"""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, ensure_ascii=False, indent=2)
            print(f"已保存 {len(self.history)} 条历史记录到 {self.history_file}")
        except Exception as e:
            print(f"保存历史记录失败: {e}")

    def add_record(self, record: dict):
        """添加一条历史记录"""
        record['timestamp'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        self.history.append(record)
        self.save_history()

    def get_history(self) -> list:
        """获取所有历史记录"""
        return self.history

    def export_history(self, file_path: str = None) -> Optional[str]:
        """导出历史记录到文件"""
        if file_path is None:
            file_path = f"vods_history_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, ensure_ascii=False, indent=2)
            return file_path
        except Exception as e:
            print(f"导出历史记录失败: {e}")
            return None

# ==================== 配置加载器 ====================
class VODSConfigLoader:
    """视频生成配置加载器"""

    def __init__(self, config_dir="vods-json"):
        self.config_dir = config_dir
        self.models = []
        self.load_configs()

    def load_configs(self):
        """加载所有 JSON 配置文件"""
        if not os.path.exists(self.config_dir):
            print(f"配置目录不存在: {self.config_dir}")
            return

        for filename in os.listdir(self.config_dir):
            if filename.endswith('.json'):
                filepath = os.path.join(self.config_dir, filename)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                        config['filename'] = filename  # 保存文件名
                        self.models.append(config)
                        print(f"已加载配置: {config.get('name', filename)}")
                except Exception as e:
                    print(f"加载配置文件失败 {filename}: {e}")

        print(f"共加载 {len(self.models)} 个视频生成模型配置")

    def get_models(self) -> List[Dict]:
        """获取所有模型配置"""
        return self.models

    def get_model_by_name(self, name: str) -> Optional[Dict]:
        """根据名称获取模型配置"""
        for model in self.models:
            if model.get('name') == name:
                return model
        return None

    def get_model_names(self) -> List[str]:
        """获取所有模型名称列表"""
        return [model.get('name', 'Unknown') for model in self.models]

# ==================== 参数定义 ====================
class ParameterType:
    """参数类型枚举"""
    IMAGE = "image"           # 图片输入
    AUDIO = "audio"           # 音频输入
    VIDEO = "video"           # 视频输入
    PROMPT = "prompt"         # 提示词（文本）
    MODEL = "model"           # 模型选择
    WIDTH = "width"           # 宽度
    HEIGHT = "height"         # 高度
    FRAMES = "frames"         # 帧数
    DURATION = "duration"     # 时长（秒）
    ASPECT_RATIO = "aspect_ratio"  # 宽高比
    RESOLUTION = "resolution" # 分辨率预设
    INTEGER = "integer"       # 整数
    FLOAT = "float"          # 浮点数
    STRING = "string"         # 字符串

class ParameterDefinition:
    """参数定义"""

    # 字段名中文名称映射
    FIELD_NAME_CN = {
        "image": "图片",
        "audio": "音频",
        "video": "视频",
        "prompt": "提示词",
        "text": "文本",
        "positive_prompt": "提示词",
        "model": "模型",
        "model_name": "模型名称",
        "width": "宽度",
        "height": "高度",
        "num_frames": "帧数",
        "duration": "时长",
        "aspect_ratio": "宽高比",
        "resolution": "分辨率",
        "frames": "帧数",
    }

    # 字段名映射规则（根据用户提供的对应表更新）
    FIELD_MAPPING = {
        # 图片字段
        "image": ["image", ".image", "LoadImage.image"],
        # 音频字段
        "audio": ["audio", ".audio", "LoadAudio.audio"],
        # 视频字段
        "video": ["video", ".video", "LoadVideo.video"],
        # 提示词字段
        "prompt": ["prompt", ".prompt", "positive_prompt", "text"],
        "text": ["text", ".text", "CLIPTextEncode.text"],
        # 模型字段
        "model": ["model", ".model", "model_name"],
        # 宽度字段
        "width": ["width", ".width", "WInteger.value",
                  "245:INTConstant.value", "131:INTConstant.value", "132:INTConstant.value"],
        # 高度字段
        "height": ["height", ".height", "JWInteger.value",
                   "246:INTConstant.value", "38:JWInteger.value"],
        # 帧数字段
        "frames": ["270:INTConstant.value", "7:PrimitiveInt.value", "num_frames",
                   "107:WanImageToVideo.length", "WanVideoEmptyEmbeds.num_frames"],
        # 时长字段
        "duration": ["duration", ".duration", "27:PrimitiveInt.value"],
        # 宽高比字段
        "aspect_ratio": ["aspect_ratio", ".aspect_ratio"],
        # 分辨率字段
        "resolution": ["resolution", ".resolution", "BizyAir_Hailuo2_3_I2V.resolution"],
    }

    # 预设值选项（按照用户要求配置，不包含多余选项）
    PRESET_OPTIONS = {
        "aspect_ratio": ["16:9", "9:16"],
        "resolution": ["768P", "1080P"],
        "duration": [5, 6, 10, 15],
    }

    @classmethod
    def detect_parameter_type(cls, key: str, value: Any = None) -> Optional[str]:
        """根据字段键和值检测参数类型"""
        key_lower = key.lower()

        # 优先进行完整字段名精确匹配（针对具体字段如 131:INTConstant.value、27:PrimitiveInt.value）
        exact_matches = {
            "131:intconstant.value": ParameterType.WIDTH,
            "132:intconstant.value": ParameterType.HEIGHT,
            "245:intconstant.value": ParameterType.WIDTH,
            "246:intconstant.value": ParameterType.HEIGHT,
            "270:intconstant.value": ParameterType.FRAMES,
            "7:primitiveint.value": ParameterType.FRAMES,
            "27:primitiveint.value": ParameterType.DURATION,
            "38:jwinteger.value": ParameterType.HEIGHT,
            "107:wanimagetovideo.length": ParameterType.FRAMES,
        }

        if key_lower in exact_matches:
            return exact_matches[key_lower]

        # 然后检查通用字段匹配（针对 image、audio、model 等）
        for param_type, patterns in cls.FIELD_MAPPING.items():
            for pattern in patterns:
                # 跳过带冒号的精确匹配模式（已在上面处理）
                if ":" in pattern:
                    continue
                # 包含匹配检查（针对通用字段如 width）
                if pattern.lower() in key_lower:
                    # 对于数值类型，进行值验证
                    if isinstance(value, int):
                        if param_type == ParameterType.WIDTH:
                            return ParameterType.WIDTH if 100 < value < 5000 else None
                        elif param_type == ParameterType.HEIGHT:
                            return ParameterType.HEIGHT if 100 < value < 5000 else None
                        elif param_type == ParameterType.FRAMES:
                            return ParameterType.FRAMES if 1 < value < 1000 else None
                        elif param_type == ParameterType.DURATION:
                            return ParameterType.DURATION if value in [5, 6, 10, 15] else None
                    # 对于字符串类型，进行格式验证
                    elif isinstance(value, str):
                        if param_type == ParameterType.ASPECT_RATIO:
                            return ParameterType.ASPECT_RATIO if ":" in value else None
                        elif param_type == ParameterType.RESOLUTION:
                            return ParameterType.RESOLUTION if "P" in value else None
                        elif param_type == ParameterType.PROMPT:
                            return param_type
                        elif param_type == ParameterType.MODEL:
                            return param_type
                    # 对于其他类型，直接返回
                    elif value is None:
                        # 如果没有值，基于字段名直接返回类型
                        return param_type

        # 根据值类型推断（作为后备方案）
        if value is not None:
            if isinstance(value, int):
                if 100 < value < 5000:
                    # 可能是宽度或高度
                    if "width" in key_lower or "w_" in key_lower or "131" in key or "245" in key:
                        return ParameterType.WIDTH
                    elif "height" in key_lower or "h_" in key_lower or "132" in key or "246" in key:
                        return ParameterType.HEIGHT
                    return ParameterType.INTEGER
                elif 1 < value < 1000:
                    # 可能是帧数
                    if "270" in key or "107" in key or "frames" in key_lower:
                        return ParameterType.FRAMES
                    return ParameterType.INTEGER
                elif value in [5, 6, 10, 15]:
                    # 可能是时长
                    if "27" in key or "duration" in key_lower:
                        return ParameterType.DURATION
                    return ParameterType.INTEGER
            elif isinstance(value, float):
                return ParameterType.FLOAT
            elif isinstance(value, str):
                if value.startswith("http") and any(ext in value for ext in [".png", ".jpg", ".jpeg", ".webp"]):
                    return ParameterType.IMAGE
                elif value.startswith("http") and any(ext in value for ext in [".mp3", ".wav", ".aac"]):
                    return ParameterType.AUDIO
                elif value.startswith("http") and any(ext in value for ext in [".mp4", ".mov", ".avi"]):
                    return ParameterType.VIDEO
                elif ":" in value and value.count(":") == 1:
                    try:
                        w, h = value.split(":")
                        int(w), int(h)
                        return ParameterType.ASPECT_RATIO
                    except:
                        pass
                elif "P" in value and value.replace("P", "").replace("p", "").isdigit():
                    return ParameterType.RESOLUTION
                elif len(value) > 50:  # 假设长文本是提示词
                    return ParameterType.PROMPT

        return None

# ==================== API Key 管理器 ====================
class APIKeyManager:
    """API 密钥管理器 - 支持多密钥轮询"""

    def __init__(self):
        self.api_keys = []
        self.key_file = ""
        self.key_text = ""
        self.current_key_index = 0
        self.key_source = "env"  # env, file, text

    def load_keys_from_file(self, file_path):
        """从文件加载 API 密钥"""
        try:
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    keys = [line.strip() for line in f.readlines()
                           if line.strip() and not line.strip().startswith('#')]
                self.api_keys = [key for key in keys if len(key) > 10]
                self.key_file = file_path
                self.key_source = "file"
                self.current_key_index = 0
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
                self.key_source = "text"
                self.current_key_index = 0
                return True
        except Exception as e:
            print(f"Failed to load API key text: {e}")
        return False

    def get_next_key(self):
        """获取下一个可用的 API 密钥（轮询模式）"""
        if self.key_source == "env":
            return os.getenv('SiliconCloud_API_KEY')
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
        else:
            return len(self.api_keys)

    def get_all_keys(self):
        """获取所有可用的 API 密钥"""
        if self.key_source == "env":
            env_key = os.getenv('SiliconCloud_API_KEY')
            return [env_key] if env_key else []
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

# ==================== 批量任务管理器 ====================
class BatchManager(QObject):
    """批量任务管理器 - 支持多密钥并发和任务队列"""

    all_tasks_finished = pyqtSignal()
    task_progress = pyqtSignal(int, str, str)  # (进度, 消息, task_id)
    task_finished = pyqtSignal(bool, str, dict, str)  # (成功, 消息, 结果, task_id)
    log_updated = pyqtSignal(str)  # 日志更新
    batch_progress_updated = pyqtSignal(int, int)  # (已完成, 总数)

    def __init__(self, api_manager=None):
        super().__init__()
        self.workers = {}
        self.completed_tasks = 0
        self.total_tasks = 0
        self.api_manager = api_manager if api_manager is not None else APIKeyManager()
        self.pending_tasks = []  # 待启动的任务队列
        self.task_timer = QTimer(self)  # 任务启动定时器
        self.task_timer.timeout.connect(self.start_next_task)

    def log_message(self, message):
        """记录日志"""
        timestamp = datetime.now().strftime('%H:%M:%S')
        self.log_updated.emit(f"[{timestamp}] [BatchManager] {message}")

    def start_next_task(self):
        """启动下一个任务（定时器回调）"""
        if not self.pending_tasks:
            self.task_timer.stop()
            return

        task_id, config, input_values, api_key = self.pending_tasks.pop(0)

        worker = AsyncVideoGenerationWorker(
            config, input_values, api_key, task_id
        )
        self.workers[task_id] = worker

        worker.progress_updated.connect(
            lambda progress, msg: self.task_progress.emit(progress, msg, task_id)
        )
        worker.finished.connect(
            lambda success, msg, result: self.on_single_task_finished(success, msg, result, task_id)
        )
        worker.log_updated.connect(self.log_updated)

        worker.start()
        self.log_message(f"启动任务 {task_id} (异步查询模式)")

        # V2.2.0: 每个任务间隔 1 分钟（60秒）
        if self.pending_tasks:
            interval_ms = 60000  # 1分钟间隔
            self.log_message(f"下一个任务将在 {interval_ms//1000} 秒后启动 (密钥轮流模式)")
            self.task_timer.start(interval_ms)

    def add_tasks(self, task_list):
        """添加任务列表
        task_list: List[Tuple[task_id, config, input_values]]
        """
        new_tasks_count = len(task_list)
        if new_tasks_count == 0:
            return

        self.total_tasks += new_tasks_count

        # 获取所有可用的 API 密钥
        available_keys = self.api_manager.get_all_keys()
        if not available_keys:
            self.log_message("错误: 没有可用的 API 密钥")
            for task_id, config, _ in task_list:
                self.task_finished.emit(False, "没有可用的 API 密钥", {}, task_id)
            if not self.workers:
                self.all_tasks_finished.emit()
            return

        self.log_message(f"添加 {new_tasks_count} 个新任务")
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

        # 将所有任务加入队列，轮询分配 API 密钥
        for i, (task_id, config, input_values) in enumerate(task_list):
            key_index = i % len(available_keys)
            api_key = available_keys[key_index]
            self.pending_tasks.append((task_id, config, input_values, api_key))

        # 只在没有正在运行的任务时，才立即启动第一个任务
        if self.pending_tasks and not self.workers:
            self.log_message("启动第一个任务...")
            self.start_next_task()
        elif self.pending_tasks and self.workers:
            self.log_message(f"任务已加入队列，等待当前任务完成后启动 (队列中还有 {len(self.pending_tasks)} 个任务)")

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

        # 检查是否有待启动的任务，如果有，启动下一个
        if self.pending_tasks:
            self.log_message(f"当前任务完成，准备启动下一个任务 (队列中还有 {len(self.pending_tasks)} 个任务)")
            # 立即启动下一个任务（不需要等待间隔，因为已经有一个任务完成了）
            self.start_next_task()
        elif self.completed_tasks >= self.total_tasks:
            self.log_message(f"当前批次任务完成! 成功: {self.completed_tasks}/{self.total_tasks}")
            self.all_tasks_finished.emit()

    def update_batch_progress(self):
        """更新批量进度"""
        self.batch_progress_updated.emit(self.completed_tasks, self.total_tasks)

    def cancel_all_tasks(self):
        """取消所有任务"""
        self.log_message("取消所有任务...")

        for worker in self.workers.values():
            if worker is not None:
                worker.cancel()

        for task_id, worker in list(self.workers.items()):
            if worker is not None and worker.isRunning():
                self.log_message(f"等待任务 {task_id} 结束...")
                worker.quit()
                worker.wait(2000)
            if worker is not None:
                worker.deleteLater()
            self.workers.pop(task_id, None)

        self.log_message("所有任务已清理")
        self.completed_tasks = self.total_tasks
        self.batch_progress_updated.emit(self.total_tasks, self.total_tasks)
        self.all_tasks_finished.emit()

# ==================== 异步查询工作线程 ====================
class AsyncVideoGenerationWorker(QThread):
    """异步视频生成工作线程"""

    progress_updated = pyqtSignal(int, str)  # (进度, 消息)
    finished = pyqtSignal(bool, str, dict)  # (成功, 消息, 结果)
    log_updated = pyqtSignal(str)  # 日志更新

    def __init__(self, config: dict, input_values: dict, api_key: str, task_id: Optional[str] = None):
        super().__init__()
        self.config = config
        self.input_values = input_values
        self.api_key = api_key
        self.task_id = task_id if task_id else f"task_{int(time.time())}"
        self.is_cancelled = False
        self.base_url = "https://api.bizyair.cn/w/v1/webapp/task/openapi"

    def log(self, message):
        """记录日志"""
        self.log_updated.emit(f"[{datetime.now().strftime('%H:%M:%S')}] {message}")

    def run(self):
        """执行异步视频生成任务"""
        try:
            self.log(f"开始任务: {self.config.get('name', 'Unknown')}")
            self.progress_updated.emit(10, "准备提交异步任务...")

            # 构建请求头
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
                "X-Bizyair-Task-Async": "enable"  # 启用异步模式
            }

            # 构建请求体
            request_data = {
                "web_app_id": self.config.get("web_app_id"),
                "suppress_preview_output": self.config.get("suppress_preview_output", True),
                "input_values": self.input_values
            }

            self.log(f"提交任务到 BizyAir API (Web App ID: {self.config.get('web_app_id')})")
            self.progress_updated.emit(20, "提交异步任务...")

            # 提交异步任务
            response = requests.post(
                f"{self.base_url}/create",
                headers=headers,
                json=request_data,
                timeout=30
            )

            response.raise_for_status()
            result = response.json()

            # 获取 request_id
            request_id = result.get("requestId") or result.get("request_id")
            if not request_id:
                raise Exception(f"API 响应中缺少 requestId: {result}")

            self.log(f"任务已提交，request_id: {request_id}")
            self.progress_updated.emit(30, f"任务已提交 (ID: {request_id[:16]}...)")

            # 轮询任务状态
            video_url = self.poll_task_status(request_id)

            if video_url:
                self.progress_updated.emit(100, "任务完成！")
                result_data = {
                    "video_url": video_url,
                    "request_id": request_id,
                    "model_name": self.config.get("name"),
                    "web_app_id": self.config.get("web_app_id")
                }
                self.finished.emit(True, "视频生成成功！", result_data)
            else:
                raise Exception("视频生成失败或超时")

        except Exception as e:
            self.log(f"任务失败: {str(e)}")
            self.finished.emit(False, f"任务失败: {str(e)}", {})

    def poll_task_status(self, request_id: str) -> Optional[str]:
        """轮询任务状态

        查询策略：
        1. 获取 request_id 后，等待 5 分钟（远程生成需要时间）
        2. 5 分钟后开始第一次查询
        3. 之后每 1 分钟查询一次
        """
        headers = {
            "Authorization": f"Bearer {self.api_key}"
        }

        # 第一次查询前的等待时间（5分钟 = 300秒）
        initial_wait = 300
        self.log(f"任务已提交，等待 {initial_wait//60} 分钟后开始查询...")
        self.progress_updated.emit(30, f"等待 {initial_wait//60} 分钟后开始查询...")

        # 分段等待，每30秒报告一次进度
        wait_steps = initial_wait // 30
        for i in range(wait_steps):
            if self.is_cancelled:
                self.log("任务已取消")
                return None
            time.sleep(30)
            remaining = (wait_steps - i - 1) * 30
            if remaining > 0:
                self.log(f"等待中... 还需 {remaining//60} 分 {(remaining%60)//10}0 秒")
                self.progress_updated.emit(30 + int((i+1)/wait_steps*20), f"等待中... {remaining//60}:{remaining%60:02d}")

        # 开始轮询查询（每1分钟一次）
        max_attempts = 30  # 最多30次（15分钟）
        check_interval = 30  # V2.2.0: 每30秒查询一次

        self.log("开始查询任务状态...")
        self.progress_updated.emit(50, "查询任务状态...")

        for attempt in range(max_attempts):
            if self.is_cancelled:
                self.log("任务已取消")
                return None

            try:
                # 查询任务详情
                response = requests.get(
                    f"{self.base_url}/detail",
                    headers=headers,
                    params={"requestId": request_id},
                    timeout=30
                )

                response.raise_for_status()
                data = response.json()
                status = data.get("data", {}).get("status")

                # 更新进度
                progress = 50 + int((attempt + 1) / max_attempts * 50)
                self.progress_updated.emit(progress, f"任务状态: {status}")
                self.log(f"查询进度 ({attempt+1}/{max_attempts}): {status}")

                if status == "Success":
                    # 任务成功，获取输出结果
                    self.log("任务成功，获取输出结果...")
                    outputs_response = requests.get(
                        f"{self.base_url}/outputs",
                        headers=headers,
                        params={"requestId": request_id},
                        timeout=30
                    )
                    outputs_response.raise_for_status()
                    outputs_data = outputs_response.json()

                    outputs = outputs_data.get("data", {}).get("outputs", [])
                    if outputs and len(outputs) > 0:
                        video_url = outputs[0].get("object_url")
                        self.log(f"视频生成成功: {video_url}")
                        return video_url
                    else:
                        self.log("任务成功但无输出结果")
                        return None

                elif status in ["Failed", "Canceled"]:
                    error_msg = data.get("data", {}).get("error_message", "任务失败")
                    self.log(f"任务失败: {error_msg}")
                    return None

                # 继续轮询
                if attempt < max_attempts - 1:
                    self.log(f"等待 {check_interval} 秒后再次查询...")
                    time.sleep(check_interval)

            except Exception as e:
                self.log(f"查询状态失败: {str(e)}")
                if attempt < max_attempts - 1:
                    self.log(f"等待 {check_interval} 秒后重试...")
                    time.sleep(check_interval)

        self.log("任务超时（超过15分钟）")
        return None

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True

# ==================== 手动轮询线程 ====================
class ManualPollThread(QThread):
    """手动轮询任务状态的线程"""

    log_signal = pyqtSignal(str)
    result_signal = pyqtSignal(bool, dict)

    def __init__(self, request_id: str, api_key: str):
        super().__init__()
        self.request_id = request_id
        self.api_key = api_key
        self.base_url = "https://api.bizyair.cn/w/v1/webapp/task/openapi"

    def run(self):
        """运行轮询任务"""
        try:
            # 查询任务状态
            self.log_signal.emit("查询任务状态...")
            status = self._query_status()

            if status == "Success":
                self.log_signal.emit("任务成功，获取输出结果...")
                video_url = self._get_outputs()
                if video_url:
                    self.result_signal.emit(True, {"video_url": video_url, "request_id": self.request_id})
                else:
                    self.result_signal.emit(False, {"error": "无法获取输出结果"})
            elif status == "Failed":
                self.result_signal.emit(False, {"error": "任务执行失败"})
            elif status == "Running":
                self.result_signal.emit(True, {"video_url": "", "request_id": self.request_id})
            else:
                self.result_signal.emit(True, {"video_url": "", "request_id": self.request_id})

        except Exception as e:
            self.log_signal.emit(f"轮询失败: {str(e)}")
            self.result_signal.emit(False, {"error": str(e)})

    def _query_status(self) -> Optional[str]:
        """查询任务状态"""
        url = f"{self.base_url}/detail"
        headers = {
            "Authorization": f"Bearer {self.api_key}"
        }

        response = requests.get(url, params={"requestId": self.request_id},
                              headers=headers, timeout=30)

        if response.status_code == 200:
            data = response.json()
            if data.get("status"):
                result_data = data.get("data", {})
                status = result_data.get("status", "")
                self.log_signal.emit(f"任务状态: {status}")
                return status
            else:
                self.log_signal.emit(f"API 错误: {data.get('message', '未知错误')}")
                return None
        else:
            self.log_signal.emit(f"HTTP 错误: {response.status_code}")
            return None

    def _get_outputs(self) -> Optional[str]:
        """获取输出结果"""
        url = f"{self.base_url}/outputs"
        headers = {
            "Authorization": f"Bearer {self.api_key}"
        }

        response = requests.get(url, params={"requestId": self.request_id},
                              headers=headers, timeout=30)

        if response.status_code == 200:
            data = response.json()
            if data.get("status"):
                outputs = data.get("data", {}).get("outputs", [])
                if outputs:
                    video_url = outputs[0].get("object_url", "")
                    self.log_signal.emit(f"获取到视频 URL: {video_url}")
                    return video_url
                else:
                    self.log_signal.emit("输出列表为空")
                    return None
            else:
                self.log_signal.emit(f"API 错误: {data.get('message', '未知错误')}")
                return None
        else:
            self.log_signal.emit(f"HTTP 错误: {response.status_code}")
            return None

# ==================== 动态参数输入组件 ====================
class DynamicParameterInput(QWidget):
    """动态参数输入组件"""

    value_changed = pyqtSignal(str, object)  # (参数名, 值)

    def __init__(self, param_name: str, param_type: str, default_value: Any = None, parent=None):
        super().__init__(parent)
        self.param_name = param_name
        self.param_type = param_type
        self.default_value = default_value
        self.init_ui()

    def init_ui(self):
        """初始化界面"""
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)

        # 参数名标签
        label = QLabel(self._get_display_name())
        label.setMinimumWidth(70)
        label.setMaximumWidth(100)
        label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(label)

        # 根据参数类型创建输入控件
        if self.param_type == ParameterType.IMAGE:
            self.input_widget = self._create_image_input()
        elif self.param_type == ParameterType.AUDIO:
            self.input_widget = self._create_audio_input()
        elif self.param_type == ParameterType.VIDEO:
            self.input_widget = self._create_video_input()
        elif self.param_type == ParameterType.PROMPT:
            self.input_widget = self._create_prompt_input()
        elif self.param_type == ParameterType.MODEL:
            self.input_widget = self._create_model_input()
        elif self.param_type == ParameterType.WIDTH:
            self.input_widget = self._create_width_input()
        elif self.param_type == ParameterType.HEIGHT:
            self.input_widget = self._create_height_input()
        elif self.param_type == ParameterType.FRAMES:
            self.input_widget = self._create_frames_input()
        elif self.param_type == ParameterType.DURATION:
            self.input_widget = self._create_duration_input()
        elif self.param_type == ParameterType.ASPECT_RATIO:
            self.input_widget = self._create_aspect_ratio_input()
        elif self.param_type == ParameterType.RESOLUTION:
            self.input_widget = self._create_resolution_input()
        else:
            self.input_widget = self._create_text_input()

        layout.addWidget(self.input_widget, 1)

        # 设置默认值
        if self.default_value is not None:
            self.set_value(self.default_value)

    def _get_display_name(self) -> str:
        """获取显示名称（使用中文映射）"""
        # 首先检查是否在中文映射中
        for cn_key, cn_name in ParameterDefinition.FIELD_NAME_CN.items():
            if cn_key in self.param_name.lower():
                return cn_name

        # 如果不在映射中，从字段名中提取可读的名称
        name = self.param_name.split(":")[-1] if ":" in self.param_name else self.param_name
        name = name.replace("_", " ").title()
        return name

    def _create_image_input(self) -> QWidget:
        """创建图片输入控件"""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)

        self.path_edit = LineEdit()
        self.path_edit.setPlaceholderText("输入图片URL或点击选择文件")
        self.path_edit.setFixedHeight(32)
        layout.addWidget(self.path_edit, 1)

        btn = PushButton(FluentIcon.FOLDER, "")
        btn.setFixedSize(40, 32)
        btn.clicked.connect(self._select_image_file)
        layout.addWidget(btn)

        self.path_edit.textChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )

        return widget

    def _create_audio_input(self) -> QWidget:
        """创建音频输入控件"""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)

        self.path_edit = LineEdit()
        self.path_edit.setPlaceholderText("输入音频URL或点击选择文件")
        self.path_edit.setFixedHeight(32)
        layout.addWidget(self.path_edit, 1)

        btn = PushButton(FluentIcon.FOLDER, "")
        btn.setFixedSize(40, 32)
        btn.clicked.connect(self._select_audio_file)
        layout.addWidget(btn)

        self.path_edit.textChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )

        return widget

    def _create_video_input(self) -> QWidget:
        """创建视频输入控件"""
        widget = QWidget()
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(0, 0, 0, 0)

        self.path_edit = LineEdit()
        self.path_edit.setPlaceholderText("输入视频URL或点击选择文件")
        self.path_edit.setFixedHeight(32)
        layout.addWidget(self.path_edit, 1)

        btn = PushButton(FluentIcon.FOLDER, "")
        btn.setFixedSize(40, 32)
        btn.clicked.connect(self._select_video_file)
        layout.addWidget(btn)

        self.path_edit.textChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )

        return widget

    def _create_prompt_input(self) -> QWidget:
        """创建提示词输入控件"""
        edit = QTextEdit()
        edit.setPlaceholderText("输入提示词...")
        edit.setMinimumHeight(60)
        edit.setMaximumHeight(120)
        edit.setStyleSheet("""
            QTextEdit {
                background-color: #1e1e1e;
                color: #cccccc;
                border: 1px solid #333333;
                border-radius: 6px;
                padding: 8px;
                font-size: 13px;
                font-family: 'SF Pro Text', 'PingFang SC', 'Microsoft YaHei', sans-serif;
                line-height: 1.5;
            }
            QTextEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        edit.textChanged.connect(
            lambda: self.value_changed.emit(self.param_name, edit.toPlainText())
        )
        return edit

    def _create_model_input(self) -> QWidget:
        """创建模型选择控件"""
        combo = ComboBox()
        combo.setFixedHeight(32)
        combo.addItems([
            "MiniMax-Hailuo-2.3-Fast",
            "Default"
        ])
        combo.currentTextChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )
        return combo

    def _create_width_input(self) -> QWidget:
        """创建宽度输入控件"""
        spin = QSpinBox()
        spin.setRange(256, 4096)
        spin.setSingleStep(64)
        spin.setFixedHeight(32)
        spin.setValue(1280)
        spin.valueChanged.connect(
            lambda val: self.value_changed.emit(self.param_name, val)
        )
        return spin

    def _create_height_input(self) -> QWidget:
        """创建高度输入控件"""
        spin = QSpinBox()
        spin.setRange(256, 4096)
        spin.setSingleStep(64)
        spin.setFixedHeight(32)
        spin.setValue(720)
        spin.valueChanged.connect(
            lambda val: self.value_changed.emit(self.param_name, val)
        )
        return spin

    def _create_frames_input(self) -> QWidget:
        """创建帧数输入控件"""
        spin = QSpinBox()
        spin.setRange(1, 1000)
        spin.setSingleStep(1)
        spin.setFixedHeight(32)
        spin.setValue(121)
        spin.valueChanged.connect(
            lambda val: self.value_changed.emit(self.param_name, val)
        )
        return spin

    def _create_duration_input(self) -> QWidget:
        """创建时长输入控件"""
        combo = ComboBox()
        combo.setFixedHeight(32)
        # 使用 addItems 添加文本列表，避免 addItem 与数据混合导致的错误
        items = [f"{val}秒" for val in ParameterDefinition.PRESET_OPTIONS["duration"]]
        combo.addItems(items)
        # 存储实际值用于后续获取
        self._duration_values = list(ParameterDefinition.PRESET_OPTIONS["duration"])
        combo.currentIndexChanged.connect(
            lambda idx: self.value_changed.emit(
                self.param_name, self._duration_values[idx] if idx >= 0 and idx < len(self._duration_values) else None
            )
        )
        return combo

    def _create_aspect_ratio_input(self) -> QWidget:
        """创建宽高比输入控件"""
        combo = ComboBox()
        combo.setFixedHeight(32)
        for val in ParameterDefinition.PRESET_OPTIONS["aspect_ratio"]:
            combo.addItem(val)
        combo.currentTextChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )
        return combo

    def _create_resolution_input(self) -> QWidget:
        """创建分辨率输入控件"""
        combo = ComboBox()
        combo.setFixedHeight(32)
        for val in ParameterDefinition.PRESET_OPTIONS["resolution"]:
            combo.addItem(val)
        combo.currentTextChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )
        return combo

    def _create_text_input(self) -> QWidget:
        """创建文本输入控件"""
        edit = LineEdit()
        edit.setPlaceholderText(f"输入{self._get_display_name()}...")
        edit.setFixedHeight(34)
        edit.setStyleSheet("""
            LineEdit {
                background-color: #1e1e1e;
                color: #cccccc;
                border: 1px solid #333333;
                border-radius: 6px;
                padding: 6px 10px;
                font-size: 13px;
            }
            LineEdit:focus {
                border: 1px solid #4a90e2;
            }
        """)
        edit.textChanged.connect(
            lambda txt: self.value_changed.emit(self.param_name, txt)
        )
        return edit

    def _select_image_file(self):
        """选择图片文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择图片",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.webp *.bmp)"
        )
        if file_path:
            self.path_edit.setText(file_path)

    def _select_audio_file(self):
        """选择音频文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择音频",
            "",
            "音频文件 (*.mp3 *.wav *.aac *.m4a)"
        )
        if file_path:
            self.path_edit.setText(file_path)

    def _select_video_file(self):
        """选择视频文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择视频",
            "",
            "视频文件 (*.mp4 *.mov *.avi *.mkv)"
        )
        if file_path:
            self.path_edit.setText(file_path)

    def get_value(self) -> Any:
        """获取当前值"""
        if hasattr(self, 'path_edit'):
            return self.path_edit.text()
        elif isinstance(self.input_widget, QTextEdit):
            return self.input_widget.toPlainText()
        elif isinstance(self.input_widget, ComboBox):
            # 对于 duration 类型，使用存储的值列表
            if self.param_type == ParameterType.DURATION and hasattr(self, '_duration_values'):
                idx = self.input_widget.currentIndex()
                if idx >= 0 and idx < len(self._duration_values):
                    return self._duration_values[idx]
            # 对于其他 ComboBox，直接返回当前文本
            return self.input_widget.currentText()
        elif isinstance(self.input_widget, QSpinBox):
            return self.input_widget.value()
        else:
            return None

    def set_value(self, value: Any):
        """设置值"""
        if hasattr(self, 'path_edit'):
            self.path_edit.setText(str(value))
        elif isinstance(self.input_widget, QTextEdit):
            self.input_widget.setPlainText(str(value))
        elif isinstance(self.input_widget, ComboBox):
            # 对于 duration 类型，在值列表中查找索引
            if self.param_type == ParameterType.DURATION and hasattr(self, '_duration_values'):
                if value in self._duration_values:
                    idx = self._duration_values.index(value)
                    self.input_widget.setCurrentIndex(idx)
            else:
                # 对于其他类型，通过文本查找
                index = self.input_widget.findText(str(value))
                if index >= 0:
                    self.input_widget.setCurrentIndex(index)
        elif isinstance(self.input_widget, QSpinBox):
            self.input_widget.setValue(int(value))

# ==================== 主视频生成组件 ====================
class TemplateVideoGenerationWidget(QWidget):
    """模板化视频生成主组件"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.config_loader = VODSConfigLoader()
        self.current_config = None
        self.parameter_inputs = {}
        self.batch_parameter_inputs = {}  # 批量模式的参数输入
        self.current_worker = None

        # API 密钥管理器
        self.api_key_manager = APIKeyManager()

        # 批量任务管理器
        self.batch_manager = BatchManager(self.api_key_manager)
        self.batch_manager.log_updated.connect(self.on_log_updated)
        self.batch_manager.task_finished.connect(self.on_batch_task_finished)
        self.batch_manager.batch_progress_updated.connect(self.on_batch_progress_updated)

        # 批量任务状态跟踪
        self.batch_tasks = {}  # {task_id: {"status": str, "result": dict, "url": str}}
        self.is_batch_mode = False

        # V2.2.0: 批量任务列表
        self.batch_task_list = []  # [{"prompt": str, "status": str}]

        # 历史记录管理器
        self.history_manager = TaskHistoryManager("vods_log.json")

        self.init_ui()
        self.load_model_list()
        self.update_api_key_status()  # 更新 API 密钥状态显示

    def init_ui(self):
        """初始化界面"""
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(12, 12, 12, 12)

        # 标题栏
        title_bar = self._create_title_bar()
        layout.addWidget(title_bar)

        # 主分割器
        splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(splitter)

        # 左侧：模型选择和参数输入
        left_panel = self._create_left_panel()
        splitter.addWidget(left_panel)

        # 右侧：任务状态和结果
        right_panel = self._create_right_panel()
        splitter.addWidget(right_panel)

        splitter.setSizes([500, 500])

    def _create_title_bar(self) -> QFrame:
        """创建标题栏"""
        bar = QFrame()
        bar.setFixedHeight(45)
        bar.setStyleSheet("""
            QFrame {
                background-color: transparent;
                border: none;
            }
        """)
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(5, 5, 5, 5)

        title = QLabel("模板化视频生成")
        title.setStyleSheet("font-size: 16px; font-weight: 500; color: #e0e0e0;")
        layout.addWidget(title)

        layout.addStretch()

        # API 设置按钮
        api_btn = PushButton(FluentIcon.SETTING, "API设置")
        api_btn.setFixedSize(200, 36)
        api_btn.clicked.connect(self.show_api_settings)
        layout.addWidget(api_btn)

        # 历史记录按钮
        history_btn = PushButton(FluentIcon.HISTORY, "历史记录")
        history_btn.setFixedSize(200, 36)
        history_btn.clicked.connect(self.export_history)
        layout.addWidget(history_btn)

        return bar

    def _create_left_panel(self) -> QFrame:
        """创建左侧面板"""
        panel = QFrame()
        panel.setStyleSheet("QFrame { background-color: transparent; border: none; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(12)
        layout.setContentsMargins(5, 5, 5, 5)

        # 模式选择标签页
        self.mode_tab_widget = QTabWidget()
        self.mode_tab_widget.setStyleSheet("""
            QTabWidget::pane {
                border: none;
                background-color: transparent;
            }
            QTabBar::tab {
                background-color: transparent;
                color: #888888;
                padding: 10px 20px;
                border: none;
                font-size: 13px;
            }
            QTabBar::tab:selected {
                color: #4a90e2;
                font-weight: 500;
            }
            QTabBar::tab:hover:!selected {
                color: #aaaaaa;
            }
        """)

        # 单个生成模式标签页
        self.single_mode_widget = self._create_single_mode_widget()
        self.mode_tab_widget.addTab(self.single_mode_widget, "单个生成")

        # 批量生成模式标签页
        self.batch_mode_widget = self._create_batch_mode_widget()
        self.mode_tab_widget.addTab(self.batch_mode_widget, "批量生成")

        self.mode_tab_widget.currentChanged.connect(self.on_mode_changed)
        layout.addWidget(self.mode_tab_widget)

        return panel

    def _create_single_mode_widget(self) -> QWidget:
        """创建单个生成模式组件"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(5, 5, 5, 5)

        # 模型选择
        model_label = QLabel("模型")
        model_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(model_label)

        self.model_combo = ComboBox()
        self.model_combo.setFixedHeight(36)
        self.model_combo.currentTextChanged.connect(self.on_model_changed)
        layout.addWidget(self.model_combo)

        # 模型信息
        self.model_info_label = QLabel("")
        self.model_info_label.setStyleSheet("color: #666666; font-size: 11px;")
        self.model_info_label.setWordWrap(True)
        layout.addWidget(self.model_info_label)

        # 分隔线
        line = QFrame()
        line.setFrameShape(QFrame.HLine)
        line.setFrameShadow(QFrame.Sunken)
        line.setStyleSheet("background-color: #2a2a2a; border: none; max-height: 1px;")
        layout.addWidget(line)

        # 参数输入区域
        param_label = QLabel("参数")
        param_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(param_label)

        # 参数输入容器（滚动区域）
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setStyleSheet("QScrollArea { border: none; background-color: transparent; }")

        self.param_container = QWidget()
        self.param_layout = QVBoxLayout(self.param_container)
        self.param_layout.setSpacing(8)
        self.param_layout.setContentsMargins(0, 0, 0, 0)
        self.param_layout.addStretch()
        scroll.setWidget(self.param_container)

        layout.addWidget(scroll, 1)

        # 生成按钮
        button_layout = QHBoxLayout()
        button_layout.setSpacing(8)

        self.generate_btn = PrimaryPushButton(FluentIcon.PLAY, "开始生成")
        self.generate_btn.setFixedHeight(38)
        self.generate_btn.clicked.connect(self.start_generation)
        button_layout.addWidget(self.generate_btn)

        self.cancel_btn = PushButton(FluentIcon.CANCEL, "取消")
        self.cancel_btn.setFixedHeight(38)
        self.cancel_btn.setEnabled(False)
        self.cancel_btn.clicked.connect(self.cancel_generation)
        button_layout.addWidget(self.cancel_btn)

        layout.addLayout(button_layout)

        return widget

    def _create_batch_mode_widget(self) -> QWidget:
        """创建批量生成模式组件 - V2.2.0 带任务管理"""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)
        layout.setContentsMargins(5, 5, 5, 5)

        # 模型选择
        model_label = QLabel("模型")
        model_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(model_label)

        self.batch_model_combo = ComboBox()
        self.batch_model_combo.setFixedHeight(36)
        self.batch_model_combo.currentTextChanged.connect(self.on_batch_model_changed)
        layout.addWidget(self.batch_model_combo)

        # 分隔线
        line1 = QFrame()
        line1.setFrameShape(QFrame.HLine)
        line1.setFrameShadow(QFrame.Sunken)
        line1.setStyleSheet("background-color: #2a2a2a; border: none; max-height: 1px;")
        layout.addWidget(line1)

        # V2.2.0: 任务列表管理区域
        task_list_label = QLabel("任务列表")
        task_list_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(task_list_label)

        # 任务输入区域（添加新任务）
        task_input_layout = QHBoxLayout()
        task_input_layout.setSpacing(8)

        self.batch_task_input = LineEdit()
        self.batch_task_input.setPlaceholderText("输入提示词，按回车添加...")
        self.batch_task_input.setFixedHeight(36)
        self.batch_task_input.returnPressed.connect(self.add_batch_task)
        task_input_layout.addWidget(self.batch_task_input, 1)

        add_task_btn = PushButton(FluentIcon.ADD, "添加")
        add_task_btn.setFixedHeight(36)
        add_task_btn.clicked.connect(self.add_batch_task)
        task_input_layout.addWidget(add_task_btn)

        layout.addLayout(task_input_layout)

        # 任务列表表格
        self.batch_task_table = TableWidget()
        self.batch_task_table.setColumnCount(4)
        self.batch_task_table.setHorizontalHeaderLabels(["序号", "提示词", "状态", "操作"])
        self.batch_task_table.setStyleSheet("""
            QTableWidget {
                background-color: #1e1e1e;
                color: #cccccc;
                border: 1px solid #333333;
                border-radius: 6px;
                gridline-color: #2a2a2a;
                font-size: 11px;
            }
            QTableWidget::item {
                padding: 5px;
            }
            QHeaderView::section {
                background-color: #2a2a2a;
                color: #e0e0e0;
                padding: 8px;
                border: none;
                border-right: 1px solid #333333;
                font-weight: 500;
            }
        """)
        self.batch_task_table.setMaximumHeight(200)
        self.batch_task_table.horizontalHeader().setSectionResizeMode(0, 0)  # 序号固定
        self.batch_task_table.setColumnWidth(0, 50)
        self.batch_task_table.horizontalHeader().setSectionResizeMode(1, 3)  # 提示词拉伸
        self.batch_task_table.horizontalHeader().setSectionResizeMode(2, 1)  # 状态固定
        self.batch_task_table.setColumnWidth(2, 80)
        self.batch_task_table.horizontalHeader().setSectionResizeMode(3, 0)  # 操作固定
        self.batch_task_table.setColumnWidth(3, 60)
        layout.addWidget(self.batch_task_table)

        # 批量操作按钮
        batch_button_layout = QHBoxLayout()
        batch_button_layout.setSpacing(8)

        clear_tasks_btn = PushButton(FluentIcon.DELETE, "清空任务")
        clear_tasks_btn.setFixedHeight(32)
        clear_tasks_btn.clicked.connect(self.clear_batch_tasks)
        batch_button_layout.addWidget(clear_tasks_btn)

        batch_button_layout.addStretch()

        # 任务计数标签
        self.batch_task_count_label = QLabel("任务数: 0")
        self.batch_task_count_label.setStyleSheet("color: #888888; font-size: 11px;")
        batch_button_layout.addWidget(self.batch_task_count_label)

        layout.addLayout(batch_button_layout)

        # 分隔线
        line2 = QFrame()
        line2.setFrameShape(QFrame.HLine)
        line2.setFrameShadow(QFrame.Sunken)
        line2.setStyleSheet("background-color: #2a2a2a; border: none; max-height: 1px;")
        layout.addWidget(line2)

        # 模板参数区域（基于选择的模型显示）
        self.batch_param_label = QLabel("模板参数")
        self.batch_param_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(self.batch_param_label)

        # 批量参数输入容器
        self.batch_param_container = QWidget()
        self.batch_param_layout = QVBoxLayout(self.batch_param_container)
        self.batch_param_layout.setSpacing(8)
        self.batch_param_layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.batch_param_container)

        # API 密钥状态提示（简化版）
        self.api_key_status_label = QLabel("")
        self.api_key_status_label.setStyleSheet("color: #666666; font-size: 11px;")
        layout.addWidget(self.api_key_status_label)

        # 批量生成按钮
        button_layout = QHBoxLayout()
        button_layout.setSpacing(8)

        self.batch_generate_btn = PrimaryPushButton(FluentIcon.PLAY, "批量生成")
        self.batch_generate_btn.setFixedHeight(38)
        self.batch_generate_btn.clicked.connect(self.start_batch_generation)
        button_layout.addWidget(self.batch_generate_btn)

        self.batch_cancel_btn = PushButton(FluentIcon.CANCEL, "取消")
        self.batch_cancel_btn.setFixedHeight(38)
        self.batch_cancel_btn.setEnabled(False)
        self.batch_cancel_btn.clicked.connect(self.cancel_batch_generation)
        button_layout.addWidget(self.batch_cancel_btn)

        layout.addLayout(button_layout)

        return widget

    def _create_right_panel(self) -> QFrame:
        """创建右侧面板"""
        panel = QFrame()
        panel.setStyleSheet("QFrame { background-color: transparent; border: none; }")
        layout = QVBoxLayout(panel)
        layout.setSpacing(12)
        layout.setContentsMargins(5, 5, 5, 5)

        # 任务状态标签
        status_label = QLabel("状态")
        status_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(status_label)

        self.status_label = QLabel("等待开始...")
        self.status_label.setStyleSheet("color: #888888; font-size: 13px;")
        layout.addWidget(self.status_label)

        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(4)
        layout.addWidget(self.progress_bar)

        # 分隔线
        line1 = QFrame()
        line1.setFrameShape(QFrame.HLine)
        line1.setFrameShadow(QFrame.Sunken)
        line1.setStyleSheet("background-color: #2a2a2a; border: none; max-height: 1px;")
        layout.addWidget(line1)

        # 日志标签
        log_label = QLabel("日志")
        log_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(log_label)

        self.log_edit = QTextEdit()
        self.log_edit.setReadOnly(True)
        self.log_edit.setStyleSheet("""
            QTextEdit {
                background-color: #1a1a1a;
                color: #888888;
                font-family: 'SF Mono', 'Menlo', 'Monaco', monospace;
                font-size: 11px;
                border: none;
                border-radius: 6px;
                padding: 8px;
            }
        """)
        layout.addWidget(self.log_edit, 1)

        # 分隔线
        line2 = QFrame()
        line2.setFrameShape(QFrame.HLine)
        line2.setFrameShadow(QFrame.Sunken)
        line2.setStyleSheet("background-color: #2a2a2a; border: none; max-height: 1px;")
        layout.addWidget(line2)

        # 结果标签
        result_label = QLabel("结果")
        result_label.setStyleSheet("color: #888888; font-size: 12px;")
        layout.addWidget(result_label)

        self.result_url_label = QLabel("未生成")
        self.result_url_label.setStyleSheet("color: #666666; font-size: 11px;")
        self.result_url_label.setWordWrap(True)
        self.result_url_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.result_url_label)

        # 按钮区域
        result_button_layout = QHBoxLayout()
        result_button_layout.setSpacing(8)

        self.play_btn = PushButton(FluentIcon.PLAY, "播放")
        self.play_btn.setFixedHeight(34)
        self.play_btn.setEnabled(False)
        self.play_btn.clicked.connect(self.play_video)
        result_button_layout.addWidget(self.play_btn)

        self.poll_btn = PushButton(FluentIcon.SYNC, "异步轮询")
        self.poll_btn.setFixedHeight(34)
        self.poll_btn.setEnabled(False)
        self.poll_btn.clicked.connect(self.manual_poll_task)
        result_button_layout.addWidget(self.poll_btn)

        layout.addLayout(result_button_layout)

        return panel

    def load_model_list(self):
        """加载模型列表"""
        model_names = self.config_loader.get_model_names()

        # 单个生成模式
        self.model_combo.clear()
        self.model_combo.addItems(model_names)
        if model_names:
            self.model_combo.setCurrentIndex(0)

        # 批量生成模式
        self.batch_model_combo.clear()
        self.batch_model_combo.addItems(model_names)
        if model_names:
            self.batch_model_combo.setCurrentIndex(0)

    def on_model_changed(self, model_name: str):
        """模型选择变化"""
        if not model_name:
            return

        self.current_config = self.config_loader.get_model_by_name(model_name)
        if not self.current_config:
            return

        # 更新模型信息
        info_text = f"Web App ID: {self.current_config.get('web_app_id')}"
        if self.current_config.get('info'):
            info_text += f"\n{self.current_config.get('info')}"
        self.model_info_label.setText(info_text)

        # 清除旧的参数输入
        self._clear_parameter_inputs()

        # 创建新的参数输入
        self._create_parameter_inputs()

    def on_batch_model_changed(self, model_name: str):
        """批量模式模型选择变化"""
        if not model_name:
            return

        config = self.config_loader.get_model_by_name(model_name)
        if not config:
            return

        # 清除旧的参数输入
        self._clear_batch_parameter_inputs()

        # 创建新的参数输入（排除 prompt 类型，因为批量提示词单独处理）
        self._create_batch_parameter_inputs(config)

    def _clear_batch_parameter_inputs(self):
        """清除批量参数输入控件"""
        for i in reversed(range(self.batch_param_layout.count())):
            item = self.batch_param_layout.itemAt(i)
            if item and item.widget():
                item.widget().deleteLater()

        if not hasattr(self, 'batch_parameter_inputs'):
            self.batch_parameter_inputs = {}
        self.batch_parameter_inputs.clear()

    def _create_batch_parameter_inputs(self, config: dict):
        """创建批量模式参数输入控件（排除 prompt）"""
        input_values = config.get("input_values", {})

        for key, value in input_values.items():
            # 检测参数类型
            param_type = ParameterDefinition.detect_parameter_type(key, value)

            # 跳过 prompt 类型，因为批量提示词单独处理
            if param_type and param_type != ParameterType.PROMPT:
                # 创建参数输入组件
                param_input = DynamicParameterInput(key, param_type, value)
                self.batch_param_layout.addWidget(param_input)
                self.batch_parameter_inputs[key] = param_input

    def _clear_parameter_inputs(self):
        """清除参数输入控件"""
        # 清除旧的输入控件
        for i in reversed(range(self.param_layout.count())):
            item = self.param_layout.itemAt(i)
            if item and item.widget():
                item.widget().deleteLater()

        self.parameter_inputs.clear()

    def _create_parameter_inputs(self):
        """创建参数输入控件"""
        if not self.current_config:
            return

        input_values = self.current_config.get("input_values", {})

        for key, value in input_values.items():
            # 检测参数类型
            param_type = ParameterDefinition.detect_parameter_type(key, value)

            if param_type:
                # 创建参数输入组件
                param_input = DynamicParameterInput(key, param_type, value)
                self.param_layout.insertWidget(self.param_layout.count() - 1, param_input)
                self.parameter_inputs[key] = param_input

    def start_generation(self):
        """开始生成视频"""
        if not self.current_config:
            QMessageBox.warning(self, "警告", "请先选择一个模型")
            return

        # 收集参数值
        input_values = {}
        for key, param_input in self.parameter_inputs.items():
            value = param_input.get_value()
            if value:
                input_values[key] = value

        if not input_values:
            QMessageBox.warning(self, "警告", "请至少填写一个参数")
            return

        # 获取 API 密钥
        api_key = os.getenv('SiliconCloud_API_KEY')
        if not api_key:
            QMessageBox.warning(self, "警告", "未配置 API 密钥，请设置环境变量 SiliconCloud_API_KEY")
            return

        # 清空日志
        self.log_edit.clear()

        # 创建工作线程
        self.current_worker = AsyncVideoGenerationWorker(
            self.current_config,
            input_values,
            api_key
        )

        # 连接信号
        self.current_worker.progress_updated.connect(self.on_progress_updated)
        self.current_worker.finished.connect(self.on_generation_finished)
        self.current_worker.log_updated.connect(self.on_log_updated)

        # 启动任务
        self.generate_btn.setEnabled(False)
        self.cancel_btn.setEnabled(True)
        self.current_worker.start()

    def cancel_generation(self):
        """取消生成"""
        if self.current_worker:
            self.current_worker.cancel()
            self.log("已取消任务")
            self.generate_btn.setEnabled(True)
            self.cancel_btn.setEnabled(False)

    def on_progress_updated(self, progress: int, message: str):
        """进度更新"""
        self.progress_bar.setValue(progress)
        self.status_label.setText(message)

    def on_log_updated(self, message: str):
        """日志更新"""
        self.log_edit.append(message)
        # 自动滚动到底部
        scrollbar = self.log_edit.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def on_generation_finished(self, success: bool, message: str, result: dict):
        """生成完成"""
        self.generate_btn.setEnabled(True)
        self.cancel_btn.setEnabled(False)

        # 获取输入参数的值（修复 JSON 序列化问题）
        input_values = {}
        for key, param_input in self.parameter_inputs.items():
            try:
                value = param_input.get_value() if hasattr(param_input, 'get_value') else str(param_input)
                input_values[key] = value
            except Exception as e:
                input_values[key] = f"<无法序列化: {str(e)}>"
                print(f"警告: 参数 {key} 无法序列化: {e}")

        # 保存历史记录
        history_record = {
            "type": "single",
            "model_name": self.current_config.get("name", "") if self.current_config else "",
            "web_app_id": self.current_config.get("web_app_id", "") if self.current_config else "",
            "input_values": input_values,
            "success": success,
            "message": message,
            "result": result
        }
        self.history_manager.add_record(history_record)

        if success:
            self.status_label.setText("生成成功！")
            video_url = result.get("video_url", "")
            self.result_url_label.setText(video_url)
            self.play_btn.setEnabled(True)
            self.poll_btn.setEnabled(True)
            self.current_video_url = video_url
            self.current_request_id = result.get("request_id", "")

            # 自动下载到 output 文件夹
            self._auto_download_video(video_url)

            QMessageBox.information(self, "成功", f"{message}\n\n视频已自动保存到 output 文件夹")
        else:
            self.status_label.setText("生成失败")
            QMessageBox.critical(self, "错误", message)

    def play_video(self):
        """播放视频"""
        if hasattr(self, 'current_video_url') and self.current_video_url:
            QDesktopServices.openUrl(QUrl(self.current_video_url))

    def _auto_download_video(self, video_url: str):
        """自动下载视频到 output 文件夹"""
        if not video_url:
            return

        # 确保 output 文件夹存在
        output_dir = "output"
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            self.log(f"创建 output 文件夹")

        # 生成文件名
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"video_{timestamp}.mp4"
        file_path = os.path.join(output_dir, filename)

        try:
            self.log(f"开始下载视频到: {file_path}")
            response = requests.get(video_url, stream=True, timeout=120)
            response.raise_for_status()

            total_size = int(response.headers.get('content-length', 0))
            downloaded = 0

            with open(file_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            progress = int(downloaded / total_size * 100)
                            self.log(f"下载进度: {progress}%")

            self.log(f"视频已保存: {file_path}")
        except Exception as e:
            self.log(f"自动下载失败: {str(e)}")
            print(f"下载视频错误: {e}")

    def manual_poll_task(self):
        """手动轮询任务状态"""
        if not hasattr(self, 'current_request_id') or not self.current_request_id:
            QMessageBox.warning(self, "提示", "当前没有可轮询的任务")
            return

        # 询问用户是要轮询当前任务还是输入自定义 request_id
        reply = QMessageBox.question(
            self, "异步轮询",
            f"当前任务 ID: {self.current_request_id}\n\n是否轮询当前任务？\n\n点击「否」可输入自定义任务 ID。",
            QMessageBox.Yes | QMessageBox.No | QMessageBox.Cancel,
            QMessageBox.Yes
        )

        if reply == QMessageBox.Cancel:
            return

        request_id = self.current_request_id

        if reply == QMessageBox.No:
            # 自定义输入
            from qfluentwidgets import MessageBox
            dialog = QDialog(self)
            dialog.setWindowTitle("自定义轮询")
            dialog.setMinimumSize(400, 150)

            layout = QVBoxLayout(dialog)

            layout.addWidget(QLabel("请输入任务 Request ID:"))
            input_edit = LineEdit()
            input_edit.setPlaceholderText("例如: ac7a607e-4ba0-4b44-9af4-14f54b265a87")
            layout.addWidget(input_edit)

            button_layout = QHBoxLayout()
            ok_btn = PrimaryPushButton("开始轮询")
            cancel_btn = PushButton("取消")
            button_layout.addStretch()
            button_layout.addWidget(ok_btn)
            button_layout.addWidget(cancel_btn)
            layout.addLayout(button_layout)

            def on_ok():
                if input_edit.text().strip():
                    dialog.accept()
                else:
                    QMessageBox.warning(dialog, "警告", "请输入 Request ID")

            def on_cancel():
                dialog.reject()

            ok_btn.clicked.connect(on_ok)
            cancel_btn.clicked.connect(on_cancel)

            if dialog.exec_() == QDialog.Accepted:
                request_id = input_edit.text().strip()
            else:
                return

        # 开始轮询
        self.log(f"开始手动轮询任务: {request_id}")
        self.status_label.setText("轮询中...")

        # 获取 API 密钥
        api_key = os.getenv('SiliconCloud_API_KEY', '')
        if not api_key:
            QMessageBox.warning(self, "错误", "未找到 API 密钥，请先配置")
            return

        # 在后台线程中轮询
        poll_thread = ManualPollThread(request_id, api_key)
        poll_thread.log_signal.connect(self.log)
        poll_thread.result_signal.connect(self._on_manual_poll_result)
        poll_thread.start()

    def _on_manual_poll_result(self, success: bool, result: dict):
        """手动轮询结果回调"""
        if success:
            video_url = result.get("video_url", "")
            if video_url:
                self.status_label.setText("轮询成功")
                self.result_url_label.setText(video_url)
                self.play_btn.setEnabled(True)
                self.current_video_url = video_url

                # 自动下载
                self._auto_download_video(video_url)

                QMessageBox.information(self, "成功", f"任务已完成！\n\n视频已自动保存到 output 文件夹")
            else:
                self.status_label.setText("任务还在运行")
                QMessageBox.information(self, "提示", "任务还在运行中，请稍后再试")
        else:
            self.status_label.setText("轮询失败")
            error_msg = result.get("error", "未知错误")
            QMessageBox.critical(self, "错误", f"轮询失败: {error_msg}")

    def show_api_settings(self):
        """显示 API 设置对话框"""
        dialog = QDialog(self)
        dialog.setWindowTitle("API 设置")
        dialog.setMinimumSize(400, 200)

        layout = QVBoxLayout(dialog)

        # API 密钥输入
        layout.addWidget(QLabel("SiliconCloud API Key:"))
        api_key_edit = LineEdit()
        api_key_edit.setText(os.getenv('SiliconCloud_API_KEY', ''))
        api_key_edit.setEchoMode(LineEdit.Password)
        api_key_edit.setFixedHeight(32)
        layout.addWidget(api_key_edit)

        # 说明
        info_label = QLabel(
            "提示：API Key 将保存到环境变量 SiliconCloud_API_KEY\n"
            "也可以直接设置系统环境变量"
        )
        info_label.setStyleSheet("color: #888; font-size: 11px;")
        layout.addWidget(info_label)

        layout.addStretch()

        # 按钮
        button_layout = QHBoxLayout()
        save_btn = PrimaryPushButton("保存")
        save_btn.clicked.connect(lambda: self._save_api_key(api_key_edit.text(), dialog))
        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(dialog.reject)
        button_layout.addStretch()
        button_layout.addWidget(save_btn)
        button_layout.addWidget(cancel_btn)
        layout.addLayout(button_layout)

        dialog.exec_()

    def _save_api_key(self, api_key: str, dialog: QDialog):
        """保存 API 密钥"""
        if api_key:
            os.environ['SiliconCloud_API_KEY'] = api_key
            QMessageBox.information(self, "成功", "API 密钥已保存到当前会话")
            dialog.accept()
        else:
            QMessageBox.warning(self, "警告", "API 密钥不能为空")

    def log(self, message: str):
        """记录日志"""
        self.on_log_updated(message)

    # ==================== 批量模式和 API 密钥管理方法 ====================

    # V2.2.0: 批量任务管理方法
    def add_batch_task(self):
        """添加批量任务"""
        prompt = self.batch_task_input.text().strip()
        if not prompt:
            QMessageBox.warning(self, "警告", "请输入提示词")
            return

        # 添加到任务列表
        self.batch_task_list.append({"prompt": prompt, "status": "待执行"})
        self._update_batch_task_table()

        # 清空输入框
        self.batch_task_input.clear()
        self.batch_task_input.setFocus()

    def _update_batch_task_table(self):
        """更新批量任务表格显示"""
        self.batch_task_table.setRowCount(len(self.batch_task_list))

        for row, task in enumerate(self.batch_task_list):
            # 序号
            num_item = QTableWidgetItem(str(row + 1))
            num_item.setTextAlignment(Qt.AlignCenter)
            self.batch_task_table.setItem(row, 0, num_item)

            # 提示词
            prompt_item = QTableWidgetItem(task["prompt"][:60] + "..." if len(task["prompt"]) > 60 else task["prompt"])
            self.batch_task_table.setItem(row, 1, prompt_item)

            # 状态
            status_item = QTableWidgetItem(task["status"])
            status_item.setTextAlignment(Qt.AlignCenter)
            # 根据状态设置颜色
            if task["status"] == "待执行":
                status_item.setStyleSheet("color: #888888;")
            elif task["status"] == "执行中":
                status_item.setStyleSheet("color: #4a90e2;")
            elif task["status"] == "已完成":
                status_item.setStyleSheet("color: #4caf50;")
            elif task["status"] == "失败":
                status_item.setStyleSheet("color: #f44336;")
            self.batch_task_table.setItem(row, 2, status_item)

            # 操作（删除按钮）
            delete_btn = PushButton("删除")
            delete_btn.setFixedHeight(24)
            delete_btn.clicked.connect(lambda checked, r=row: self._remove_batch_task(r))
            self.batch_task_table.setCellWidget(row, 3, delete_btn)

        # 更新任务计数
        self.batch_task_count_label.setText(f"任务数: {len(self.batch_task_list)}")

    def _remove_batch_task(self, row: int):
        """删除批量任务"""
        if 0 <= row < len(self.batch_task_list):
            self.batch_task_list.pop(row)
            self._update_batch_task_table()

    def clear_batch_tasks(self):
        """清空批量任务列表"""
        if not self.batch_task_list:
            return

        reply = QMessageBox.question(
            self, "确认",
            f"确定要清空 {len(self.batch_task_list)} 个任务吗？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            self.batch_task_list.clear()
            self._update_batch_task_table()

    def on_mode_changed(self, index: int):
        """模式切换处理"""
        self.is_batch_mode = (index == 1)  # 0: 单个模式, 1: 批量模式
        if self.is_batch_mode:
            # 初始化批量模式的模型列表
            self._load_batch_model_list()

    def _load_batch_model_list(self):
        """加载批量模式的模型列表"""
        model_names = self.config_loader.get_model_names()
        self.batch_model_combo.clear()
        self.batch_model_combo.addItems(model_names)
        if model_names:
            self.batch_model_combo.setCurrentIndex(0)

    def on_api_key_source_changed(self, source: str):
        """API 密钥来源切换处理"""
        source_map = {"系统变量": "env", "密钥文本": "text", "文件密钥": "file"}
        self.api_key_manager.set_key_source(source_map.get(source, "env"))

        # 根据来源显示/隐藏不同的输入控件
        if source == "系统变量":
            self.api_key_text_edit.setVisible(False)
            self.api_key_file_edit.setVisible(False)
            # 更新状态
            env_key = os.getenv('SiliconCloud_API_KEY')
            if env_key:
                self.api_key_status_label.setText(f"已加载系统环境变量密钥: {env_key[:8]}...")
                self.api_key_status_label.setStyleSheet("color: #4caf50; font-size: 11px;")
            else:
                self.api_key_status_label.setText("未设置系统环境变量 SiliconCloud_API_KEY")
                self.api_key_status_label.setStyleSheet("color: #f44336; font-size: 11px;")

        elif source == "密钥文本":
            self.api_key_text_edit.setVisible(True)
            self.api_key_file_edit.setVisible(False)
            # 检查是否有输入
            text = self.api_key_text_edit.toPlainText()
            if text:
                self.api_key_manager.load_keys_from_text(text)
                count = self.api_key_manager.get_available_keys_count()
                self.api_key_status_label.setText(f"已加载 {count} 个密钥")
                self.api_key_status_label.setStyleSheet("color: #4caf50; font-size: 11px;")
            else:
                self.api_key_status_label.setText("请输入 API 密钥")
                self.api_key_status_label.setStyleSheet("color: #ff9800; font-size: 11px;")

        elif source == "文件密钥":
            self.api_key_text_edit.setVisible(False)
            self.api_key_file_edit.setVisible(True)
            # 检查是否有文件
            file_path = self.api_key_file_edit.text()
            if file_path and os.path.exists(file_path):
                self.api_key_manager.load_keys_from_file(file_path)
                count = self.api_key_manager.get_available_keys_count()
                self.api_key_status_label.setText(f"已加载 {count} 个密钥")
                self.api_key_status_label.setStyleSheet("color: #4caf50; font-size: 11px;")
            else:
                self.api_key_status_label.setText("请选择 API 密钥文件")
                self.api_key_status_label.setStyleSheet("color: #ff9800; font-size: 11px;")

        # 更新子控件可见性
        for i in range(self.api_key_input_container.layout().count()):
            item = self.api_key_input_container.layout().itemAt(i)
            if item and item.widget():
                widget = item.widget()
                if isinstance(widget, QHBoxLayout):
                    for j in range(item.count()):
                        sub_item = item.itemAt(j)
                        if sub_item and sub_item.widget():
                            sub_item.widget().setVisible(source == "文件密钥")

    def select_api_key_file(self):
        """选择 API 密钥文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择 API 密钥文件",
            "",
            "文本文件 (*.txt);;所有文件 (*)"
        )
        if file_path:
            self.api_key_file_edit.setText(file_path)
            self.api_key_manager.load_keys_from_file(file_path)
            count = self.api_key_manager.get_available_keys_count()
            self.api_key_status_label.setText(f"已加载 {count} 个密钥")
            self.api_key_status_label.setStyleSheet("color: #4caf50; font-size: 11px;")

    def start_batch_generation(self):
        """V2.2.0: 开始批量生成（从任务列表读取）"""
        # 检查模型选择
        model_name = self.batch_model_combo.currentText()
        if not model_name:
            QMessageBox.warning(self, "警告", "请先选择一个模型")
            return

        config = self.config_loader.get_model_by_name(model_name)
        if not config:
            QMessageBox.warning(self, "警告", "未找到模型配置")
            return

        # V2.2.0: 检查任务列表
        if not self.batch_task_list:
            QMessageBox.warning(self, "警告", "请先添加任务")
            return

        # 检查 API 密钥
        available_keys = self.api_key_manager.get_all_keys()
        if not available_keys:
            QMessageBox.warning(self, "警告", "没有可用的 API 密钥，请先配置")
            return

        # 清空日志和状态
        self.log_edit.clear()
        self.batch_tasks.clear()

        # 获取基础输入值（从模型配置中）
        base_input_values = config.get("input_values", {}).copy()

        # 从批量参数输入中收集值（如果有）
        for key, param_input in self.batch_parameter_inputs.items():
            value = param_input.get_value()
            if value:
                base_input_values[key] = value

        # V2.2.0: 从任务列表构建任务
        task_list = []
        for i, task_data in enumerate(self.batch_task_list):
            task_id = f"batch_task_{i+1}_{int(time.time())}"
            prompt = task_data["prompt"]

            # 复制基础参数并替换 prompt
            input_values = base_input_values.copy()
            for key in list(input_values.keys()):
                param_type = ParameterDefinition.detect_parameter_type(key, input_values[key])
                if param_type == ParameterType.PROMPT:
                    input_values[key] = prompt

            task_list.append((task_id, config, input_values))

            # 更新任务状态
            task_data["status"] = "执行中"

        self._update_batch_task_table()

        # 开始批量生成
        self.batch_generate_btn.setEnabled(False)
        self.batch_cancel_btn.setEnabled(True)
        self.log(f"=== V2.2.0 批量生成开始 ===")
        self.log(f"模型: {model_name}")
        self.log(f"任务数: {len(task_list)}")
        self.log(f"API 密钥数: {len(available_keys)} (密钥轮流模式)")
        self.log(f"任务间隔: 1 分钟")
        self.log(f"轮询间隔: 30 秒")
        self.log(f"轮询等待: 5 分钟")

        self.batch_manager.add_tasks(task_list)

    def cancel_batch_generation(self):
        """取消批量生成"""
        reply = QMessageBox.question(
            self, "确认",
            "确定要取消所有任务吗？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )
        if reply == QMessageBox.Yes:
            self.batch_manager.cancel_all_tasks()
            self.batch_generate_btn.setEnabled(True)
            self.batch_cancel_btn.setEnabled(False)
            self.log("已取消批量生成")

    def on_batch_task_finished(self, success: bool, _message: str, result_data: dict, task_id: str):
        """V2.2.0: 批量任务完成回调"""
        status = "成功" if success else "失败"
        video_url = result_data.get("video_url", "")
        self.batch_tasks[task_id] = {
            "status": status,
            "result": result_data,
            "url": video_url
        }
        self.log(f"任务 {task_id} {status}")

        # V2.2.0: 更新任务列表中的对应任务状态
        # 从 task_id 中提取任务索引
        try:
            task_index = int(task_id.split("_")[2]) - 1  # batch_task_X_YYYY
            if 0 <= task_index < len(self.batch_task_list):
                self.batch_task_list[task_index]["status"] = "已完成" if success else "失败"
                self._update_batch_task_table()
        except (IndexError, ValueError):
            pass

        # 保存批量任务历史记录
        model_name = self.batch_model_combo.currentText()
        config = self.config_loader.get_model_by_name(model_name)
        history_record = {
            "type": "batch",
            "task_id": task_id,
            "model_name": model_name,
            "web_app_id": config.get("web_app_id", "") if config else "",
            "success": success,
            "result": result_data,
            "video_url": video_url
        }
        self.history_manager.add_record(history_record)

        # V2.2.0: 自动下载成功的视频
        if success and video_url:
            self._auto_download_video(video_url)

    def on_batch_progress_updated(self, completed: int, total: int):
        """批量进度更新"""
        self.status_label.setText(f"批量进度: {completed}/{total}")
        self.progress_bar.setValue(int(completed / total * 100) if total > 0 else 0)

        if completed >= total and total > 0:
            self.batch_generate_btn.setEnabled(True)
            self.batch_cancel_btn.setEnabled(False)
            self.status_label.setText("批量任务完成！")
            self.log(f"批量任务全部完成！成功: {completed}/{total}")

    def update_api_key_status(self):
        """更新 API 密钥状态显示"""
        available_keys = self.api_key_manager.get_all_keys()
        count = len(available_keys)
        if count > 0:
            self.api_key_status_label.setText(f"API 密钥: {count} 个可用")
            self.api_key_status_label.setStyleSheet("color: #4caf50; font-size: 11px;")
        else:
            env_key = os.getenv('SiliconCloud_API_KEY')
            if env_key:
                self.api_key_status_label.setText("API 密钥: 系统变量")
                self.api_key_status_label.setStyleSheet("color: #4caf50; font-size: 11px;")
            else:
                self.api_key_status_label.setText("API 密钥: 未配置")
                self.api_key_status_label.setStyleSheet("color: #f44336; font-size: 11px;")

    def show_api_settings(self):
        """显示 API 设置对话框"""
        dialog = QDialog(self)
        dialog.setWindowTitle("API 设置")
        dialog.setMinimumSize(500, 300)

        layout = QVBoxLayout(dialog)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        # 标题
        title = QLabel("API 密钥配置")
        title.setStyleSheet("font-size: 16px; font-weight: 500; color: #e0e0e0;")
        layout.addWidget(title)

        # 密钥来源选择
        source_layout = QHBoxLayout()
        source_layout.addWidget(QLabel("密钥来源:"))
        source_combo = ComboBox()
        source_combo.addItems(["系统变量", "密钥文本", "文件密钥"])
        source_combo.setFixedHeight(36)
        source_combo.setCurrentIndex(0)
        source_layout.addWidget(source_combo)
        layout.addLayout(source_layout)

        # 内容区域（使用 stacked widget）
        from PyQt5.QtWidgets import QStackedWidget
        content_stack = QStackedWidget()

        # 系统变量页面
        env_page = QWidget()
        env_layout = QVBoxLayout(env_page)
        env_layout.addWidget(QLabel("使用系统环境变量 SiliconCloud_API_KEY"))
        env_key = os.getenv('SiliconCloud_API_KEY', '')
        if env_key:
            env_key_label = QLabel(f"当前值: {env_key[:8]}...{env_key[-4:]}")
            env_key_label.setStyleSheet("color: #4caf50;")
        else:
            env_key_label = QLabel("未设置环境变量")
            env_key_label.setStyleSheet("color: #f44336;")
        env_layout.addWidget(env_key_label)
        env_layout.addStretch()
        content_stack.addWidget(env_page)

        # 密钥文本页面
        text_page = QWidget()
        text_layout = QVBoxLayout(text_page)
        text_layout.addWidget(QLabel("每行输入一个 API 密钥:"))
        text_edit = QTextEdit()
        text_edit.setPlaceholderText("sk-xxxxxxxxxxxx\nsk-yyyyyyyyyyyyy\nsk-zzzzzzzzzzzz")
        text_edit.setStyleSheet("""
            QTextEdit {
                background-color: #1e1e1e;
                color: #cccccc;
                border: 1px solid #333333;
                border-radius: 6px;
                padding: 8px;
                font-size: 12px;
                font-family: 'SF Mono', 'Menlo', monospace;
            }
        """)
        text_layout.addWidget(text_edit)
        content_stack.addWidget(text_page)

        # 文件密钥页面
        file_page = QWidget()
        file_layout = QVBoxLayout(file_page)
        file_input_layout = QHBoxLayout()
        file_edit = LineEdit()
        file_edit.setReadOnly(True)
        file_edit.setPlaceholderText("选择 API 密钥文件...")
        file_input_layout.addWidget(file_edit, 1)
        file_btn = PushButton(FluentIcon.FOLDER, "")
        file_btn.setFixedSize(36, 34)
        file_input_layout.addWidget(file_btn)
        file_layout.addLayout(file_input_layout)
        file_layout.addWidget(QLabel("文件格式：每行一个 API 密钥的文本文件"))
        file_layout.addStretch()
        content_stack.addWidget(file_page)

        layout.addWidget(content_stack, 1)

        # 切换页面
        def on_source_changed(index):
            content_stack.setCurrentIndex(index)

        source_combo.currentIndexChanged.connect(on_source_changed)

        # 文件选择
        def select_file():
            file_path, _ = QFileDialog.getOpenFileName(
                dialog, "选择 API 密钥文件",
                "",
                "文本文件 (*.txt);;所有文件 (*)"
            )
            if file_path:
                file_edit.setText(file_path)

        file_btn.clicked.connect(select_file)

        # 按钮
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        save_btn = PrimaryPushButton("保存")
        cancel_btn = PushButton("取消")
        button_layout.addWidget(save_btn)
        button_layout.addWidget(cancel_btn)
        layout.addLayout(button_layout)

        # 保存处理
        def save_settings():
            source = source_combo.currentText()
            if source == "系统变量":
                self.api_key_manager.set_key_source("env")
            elif source == "密钥文本":
                text = text_edit.toPlainText().strip()
                if text:
                    self.api_key_manager.load_keys_from_text(text)
                    self.api_key_manager.set_key_source("text")
                else:
                    QMessageBox.warning(dialog, "警告", "请输入 API 密钥")
                    return
            elif source == "文件密钥":
                file_path = file_edit.text()
                if file_path and os.path.exists(file_path):
                    self.api_key_manager.load_keys_from_file(file_path)
                    self.api_key_manager.set_key_source("file")
                else:
                    QMessageBox.warning(dialog, "警告", "请选择有效的密钥文件")
                    return

            self.update_api_key_status()
            QMessageBox.information(dialog, "成功", "API 密钥设置已保存")
            dialog.accept()

        save_btn.clicked.connect(save_settings)
        cancel_btn.clicked.connect(dialog.reject)

        dialog.exec_()

    def log(self, message: str):
        """记录日志"""
        self.on_log_updated(message)

    def export_history(self):
        """显示历史记录对话框"""
        history = self.history_manager.get_history()

        # 创建对话框
        dialog = QDialog(self)
        dialog.setWindowTitle("历史记录")
        dialog.setMinimumSize(900, 600)

        layout = QVBoxLayout(dialog)

        # 标题
        title = QLabel(f"历史记录 (共 {len(history)} 条)")
        title.setStyleSheet("font-size: 14px; font-weight: 500; color: #e0e0e0;")
        layout.addWidget(title)

        # 创建表格
        table = TableWidget()
        table.setColumnCount(6)
        table.setHorizontalHeaderLabels(["时间", "类型", "模型", "状态", "视频 URL", "详情"])

        # 设置表格样式
        table.setStyleSheet("""
            QTableWidget {
                background-color: #1e1e1e;
                color: #cccccc;
                border: 1px solid #333333;
                border-radius: 6px;
                gridline-color: #2a2a2a;
                font-size: 11px;
            }
            QTableWidget::item {
                padding: 5px;
            }
            QTableWidget::item:selected {
                background-color: #4a90e2;
                color: #ffffff;
            }
            QHeaderView::section {
                background-color: #2a2a2a;
                color: #e0e0e0;
                padding: 8px;
                border: none;
                border-right: 1px solid #333333;
                font-weight: 500;
            }
        """)

        # 填充数据
        table.setRowCount(len(history))
        for row, record in enumerate(reversed(history)):
            # 时间
            time_item = QTableWidgetItem(record.get("timestamp", ""))
            table.setItem(row, 0, time_item)

            # 类型
            type_item = QTableWidgetItem(record.get("type", ""))
            table.setItem(row, 1, type_item)

            # 模型名称
            model_item = QTableWidgetItem(record.get("model_name", ""))
            table.setItem(row, 2, model_item)

            # 状态
            success = record.get("success", False)
            status_text = "成功" if success else "失败"
            status_item = QTableWidgetItem(status_text)
            table.setItem(row, 3, status_item)

            # 视频 URL
            result = record.get("result", {})
            video_url = result.get("video_url", "") if isinstance(result, dict) else ""
            url_item = QTableWidgetItem(video_url[:50] + "..." if len(video_url) > 50 else video_url)
            table.setItem(row, 4, url_item)

            # 详情按钮
            detail_btn = PushButton("查看")
            detail_btn.setFixedHeight(28)
            detail_btn.clicked.connect(lambda checked, r=record: self._show_record_detail(r, dialog))
            table.setCellWidget(row, 5, detail_btn)

        # 调整列宽
        table.horizontalHeader().setSectionResizeMode(0, 1)  # 时间自动
        table.horizontalHeader().setSectionResizeMode(1, 1)  # 类型自动
        table.horizontalHeader().setSectionResizeMode(2, 2)  # 模型拉伸
        table.horizontalHeader().setSectionResizeMode(3, 1)  # 状态自动
        table.horizontalHeader().setSectionResizeMode(4, 3)  # URL拉伸
        table.horizontalHeader().setSectionResizeMode(5, 0)  # 详情固定
        table.setColumnWidth(5, 80)

        layout.addWidget(table)

        # 按钮区域
        button_layout = QHBoxLayout()
        button_layout.addStretch()

        export_btn = PrimaryPushButton("导出历史")
        export_btn.clicked.connect(lambda: self._export_history_from_dialog(history, dialog))
        button_layout.addWidget(export_btn)

        clear_btn = PushButton("清空历史")
        clear_btn.clicked.connect(lambda: self._clear_history(dialog))
        button_layout.addWidget(clear_btn)

        close_btn = PushButton("关闭")
        close_btn.clicked.connect(dialog.accept)
        button_layout.addWidget(close_btn)

        layout.addLayout(button_layout)

        dialog.exec_()

    def _show_record_detail(self, record: dict, parent_dialog: QDialog):
        """显示记录详情"""
        detail_dialog = QDialog(parent_dialog)
        detail_dialog.setWindowTitle("记录详情")
        detail_dialog.setMinimumSize(600, 400)

        layout = QVBoxLayout(detail_dialog)

        # 创建文本显示
        text_edit = QTextEdit()
        text_edit.setReadOnly(True)
        text_edit.setStyleSheet("""
            QTextEdit {
                background-color: #1e1e1e;
                color: #cccccc;
                border: 1px solid #333333;
                border-radius: 6px;
                padding: 10px;
                font-family: 'SF Mono', 'Menlo', monospace;
                font-size: 11px;
            }
        """)

        # 格式化 JSON 显示
        import json
        try:
            formatted_json = json.dumps(record, ensure_ascii=False, indent=2)
            text_edit.setText(formatted_json)
        except Exception as e:
            text_edit.setText(f"无法格式化记录: {str(e)}\n\n原始数据:\n{str(record)}")

        layout.addWidget(text_edit)

        # 关闭按钮
        close_btn = PushButton("关闭")
        close_btn.clicked.connect(detail_dialog.accept)
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        button_layout.addWidget(close_btn)
        layout.addLayout(button_layout)

        detail_dialog.exec_()

    def _export_history_from_dialog(self, history: list, parent_dialog: QDialog):
        """从对话框导出历史记录"""
        default_name = f"vods_history_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        file_path, _ = QFileDialog.getSaveFileName(
            parent_dialog, "导出历史记录",
            default_name,
            "JSON 文件 (*.json);;所有文件 (*)"
        )

        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(history, f, ensure_ascii=False, indent=2)
                QMessageBox.information(
                    parent_dialog, "成功",
                    f"历史记录已导出到:\n{file_path}\n\n共 {len(history)} 条记录"
                )
            except Exception as e:
                QMessageBox.warning(parent_dialog, "错误", f"导出失败: {str(e)}")

    def _clear_history(self, parent_dialog: QDialog):
        """清空历史记录"""
        reply = QMessageBox.question(
            parent_dialog, "确认",
            "确定要清空所有历史记录吗？此操作不可恢复。",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            self.history_manager.history = []
            self.history_manager.save_history()
            QMessageBox.information(parent_dialog, "成功", "历史记录已清空")
            parent_dialog.accept()  # 关闭对话框
