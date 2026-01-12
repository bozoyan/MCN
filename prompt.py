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

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QSpinBox,
                            QMessageBox, QGroupBox, QDialog, QToolButton,
                            QSizePolicy, QSplitter, QTabWidget, QScrollArea)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QUrl, QSize
from PyQt5.QtGui import QFont, QIcon, QDesktopServices, QPixmap
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, RadioButton,
                          ProgressBar, InfoBar, InfoBarPosition, SmoothScrollArea,
                          CardWidget, setTheme, Theme)

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

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
                    return json.load(f)
            except Exception as e:
                logger.error(f"加载 VLM 配置失败: {e}")

        # 默认配置
        return {
            "web_app_id": 40122,
            "model": "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct",
            "suppress_preview_output": True,
            "default_template": "default",
            "available_models": [
                "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct",
                "SiliconFlow:Qwen/Qwen2-VL-7B-Instruct",
                "SiliconFlow:Qwen/Qwen-VL-Plus-01",
                "OpenAI:gpt-4o",
                "OpenAI:gpt-4-vision-preview"
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
            "SiliconFlow:Qwen/Qwen2-VL-7B-Instruct"
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

    def add_record(self, image_url, result):
        """添加历史记录"""
        record = {
            "id": str(int(time.time() * 1000)),
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "image_url": image_url,
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
        self.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #f9f9f9;")

    def dropEvent(self, event):
        """拖拽放下事件"""
        self.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #f9f9f9;")

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
                        QMessageBox.warning(self, "警告", "请拖拽图片文件")
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
                    QMessageBox.warning(self, "警告", "请输入图片文件路径")
            else:
                event.ignore()
        else:
            event.ignore()


# ==================== VLM 图片识别工作线程 ====================
class VLMImageWorker(QThread):
    """VLM 图片识别工作线程"""

    progress_updated = pyqtSignal(str)
    time_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, dict, str)  # success, result, image_url
    error_occurred = pyqtSignal(str)

    def __init__(self, image_url, config_manager, template):
        super().__init__()
        self.image_url = image_url
        self.config_manager = config_manager
        self.template = template
        self.is_cancelled = False
        self.start_time = None

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True

    def run(self):
        """运行图片识别"""
        try:
            self.start_time = time.time()
            self.progress_updated.emit("正在初始化 VLM API...")

            # 使用全局MODEL_API_KEY作为API密钥
            api_key = MODEL_API_KEY
            if not api_key:
                self.finished.emit(False, {}, self.image_url)
                self.error_occurred.emit("API密钥未配置")
                return

            base_url = 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create'
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }

            # 构建请求参数
            input_values = {
                "65:LoadImage.image": self.image_url,
                "64:BizyAirSiliconCloudVLMAPI.model": self.config_manager.get("model", "SiliconFlow:Qwen/Qwen3-VL-8B-Instruct"),
                "64:BizyAirSiliconCloudVLMAPI.user_prompt": self.template
            }

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
                response = requests.post(
                    base_url,
                    headers=headers,
                    json={
                        "web_app_id": self.config_manager.get("web_app_id", 40122),
                        "suppress_preview_output": self.config_manager.get("suppress_preview_output", True),
                        "input_values": input_values
                    },
                    timeout=180  # 3分钟超时
                )

                stop_time_update.set()
                time_thread.join(timeout=0.5)

                response.raise_for_status()
                result = response.json()

                if result.get("status") == "Success" and result.get("outputs"):
                    # 获取提示词文件 URL
                    prompt_url = result["outputs"][0].get("object_url", "")
                    if prompt_url:
                        self.progress_updated.emit("正在下载识别结果...")

                        # 下载提示词文件
                        prompt_response = requests.get(prompt_url, timeout=30)
                        if prompt_response.status_code == 200:
                            # 判断文件类型
                            if prompt_url.endswith('.json'):
                                prompt_data = prompt_response.json()
                            else:
                                # TXT 文件使用 UTF-8 解码
                                import chardet
                                raw_data = prompt_response.content
                                encoding = chardet.detect(raw_data)['encoding'] or 'utf-8'
                                text_content = raw_data.decode(encoding)
                                prompt_data = json.loads(text_content)

                            total_time = time.time() - self.start_time
                            self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
                            self.progress_updated.emit("识别完成！")
                            self.finished.emit(True, prompt_data, self.image_url)
                        else:
                            raise Exception(f"下载提示词文件失败: HTTP {prompt_response.status_code}")
                    else:
                        raise Exception("未获取到提示词文件 URL")
                else:
                    error_msg = result.get("message", "未知错误")
                    raise Exception(f"VLM API 返回错误: {error_msg}")

            except Exception as e:
                stop_time_update.set()
                if time_thread.is_alive():
                    time_thread.join(timeout=0.5)
                raise e

        except requests.exceptions.Timeout:
            total_time = time.time() - self.start_time if self.start_time else 0
            self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
            self.error_occurred.emit("请求超时，请稍后重试")
            self.finished.emit(False, {}, self.image_url)
        except Exception as e:
            total_time = time.time() - self.start_time if self.start_time else 0
            self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
            logger.error(f"VLM 图片识别失败: {e}")
            self.error_occurred.emit(f"识别失败: {str(e)}")
            self.finished.emit(False, {}, self.image_url)


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

        # Web App ID
        api_layout.addWidget(QLabel("Web App ID:"), 0, 0)
        self.web_app_id_edit = LineEdit()
        self.web_app_id_edit.setFixedHeight(32)
        api_layout.addWidget(self.web_app_id_edit, 0, 1)

        # 模型选择（下拉框 + 自定义输入）
        api_layout.addWidget(QLabel("VLM 模型:"), 1, 0)

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

        api_layout.addLayout(model_layout, 1, 1)

        # 自定义模型输入
        api_layout.addWidget(QLabel("自定义模型:"), 2, 0)
        self.custom_model_edit = LineEdit()
        self.custom_model_edit.setPlaceholderText("输入自定义模型 (如: SiliconFlow:Qwen/Qwen2-VL-7B-Instruct)")
        self.custom_model_edit.setFixedHeight(32)
        api_layout.addWidget(self.custom_model_edit, 2, 1)

        # 模型说明标签
        self.model_help_label = QLabel("💡 可选择预设模型或在下方输入自定义模型")
        self.model_help_label.setStyleSheet("color: #666; font-size: 11px;")
        api_layout.addWidget(self.model_help_label, 3, 0, 1, 2)

        # Suppress Preview Output
        self.suppress_preview_check = RadioButton("启用")
        api_layout.addWidget(QLabel("抑制预览输出:"), 4, 0)
        api_layout.addWidget(self.suppress_preview_check, 4, 1)

        layout.addWidget(api_group)

        # --- 提示词模板管理 ---
        template_group = QGroupBox("📝 提示词模板管理")
        template_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        template_layout = QVBoxLayout(template_group)

        # 模板选择
        template_select_layout = QHBoxLayout()
        template_select_layout.addWidget(QLabel("选择模板:"))
        self.template_combo = ComboBox()
        self.template_combo.setFixedHeight(32)
        self.template_combo.currentIndexChanged.connect(self.on_template_changed)
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

    def load_current_config(self):
        """加载当前配置"""
        self.web_app_id_edit.setText(str(self.vlm_config.get("web_app_id", 40122)))

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
        # 设置默认模板
        default_template = self.vlm_config.get("default_template", "default")
        for i in range(self.template_combo.count()):
            if self.template_combo.itemData(i) == default_template:
                self.template_combo.setCurrentIndex(i)
                break

    def update_template_combo(self):
        """更新模板下拉框"""
        self.template_combo.clear()
        for key, template in self.vlm_config.templates.items():
            self.template_combo.addItem(template.get("name", key), key)

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
            QMessageBox.warning(self, "警告", "模板名称和内容不能为空")
            return

        # 生成模板 key
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

        if self.vlm_config.save_templates():
            QMessageBox.information(self, "成功", "模板保存成功")
            self.update_template_combo()
            # 选中新保存的模板
            for i in range(self.template_combo.count()):
                if self.template_combo.itemData(i) == template_key:
                    self.template_combo.setCurrentIndex(i)
                    break
        else:
            QMessageBox.critical(self, "错误", "模板保存失败")

    def delete_template(self):
        """删除模板"""
        template_key = self.template_combo.itemData(self.template_combo.currentIndex())
        if not template_key:
            return

        if template_key == "default":
            QMessageBox.warning(self, "警告", "默认模板不能删除")
            return

        reply = QMessageBox.question(
            self, "确认删除",
            f"确定要删除模板 '{self.template_name_edit.text()}' 吗？",
            QMessageBox.Yes | QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            del self.vlm_config.templates[template_key]
            if self.vlm_config.save_templates():
                QMessageBox.information(self, "成功", "模板删除成功")
                self.update_template_combo()
            else:
                QMessageBox.critical(self, "错误", "模板删除失败")

    def add_custom_model(self):
        """将自定义模型添加到列表"""
        custom_model = self.custom_model_edit.text().strip()
        if not custom_model:
            QMessageBox.warning(self, "警告", "请先输入自定义模型名称")
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

            QMessageBox.information(self, "成功", f"模型 '{custom_model}' 已添加到列表")
        else:
            QMessageBox.warning(self, "警告", "添加模型失败")

    def save_settings(self):
        """保存设置"""
        try:
            self.vlm_config.set("web_app_id", int(self.web_app_id_edit.text()))
        except ValueError:
            QMessageBox.warning(self, "警告", "Web App ID 必须是数字")
            return

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
            QMessageBox.information(self, "成功", "设置保存成功")
            self.accept()
        else:
            QMessageBox.critical(self, "错误", "设置保存失败")


# ==================== VLM 历史记录对话框 ====================
class VLMHistoryDialog(QDialog):
    """VLM 历史记录管理对话框"""

    def __init__(self, vlm_history, parent=None):
        super().__init__(parent)
        self.vlm_history = vlm_history
        self.setWindowTitle("历史记录管理")
        self.setMinimumSize(900, 600)
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
        top_layout.addWidget(self.clear_all_btn)
        layout.addLayout(top_layout)

        # 历史记录列表
        self.history_table = QTextEdit()
        self.history_table.setReadOnly(True)
        self.history_table.setMinimumHeight(400)
        layout.addWidget(self.history_table)

        # 底部按钮
        button_layout = QHBoxLayout()
        self.close_btn = PushButton("关闭")
        self.close_btn.clicked.connect(self.accept)
        button_layout.addStretch()
        button_layout.addWidget(self.close_btn)
        layout.addLayout(button_layout)

    def load_history(self):
        """加载历史记录"""
        history = self.vlm_history.get_history()
        if not history:
            self.history_table.setText("暂无历史记录")
            return

        html_content = "<html><head><style>"
        html_content += """
            body { font-family: 'PingFang SC', sans-serif; font-size: 14px; }
            .record { border: 1px solid #ddd; margin: 10px 0; padding: 10px; border-radius: 8px; }
            .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
            .timestamp { color: #666; font-size: 12px; }
            .image-url { color: #2196f3; word-break: break-all; }
            .result-section { margin-top: 10px; }
            .result-title { font-weight: bold; color: #333; margin-top: 10px; }
            .result-content { background: #f5f5f5; padding: 8px; border-radius: 4px; margin-top: 5px; white-space: pre-wrap; }
        """
        html_content += "</style></head><body>"

        for record in history:
            result = record.get("result", {})
            html_content += f"""
                <div class="record">
                    <div class="header">
                        <span class="timestamp">{record.get('timestamp', '')}</span>
                    </div>
                    <div class="result-section">
                        <div class="result-title">图片 URL:</div>
                        <div class="image-url">{record.get('image_url', '')}</div>
                    </div>
                    <div class="result-section">
                        <div class="result-title">中文描述 (CN):</div>
                        <div class="result-content">{result.get('CN', '')}</div>
                    </div>
                    <div class="result-section">
                        <div class="result-title">英文描述 (EN):</div>
                        <div class="result-content">{result.get('EN', '')}</div>
                    </div>
                    <div class="result-section">
                        <div class="result-title">中文标签 (CN_tag):</div>
                        <div class="result-content">{result.get('CN_tag', '')}</div>
                    </div>
                    <div class="result-section">
                        <div class="result-title">英文标签 (EN_tag):</div>
                        <div class="result-content">{result.get('EN_tag', '')}</div>
                    </div>
                </div>
            """

        html_content += "</body></html>"
        self.history_table.setHtml(html_content)

    def clear_all_history(self):
        """清空所有历史记录"""
        reply = QMessageBox.question(
            self, "确认清空",
            "确定要清空所有历史记录吗？此操作不可恢复！",
            QMessageBox.Yes | QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            self.vlm_history.clear_all()
            self.load_history()
            QMessageBox.information(self, "成功", "历史记录已清空")


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
        top_bar_layout.addStretch()

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

        # 标题和模式选择（横向布局，节省垂直空间）
        header_layout = QHBoxLayout()
        upload_title = SubtitleLabel("📤 图片上传")
        upload_title.setFont(QFont("", 13, QFont.Bold))
        header_layout.addWidget(upload_title)
        header_layout.addStretch()

        # 模式选择按钮
        self.single_mode_btn = PushButton("单个")
        self.batch_mode_btn = PushButton("批量")
        self.single_mode_btn.setCheckable(True)
        self.batch_mode_btn.setCheckable(True)
        self.single_mode_btn.setChecked(True)
        self.single_mode_btn.setFixedWidth(70)
        self.batch_mode_btn.setFixedWidth(70)
        self.single_mode_btn.clicked.connect(lambda: self.switch_to_single_mode())
        self.batch_mode_btn.clicked.connect(lambda: self.switch_to_batch_mode())
        header_layout.addWidget(self.single_mode_btn)
        header_layout.addWidget(self.batch_mode_btn)
        upload_layout.addLayout(header_layout)

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
        url_input_layout.addWidget(self.image_url_edit, 1)
        self.select_file_btn = PushButton(FluentIcon.FOLDER, "")
        self.select_file_btn.setFixedWidth(50)
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
        self.select_folder_btn.setFixedWidth(50)
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
        batch_layout.addWidget(self.batch_list_edit)

        upload_layout.addWidget(self.batch_group)
        self.batch_group.setVisible(False)

        # 图片预览区域（固定高度，支持拖拽）
        upload_layout.addWidget(QLabel("图片预览 (支持拖拽):"))
        self.image_preview_label = DragDropImageLabel()
        self.image_preview_label.setAlignment(Qt.AlignCenter)
        self.image_preview_label.setFixedHeight(160)
        self.image_preview_label.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #f9f9f9;")
        self.image_preview_label.setText("暂无图片\n\n支持拖拽本地图片或网络 URL\n本地图片自动转换为 base64")
        # 连接拖拽信号
        self.image_preview_label.image_dropped.connect(self.on_image_dropped)
        upload_layout.addWidget(self.image_preview_label)

        left_layout.addWidget(upload_card)

        # 生成按钮
        self.generate_btn = PrimaryPushButton(FluentIcon.PLAY, "开始识别")
        self.generate_btn.setFixedHeight(40)
        self.generate_btn.clicked.connect(self.start_recognition)
        left_layout.addWidget(self.generate_btn)

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
        cn_layout.addWidget(QLabel("完整中文描述"))
        self.cn_edit = QTextEdit()
        self.cn_edit.setReadOnly(True)
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
        en_layout.addWidget(QLabel("完整英文描述"))
        self.en_edit = QTextEdit()
        self.en_edit.setReadOnly(True)
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
        cn_tag_layout.addWidget(QLabel("中文标签 (逗号分隔)"))
        self.cn_tag_edit = QTextEdit()
        self.cn_tag_edit.setReadOnly(True)
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
        en_tag_layout.addWidget(QLabel("英文标签 (逗号分隔)"))
        self.en_tag_edit = QTextEdit()
        self.en_tag_edit.setReadOnly(True)
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
        log_layout.addWidget(QLabel("API 操作日志"))
        self.log_edit = QTextEdit()
        self.log_edit.setReadOnly(True)
        self.log_edit.setStyleSheet("font-family: 'Menlo', 'Monaco', 'Courier New', monospace; font-size: 11px; background: #1e1e1e; color: #d4d4d4;")
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
        main_splitter.setSizes([500, 500])

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
            # 在 URL 输入框中显示文件路径
            self.image_url_edit.setText(file_path)
            # 显示预览
            pixmap = QPixmap(file_path)
            if not pixmap.isNull():
                scaled_pixmap = pixmap.scaled(
                    self.image_preview_label.size(),
                    Qt.KeepAspectRatio,
                    Qt.SmoothTransformation
                )
                self.image_preview_label.setPixmap(scaled_pixmap)
                self.image_preview_label.setText("")

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
                QMessageBox.warning(self, "警告", "所选文件夹中没有找到图片文件")

    def show_settings(self):
        """显示设置对话框"""
        dialog = VLMSettingsDialog(self.vlm_config, self)
        if dialog.exec_() == QDialog.Accepted:
            QMessageBox.information(self, "成功", "设置已保存")

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
                QMessageBox.warning(self, "警告", "请输入图片 URL 或拖拽图片")
                return

            # 支持的格式：data URL (base64)、http://、https://
            if not (image_url.startswith('data:image/') or
                    image_url.startswith('http://') or
                    image_url.startswith('https://')):
                QMessageBox.warning(
                    self,
                    "警告",
                    "不支持的图片格式\n\n"
                    "支持的格式：\n"
                    "• 网络 URL (http:// 或 https://)\n"
                    "• 拖拽本地图片（自动转换为 base64）"
                )
                return

            self.process_single_image(image_url)
        else:
            # 批量识别
            if not hasattr(self, 'batch_files') or not self.batch_files:
                QMessageBox.warning(self, "警告", "请先选择包含图片的文件夹")
                return

            self.process_batch_images()

    def process_single_image(self, image_url):
        """处理单个图片"""
        # 获取当前选中的模板
        default_template = self.vlm_config.get("default_template", "default")
        template_dict = self.vlm_config.templates.get(default_template, {})
        template = template_dict.get("template", "") if isinstance(template_dict, dict) else ""

        self.add_log(f"开始识别图片: {image_url}")
        self.add_log(f"使用模板: {default_template}")

        self.generate_btn.setEnabled(False)
        self.progress_bar.setRange(0, 0)
        self.status_label.setText("准备识别...")

        self.current_worker = VLMImageWorker(image_url, self.vlm_config, template)
        self.current_worker.progress_updated.connect(self.on_progress_updated)
        self.current_worker.time_updated.connect(self.on_time_updated)
        self.current_worker.finished.connect(self.on_recognition_finished)
        self.current_worker.error_occurred.connect(self.on_recognition_error)
        self.current_worker.start()

    def process_batch_images(self):
        """处理批量图片"""
        # TODO: 实现批量处理逻辑
        QMessageBox.information(self, "提示", "批量处理功能开发中...")

    def on_progress_updated(self, msg):
        """更新进度"""
        self.status_label.setText(msg)
        self.add_log(f"进度: {msg}")

    def on_time_updated(self, time_str):
        """更新运行时间"""
        self.time_label.setText(time_str)

    def on_recognition_finished(self, success, result, image_url):
        """识别完成"""
        self.generate_btn.setEnabled(True)
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100 if success else 0)

        if success:
            self.current_result = result
            self.cn_edit.setText(result.get("CN", ""))
            self.en_edit.setText(result.get("EN", ""))
            self.cn_tag_edit.setText(result.get("CN_tag", ""))
            self.en_tag_edit.setText(result.get("EN_tag", ""))

            # 添加到历史记录
            self.vlm_history.add_record(image_url, result)

            # 记录日志
            self.add_log(f"识别成功！结果预览:")
            self.add_log(f"  CN: {result.get('CN', '')[:50]}...")
            self.add_log(f"  EN: {result.get('EN', '')[:50]}...")

            QMessageBox.information(self, "成功", "识别完成！")
        else:
            self.add_log(f"识别失败: {image_url}")
            QMessageBox.critical(self, "错误", "识别失败")

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
            QMessageBox.information(self, "成功", f"已复制到剪贴板")
        else:
            QMessageBox.warning(self, "警告", "没有可复制的内容")

    def export_result(self, field):
        """导出结果为 TXT 文件"""
        text = self.current_result.get(field, "")
        if not text:
            QMessageBox.warning(self, "警告", "没有可导出的内容")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self, "导出文本",
            f"prompt_{field}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
            "文本文件 (*.txt);;所有文件 (*)"
        )

        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(text)
                QMessageBox.information(self, "成功", f"文件已保存到: {file_path}")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"导出失败: {str(e)}")

    def on_image_dropped(self, path_or_url):
        """处理图片拖拽事件"""
        # 判断是网络URL还是本地路径
        if path_or_url.startswith(('http://', 'https://')):
            # 网络URL - 直接使用
            self.image_url_edit.setText(path_or_url)
            self.image_preview_label.setText(f"✓ 网络图片:\n{path_or_url}")
            self.add_log(f"拖拽网络图片URL: {path_or_url}")
        else:
            # 本地文件路径 - 转换为 base64 data URL
            abs_path = os.path.abspath(path_or_url)
            self.add_log(f"拖拽本地图片，正在转换为 base64...")

            # 确定图片 MIME 类型
            ext = os.path.splitext(abs_path)[1].lower()
            mime_map = {
                '.png': 'image/png',
                '.jpg': 'image/jpeg',
                '.jpeg': 'image/jpeg',
                '.gif': 'image/gif',
                '.bmp': 'image/bmp',
                '.webp': 'image/webp'
            }
            mime_type = mime_map.get(ext, 'image/png')

            try:
                # 读取图片文件并转换为 base64
                with open(abs_path, 'rb') as f:
                    image_data = f.read()
                    base64_data = base64.b64encode(image_data).decode('utf-8')

                # 创建 data URL
                data_url = f"data:{mime_type};base64,{base64_data}"

                # 显示预览
                pixmap = QPixmap(abs_path)
                if not pixmap.isNull():
                    scaled_pixmap = pixmap.scaled(
                        self.image_preview_label.size(),
                        Qt.KeepAspectRatio,
                        Qt.SmoothTransformation
                    )
                    self.image_preview_label.setPixmap(scaled_pixmap)
                    self.image_preview_label.setText("")

                # 将 data URL 设置到输入框
                self.image_url_edit.setText(data_url)
                self.add_log(f"本地图片已转换为 base64 data URL (大小: {len(image_data)} 字节)")

            except Exception as e:
                self.image_preview_label.setText(f"❌ 转换失败:\n{str(e)}")
                self.add_log(f"转换失败: {str(e)}")
                QMessageBox.critical(self, "错误", f"无法读取图片文件:\n{str(e)}")

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
