#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 图片提示词生成器
基于 PyQt5 和 qfluentwidgets 开发的图片识别与提示词生成工具
独立运行版本
"""
import os
import sys
import json
import requests
import logging
import base64
import threading
import time
from datetime import datetime
from io import BytesIO
from PIL import Image

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QSpinBox,
                            QMessageBox, QGroupBox, QDialog, QToolButton,
                            QSizePolicy, QSplitter, QTabWidget, QScrollArea,
                            QListWidget, QListWidgetItem, QFrame)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QUrl, QSize, QTimer
from PyQt5.QtGui import QFont, QIcon, QDesktopServices, QPixmap
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, RadioButton,
                          ProgressBar, InfoBar, InfoBarPosition, SmoothScrollArea,
                          CardWidget, setTheme, Theme, InfoBarIcon)

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# ==================== 自动消失消息辅助函数 ====================
def show_auto_hide_message(parent, title, content, severity='info', duration=3000):
    """显示自动消失的 InfoBar 消息

    Args:
        parent: 父窗口或 Widget
        title: 消息标题
        content: 消息内容
        severity: 消息类型 ('info', 'success', 'warning', 'error')
        duration: 显示时长（毫秒），默认 3 秒
    """
    # 根据 severity 选择图标和类型
    icon_config = {
        'info': (InfoBarIcon.INFORMATION, InfoBarPosition.TOP),
        'success': (InfoBarIcon.SUCCESS, InfoBarPosition.TOP),
        'warning': (InfoBarIcon.WARNING, InfoBarPosition.TOP),
        'error': (InfoBarIcon.ERROR, InfoBarPosition.TOP)
    }

    icon, position = icon_config.get(severity, icon_config['info'])

    # 创建 InfoBar
    info_bar = InfoBar(
        icon,
        title,
        content,
        parent=parent,
        position=position,
        duration=duration
    )
    info_bar.show()


# API 配置
MODEL_API_KEY = os.getenv('SiliconCloud_API_KEY')


# ==================== VLM 配置管理器 ====================
class VLMConfigManager:
    """VLM API 配置管理器"""

    def __init__(self, config_file="vlm_config.json"):
        self.config_file = config_file
        self.config = self.load_config()
        self.templates_file = "vlm_prompt_templates.json"
        self.templates = self.load_templates()

    def load_config(self):
        """加载 VLM 配置"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                # 补全缺失的默认字段
                defaults = {
                    "default_template": "default",
                    "default_template_gemini_vlm": "人像",
                }
                for key, value in defaults.items():
                    if key not in config:
                        config[key] = value
                return config
            except Exception as e:
                logger.error(f"加载 VLM 配置失败: {e}")

        # 默认配置
        return {
            "web_app_id": 40122,
            "model": "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct",
            "suppress_preview_output": True,
            "default_template": "default",
            "default_template_gemini_vlm": "人像",
            "available_models": [
                "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct",
                "SiliconFlow:Qwen/Qwen3-VL-32B-Instruct",
                "SiliconFlow:Qwen/Qwen3-VL-30B-A3B-Instruct",
                "SiliconFlow:THUDM/GLM-4.1V-9B-Thinking",
                "SiliconFlow:zai-org/GLM-4.5V",
                "SiliconFlow:zai-org/GLM-4.6V"
            ]
        }

    def save_config(self):
        """保存 VLM 配置"""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
            return True
        except Exception as e:
            logger.error(f"保存 VLM 配置失败: {e}")
            return False

    def load_templates(self):
        """加载提示词模板"""
        if os.path.exists(self.templates_file):
            try:
                with open(self.templates_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"加载模板失败: {e}")

        # 默认模板
        return {
            "default": {
                "name": "默认模板",
                "template": "请描述这张图片的内容，提供一段丰富的中英文画面详细描述，这些描述信息将用于AI绘画的prompt，最后再将中英文的prompt描述内容简化成tag关键字标签。请用json 数据格式返回，json返回的四段信息分别是：CN（用于AI绘画的中文详细信息Prompt）、 EN（用于AI绘画的英文详细信息Prompt）、CN_tag（中文Tag标签用中文逗号隔开）、EN_tag（英文Tag标签用英文逗号隔开）。所有返回信息仅仅输出解析后的json格式数据就可以。我将导出保存 json 格式的文件数据。"
            }
        }

    def save_templates(self):
        """保存提示词模板"""
        try:
            with open(self.templates_file, 'w', encoding='utf-8') as f:
                json.dump(self.templates, f, indent=4, ensure_ascii=False)
            return True
        except Exception as e:
            logger.error(f"保存模板失败: {e}")
            return False

    def get(self, key, default=None):
        """获取配置值"""
        return self.config.get(key, default)

    def set(self, key, value):
        """设置配置值"""
        self.config[key] = value

    def add_model(self, model_name):
        """添加新模型到可用模型列表"""
        if "available_models" not in self.config:
            self.config["available_models"] = []
        if model_name not in self.config["available_models"]:
            self.config["available_models"].append(model_name)
            return self.save_config()
        return True

    def get_available_models(self):
        """获取可用模型列表"""
        return self.config.get("available_models", [
            "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct",
            "SiliconFlow:Qwen/Qwen3-VL-32B-Instruct",
            "SiliconFlow:Qwen/Qwen3-VL-30B-A3B-Instruct",
            "SiliconFlow:THUDM/GLM-4.1V-9B-Thinking",
            "SiliconFlow:zai-org/GLM-4.5V",
            "SiliconFlow:zai-org/GLM-4.6V"
        ])


# ==================== VLM 历史记录管理器 ====================
class VLMHistoryManager:
    """VLM 历史记录管理器"""

    def __init__(self, history_file="vlm_history.json"):
        self.history_file = history_file
        self.history = self.load_history()

    def load_history(self):
        """加载历史记录"""
        if os.path.exists(self.history_file):
            try:
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"加载历史记录失败: {e}")
        return []

    def save_history(self):
        """保存历史记录"""
        try:
            # 只保留最近 100 条记录
            if len(self.history) > 100:
                self.history = self.history[-100:]
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, indent=4, ensure_ascii=False)
            return True
        except Exception as e:
            logger.error(f"保存历史记录失败: {e}")
            return False

    def add_record(self, image_url, result, task_id=None, result_file_url=None, local_file_path=None, webp_image_path=None):
        """添加历史记录

        Args:
            image_url: 图片URL（可能是网络URL或base64 data URL）
            result: 识别结果字典
            task_id: API任务ID
            result_file_url: 结果文件的下载URL
            local_file_path: 保存到本地的结果文件路径
            webp_image_path: 保存到本地的 webp 图片路径
        """
        # 确定图片类型和显示名称
        image_display = ""
        image_type = ""
        if webp_image_path:
            # 优先使用 webp 图片路径
            image_type = "webp"
            image_display = webp_image_path
        elif image_url.startswith('data:image/'):
            image_type = "local"
            image_display = local_file_path if local_file_path else "[本地图片]"
        elif image_url.startswith(('http://', 'https://')):
            image_type = "network"
            image_display = image_url
        else:
            image_type = "local"
            image_display = image_url if image_url else "[本地图片]"

        record = {
            "id": str(int(time.time() * 1000)),
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "task_id": task_id or "",
            "image_type": image_type,
            "image_url": image_url[:500] if len(image_url) > 500 else image_url,  # 限制长度
            "image_display": image_display,
            "webp_image_path": webp_image_path or "",  # webp 图片路径
            "result_file_url": result_file_url or "",
            "local_file_path": local_file_path or "",
            "result": {
                "CN": result.get("CN", ""),
                "EN": result.get("EN", ""),
                "CN_tag": result.get("CN_tag", ""),
                "EN_tag": result.get("EN_tag", "")
            }
        }
        self.history.insert(0, record)  # 插入到开头
        self.save_history()

    def delete_record(self, record_id):
        """删除历史记录"""
        self.history = [r for r in self.history if r.get("id") != record_id]
        self.save_history()

    def clear_all(self):
        """清空所有记录"""
        self.history.clear()
        self.save_history()

    def get_history(self):
        """获取所有历史记录"""
        return self.history


# ==================== 支持拖拽的图片预览标签 ====================
class DragDropImageLabel(QLabel):
    """支持拖拽本地图片和网络URL的图片预览标签"""

    image_dropped = pyqtSignal(str)  # 发射信号：文件路径或URL

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.setAlignment(Qt.AlignCenter)

    def dragEnterEvent(self, event):
        """拖拽进入事件"""
        if event.mimeData().hasUrls() or event.mimeData().hasText():
            event.acceptProposedAction()
            self.setStyleSheet("border: 2px dashed #6699ff; border-radius: 8px; background: #e6f0ff;")
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        """拖拽移动事件"""
        if event.mimeData().hasUrls() or event.mimeData().hasText():
            event.acceptProposedAction()
        else:
            event.ignore()

    def dragLeaveEvent(self, event):
        """拖拽离开事件"""
        event.accept()
        self.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #1E1E1E;")

    def dropEvent(self, event):
        """拖拽放下事件"""
        self.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #1E1E1E;")

        # 首先检查是否有URL（支持拖拽文件）
        if event.mimeData().hasUrls():
            urls = event.mimeData().urls()
            if urls:
                url = urls[0]
                if url.isLocalFile():
                    # 本地文件
                    local_path = url.toLocalFile()
                    # 检查是否为图片文件
                    image_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp']
                    if any(local_path.lower().endswith(ext) for ext in image_extensions):
                        self.image_dropped.emit(local_path)
                    else:
                        show_auto_hide_message(self.window(), "警告", "请拖拽图片文件", "warning")
                else:
                    # 网络URL
                    network_url = url.toString()
                    self.image_dropped.emit(network_url)
                event.acceptProposedAction()
        # 其次检查是否有文本（支持拖拽URL文本）
        elif event.mimeData().hasText():
            text = event.mimeData().text().strip()
            # 判断是否为URL
            if text.startswith(('http://', 'https://')):
                self.image_dropped.emit(text)
                event.acceptProposedAction()
            # 判断是否为本地文件路径
            elif text.startswith('/') or text.startswith('.'):
                image_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp']
                if any(text.lower().endswith(ext) for ext in image_extensions):
                    self.image_dropped.emit(text)
                    event.acceptProposedAction()
                else:
                    show_auto_hide_message(self.window(), "警告", "请输入图片文件路径", "warning")
            else:
                event.ignore()
        else:
            event.ignore()


# ==================== VLM 图片识别工作线程 ====================
class VLMImageWorker(QThread):
    """VLM 图片识别工作线程"""

    progress_updated = pyqtSignal(str)
    time_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, dict, str, str, str, str)  # success, result, image_url, task_id, result_file_url, local_file_path
    error_occurred = pyqtSignal(str)
    log_message = pyqtSignal(str)  # 新增：日志消息信号

    def __init__(self, image_url, config_manager, template, mode="base"):
        super().__init__()
        self.image_url = image_url
        self.config_manager = config_manager
        self.template = template
        self.mode = mode  # "base" 或 "gemini_vlm"
        self.is_cancelled = False
        self.start_time = None
        # 存储任务信息
        self.task_id = ""
        self.result_file_url = ""
        self.local_file_path = ""

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True

    def _log(self, message):
        """内部日志方法"""
        self.log_message.emit(message)
        logger.info(message)

    @staticmethod
    def _clean_think_mode_json(text):
        """清理 think 模式模型返回的 JSON 中的 Unicode 转义字符和 think 标签"""
        import re
        # 移除 <think...</think] 或 <think...>...</think] 包裹的思考过程
        text = re.sub(r'<think[^>]*>.*?</think\s*>', '', text, flags=re.DOTALL)
        text = re.sub(r'<think[^]]*>.*?</think\s*\]>', '', text, flags=re.DOTALL)
        # 解码常见的 HTML 实体转义（think 模式模型会生成这些）
        text = text.replace('\\u003c', '<').replace('\\u003e', '>')
        text = text.replace('\\u0026', '&').replace('\\u0022', '"')
        text = text.replace('\\u0027', "'")
        # 清理可能残留的 \\n \\t
        text = text.replace('\\n', '\n').replace('\\t', '\t')
        return text.strip()

    def run(self):
        """运行图片识别"""
        try:
            self.start_time = time.time()
            self.progress_updated.emit("正在初始化 VLM API...")
            self._log("=" * 60)
            self._log("开始 VLM 图片识别任务")

            # 使用全局MODEL_API_KEY作为API密钥
            api_key = MODEL_API_KEY
            if not api_key:
                self._log("❌ 错误：API密钥未配置")
                self.finished.emit(False, {}, self.image_url, "", "", "")
                self.error_occurred.emit("API密钥未配置")
                return

            base_url = 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create'
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }

            # 根据模式构建不同的请求参数
            if self.mode == "gemini_vlm":
                # Gemini VLM 模式
                web_app_id = 44279
                suppress_preview = True
                input_values = {
                    "2:LoadImage.image": self.image_url,
                    "20:BizyAir_TRD_VLM_API.system_prompt": "你是一个能分析图像的AI助手。请仔细观察图像，并根据用户的问题提供详细、准确的描述。当你接收到上传的一张图片时，请遵循以下核心原则和结构化标准，生成详细的 AI 绘画提示词。",
                    "20:BizyAir_TRD_VLM_API.user_prompt": self.template,
                    "25:EG_TC_Node.文本3": ".md"
                }
            else:
                # 基础模型模式（默认）
                web_app_id = 40122  # 硬编码基础模型 web_app_id
                model = self.config_manager.get("model", "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct")
                suppress_preview = self.config_manager.get("suppress_preview_output", True)

                input_values = {
                    "65:LoadImage.image": self.image_url,
                    "64:BizyAirSiliconCloudVLMAPI.model": model,
                    "64:BizyAirSiliconCloudVLMAPI.user_prompt": self.template
                }

            # 输出完整的 API 请求信息
            mode_label = "Gemini VLM" if self.mode == "gemini_vlm" else "基础模型"
            self._log("📤 API 请求信息:")
            self._log(f"  URL: {base_url}")
            self._log(f"  模式: {mode_label}")
            self._log(f"  Web App ID: {web_app_id}")
            if self.mode == "base":
                self._log(f"  模型: {self.config_manager.get('model', 'SiliconFlow:Qwen/Qwen3-VL-8B-Instruct')}")
            self._log(f"  抑制预览输出: {suppress_preview}")
            self._log(f"  图片大小: {len(self.image_url)} 字符")
            self._log(f"  提示词模板长度: {len(self.template)} 字符")

            request_data = {
                "web_app_id": web_app_id,
                "suppress_preview_output": suppress_preview,
                "input_values": input_values
            }
            self._log(f"  请求数据: {json.dumps(request_data, ensure_ascii=False)[:500]}...")

            self.progress_updated.emit("正在提交识别请求...")

            # 启动时间更新线程
            stop_time_update = threading.Event()

            def time_update_thread():
                while not stop_time_update.is_set():
                    elapsed = time.time() - self.start_time
                    self.time_updated.emit(f"运行时间: {elapsed:.1f}秒")
                    stop_time_update.wait(1.0)

            time_thread = threading.Thread(target=time_update_thread, daemon=True)
            time_thread.start()

            try:
                self._log("🔄 正在发送 API 请求...")
                response = requests.post(
                    base_url,
                    headers=headers,
                    json=request_data,
                    timeout=180  # 3分钟超时
                )

                stop_time_update.set()
                time_thread.join(timeout=0.5)

                # 输出响应状态
                self._log(f"📥 API 响应状态: HTTP {response.status_code}")

                response.raise_for_status()
                result = response.json()

                # 输出完整响应信息
                self._log("📋 API 响应数据:")
                self._log(f"  状态: {result.get('status', 'Unknown')}")
                self._log(f"  任务ID: {result.get('task_id', 'N/A')}")
                self._log(f"  消息: {result.get('message', 'N/A')}")

                # 保存任务ID
                self.task_id = result.get('task_id', '')

                if "outputs" in result:
                    self._log(f"  输出数量: {len(result.get('outputs', []))}")
                    for i, output in enumerate(result.get('outputs', [])):
                        self._log(f"    输出[{i}]: {output.get('object_url', 'N/A')[:100]}...")

                if result.get("status") == "Success" and result.get("outputs"):
                    # 获取提示词文件 URL
                    prompt_url = result["outputs"][0].get("object_url", "")
                    self.result_file_url = prompt_url  # 保存结果文件URL
                    if prompt_url:
                        self._log(f"✅ 成功获取结果文件 URL")
                        self._log(f"  文件 URL: {prompt_url}")
                        self.progress_updated.emit("正在下载识别结果...")

                        # 确保 output 目录存在
                        output_dir = "output"
                        os.makedirs(output_dir, exist_ok=True)

                        # 从远程 URL 中提取原始文件名
                        original_filename = os.path.basename(prompt_url)
                        if not original_filename or original_filename == '':
                            # 如果无法提取文件名，使用默认命名
                            original_filename = f"vlm_result_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

                        # 构建保存路径
                        save_path = os.path.join(output_dir, original_filename)
                        self.local_file_path = save_path  # 保存本地文件路径

                        self._log(f"💾 开始下载结果文件到: {save_path}")
                        self._log(f"  远程文件名: {original_filename}")

                        # 下载提示词文件
                        prompt_response = requests.get(prompt_url, timeout=30)
                        self._log(f"  下载状态: HTTP {prompt_response.status_code}")

                        if prompt_response.status_code == 200:
                            # 保存文件到 output 目录
                            with open(save_path, 'wb') as f:
                                f.write(prompt_response.content)
                            self._log(f"  文件已保存: {save_path} ({len(prompt_response.content)} 字节)")

                            # 判断文件类型并解析
                            self._log("🔍 开始解析结果文件...")
                            prompt_data = None

                            # Gemini VLM 模式：返回 MD 文件
                            if self.mode == "gemini_vlm":
                                self._log("  检测到 Gemini VLM 模式（MD 格式）")
                                import chardet
                                raw_data = prompt_response.content
                                encoding = chardet.detect(raw_data)['encoding'] or 'utf-8'
                                md_content = raw_data.decode(encoding)
                                self._log(f"  MD 内容长度: {len(md_content)} 字符")

                                # 尝试从 MD 内容中提取四维 JSON 数据
                                extracted_json = False
                                cleaned = self._clean_think_mode_json(md_content)
                                import re
                                json_match = re.search(r'\{[\s\S]*\}', cleaned)
                                if json_match:
                                    try:
                                        parsed = json.loads(json_match.group())
                                        if isinstance(parsed, dict) and all(k in parsed for k in ("CN", "EN", "CN_tag", "EN_tag")):
                                            self._log("  ✅ 从 MD 内容中成功提取四维 JSON 数据")
                                            prompt_data = {
                                                "CN": parsed["CN"],
                                                "EN": parsed["EN"],
                                                "CN_tag": parsed["CN_tag"],
                                                "EN_tag": parsed["EN_tag"]
                                            }
                                            extracted_json = True
                                    except (json.JSONDecodeError, ValueError):
                                        pass

                                if not extracted_json:
                                    self._log("  ⚠️ 未提取到四维 JSON，MD 内容放入中文描述")
                                    prompt_data = {
                                        "CN": md_content,
                                        "EN": "",
                                        "CN_tag": "",
                                        "EN_tag": ""
                                    }
                            elif prompt_url.endswith('.json') or save_path.endswith('.json'):
                                # JSON 文件
                                self._log("  检测到 JSON 格式")
                                import chardet
                                raw_data = prompt_response.content
                                encoding = chardet.detect(raw_data)['encoding'] or 'utf-8'
                                text_content = raw_data.decode(encoding)
                                # 清理 think 模式的转义字符
                                text_content = self._clean_think_mode_json(text_content)
                                self._log(f"  清理后文本长度: {len(text_content)} 字符")
                                try:
                                    prompt_data = json.loads(text_content)
                                    self._log(f"  JSON 解析成功，包含键: {list(prompt_data.keys()) if isinstance(prompt_data, dict) else 'N/A'}")
                                except json.JSONDecodeError as e:
                                    self._log(f"  ❌ JSON 解析失败: {e}")
                                    # 尝试提取 JSON 部分
                                    import re
                                    json_match = re.search(r'\{[\s\S]*\}', text_content)
                                    if json_match:
                                        self._log("  尝试提取 JSON 片段...")
                                        prompt_data = json.loads(json_match.group())
                                    else:
                                        raise
                            else:
                                # TXT 文件 - 尝试检测编码并解析
                                self._log("  检测到 TXT 格式")
                                import chardet
                                raw_data = prompt_response.content
                                encoding = chardet.detect(raw_data)['encoding'] or 'utf-8'
                                self._log(f"  检测到编码: {encoding}")
                                text_content = raw_data.decode(encoding)
                                # 清理 think 模式的转义字符
                                text_content = self._clean_think_mode_json(text_content)
                                self._log(f"  清理后文本长度: {len(text_content)} 字符")

                                # 尝试解析为 JSON
                                try:
                                    prompt_data = json.loads(text_content)
                                    self._log(f"  ✅ 成功从文本中解析 JSON")
                                except json.JSONDecodeError:
                                    # 尝试提取 JSON 部分
                                    import re
                                    json_match = re.search(r'\{[\s\S]*\}', text_content)
                                    if json_match:
                                        self._log("  尝试提取 JSON 片段...")
                                        try:
                                            prompt_data = json.loads(json_match.group())
                                            self._log(f"  ✅ JSON 片段解析成功")
                                        except json.JSONDecodeError:
                                            self._log(f"  ⚠️ 文本内容不是 JSON 格式，保持原样")
                                            prompt_data = {"raw_text": text_content}
                                    else:
                                        self._log(f"  ⚠️ 文本内容不是 JSON 格式，保持原样")
                                        prompt_data = {"raw_text": text_content}

                            # 验证解析结果
                            if prompt_data:
                                if isinstance(prompt_data, dict):
                                    required_fields = ["CN", "EN", "CN_tag", "EN_tag"]
                                    missing_fields = [f for f in required_fields if f not in prompt_data]
                                    if missing_fields:
                                        self._log(f"  ⚠️ 缺少字段: {missing_fields}")
                                    else:
                                        self._log(f"  ✅ 包含所有必需字段: {required_fields}")

                                    # 输出解析后的数据预览
                                    for key, value in prompt_data.items():
                                        if isinstance(value, str):
                                            self._log(f"    {key}: {value[:100]}{'...' if len(value) > 100 else ''}")
                                        elif isinstance(value, (dict, list)):
                                            self._log(f"    {key}: {str(type(value).__name__)}")
                                else:
                                    self._log(f"  ⚠️ 解析结果不是字典类型: {type(prompt_data)}")

                            total_time = time.time() - self.start_time
                            self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
                            self.progress_updated.emit("识别完成！")
                            self._log(f"✅ 识别完成！总耗时: {total_time:.1f}秒")
                            self._log("=" * 60)
                            self.finished.emit(True, prompt_data, self.image_url, self.task_id, self.result_file_url, self.local_file_path)
                        else:
                            error_msg = f"下载提示词文件失败: HTTP {prompt_response.status_code}"
                            self._log(f"❌ {error_msg}")
                            raise Exception(error_msg)
                    else:
                        error_msg = "未获取到提示词文件 URL"
                        self._log(f"❌ {error_msg}")
                        raise Exception(error_msg)
                else:
                    error_msg = result.get("message", "未知错误")
                    self._log(f"❌ VLM API 返回错误: {error_msg}")
                    self._log(f"  完整响应: {json.dumps(result, ensure_ascii=False, indent=2)}")
                    raise Exception(f"VLM API 返回错误: {error_msg}")

            except Exception as e:
                stop_time_update.set()
                if time_thread.is_alive():
                    time_thread.join(timeout=0.5)
                raise e

        except requests.exceptions.Timeout:
            total_time = time.time() - self.start_time if self.start_time else 0
            self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
            self._log(f"❌ 请求超时，耗时: {total_time:.1f}秒")
            self.error_occurred.emit("请求超时，请稍后重试")
            self.finished.emit(False, {}, self.image_url, "", "", "")
        except Exception as e:
            total_time = time.time() - self.start_time if self.start_time else 0
            self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
            error_msg = str(e)
            self._log(f"❌ VLM 图片识别失败: {error_msg}")
            self._log(f"  错误类型: {type(e).__name__}")
            self._log("=" * 60)
            self.error_occurred.emit(f"识别失败: {error_msg}")
            self.finished.emit(False, {}, self.image_url, "", "", "")


# ==================== VLM 设置对话框（增强版） ====================
class VLMSettingsDialog(QDialog):
    """VLM API 设置对话框（支持模型选择和自定义模型添加）"""

    def __init__(self, vlm_config, parent=None):
        super().__init__(parent)
        self.vlm_config = vlm_config
        self.setWindowTitle("VLM API 设置")
        self.setMinimumSize(650, 550)
        self.init_ui()
        self.load_current_config()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # --- API 设置 ---
        api_group = QGroupBox("🔑 VLM API 设置")
        api_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        api_layout = QGridLayout(api_group)

        # 模型选择（下拉框 + 自定义输入）
        api_layout.addWidget(QLabel("VLM 模型:"), 0, 0)

        model_layout = QHBoxLayout()
        self.model_combo = ComboBox()
        self.model_combo.setFixedHeight(32)
        model_layout.addWidget(self.model_combo, 1)

        # 添加模型按钮
        self.add_model_btn = PushButton(FluentIcon.ADD, "")
        self.add_model_btn.setFixedWidth(40)
        self.add_model_btn.setFixedHeight(32)
        self.add_model_btn.setToolTip("添加自定义模型到列表")
        self.add_model_btn.clicked.connect(self.add_custom_model)
        model_layout.addWidget(self.add_model_btn)

        api_layout.addLayout(model_layout, 0, 1)

        # 自定义模型输入
        api_layout.addWidget(QLabel("自定义模型:"), 1, 0)
        self.custom_model_edit = LineEdit()
        self.custom_model_edit.setPlaceholderText("输入自定义模型 (如: SiliconFlow:Qwen/Qwen2-VL-7B-Instruct)")
        self.custom_model_edit.setFixedHeight(32)
        api_layout.addWidget(self.custom_model_edit, 1, 1)

        # 模型说明标签
        self.model_help_label = QLabel("💡 可选择预设模型或在下方输入自定义模型")
        self.model_help_label.setStyleSheet("color: #666; font-size: 11px;")
        api_layout.addWidget(self.model_help_label, 2, 0, 1, 2)

        # Suppress Preview Output
        self.suppress_preview_check = RadioButton("启用")
        api_layout.addWidget(QLabel("抑制预览输出:"), 3, 0)
        api_layout.addWidget(self.suppress_preview_check, 3, 1)

        layout.addWidget(api_group)

        # --- 提示词模板管理（两种模式通用 user_prompt） ---
        template_group = QGroupBox("📝 提示词模板管理（基础模型 / Gemini VLM 通用 user_prompt）")
        template_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        template_layout = QVBoxLayout(template_group)

        # 模板选择
        template_select_layout = QHBoxLayout()
        template_select_layout.addWidget(QLabel("选择模板:"))
        self.template_combo = ComboBox()
        self.template_combo.setFixedHeight(32)
        self.template_combo.currentIndexChanged.connect(self._on_template_user_changed)
        template_select_layout.addWidget(self.template_combo)
        template_layout.addLayout(template_select_layout)

        # 模板名称
        template_layout.addWidget(QLabel("模板名称:"))
        self.template_name_edit = LineEdit()
        self.template_name_edit.setFixedHeight(32)
        template_layout.addWidget(self.template_name_edit)

        # 模板内容
        template_layout.addWidget(QLabel("模板内容:"))
        self.template_content_edit = QTextEdit()
        self.template_content_edit.setMinimumHeight(150)
        template_layout.addWidget(self.template_content_edit)

        # 模板操作按钮
        template_btn_layout = QHBoxLayout()
        self.new_template_btn = PushButton(FluentIcon.ADD, "新建模板")
        self.new_template_btn.clicked.connect(self.new_template)
        self.save_template_btn = PrimaryPushButton(FluentIcon.SAVE, "保存模板")
        self.save_template_btn.clicked.connect(self.save_template)
        self.delete_template_btn = PushButton(FluentIcon.DELETE, "删除模板")
        self.delete_template_btn.clicked.connect(self.delete_template)
        template_btn_layout.addWidget(self.new_template_btn)
        template_btn_layout.addWidget(self.save_template_btn)
        template_btn_layout.addWidget(self.delete_template_btn)
        template_btn_layout.addStretch()
        template_layout.addLayout(template_btn_layout)

        layout.addWidget(template_group)

        # 底部按钮
        button_layout = QHBoxLayout()
        save_btn = PrimaryPushButton("保存设置")
        save_btn.clicked.connect(self.save_settings)
        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addStretch()
        button_layout.addWidget(save_btn)
        button_layout.addWidget(cancel_btn)
        layout.addLayout(button_layout)

    def _on_template_user_changed(self, index):
        """用户主动切换模板时触发"""
        self.on_template_changed(index)
        # 自动设为默认模板并持久化
        template_key = self.template_combo.itemData(index)
        if template_key:
            self.vlm_config.set("default_template", template_key)
            self.vlm_config.save_config()

    def load_current_config(self):
        """加载当前配置"""
        # 加载可用模型列表
        available_models = self.vlm_config.get_available_models()
        self.model_combo.clear()
        for model in available_models:
            self.model_combo.addItem(model)

        # 设置当前模型
        current_model = self.vlm_config.get("model", "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct")
        index = self.model_combo.findText(current_model)
        if index >= 0:
            self.model_combo.setCurrentIndex(index)
        else:
            # 如果当前模型不在列表中，添加它
            self.model_combo.addItem(current_model)
            self.model_combo.setCurrentIndex(self.model_combo.count() - 1)

        self.suppress_preview_check.setChecked(self.vlm_config.get("suppress_preview_output", True))

        # 加载模板列表
        self.update_template_combo()
        # 设置默认模板（阻塞信号避免误触发自动保存）
        self.template_combo.blockSignals(True)
        default_template = self.vlm_config.get("default_template", "default")
        for i in range(self.template_combo.count()):
            if self.template_combo.itemData(i) == default_template:
                self.template_combo.setCurrentIndex(i)
                break
        self.template_combo.blockSignals(False)
        # 手动触发一次加载模板内容
        self.on_template_changed(self.template_combo.currentIndex())

    def update_template_combo(self):
        """更新模板下拉框"""
        self.template_combo.blockSignals(True)
        self.template_combo.clear()
        for key, template in self.vlm_config.templates.items():
            self.template_combo.addItem(template.get("name", key), key)
        self.template_combo.blockSignals(False)

    def on_template_changed(self, index):
        """模板选择变化"""
        template_key = self.template_combo.itemData(index)
        if template_key and template_key in self.vlm_config.templates:
            template = self.vlm_config.templates[template_key]
            self.template_name_edit.setText(template.get("name", ""))
            self.template_content_edit.setText(template.get("template", ""))

    def new_template(self):
        """新建模板"""
        self.template_name_edit.clear()
        self.template_content_edit.clear()
        self.template_name_edit.setFocus()

    def save_template(self):
        """保存模板"""
        name = self.template_name_edit.text().strip()
        content = self.template_content_edit.toPlainText().strip()

        if not name or not content:
            show_auto_hide_message(self, "警告", "模板名称和内容不能为空", "warning")
            return

        # 判断是编辑现有模板还是新建
        current_key = self.template_combo.itemData(self.template_combo.currentIndex())
        current_name = self.vlm_config.templates.get(current_key, {}).get("name", "") if current_key else ""

        if current_key and current_name == name:
            # 编辑现有模板：原地更新
            template_key = current_key
        else:
            # 新建模板：生成唯一 key
            base_key = name.replace(" ", "_").lower()
            template_key = base_key
            counter = 1
            while template_key in self.vlm_config.templates:
                template_key = f"{base_key}_{counter}"
                counter += 1

        self.vlm_config.templates[template_key] = {
            "name": name,
            "template": content
        }

        # 立即设为默认模板
        self.vlm_config.set("default_template", template_key)

        if self.vlm_config.save_templates() and self.vlm_config.save_config():
            show_auto_hide_message(self, "成功", "模板保存成功", "success")
            self.update_template_combo()
            # 选中刚保存的模板
            for i in range(self.template_combo.count()):
                if self.template_combo.itemData(i) == template_key:
                    self.template_combo.setCurrentIndex(i)
                    break
        else:
            show_auto_hide_message(self, "错误", "模板保存失败", "error")

    def delete_template(self):
        """删除模板"""
        template_key = self.template_combo.itemData(self.template_combo.currentIndex())
        if not template_key:
            return

        if template_key == "default":
            show_auto_hide_message(self, "警告", "默认模板不能删除", "warning")
            return

        reply = QMessageBox.question(
            self, "确认删除",
            f"确定要删除模板 '{self.template_name_edit.text()}' 吗？",
            QMessageBox.Yes | QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            del self.vlm_config.templates[template_key]
            if self.vlm_config.save_templates():
                show_auto_hide_message(self, "成功", "模板删除成功", "success")
                self.update_template_combo()
            else:
                show_auto_hide_message(self, "错误", "模板删除失败", "error")

    def add_custom_model(self):
        """将自定义模型添加到列表"""
        custom_model = self.custom_model_edit.text().strip()
        if not custom_model:
            show_auto_hide_message(self, "警告", "请先输入自定义模型名称", "warning")
            return

        # 添加到配置
        if self.vlm_config.add_model(custom_model):
            # 重新加载下拉框
            available_models = self.vlm_config.get_available_models()
            self.model_combo.clear()
            for model in available_models:
                self.model_combo.addItem(model)

            # 选中新添加的模型
            index = self.model_combo.findText(custom_model)
            if index >= 0:
                self.model_combo.setCurrentIndex(index)

            # 清空输入框
            self.custom_model_edit.clear()

            show_auto_hide_message(self, "成功", f"模型 '{custom_model}' 已添加到列表", "success")
        else:
            show_auto_hide_message(self, "警告", "添加模型失败", "warning")

    def save_settings(self):
        """保存设置"""
        # 保存当前选择的模型（支持下拉框选择或手动输入）
        current_model = self.model_combo.currentText().strip()
        if current_model:
            self.vlm_config.set("model", current_model)
            # 如果模型不在列表中，自动添加
            if current_model not in self.vlm_config.get_available_models():
                self.vlm_config.add_model(current_model)

        self.vlm_config.set("suppress_preview_output", self.suppress_preview_check.isChecked())

        # 保存当前选中的模板为默认模板
        current_template_key = self.template_combo.itemData(self.template_combo.currentIndex())
        if current_template_key:
            self.vlm_config.set("default_template", current_template_key)

        if self.vlm_config.save_config():
            show_auto_hide_message(self, "成功", "设置保存成功", "success")
            self.accept()
        else:
            show_auto_hide_message(self, "错误", "设置保存失败", "error")


# ==================== VLM 历史记录对话框 ====================
class VLMHistoryDialog(QDialog):
    """VLM 历史记录管理对话框"""

    def __init__(self, vlm_history, parent=None):
        super().__init__(parent)
        self.vlm_history = vlm_history
        self.setWindowTitle("历史记录管理")
        self.setMinimumSize(1000, 700)
        self.history_records = []
        self.init_ui()
        self.load_history()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # 顶部操作栏
        top_layout = QHBoxLayout()
        top_layout.addWidget(SubtitleLabel("📋 识别历史记录"))
        top_layout.addStretch()
        self.clear_all_btn = PushButton(FluentIcon.DELETE, "清空全部")
        self.clear_all_btn.clicked.connect(self.clear_all_history)
        self.refresh_btn = PushButton(FluentIcon.SYNC, "刷新")
        self.refresh_btn.clicked.connect(self.load_history)
        top_layout.addWidget(self.refresh_btn)
        top_layout.addWidget(self.clear_all_btn)
        layout.addLayout(top_layout)

        # 历史记录列表（使用 QListWidget）
        self.history_list = QListWidget()
        self.history_list.setMinimumHeight(600)
        # 增大字体
        self.history_list.setStyleSheet("QListWidget { font-size: 14px; } QListWidget::item { height: 40px; padding: 8px; }")
        self.history_list.itemDoubleClicked.connect(self.on_item_double_clicked)
        layout.addWidget(self.history_list)

        # 底部按钮
        button_layout = QHBoxLayout()
        self.view_detail_btn = PushButton(FluentIcon.VIEW, "查看详情")
        self.view_detail_btn.clicked.connect(self.show_selected_detail)
        self.close_btn = PushButton("关闭")
        self.close_btn.clicked.connect(self.accept)
        button_layout.addStretch()
        button_layout.addWidget(self.view_detail_btn)
        button_layout.addWidget(self.close_btn)
        layout.addLayout(button_layout)

    def load_history(self):
        """加载历史记录"""
        self.history_list.clear()
        self.history_records = []
        history = self.vlm_history.get_history()

        if not history:
            item = QListWidgetItem("暂无历史记录")
            item.setFlags(Qt.NoItemFlags)
            self.history_list.addItem(item)
            return

        for idx, record in enumerate(history):
            self.history_records.append(record)

            # 格式化显示文本
            timestamp = record.get('timestamp', '')
            task_id = record.get('task_id', '')
            image_type = record.get('image_type', '')
            image_display = record.get('image_display', '')

            if image_type == 'local':
                type_icon = "📁"
                display_name = os.path.basename(image_display) if image_display and image_display != '[本地图片]' else '本地图片'
            else:
                type_icon = "🌐"
                display_name = image_display[:60] + '...' if len(image_display) > 60 else image_display

            item_text = f"{idx + 1}. [{timestamp}] {type_icon} {display_name}"
            if task_id:
                item_text += f" | 任务ID: {task_id}"

            item = QListWidgetItem(item_text)
            item.setData(Qt.UserRole, idx)  # 存储索引
            self.history_list.addItem(item)

    def show_selected_detail(self):
        """显示选中项的详情"""
        current_item = self.history_list.currentItem()
        if current_item:
            idx = current_item.data(Qt.UserRole)
            if idx is not None and 0 <= idx < len(self.history_records):
                self.show_detail_dialog(idx)

    def on_item_double_clicked(self, item):
        """处理列表项双击事件"""
        if item:
            idx = item.data(Qt.UserRole)
            if idx is not None and 0 <= idx < len(self.history_records):
                self.show_detail_dialog(idx)

    def show_detail_dialog(self, idx):
        """显示详情对话框"""
        if idx < 0 or idx >= len(self.history_records):
            return

        record = self.history_records[idx]
        # 传递当前索引、总记录数和历史记录列表
        dialog = HistoryDetailDialog(record, self, idx, len(self.history_records), self.history_records)
        dialog.exec_()

    def clear_all_history(self):
        """清空所有历史记录"""
        reply = QMessageBox.question(
            self, "确认清空",
            "确定要清空所有历史记录吗？此操作不可恢复！",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            self.vlm_history.clear_all()
            self.load_history()
            show_auto_hide_message(self, "成功", "历史记录已清空", "success")


# ==================== 历史记录详情弹出窗口（简约无边框风格） ====================
class HistoryDetailDialog(QDialog):
    """历史记录详情弹出窗口 - 简约无边框风格"""

    def __init__(self, record, parent=None, current_index=0, total_records=0, records_list=None):
        super().__init__(parent)
        self.record = record
        self.current_index = current_index
        self.total_records = total_records
        self.records_list = records_list or []
        self.parent_dialog = parent  # 保存父对话框引用
        self.setWindowTitle("历史记录详情")
        self.setMinimumSize(1100, 750)

        # 设置无边框窗口
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.setAttribute(Qt.WA_TranslucentBackground)

        self.init_ui()
        self.update_navigation_buttons()  # 更新导航按钮状态

    def init_ui(self):
        # 主容器（带圆角和阴影效果）
        self.main_container = QWidget()
        self.main_container.setStyleSheet("""
            QWidget {
                background: #1E1E1E;
                border-radius: 12px;
            }
        """)
        main_layout = QVBoxLayout(self.main_container)
        main_layout.setSpacing(12)
        main_layout.setContentsMargins(20, 20, 20, 20)

        # ==================== 顶部区域（图片缩略图 + 信息 + 导航按钮） ====================
        top_widget = QWidget()
        top_layout = QHBoxLayout(top_widget)
        top_layout.setSpacing(15)
        top_layout.setContentsMargins(0, 0, 0, 0)

        # 左边：图片缩略图
        webp_path = self.record.get('webp_image_path', '')
        image_label = QLabel()
        image_label.setFixedSize(200, 290)
        image_label.setStyleSheet("""
            QLabel {
                background: #2d2d2d;
                border-radius: 8px;
                border: 2px solid #3d3d3d;
            }
        """)
        image_label.setAlignment(Qt.AlignCenter)

        if webp_path and os.path.exists(webp_path):
            pixmap = QPixmap(webp_path)
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    190, 280,
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                image_label.setPixmap(scaled_pixmap)
            else:
                image_label.setText("📷\n图片加载失败")
                image_label.setStyleSheet("color: #666; font-size: 14px;")
        else:
            image_label.setText("📷\n无图片")
            image_label.setStyleSheet("color: #666; font-size: 14px;")

        top_layout.addWidget(image_label)

        # 右边：信息区域
        info_widget = QWidget()
        info_layout = QGridLayout(info_widget)
        info_layout.setSpacing(8)
        info_layout.setContentsMargins(0, 0, 0, 0)

        row = 0
        # 时间
        info_layout.addWidget(QLabel("时间:"), row, 0)
        info_layout.addWidget(QLabel(self.record.get('timestamp', '')), row, 1)
        row += 1

        # 任务ID
        record_id = self.record.get('id', '')
        info_layout.addWidget(QLabel("任务ID:"), row, 0)
        info_layout.addWidget(QLabel(record_id if record_id else 'N/A'), row, 1)
        row += 1

        # 图片类型
        image_type = self.record.get('image_type', '')
        type_text = "📁 WebP" if image_type == 'webp' else ("📁 本地" if image_type == 'local' else "🌐 网络")
        info_layout.addWidget(QLabel("类型:"), row, 0)
        info_layout.addWidget(QLabel(type_text), row, 1)
        row += 1

        # 本地结果文件路径
        local_file = self.record.get('local_file_path', '')
        if local_file:
            info_layout.addWidget(QLabel("结果文件:"), row, 0)
            file_label = QLabel(local_file)
            file_label.setStyleSheet("color: #4CAF50; font-size: 14px;")
            file_label.setWordWrap(True)
            info_layout.addWidget(file_label, row, 1)
            row += 1

        # 结果文件URL
        result_url = self.record.get('result_file_url', '')
        if result_url:
            info_layout.addWidget(QLabel("结果URL:"), row, 0)
            url_label = QLabel(result_url[:80] + '...' if len(result_url) > 80 else result_url)
            url_label.setStyleSheet("color: #2196f3; font-size: 14px;")
            url_label.setWordWrap(True)
            info_layout.addWidget(url_label, row, 1)
            row += 1

        # WebP 图片路径
        if webp_path:
            info_layout.addWidget(QLabel("图片路径:"), row, 0)
            img_label = QLabel(webp_path)
            img_label.setStyleSheet("color: #FFA726; font-size: 14px;")
            img_label.setWordWrap(True)
            info_layout.addWidget(img_label, row, 1)

        info_layout.setColumnStretch(1, 1)
        top_layout.addWidget(info_widget, 1)

        # 右边：导航按钮区域
        nav_widget = QWidget()
        nav_layout = QVBoxLayout(nav_widget)
        nav_layout.setSpacing(8)
        nav_layout.setContentsMargins(0, 0, 0, 0)

        # 上一个按钮
        self.prev_btn = PushButton(FluentIcon.LEFT_ARROW, "上一个")
        self.prev_btn.setFixedHeight(40)
        self.prev_btn.setFixedWidth(90)
        self.prev_btn.clicked.connect(self.go_to_previous)
        nav_layout.addWidget(self.prev_btn)

        # 当前记录显示
        self.record_index_label = QLabel(f"{self.current_index + 1}/{self.total_records}")
        self.record_index_label.setAlignment(Qt.AlignCenter)
        self.record_index_label.setStyleSheet("color: #aaa; font-size: 13px; font-weight: bold;")
        nav_layout.addWidget(self.record_index_label)

        # 下一个按钮
        self.next_btn = PushButton(FluentIcon.RIGHT_ARROW, "下一个")
        self.next_btn.setFixedHeight(40)
        self.next_btn.setFixedWidth(90)
        self.next_btn.clicked.connect(self.go_to_next)
        nav_layout.addWidget(self.next_btn)

        nav_layout.addStretch()
        top_layout.addWidget(nav_widget)

        main_layout.addWidget(top_widget)

        # ==================== 提示词选项卡 ====================
        result = self.record.get('result', {})

        tab_widget = QTabWidget()
        tab_widget.setStyleSheet("""
            QTabWidget::pane {
                border: none;
                background: #2d2d2d;
                border-radius: 8px;
            }
            QTabBar::tab {
                background: #3d3d3d;
                color: #aaa;
                padding: 10px 20px;
                font-size: 14px;
                border: none;
                border-top-left-radius: 6px;
                border-top-right-radius: 6px;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background: #2d2d2d;
                color: white;
                font-weight: bold;
            }
            QTabBar::tab:hover:!selected {
                background: #4d4d4d;
            }
        """)

        # 计算文本框高度（8行）
        font_height = 40  # 每行约40px
        text_height = font_height * 8

        # 创建四个选项卡（无内部复制按钮）
        tabs_data = [
            ("中文描述", "CN"),
            ("英文描述", "EN"),
            ("中文标签", "CN_tag"),
            ("英文标签", "EN_tag")
        ]

        for tab_name, result_key in tabs_data:
            page = QWidget()
            page_layout = QVBoxLayout(page)
            page_layout.setContentsMargins(0, 0, 0, 0)

            text_edit = QTextEdit()
            text_edit.setReadOnly(True)
            text_edit.setText(result.get(result_key, ''))
            text_edit.setFixedHeight(text_height)
            text_edit.setStyleSheet("""
                QTextEdit {
                    background: #1a1a1a;
                    color: white;
                    border: none;
                    border-radius: 8px;
                    padding: 15px;
                    font-size: 28px;
                    line-height: 1.6;
                }
                QScrollBar:vertical {
                    background: #2d2d2d;
                    width: 10px;
                    border-radius: 5px;
                }
                QScrollBar::handle:vertical {
                    background: #555;
                    border-radius: 5px;
                    min-height: 30px;
                }
                QScrollBar::handle:vertical:hover {
                    background: #666;
                }
            """)
            page_layout.addWidget(text_edit)

            tab_widget.addTab(page, tab_name)
            # 保存引用以便底部复制按钮使用
            setattr(self, f'{result_key}_text_edit', text_edit)

        main_layout.addWidget(tab_widget)

        # ==================== 底部按钮栏 ====================
        button_layout = QHBoxLayout()
        button_layout.setSpacing(10)

        # 为每个选项卡添加复制按钮和导出按钮
        for tab_name, result_key in tabs_data:
            # 复制按钮
            copy_btn = PushButton(f"复制{tab_name}")
            copy_btn.setFixedHeight(36)
            copy_btn.clicked.connect(lambda checked, k=result_key, n=tab_name: self.copy_result(k, n))
            button_layout.addWidget(copy_btn)

            # 导出按钮
            export_btn = PushButton(FluentIcon.SAVE, f"导出")
            export_btn.setFixedHeight(36)
            export_btn.clicked.connect(lambda checked, k=result_key, n=tab_name: self.export_tab(k, n))
            button_layout.addWidget(export_btn)

        button_layout.addStretch()

        # 删除按钮
        delete_btn = PushButton(FluentIcon.DELETE, "删除")
        delete_btn.setFixedHeight(36)
        delete_btn.clicked.connect(self.delete_current_record)
        button_layout.addWidget(delete_btn)

        # 导出全部按钮
        export_all_btn = PrimaryPushButton(FluentIcon.SAVE, "导出全部")
        export_all_btn.setFixedHeight(36)
        export_all_btn.clicked.connect(self.export_all)
        button_layout.addWidget(export_all_btn)

        # 关闭按钮
        close_btn = PushButton("关闭")
        close_btn.setFixedHeight(36)
        close_btn.clicked.connect(self.accept)
        button_layout.addWidget(close_btn)

        main_layout.addLayout(button_layout)

        # ==================== 设置主布局 ====================
        # 创建外层容器以支持半透明背景
        outer_layout = QVBoxLayout(self)
        outer_layout.setContentsMargins(10, 10, 10, 10)
        outer_layout.addWidget(self.main_container)

    def copy_result(self, result_key, tab_name):
        """复制指定结果到剪贴板"""
        text_edit = getattr(self, f'{result_key}_text_edit', None)
        if text_edit:
            text = text_edit.toPlainText()
            if text:
                clipboard = QApplication.clipboard()
                clipboard.setText(text)
                # 使用 InfoBar 显示提示（更轻量）
                show_auto_hide_message(self, "成功", f"{tab_name}已复制到剪贴板", "success")
            else:
                show_auto_hide_message(self, "提示", "没有可复制的内容", "warning")

    def export_tab(self, result_key, tab_name):
        """导出指定选项卡内容到txt文件（与图片同目录）"""
        text_edit = getattr(self, f'{result_key}_text_edit', None)
        if not text_edit:
            show_auto_hide_message(self, "提示", "无法获取内容", "warning")
            return

        text = text_edit.toPlainText()
        if not text:
            show_auto_hide_message(self, "提示", "没有可导出的内容", "warning")
            return

        # 获取图片路径
        webp_path = self.record.get('webp_image_path', '')
        if not webp_path or not os.path.exists(webp_path):
            show_auto_hide_message(self, "提示", "无法找到图片路径", "warning")
            return

        # 获取图片所在目录和文件名
        img_dir = os.path.dirname(webp_path)
        img_filename = os.path.basename(webp_path)

        # 将文件扩展名改为 .txt
        name_without_ext = os.path.splitext(img_filename)[0]
        txt_filename = f"{name_without_ext}.txt"
        txt_path = os.path.join(img_dir, txt_filename)

        # 保存到txt文件（直接覆盖）
        try:
            with open(txt_path, 'w', encoding='utf-8') as f:
                f.write(text)
            show_auto_hide_message(self, "成功", f"{tab_name}已导出到:\n{txt_path}", "success")
        except Exception as e:
            show_auto_hide_message(self, "错误", f"导出失败: {str(e)}", "error")

    def copy_to_clipboard(self, text):
        """复制到剪贴板（保留兼容性）"""
        clipboard = QApplication.clipboard()
        clipboard.setText(text)
        show_auto_hide_message(self, "成功", "已复制到剪贴板", "success")

    def export_all(self):
        """导出全部结果"""
        result = self.record.get('result', {})
        timestamp = self.record.get('timestamp', '').replace(' ', '_').replace(':', '-')

        file_path, _ = QFileDialog.getSaveFileName(
            self, "导出全部结果",
            f"vlm_history_{timestamp}.json",
            "JSON 文件 (*.json);;所有文件 (*)"
        )

        if file_path:
            try:
                export_data = {
                    "timestamp": self.record.get('timestamp'),
                    "task_id": self.record.get('task_id'),
                    "image_type": self.record.get('image_type'),
                    "image_display": self.record.get('image_display'),
                    "webp_image_path": self.record.get('webp_image_path', ''),
                    "result_file_url": self.record.get('result_file_url'),
                    "local_file_path": self.record.get('local_file_path'),
                    "result": result
                }
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(export_data, f, indent=4, ensure_ascii=False)
                show_auto_hide_message(self, "成功", f"文件已保存到: {file_path}", "success")
            except Exception as e:
                show_auto_hide_message(self, "错误", f"导出失败: {str(e)}", "error")

    def delete_current_record(self):
        """删除当前记录并跳转到下一条"""
        # 确认删除
        reply = QMessageBox.question(
            self, "确认删除",
            "确定要删除这条记录吗？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )
        if reply == QMessageBox.No:
            return

        record_id = self.record.get('id')

        # 删除记录
        if hasattr(self.parent_dialog, 'vlm_history'):
            self.parent_dialog.vlm_history.delete_record(record_id)

            # 更新父对话框的记录列表和显示
            if hasattr(self.parent_dialog, 'history_records'):
                self.parent_dialog.history_records = self.parent_dialog.vlm_history.get_history()
                self.parent_dialog.load_history()

            # 检查是否还有记录
            remaining_records = self.parent_dialog.vlm_history.get_history()
            if not remaining_records:
                show_auto_hide_message(self, "提示", "无记录", "info")
                self.accept()
                return

            # 更新记录列表
            self.records_list = remaining_records
            self.total_records = len(remaining_records)

            # 跳转到下一条记录（如果当前是最后一条，则跳到上一条）
            if self.current_index >= self.total_records:
                self.current_index = self.total_records - 1

            if self.current_index >= 0:
                self.load_record(self.current_index)
            else:
                show_auto_hide_message(self, "提示", "无记录", "info")
                self.accept()

    def update_navigation_buttons(self):
        """更新导航按钮状态"""
        # 禁用"上一个"按钮（如果是第一条记录）
        self.prev_btn.setEnabled(self.current_index > 0)

        # 禁用"下一个"按钮（如果是最后一条记录）
        self.next_btn.setEnabled(self.current_index < self.total_records - 1)

        # 更新记录索引显示
        self.record_index_label.setText(f"{self.current_index + 1}/{self.total_records}")

    def go_to_previous(self):
        """跳转到上一条记录"""
        if self.current_index > 0:
            self.current_index -= 1
            self.load_record(self.current_index)

    def go_to_next(self):
        """跳转到下一条记录"""
        if self.current_index < self.total_records - 1:
            self.current_index += 1
            self.load_record(self.current_index)

    def load_record(self, index):
        """加载指定索引的记录"""
        if 0 <= index < len(self.records_list):
            self.record = self.records_list[index]

            # 保存对话框的几何状态
            geometry = self.geometry()

            # 清空 main_container 的布局
            if hasattr(self, 'main_container') and self.main_container:
                main_container_layout = self.main_container.layout()
                if main_container_layout:
                    while main_container_layout.count():
                        item = main_container_layout.takeAt(0)
                        if item.widget():
                            item.widget().deleteLater()
                        elif item.layout():
                            # 清空子布局
                            sub_layout = item.layout()
                            while sub_layout.count():
                                sub_item = sub_layout.takeAt(0)
                                if sub_item.widget():
                                    sub_item.widget().deleteLater()

            # 重新初始化 main_container 的内容
            # 手动重新创建 main_container 的内容，不调用 init_ui()
            self._rebuild_main_container()

            # 更新导航按钮状态
            self.update_navigation_buttons()

            # 恢复对话框大小和位置
            self.setGeometry(geometry)

    def _rebuild_main_container(self):
        """重新构建 main_container 的内容"""
        # 获取现有的布局或创建新的布局
        main_layout = self.main_container.layout()
        if main_layout is None:
            main_layout = QVBoxLayout(self.main_container)

        main_layout.setSpacing(12)
        main_layout.setContentsMargins(20, 20, 20, 20)

        # ==================== 顶部区域（图片缩略图 + 信息 + 导航按钮） ====================
        top_widget = QWidget()
        top_layout = QHBoxLayout(top_widget)
        top_layout.setSpacing(15)
        top_layout.setContentsMargins(0, 0, 0, 0)

        # 左边：图片缩略图
        webp_path = self.record.get('webp_image_path', '')
        image_label = QLabel()
        image_label.setFixedSize(200, 290)
        image_label.setStyleSheet("""
            QLabel {
                background: #2d2d2d;
                border-radius: 8px;
                border: 2px solid #3d3d3d;
            }
        """)
        image_label.setAlignment(Qt.AlignCenter)

        if webp_path and os.path.exists(webp_path):
            pixmap = QPixmap(webp_path)
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    190, 280,
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                image_label.setPixmap(scaled_pixmap)
            else:
                image_label.setText("📷\n图片加载失败")
                image_label.setStyleSheet("color: #666; font-size: 14px;")
        else:
            image_label.setText("📷\n无图片")
            image_label.setStyleSheet("color: #666; font-size: 14px;")

        top_layout.addWidget(image_label)

        # 右边：信息区域
        info_widget = QWidget()
        info_layout = QGridLayout(info_widget)
        info_layout.setSpacing(8)
        info_layout.setContentsMargins(0, 0, 0, 0)

        row = 0
        # 时间
        info_layout.addWidget(QLabel("时间:"), row, 0)
        info_layout.addWidget(QLabel(self.record.get('timestamp', '')), row, 1)
        row += 1

        # 任务ID
        record_id = self.record.get('id', '')
        info_layout.addWidget(QLabel("任务ID:"), row, 0)
        info_layout.addWidget(QLabel(record_id if record_id else 'N/A'), row, 1)
        row += 1

        # 图片类型
        image_type = self.record.get('image_type', '')
        type_text = "📁 WebP" if image_type == 'webp' else ("📁 本地" if image_type == 'local' else "🌐 网络")
        info_layout.addWidget(QLabel("类型:"), row, 0)
        info_layout.addWidget(QLabel(type_text), row, 1)
        row += 1

        # 本地结果文件路径
        local_file = self.record.get('local_file_path', '')
        if local_file:
            info_layout.addWidget(QLabel("结果文件:"), row, 0)
            file_label = QLabel(local_file)
            file_label.setStyleSheet("color: #4CAF50; font-size: 14px;")
            file_label.setWordWrap(True)
            info_layout.addWidget(file_label, row, 1)
            row += 1

        # 结果文件URL
        result_url = self.record.get('result_file_url', '')
        if result_url:
            info_layout.addWidget(QLabel("结果URL:"), row, 0)
            url_label = QLabel(result_url[:80] + '...' if len(result_url) > 80 else result_url)
            url_label.setStyleSheet("color: #2196f3; font-size: 14px;")
            url_label.setWordWrap(True)
            info_layout.addWidget(url_label, row, 1)
            row += 1

        # WebP 图片路径
        if webp_path:
            info_layout.addWidget(QLabel("图片路径:"), row, 0)
            img_label = QLabel(webp_path)
            img_label.setStyleSheet("color: #FFA726; font-size: 14px;")
            img_label.setWordWrap(True)
            info_layout.addWidget(img_label, row, 1)

        info_layout.setColumnStretch(1, 1)
        top_layout.addWidget(info_widget, 1)

        # 右边：导航按钮区域
        nav_widget = QWidget()
        nav_layout = QVBoxLayout(nav_widget)
        nav_layout.setSpacing(8)
        nav_layout.setContentsMargins(0, 0, 0, 0)

        # 上一个按钮
        self.prev_btn = PushButton(FluentIcon.LEFT_ARROW, "上一个")
        self.prev_btn.setFixedHeight(40)
        self.prev_btn.setFixedWidth(90)
        self.prev_btn.clicked.connect(self.go_to_previous)
        nav_layout.addWidget(self.prev_btn)

        # 当前记录显示
        self.record_index_label = QLabel(f"{self.current_index + 1}/{self.total_records}")
        self.record_index_label.setAlignment(Qt.AlignCenter)
        self.record_index_label.setStyleSheet("color: #aaa; font-size: 13px; font-weight: bold;")
        nav_layout.addWidget(self.record_index_label)

        # 下一个按钮
        self.next_btn = PushButton(FluentIcon.RIGHT_ARROW, "下一个")
        self.next_btn.setFixedHeight(40)
        self.next_btn.setFixedWidth(90)
        self.next_btn.clicked.connect(self.go_to_next)
        nav_layout.addWidget(self.next_btn)

        nav_layout.addStretch()
        top_layout.addWidget(nav_widget)

        main_layout.addWidget(top_widget)

        # ==================== 提示词选项卡 ====================
        result = self.record.get('result', {})

        tab_widget = QTabWidget()
        tab_widget.setStyleSheet("""
            QTabWidget::pane {
                border: none;
                background: #2d2d2d;
                border-radius: 8px;
            }
            QTabBar::tab {
                background: #3d3d3d;
                color: #aaa;
                padding: 10px 20px;
                font-size: 14px;
                border: none;
                border-top-left-radius: 6px;
                border-top-right-radius: 6px;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background: #2d2d2d;
                color: white;
                font-weight: bold;
            }
            QTabBar::tab:hover:!selected {
                background: #4d4d4d;
            }
        """)

        # 计算文本框高度（8行）
        font_height = 40  # 每行约40px
        text_height = font_height * 8

        # 创建四个选项卡（无内部复制按钮）
        tabs_data = [
            ("中文描述", "CN"),
            ("英文描述", "EN"),
            ("中文标签", "CN_tag"),
            ("英文标签", "EN_tag")
        ]

        for tab_name, result_key in tabs_data:
            page = QWidget()
            page_layout = QVBoxLayout(page)
            page_layout.setContentsMargins(0, 0, 0, 0)

            text_edit = QTextEdit()
            text_edit.setReadOnly(True)
            text_edit.setText(result.get(result_key, ''))
            text_edit.setFixedHeight(text_height)
            text_edit.setStyleSheet("""
                QTextEdit {
                    background: #1a1a1a;
                    color: white;
                    border: none;
                    border-radius: 8px;
                    padding: 15px;
                    font-size: 28px;
                    line-height: 1.6;
                }
                QScrollBar:vertical {
                    background: #2d2d2d;
                    width: 10px;
                    border-radius: 5px;
                }
                QScrollBar::handle:vertical {
                    background: #555;
                    border-radius: 5px;
                    min-height: 30px;
                }
                QScrollBar::handle:vertical:hover {
                    background: #666;
                }
            """)
            page_layout.addWidget(text_edit)

            tab_widget.addTab(page, tab_name)
            # 保存引用以便底部复制按钮使用
            setattr(self, f'{result_key}_text_edit', text_edit)

        main_layout.addWidget(tab_widget)

        # ==================== 底部按钮栏 ====================
        button_layout = QHBoxLayout()
        button_layout.setSpacing(10)

        # 为每个选项卡添加复制按钮和导出按钮
        for tab_name, result_key in tabs_data:
            # 复制按钮
            copy_btn = PushButton(f"复制{tab_name}")
            copy_btn.setFixedHeight(36)
            copy_btn.clicked.connect(lambda checked, k=result_key, n=tab_name: self.copy_result(k, n))
            button_layout.addWidget(copy_btn)

            # 导出按钮
            export_btn = PushButton(FluentIcon.SAVE, f"导出")
            export_btn.setFixedHeight(36)
            export_btn.clicked.connect(lambda checked, k=result_key, n=tab_name: self.export_tab(k, n))
            button_layout.addWidget(export_btn)

        button_layout.addStretch()

        # 删除按钮
        delete_btn = PushButton(FluentIcon.DELETE, "删除")
        delete_btn.setFixedHeight(36)
        delete_btn.clicked.connect(self.delete_current_record)
        button_layout.addWidget(delete_btn)

        # 导出全部按钮
        export_all_btn = PrimaryPushButton(FluentIcon.SAVE, "导出全部")
        export_all_btn.setFixedHeight(36)
        export_all_btn.clicked.connect(self.export_all)
        button_layout.addWidget(export_all_btn)

        # 关闭按钮
        close_btn = PushButton("关闭")
        close_btn.setFixedHeight(36)
        close_btn.clicked.connect(self.accept)
        button_layout.addWidget(close_btn)

        main_layout.addLayout(button_layout)


# ==================== 图片提示词生成页面 ====================
class ImagePromptPage(SmoothScrollArea):
    """图片提示词生成页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.vlm_config = VLMConfigManager()
        self.vlm_history = VLMHistoryManager()
        self.current_worker = None
        self.current_result = {}
        self.operation_logs = []  # 操作日志列表
        self.current_webp_path = ""  # 当前保存的 webp 图片路径
        # 批量处理相关
        self.batch_files = []  # 批量图片文件列表
        self.batch_current_index = 0  # 当前处理的索引
        self.batch_results = []  # 批量处理结果
        self.is_batch_processing = False  # 是否正在批量处理
        self.init_ui()

    def init_ui(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(10)
        layout.setContentsMargins(15, 10, 15, 10)

        # --- 顶部控制栏（固定高度）---
        top_bar = QWidget()
        top_bar.setFixedHeight(50)
        top_bar_layout = QHBoxLayout(top_bar)
        top_bar_layout.setContentsMargins(0, 5, 0, 5)

        title = SubtitleLabel("🖼️ 图片提示词生成")
        title.setFont(QFont("", 16, QFont.Bold))
        top_bar_layout.addWidget(title)

        # 模式选择按钮（移到标题后面）
        self.single_mode_btn = PushButton("单个")
        self.batch_mode_btn = PushButton("批量")
        self.single_mode_btn.setCheckable(True)
        self.batch_mode_btn.setCheckable(True)
        self.single_mode_btn.setChecked(True)
        self.single_mode_btn.setFixedHeight(36)
        self.batch_mode_btn.setFixedHeight(36)
        self.single_mode_btn.clicked.connect(lambda: self.switch_to_single_mode())
        self.batch_mode_btn.clicked.connect(lambda: self.switch_to_batch_mode())
        top_bar_layout.addWidget(self.single_mode_btn)
        top_bar_layout.addWidget(self.batch_mode_btn)

        top_bar_layout.addStretch()

        # 当前模板名称标签
        self.template_name_label = QLabel()
        self.template_name_label.setStyleSheet("color: #aaa; font-size: 12px; padding: 4px 10px; border: 1px solid #444; border-radius: 4px;")
        self.template_name_label.setFixedHeight(30)
        top_bar_layout.addWidget(self.template_name_label)

        # 设置按钮
        self.settings_btn = PushButton(FluentIcon.SETTING, "设置")
        self.settings_btn.setFixedHeight(36)
        self.settings_btn.clicked.connect(self.show_settings)
        top_bar_layout.addWidget(self.settings_btn)

        # 历史记录按钮
        self.history_btn = PushButton(FluentIcon.HISTORY, "历史记录")
        self.history_btn.setFixedHeight(36)
        self.history_btn.clicked.connect(self.show_history)
        top_bar_layout.addWidget(self.history_btn)

        layout.addWidget(top_bar)

        # --- 主内容区域 ---
        main_splitter = QSplitter(Qt.Horizontal)

        # 左侧：图片上传区域
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setSpacing(12)
        left_layout.setContentsMargins(0, 0, 0, 0)

        # 图片上传卡片
        upload_card = CardWidget()
        upload_layout = QVBoxLayout(upload_card)
        upload_layout.setContentsMargins(15, 15, 15, 15)
        upload_layout.setSpacing(10)

        # 标题（移除模式选择按钮，已移到顶部）
        upload_title = SubtitleLabel("") #📤 图片上传
        upload_title.setFont(QFont("", 13, QFont.Bold))
        upload_layout.addWidget(upload_title)

        # 单个图片输入组
        self.single_url_group = QWidget()
        single_url_layout = QVBoxLayout(self.single_url_group)
        single_url_layout.setContentsMargins(0, 0, 0, 0)
        single_url_layout.setSpacing(8)

        # URL输入行（横向布局）
        url_input_layout = QHBoxLayout()
        url_input_layout.addWidget(QLabel("图片 URL:"))
        self.image_url_edit = LineEdit()
        self.image_url_edit.setPlaceholderText("输入图片 URL...")
        self.image_url_edit.setFixedHeight(32)
        # 移除最大长度限制（默认 32767 会截断长 Base64 数据）
        self.image_url_edit.setMaxLength(10 * 1024 * 1024)  # 设置为 10MB
        url_input_layout.addWidget(self.image_url_edit, 1)
        self.select_file_btn = PushButton(FluentIcon.FOLDER, "")
        self.select_file_btn.setFixedWidth(80)
        self.select_file_btn.setFixedHeight(32)
        self.select_file_btn.setToolTip("选择本地图片")
        self.select_file_btn.clicked.connect(self.select_local_file)
        url_input_layout.addWidget(self.select_file_btn)
        single_url_layout.addLayout(url_input_layout)

        upload_layout.addWidget(self.single_url_group)

        # 批量文件夹选择组
        self.batch_group = QWidget()
        batch_layout = QVBoxLayout(self.batch_group)
        batch_layout.setContentsMargins(0, 0, 0, 0)
        batch_layout.setSpacing(8)

        # 文件夹选择行
        folder_input_layout = QHBoxLayout()
        folder_input_layout.addWidget(QLabel("文件夹:"))
        self.folder_path_edit = LineEdit()
        self.folder_path_edit.setPlaceholderText("选择包含图片的文件夹...")
        self.folder_path_edit.setReadOnly(True)
        self.folder_path_edit.setFixedHeight(32)
        folder_input_layout.addWidget(self.folder_path_edit, 1)
        self.select_folder_btn = PushButton(FluentIcon.FOLDER, "")
        self.select_folder_btn.setFixedWidth(80)
        self.select_folder_btn.setFixedHeight(32)
        self.select_folder_btn.setToolTip("选择文件夹")
        self.select_folder_btn.clicked.connect(self.select_folder)
        folder_input_layout.addWidget(self.select_folder_btn)
        batch_layout.addLayout(folder_input_layout)

        # 批量图片列表（固定高度）
        batch_layout.addWidget(QLabel("待处理图片列表:"))
        self.batch_list_edit = QTextEdit()
        self.batch_list_edit.setReadOnly(True)
        self.batch_list_edit.setFixedHeight(120)
        self.batch_list_edit.setStyleSheet("margin-top:-60px;")
        batch_layout.addWidget(self.batch_list_edit)

        upload_layout.addWidget(self.batch_group)
        self.batch_group.setVisible(False)

        # 图片预览区域（2:3 竖版比例，支持拖拽）
        self.image_preview_label = DragDropImageLabel()
        self.image_preview_label.setAlignment(Qt.AlignCenter)
        # 2:3 竖版比例：宽 400，高 600
        self.image_preview_label.setFixedSize(400, 600)
        self.image_preview_label.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #1E1E1E;")
        self.image_preview_label.setText("暂无图片\n\n支持拖拽本地图片或网络 URL\n本地图片自动转换为 base64")
        # 连接拖拽信号
        self.image_preview_label.image_dropped.connect(self.on_image_dropped)
        # 居中显示预览区域
        preview_container = QWidget()
        preview_layout = QHBoxLayout(preview_container)
        preview_layout.addStretch()
        preview_layout.addWidget(self.image_preview_label)
        preview_layout.addStretch()
        upload_layout.addWidget(preview_container)

        left_layout.addWidget(upload_card)

        # 生成按钮区域（模式选择 + 开始识别）
        generate_layout = QHBoxLayout()
        generate_layout.setSpacing(10)

        # 识别模式选择
        self.model_mode_combo = ComboBox()
        self.model_mode_combo.addItems(["基础模型", "Gemini VLM"])
        self.model_mode_combo.setFixedHeight(40)
        self.model_mode_combo.setFixedWidth(140)
        self.model_mode_combo.setToolTip("选择识别模型模式")
        self.model_mode_combo.currentIndexChanged.connect(lambda: self._refresh_template_label())
        generate_layout.addWidget(self.model_mode_combo)
        # 初始化模板标签（在 combo 创建后才能调用）
        self._refresh_template_label()

        # 开始识别按钮
        self.generate_btn = PrimaryPushButton(FluentIcon.PLAY, "开始识别")
        self.generate_btn.setFixedHeight(40)
        self.generate_btn.clicked.connect(self.start_recognition)
        generate_layout.addWidget(self.generate_btn, 1)

        left_layout.addLayout(generate_layout)

        # 进度显示卡片（固定高度）
        progress_card = CardWidget()
        progress_layout = QVBoxLayout(progress_card)
        progress_layout.setContentsMargins(15, 10, 15, 10)
        progress_layout.setSpacing(5)

        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(8)
        progress_layout.addWidget(self.progress_bar)

        self.status_label = QLabel("准备就绪")
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("font-size: 12px;")
        progress_layout.addWidget(self.status_label)

        self.time_label = QLabel("运行时间: 0.0秒")
        self.time_label.setAlignment(Qt.AlignCenter)
        self.time_label.setStyleSheet("color: #666; font-size: 11px;")
        progress_layout.addWidget(self.time_label)

        left_layout.addWidget(progress_card)
        left_layout.addStretch()

        # 右侧：识别结果选项卡
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)

        result_card = CardWidget()
        result_layout = QVBoxLayout(result_card)
        result_layout.setContentsMargins(15, 15, 15, 15)
        result_layout.setSpacing(10)

        result_title = SubtitleLabel("")
        result_title.setFont(QFont("", 13, QFont.Bold))
        result_layout.addWidget(result_title)

        # 选项卡
        self.result_tab = QTabWidget()
        self.result_tab.setMinimumHeight(380)

        # 中文描述
        self.cn_page = QWidget()
        cn_layout = QVBoxLayout(self.cn_page)
        cn_layout.addWidget(QLabel("")) #完整中文描述
        self.cn_edit = QTextEdit()
        self.cn_edit.setReadOnly(False)
        self.cn_edit.setStyleSheet("font-size: 32px; color: white; background: #2d2d2d; padding: 20px;")
        cn_layout.addWidget(self.cn_edit)
        # 复制/导出按钮移到右下角
        cn_btn_layout = QHBoxLayout()
        cn_btn_layout.addStretch()
        self.copy_cn_btn = PushButton(FluentIcon.COPY, "复制")
        self.copy_cn_btn.clicked.connect(lambda: self.copy_result("CN"))
        self.export_cn_btn = PushButton(FluentIcon.DOWNLOAD, "导出")
        self.export_cn_btn.clicked.connect(lambda: self.export_result("CN"))
        cn_btn_layout.addWidget(self.copy_cn_btn)
        cn_btn_layout.addWidget(self.export_cn_btn)
        cn_layout.addLayout(cn_btn_layout)
        self.result_tab.addTab(self.cn_page, "中文描述")

        # 英文描述
        self.en_page = QWidget()
        en_layout = QVBoxLayout(self.en_page)
        en_layout.addWidget(QLabel("")) #完整英文描述
        self.en_edit = QTextEdit()
        self.en_edit.setReadOnly(False)
        self.en_edit.setStyleSheet("font-size: 32px; color: white; background: #2d2d2d; padding: 20px;")
        en_layout.addWidget(self.en_edit)
        # 复制/导出按钮移到右下角
        en_btn_layout = QHBoxLayout()
        en_btn_layout.addStretch()
        self.copy_en_btn = PushButton(FluentIcon.COPY, "复制")
        self.copy_en_btn.clicked.connect(lambda: self.copy_result("EN"))
        self.export_en_btn = PushButton(FluentIcon.DOWNLOAD, "导出")
        self.export_en_btn.clicked.connect(lambda: self.export_result("EN"))
        en_btn_layout.addWidget(self.copy_en_btn)
        en_btn_layout.addWidget(self.export_en_btn)
        en_layout.addLayout(en_btn_layout)
        self.result_tab.addTab(self.en_page, "英文描述")

        # 中文Tag
        self.cn_tag_page = QWidget()
        cn_tag_layout = QVBoxLayout(self.cn_tag_page)
        cn_tag_layout.addWidget(QLabel("")) #中文标签 (逗号分隔)
        self.cn_tag_edit = QTextEdit()
        self.cn_tag_edit.setReadOnly(False)
        self.cn_tag_edit.setStyleSheet("font-size: 32px; color: white; background: #2d2d2d; padding: 20px;")
        cn_tag_layout.addWidget(self.cn_tag_edit)
        # 复制/导出按钮移到右下角
        cn_tag_btn_layout = QHBoxLayout()
        cn_tag_btn_layout.addStretch()
        self.copy_cn_tag_btn = PushButton(FluentIcon.COPY, "复制")
        self.copy_cn_tag_btn.clicked.connect(lambda: self.copy_result("CN_tag"))
        self.export_cn_tag_btn = PushButton(FluentIcon.DOWNLOAD, "导出")
        self.export_cn_tag_btn.clicked.connect(lambda: self.export_result("CN_tag"))
        cn_tag_btn_layout.addWidget(self.copy_cn_tag_btn)
        cn_tag_btn_layout.addWidget(self.export_cn_tag_btn)
        cn_tag_layout.addLayout(cn_tag_btn_layout)
        self.result_tab.addTab(self.cn_tag_page, "中文Tag")

        # 英文Tag
        self.en_tag_page = QWidget()
        en_tag_layout = QVBoxLayout(self.en_tag_page)
        en_tag_layout.addWidget(QLabel("")) #英文标签 (逗号分隔)
        self.en_tag_edit = QTextEdit()
        self.en_tag_edit.setReadOnly(False)
        self.en_tag_edit.setStyleSheet("font-size: 32px; color: white; background: #2d2d2d; padding: 20px;")
        en_tag_layout.addWidget(self.en_tag_edit)
        # 复制/导出按钮移到右下角
        en_tag_btn_layout = QHBoxLayout()
        en_tag_btn_layout.addStretch()
        self.copy_en_tag_btn = PushButton(FluentIcon.COPY, "复制")
        self.copy_en_tag_btn.clicked.connect(lambda: self.copy_result("EN_tag"))
        self.export_en_tag_btn = PushButton(FluentIcon.DOWNLOAD, "导出")
        self.export_en_tag_btn.clicked.connect(lambda: self.export_result("EN_tag"))
        en_tag_btn_layout.addWidget(self.copy_en_tag_btn)
        en_tag_btn_layout.addWidget(self.export_en_tag_btn)
        en_tag_layout.addLayout(en_tag_btn_layout)
        self.result_tab.addTab(self.en_tag_page, "英文Tag")

        # 操作日志选项卡
        self.log_page = QWidget()
        log_layout = QVBoxLayout(self.log_page)
        log_layout.addWidget(QLabel("")) #API 操作日志
        self.log_edit = QTextEdit()
        self.log_edit.setReadOnly(True)
        self.log_edit.setStyleSheet("font-family: 'Menlo', 'Monaco', 'Courier New', monospace; font-size: 12px; background: #1e1e1e; color: #d4d4d4;")
        log_layout.addWidget(self.log_edit)
        # 日志操作按钮
        log_btn_layout = QHBoxLayout()
        log_btn_layout.addStretch()
        self.clear_log_btn = PushButton(FluentIcon.DELETE, "清空日志")
        self.clear_log_btn.clicked.connect(self.clear_log)
        log_btn_layout.addWidget(self.clear_log_btn)
        log_layout.addLayout(log_btn_layout)
        self.result_tab.addTab(self.log_page, "操作日志")

        result_layout.addWidget(self.result_tab)
        right_layout.addWidget(result_card)

        # 添加到分割器
        main_splitter.addWidget(left_widget)
        main_splitter.addWidget(right_widget)
        main_splitter.setSizes([480, 520])
        # 设置分割器拉伸因子：左侧不拉伸，右侧可拉伸
        main_splitter.setStretchFactor(0, 0)
        main_splitter.setStretchFactor(1, 1)

        layout.addWidget(main_splitter)

        self.setWidget(widget)
        self.setWidgetResizable(True)

    def switch_to_single_mode(self):
        """切换到单个图片模式"""
        self.single_mode_btn.setChecked(True)
        self.batch_mode_btn.setChecked(False)
        self.single_url_group.setVisible(True)
        self.batch_group.setVisible(False)
        # 清空批量模式的状态
        self.batch_list_edit.clear()
        if hasattr(self, 'folder_path_edit'):
            self.folder_path_edit.clear()

    def switch_to_batch_mode(self):
        """切换到批量图片模式"""
        self.single_mode_btn.setChecked(False)
        self.batch_mode_btn.setChecked(True)
        self.single_url_group.setVisible(False)
        self.batch_group.setVisible(True)
        # 清空单个模式的状态
        self.image_url_edit.clear()
        self.image_preview_label.clear()
        self.image_preview_label.setText("暂无图片")

    def select_local_file(self):
        """选择本地文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "选择图片",
            "",
            "图片文件 (*.png *.jpg *.jpeg *.gif *.bmp *.webp);;所有文件 (*)"
        )
        if file_path:
            # 复用拖拽处理逻辑（包含 Base64 转换）
            self.on_image_dropped(file_path)

    def select_folder(self):
        """选择文件夹"""
        folder_path = QFileDialog.getExistingDirectory(self, "选择包含图片的文件夹")
        if folder_path:
            self.folder_path_edit.setText(folder_path)
            # 扫描图片文件
            image_extensions = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'}
            image_files = []

            for file in os.listdir(folder_path):
                if os.path.splitext(file)[1].lower() in image_extensions:
                    image_files.append(os.path.join(folder_path, file))

            if image_files:
                # 显示文件列表
                file_list_text = "\n".join([os.path.basename(f) for f in image_files])
                self.batch_list_edit.setText(file_list_text)
                self.batch_files = image_files
            else:
                show_auto_hide_message(self, "警告", "所选文件夹中没有找到图片文件", "warning")

    def show_settings(self):
        """显示设置对话框"""
        dialog = VLMSettingsDialog(self.vlm_config, self)
        if dialog.exec_() == QDialog.Accepted:
            show_auto_hide_message(self, "成功", "设置已保存", "success")
            self._refresh_template_label()

    def show_history(self):
        """显示历史记录"""
        dialog = VLMHistoryDialog(self.vlm_history, self)
        dialog.exec_()

    def start_recognition(self):
        """开始识别"""
        if self.single_mode_btn.isChecked():
            # 单个图片识别
            image_url = self.image_url_edit.text().strip()
            if not image_url:
                show_auto_hide_message(self, "警告", "请输入图片 URL 或拖拽图片", "warning")
                return

            # 处理网络 URL：先下载转换为 WebP，然后自动触发识别
            if image_url.startswith(('http://', 'https://')):
                self._process_network_image_and_recognize(image_url)
                return

            # 检查是否是本地文件格式（file:xxx.webp）
            if image_url.startswith('file:'):
                # 使用内部存储的实际 data URL
                if hasattr(self, '_actual_data_url') and self._actual_data_url:
                    image_url = self._actual_data_url
                else:
                    show_auto_hide_message(self, "警告", "无法找到图片数据，请重新上传图片", "warning")
                    return
            # 支持的格式：data URL (base64)、http://、https://、file:
            elif not (image_url.startswith('data:image/') or
                    image_url.startswith('http://') or
                    image_url.startswith('https://')):
                show_auto_hide_message(
                    self,
                    "警告",
                    "不支持的图片格式。支持的格式：网络 URL (http:// 或 https://)、拖拽本地图片（自动转换为 base64）",
                    "warning"
                )
                return

            self.process_single_image(image_url)
        else:
            # 批量识别
            if not hasattr(self, 'batch_files') or not self.batch_files:
                show_auto_hide_message(self, "警告", "请先选择包含图片的文件夹", "warning")
                return

            self.process_batch_images()

    def _get_current_mode(self):
        """获取当前选择的识别模式"""
        return "gemini_vlm" if self.model_mode_combo.currentIndex() == 1 else "base"

    def _refresh_template_label(self):
        """刷新顶部模板名称标签"""
        mode = self._get_current_mode()
        if mode == "gemini_vlm":
            key = self.vlm_config.get("default_template_gemini_vlm", "default")
        else:
            key = self.vlm_config.get("default_template", "default")
        template_dict = self.vlm_config.templates.get(key, {})
        name = template_dict.get("name", "默认模板") if isinstance(template_dict, dict) else "默认模板"
        self.template_name_label.setText(f"📝 模板: {name}")

    def _get_template_for_mode(self, mode):
        """根据模式获取对应的模板内容"""
        if mode == "gemini_vlm":
            key = self.vlm_config.get("default_template_gemini_vlm", "default")
        else:
            key = self.vlm_config.get("default_template", "default")
        template_dict = self.vlm_config.templates.get(key, {})
        return template_dict.get("template", "") if isinstance(template_dict, dict) else ""

    def process_single_image(self, image_url):
        """处理单个图片"""
        mode = self._get_current_mode()

        # 根据模式获取对应的模板
        template = self._get_template_for_mode(mode)

        # 简化日志显示：本地图片只显示文件名
        display_name = self._format_image_url_for_log(image_url)
        mode_label = "Gemini VLM" if mode == "gemini_vlm" else "基础模型"
        self.add_log(f"开始识别图片: {display_name}")
        self.add_log(f"识别模式: {mode_label}")

        self.generate_btn.setEnabled(False)
        self.progress_bar.setRange(0, 0)
        self.status_label.setText(f"准备识别（{mode_label}）...")

        self.current_worker = VLMImageWorker(image_url, self.vlm_config, template, mode=mode)
        self.current_worker.progress_updated.connect(self.on_progress_updated)
        self.current_worker.time_updated.connect(self.on_time_updated)
        self.current_worker.finished.connect(self.on_recognition_finished)
        self.current_worker.error_occurred.connect(self.on_recognition_error)
        self.current_worker.log_message.connect(self.add_log)
        self.current_worker.start()

    def _format_image_url_for_log(self, image_url):
        """格式化图片 URL 用于日志显示"""
        if image_url.startswith('data:image/'):
            # Base64 编码的本地图片，提取文件名信息
            return "[本地图片] base64编码图片"
        elif image_url.startswith(('http://', 'https://')):
            # 网络图片，显示完整 URL
            return f"[网络图片] {image_url}"
        else:
            # 本地文件路径
            filename = os.path.basename(image_url) if image_url else "未知"
            return f"[本地图片] {filename}"

    def process_batch_images(self):
        """处理批量图片"""
        if not hasattr(self, 'batch_files') or not self.batch_files:
            show_auto_hide_message(self, "警告", "请先选择包含图片的文件夹", "warning")
            return

        # 初始化批量处理
        self.is_batch_processing = True
        self.batch_current_index = 0
        self.batch_results = []

        total = len(self.batch_files)
        self.add_log(f"=" * 60)
        self.add_log(f"🚀 开始批量处理：共 {total} 张图片")
        self.add_log(f"=" * 60)

        # 禁用生成按钮
        self.generate_btn.setEnabled(False)
        self.generate_btn.setText("批量处理中...")

        # 开始处理第一张
        self.process_next_batch_image()

    def process_next_batch_image(self):
        """处理下一张批量图片"""
        # 检查是否还有图片需要处理
        if self.batch_current_index >= len(self.batch_files):
            # 批量处理完成
            self.batch_processing_complete()
            return

        # 获取当前图片
        current_file = self.batch_files[self.batch_current_index]
        total = len(self.batch_files)
        current_num = self.batch_current_index + 1

        self.add_log(f"\n[{current_num}/{total}] 处理图片: {os.path.basename(current_file)}")

        # 处理图片（转换为 webp 并获取 data URL）
        try:
            # 使用图片处理逻辑
            self._process_local_image(current_file)

            # 等待图片处理完成后启动识别
            # 由于 _process_local_image 是异步的，我们需要等待它完成
            # 使用 QTimer 延迟启动识别
            QTimer.singleShot(500, lambda: self.start_batch_recognition())

        except Exception as e:
            self.add_log(f"❌ 处理图片失败: {str(e)}")
            # 跳过当前图片，处理下一张
            self.batch_current_index += 1
            QTimer.singleShot(100, self.process_next_batch_image)

    def start_batch_recognition(self):
        """启动批量图片识别"""
        # 获取图片 URL
        image_url = self.image_url_edit.text().strip()
        if not image_url:
            self.add_log(f"⚠️ 图片未正确处理，跳过")
            self.batch_current_index += 1
            QTimer.singleShot(100, self.process_next_batch_image)
            return

        # 检查是否是本地文件格式（file:xxx.webp）
        if image_url.startswith('file:'):
            # 使用内部存储的实际 data URL
            if hasattr(self, '_actual_data_url') and self._actual_data_url:
                image_url = self._actual_data_url
            else:
                self.add_log(f"⚠️ 无法找到图片数据，跳过")
                self.batch_current_index += 1
                QTimer.singleShot(100, self.process_next_batch_image)
                return
        # 如果不是 data URL，则跳过
        elif not image_url.startswith('data:image/'):
            self.add_log(f"⚠️ 图片未正确处理，跳过")
            self.batch_current_index += 1
            QTimer.singleShot(100, self.process_next_batch_image)
            return

        # 获取模板
        mode = self._get_current_mode()
        template = self._get_template_for_mode(mode)

        # 更新进度
        total = len(self.batch_files)
        current_num = self.batch_current_index + 1
        self.progress_bar.setRange(0, total)
        self.progress_bar.setValue(current_num - 1)
        self.status_label.setText(f"批量处理中: {current_num}/{total}")

        # 启动识别线程
        mode = self._get_current_mode()
        self.current_worker = VLMImageWorker(image_url, self.vlm_config, template, mode=mode)
        self.current_worker.progress_updated.connect(self.on_batch_progress_updated)
        self.current_worker.time_updated.connect(self.on_time_updated)
        self.current_worker.finished.connect(self.on_batch_recognition_finished)
        self.current_worker.error_occurred.connect(self.on_batch_recognition_error)
        self.current_worker.log_message.connect(self.add_log)
        self.current_worker.start()

    def on_batch_progress_updated(self, msg):
        """批量处理进度更新"""
        current_num = self.batch_current_index + 1
        total = len(self.batch_files)
        self.status_label.setText(f"批量处理中: {current_num}/{total} - {msg}")

    def on_batch_recognition_finished(self, success, result, image_url, task_id, result_file_url, local_file_path):
        """批量识别完成"""
        current_num = self.batch_current_index + 1
        total = len(self.batch_files)

        if success:
            # 保存结果
            self.batch_results.append({
                'index': current_num,
                'file': self.batch_files[self.batch_current_index],
                'result': result,
                'task_id': task_id,
                'result_file_url': result_file_url,
                'local_file_path': local_file_path,
                'webp_path': getattr(self, 'current_webp_path', '')
            })

            # 添加到历史记录
            self.vlm_history.add_record(
                image_url=image_url,
                result=result,
                task_id=task_id,
                result_file_url=result_file_url,
                local_file_path=local_file_path,
                webp_image_path=getattr(self, 'current_webp_path', '')
            )

            self.add_log(f"✅ [{current_num}/{total}] 识别成功！")
            self.add_log(f"  任务ID: {task_id}")

            # 更新结果显示最后一个成功的结果
            self.current_result = result
            self.cn_edit.setText(result.get("CN", ""))
            self.en_edit.setText(result.get("EN", ""))
            self.cn_tag_edit.setText(result.get("CN_tag", ""))
            self.en_tag_edit.setText(result.get("EN_tag", ""))
        else:
            self.add_log(f"❌ [{current_num}/{total}] 识别失败")

        # 清空 webp 路径
        self.current_webp_path = ""

        # 移动到下一张图片
        self.batch_current_index += 1

        # 延迟处理下一张（避免过快）
        from PyQt5.QtCore import QTimer
        QTimer.singleShot(1000, self.process_next_batch_image)

    def on_batch_recognition_error(self, error_msg):
        """批量识别错误"""
        current_num = self.batch_current_index + 1
        total = len(self.batch_files)
        self.add_log(f"❌ [{current_num}/{total}] 识别错误: {error_msg}")

    def batch_processing_complete(self):
        """批量处理完成"""
        self.is_batch_processing = False
        self.generate_btn.setEnabled(True)
        self.generate_btn.setText("开始识别")
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100)
        self.status_label.setText("批量处理完成")

        total = len(self.batch_files)
        success_count = len(self.batch_results)

        self.add_log(f"=" * 60)
        self.add_log(f"🎉 批量处理完成！")
        self.add_log(f"  总数: {total}")
        self.add_log(f"  成功: {success_count}")
        self.add_log(f"  失败: {total - success_count}")
        self.add_log(f"=" * 60)

        show_auto_hide_message(
            self, "批量处理完成",
            f"总数: {total}\n成功: {success_count}\n失败: {total - success_count}",
            "success"
        )

    def on_progress_updated(self, msg):
        """更新进度"""
        if not self.is_batch_processing:
            self.status_label.setText(msg)
            self.add_log(f"进度: {msg}")

    def on_time_updated(self, time_str):
        """更新运行时间"""
        self.time_label.setText(time_str)

    def on_recognition_finished(self, success, result, image_url, task_id, result_file_url, local_file_path):
        """识别完成（单个模式）"""
        # 如果是批量处理模式，不执行这里的逻辑
        if self.is_batch_processing:
            return

        self.generate_btn.setEnabled(True)
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100 if success else 0)

        if success:
            self.current_result = result
            self.cn_edit.setText(result.get("CN", ""))
            self.en_edit.setText(result.get("EN", ""))
            self.cn_tag_edit.setText(result.get("CN_tag", ""))
            self.en_tag_edit.setText(result.get("EN_tag", ""))

            # 添加到历史记录（包含 webp 图片路径）
            self.vlm_history.add_record(
                image_url=image_url,
                result=result,
                task_id=task_id,
                result_file_url=result_file_url,
                local_file_path=local_file_path,
                webp_image_path=getattr(self, 'current_webp_path', '')
            )

            # 记录日志
            self.add_log(f"✅ 识别成功！")
            self.add_log(f"  任务ID: {task_id}")
            self.add_log(f"  结果文件: {local_file_path}")
            self.add_log(f"  WebP图片: {self.current_webp_path if hasattr(self, 'current_webp_path') else 'N/A'}")
            self.add_log(f"  CN: {result.get('CN', '')[:50]}...")
            self.add_log(f"  EN: {result.get('EN', '')[:50]}...")

            # 注意：不清空 current_webp_path，保留用于导出功能
            # 下一张图片上传时会自然覆盖

            show_auto_hide_message(self, "成功", "识别完成！", "success")
        else:
            self.add_log(f"❌ 识别失败")
            show_auto_hide_message(self, "错误", "识别失败", "error")

    def on_recognition_error(self, error_msg):
        """识别错误"""
        self.status_label.setText(f"错误: {error_msg}")
        self.add_log(f"错误: {error_msg}")

    def copy_result(self, field):
        """复制结果到剪贴板"""
        text = self.current_result.get(field, "")
        if text:
            clipboard = QApplication.clipboard()
            clipboard.setText(text)
            show_auto_hide_message(self, "成功", f"已复制到剪贴板", "success")
        else:
            show_auto_hide_message(self, "警告", "没有可复制的内容", "warning")

    def export_result(self, field):
        """导出结果为 TXT 文件（保存到图片所在目录）"""
        text = self.current_result.get(field, "")
        if not text:
            show_auto_hide_message(self, "警告", "没有可导出的内容", "warning")
            return

        # 获取当前 WebP 图片路径
        webp_path = getattr(self, 'current_webp_path', '')
        if not webp_path or not os.path.exists(webp_path):
            show_auto_hide_message(self, "警告", "无法找到图片路径，请先上传图片", "warning")
            return

        # 获取图片所在目录和文件名
        img_dir = os.path.dirname(webp_path)
        img_filename = os.path.basename(webp_path)

        # 将文件扩展名改为 .txt
        name_without_ext = os.path.splitext(img_filename)[0]
        txt_filename = f"{name_without_ext}.txt"
        txt_path = os.path.join(img_dir, txt_filename)

        # 直接保存到 txt 文件（覆盖已存在的文件）
        try:
            with open(txt_path, 'w', encoding='utf-8') as f:
                f.write(text)
            show_auto_hide_message(self, "成功", f"已导出到:\n{txt_path}", "success")
        except Exception as e:
            show_auto_hide_message(self, "错误", f"导出失败: {str(e)}", "error")

    def on_image_dropped(self, path_or_url):
        """处理图片拖拽事件"""
        # 判断是网络URL还是本地路径
        if path_or_url.startswith(('http://', 'https://')):
            # 网络URL - 需要下载并转换为 webp
            self._process_network_image(path_or_url)
        else:
            # 本地文件路径 - 转换为 webp 并保存
            self._process_local_image(path_or_url)

    def _process_network_image(self, url):
        """处理网络图片：下载并转换为 webp"""
        self.add_log(f"拖拽网络图片: {url}")

        try:
            # 下载图片
            self.add_log(f"正在下载网络图片...")
            response = requests.get(url, timeout=30)
            response.raise_for_status()

            # 从响应中获取图片数据
            image_data = response.content
            self.add_log(f"  下载大小: {len(image_data)} 字节 ({len(image_data) / 1024:.2f} KB)")

            # 使用 Pillow 打开图片
            img = Image.open(BytesIO(image_data))
            self.add_log(f"  图片尺寸: {img.size[0]}x{img.size[1]}")

            # 转换为 webp 并保存
            self._save_as_webp(img, url, is_network=True)

        except Exception as e:
            self.image_preview_label.setText(f"❌ 下载失败:\n{str(e)}")
            self.add_log(f"❌ 下载网络图片失败: {str(e)}")
            show_auto_hide_message(self, "错误", f"无法下载网络图片:\n{str(e)}", "error")

    def _process_network_image_and_recognize(self, url):
        """处理网络图片：下载并转换为 webp，然后自动触发识别"""
        self.add_log(f"处理网络 URL: {url}")

        try:
            # 下载图片
            self.add_log(f"正在下载网络图片...")
            response = requests.get(url, timeout=30)
            response.raise_for_status()

            # 从响应中获取图片数据
            image_data = response.content
            self.add_log(f"  下载大小: {len(image_data)} 字节 ({len(image_data) / 1024:.2f} KB)")

            # 使用 Pillow 打开图片
            img = Image.open(BytesIO(image_data))
            self.add_log(f"  图片尺寸: {img.size[0]}x{img.size[1]}")

            # 转换为 webp 并保存
            self._save_as_webp(img, url, is_network=True)

            # 保存完成后自动触发识别（使用内部存储的 data URL）
            if hasattr(self, '_actual_data_url') and self._actual_data_url:
                self.add_log(f"✅ 网络图片已处理，开始识别...")
                # 直接调用 process_single_image 使用内部存储的 data URL
                self.process_single_image(self._actual_data_url)
            else:
                show_auto_hide_message(self, "警告", "图片处理失败，无法获取数据", "warning")

        except Exception as e:
            self.image_preview_label.setText(f"❌ 下载失败:\n{str(e)}")
            self.add_log(f"❌ 下载网络图片失败: {str(e)}")
            show_auto_hide_message(self, "错误", f"无法下载网络图片:\n{str(e)}", "error")

    def _process_local_image(self, path_or_url):
        """处理本地图片：转换为 webp 并保存"""
        abs_path = os.path.abspath(path_or_url)
        filename = os.path.basename(abs_path)
        file_size = os.path.getsize(abs_path)

        self.add_log(f"拖拽本地图片: {filename}")
        self.add_log(f"文件路径: {abs_path}")
        self.add_log(f"文件大小: {file_size} 字节 ({file_size / 1024:.2f} KB)")

        # 检查文件大小（建议限制在 5MB 以内）
        if file_size > 5 * 1024 * 1024:
            reply = QMessageBox.question(
                self, "文件过大警告",
                f"图片文件较大 ({file_size / 1024 / 1024:.2f} MB)\n\n"
                f"建议：\n"
                f"• 压缩图片后再试\n"
                f"• 或使用网络图片 URL\n\n"
                f"是否继续转换？",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No
            )
            if reply == QMessageBox.No:
                self.add_log(f"❌ 用户取消转换（文件过大）")
                return

        try:
            # 使用 Pillow 打开图片
            self.add_log(f"正在使用 Pillow 处理图片...")
            img = Image.open(abs_path)

            # 获取原始图片信息
            original_format = img.format or "UNKNOWN"
            original_size = os.path.getsize(abs_path)
            self.add_log(f"  原始格式: {original_format}")
            self.add_log(f"  原始大小: {original_size} 字节 ({original_size / 1024:.2f} KB)")

            # 转换为 webp 并保存
            self._save_as_webp(img, abs_path, is_network=False)

        except Exception as e:
            self.image_preview_label.setText(f"❌ 转换失败:\n{str(e)}")
            self.add_log(f"❌ 转换失败: {str(e)}")
            self.add_log(f"  错误类型: {type(e).__name__}")
            show_auto_hide_message(self, "错误", f"无法处理图片文件:\n{str(e)}", "error")

    def _save_as_webp(self, img, source_path, is_network=False):
        """将图片转换为 webp 并保存到 output/up/ 文件夹

        Args:
            img: PIL Image 对象
            source_path: 源路径（本地路径或网络URL）
            is_network: 是否为网络图片
        """
        # 确保 output/up/ 目录存在
        output_dir = os.path.join("output", "up")
        os.makedirs(output_dir, exist_ok=True)

        # 生成时间戳文件名
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]  # 精确到毫秒
        webp_filename = f"{timestamp}.webp"
        webp_path = os.path.join(output_dir, webp_filename)
        webp_abs_path = os.path.abspath(webp_path)

        self.add_log(f"正在转换为 WebP 格式...")

        # 获取原始图片信息
        original_size = len(img.tobytes()) if hasattr(img, 'tobytes') else 0

        # 转换为 RGB 模式（WebP 不支持 RGBA）
        if img.mode in ('RGBA', 'LA', 'P'):
            # 创建白色背景
            background = Image.new('RGB', img.size, (255, 255, 255))
            if img.mode == 'P':
                img = img.convert('RGBA')
            if img.mode in ('RGBA', 'LA'):
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background
            else:
                img = img.convert('RGB')
        elif img.mode != 'RGB':
            img = img.convert('RGB')

        # 保存为 WebP 格式（99% 画质）
        img.save(webp_abs_path, format='WebP', quality=99, method=6)

        # 获取保存后的大小
        webp_size = os.path.getsize(webp_abs_path)

        # 计算压缩率
        if original_size > 0:
            compression_ratio = (1 - webp_size / original_size) * 100
        else:
            compression_ratio = 0

        self.add_log(f"  保存格式: WebP (quality=99, method=6)")
        self.add_log(f"  保存路径: {webp_abs_path}")
        self.add_log(f"  保存大小: {webp_size} 字节 ({webp_size / 1024:.2f} KB)")
        if compression_ratio != 0:
            self.add_log(f"  压缩率: {compression_ratio:.1f}%")

        # 读取 webp 文件并转换为 base64
        with open(webp_abs_path, 'rb') as f:
            webp_data = f.read()

        base64_data = base64.b64encode(webp_data).decode('utf-8')

        # 验证 Base64 长度（必须是 4 的倍数，否则需要填充）
        base64_length = len(base64_data)
        padding_needed = (4 - base64_length % 4) % 4
        if padding_needed > 0:
            self.add_log(f"⚠️ Base64 数据需要填充 {padding_needed} 个字符")
            base64_data += '=' * padding_needed

        # 创建 data URL
        data_url = f"data:image/webp;base64,{base64_data}"

        # 显示预览
        pixmap = QPixmap(webp_abs_path)
        if not pixmap.isNull():
            scaled_pixmap = pixmap.scaled(
                self.image_preview_label.size(),
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation
            )
            self.image_preview_label.setPixmap(scaled_pixmap)
            self.image_preview_label.setText("")

        # 保存实际的 data URL 到内部变量（用于 API 调用）
        self._actual_data_url = data_url

        # 在输入框中只显示文件名（更简洁）
        self.image_url_edit.setText(f"file:{webp_filename}")

        # 保存 webp 路径到实例变量（用于历史记录）
        self.current_webp_path = webp_abs_path

        source_type = "网络图片" if is_network else "本地图片"
        source_display = source_path if is_network else os.path.basename(source_path)

        self.add_log(f"✅ {source_type}已处理并保存")
        self.add_log(f"  源文件: {source_display}")
        self.add_log(f"  MIME类型: image/webp")
        self.add_log(f"  Base64长度: {len(base64_data)} 字符 ({len(base64_data) / 1024:.2f} KB)")
        self.add_log(f"  总URL长度: {len(data_url)} 字符 ({len(data_url) / 1024:.2f} KB)")

        # 检查最终 Base64 长度是否正确
        final_base64 = data_url.split(',', 1)[1]  # 提取 base64 部分
        if len(final_base64) % 4 != 0:
            self.add_log(f"❌ 警告: Base64 长度 ({len(final_base64)}) 不是 4 的倍数!")
        else:
            self.add_log(f"✅ Base64 长度验证通过")

    def add_log(self, message):
        """添加操作日志"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}"
        self.operation_logs.append(log_entry)

        # 更新日志显示
        self.log_edit.append(log_entry)
        # 自动滚动到底部
        scrollbar = self.log_edit.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def clear_log(self):
        """清空操作日志"""
        self.operation_logs.clear()
        self.log_edit.clear()
        self.add_log("日志已清空")


# ==================== 主窗口 ====================
class MainWindow(FluentWindow):
    """图片提示词生成器主窗口"""

    def __init__(self):
        super().__init__()
        self.init_window()
        self.init_navigation()

    def init_window(self):
        """初始化主窗口"""
        self.setWindowTitle("🖼️ BOZO-MCN 图片提示词生成器 v1.0")
        self.setMinimumSize(1200, 800)

    def init_navigation(self):
        """初始化导航栏"""
        # 添加图片提示词生成页面
        self.image_prompt_page = ImagePromptPage(self)
        self.image_prompt_page.setObjectName("image_prompt_page")
        self.addSubInterface(
            self.image_prompt_page,
            FluentIcon.PHOTO,
            "图片提示词",
            NavigationItemPosition.TOP
        )


# ==================== 主程序入口 ====================
def main():
    """主程序入口"""
    os.environ["QT_LOGGING_RULES"] = "qt.qpa.fonts.warning=false"
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    QFont.insertSubstitution("Segoe UI", ".AppleSystemUIFont")
    QFont.insertSubstitution("Microsoft YaHei", "PingFang SC")

    app = QApplication(sys.argv)

    default_font = QFont()
    default_font.setPointSize(12)
    app.setFont(default_font)

    app.setApplicationName("BOZO-MCN图片提示词生成器")
    app.setApplicationVersion("1.0")
    app.setOrganizationName("BOZO-MCN")

    # 设置全局样式
    app.setStyleSheet("""
        QGroupBox {
            font-weight: bold;
            border-radius: 8px;
            margin-top: 1ex;
            padding-top: 10px;
        }
        QGroupBox::title {
            subcontrol-origin: margin;
            left: 10px;
            padding: 0 5px 0 5px;
        }
        QTabWidget::pane {
            border-top: none;
        }
        QTabWidget::tab-bar {
            left: 5px;
        }
        QTabBar::tab {
            font-size: 16px;
            padding: 8px 15px;
            width: 100px;
            border: 2px solid transparent;
            border-radius: 8px;
            margin-right: 3px;
            background-color: #cccccc;
            color: #666;
        }
        QTabBar::tab:selected {
            background-color: #2196f3;
            color: white;
            border-color: #2196f3;
            font-weight: bold;
        }
        QTabBar::tab:hover:!selected {
            background-color: #e3f2fd;
            color: #1976d2;
            border-color: #bbdefb;
        }
        ComboBox, LineEdit, SpinBox, DoubleSpinBox {
            padding: 5px;
            border-radius: 4px;
            background: white;
        }
        ComboBox:hover, LineEdit:hover, SpinBox:hover, DoubleSpinBox:hover {
            border-color: #888888;
        }
        ComboBox:focus, LineEdit:focus, SpinBox:focus, DoubleSpinBox:focus {
            border-color: #0078d4;
        }
        QRadioButton {
            margin-right: 10px;
        }
        QTextEdit {
            border-radius: 4px;
            padding: 10px;
            min-height: 250px;
        }
    """)

    # 设置主题
    setTheme(Theme.DARK)

    # 创建并显示主窗口
    window = MainWindow()

    # 设置窗口图标
    icon_path = os.path.join(os.path.dirname(__file__), "icon.png")
    if os.path.exists(icon_path):
        window.setWindowIcon(QIcon(icon_path))

    window.show()

    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
