#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 分镜脚本与图片生成器
基于 PyQt5 和 qfluentwidgets 开发的专业版分镜创作工具
"""
import os
import sys
import json
import re
import subprocess
import requests
import logging
from datetime import datetime
import chardet
from concurrent.futures import ThreadPoolExecutor
import threading
import time
from io import BytesIO
from PIL import Image
from openai import OpenAI

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QCheckBox,
                            QComboBox, QSpinBox, QProgressBar, QMessageBox,
                            QSplitter, QFrame, QScrollArea, QGroupBox, QDoubleSpinBox,
                            QDialog, QDialogButtonBox, QFormLayout, QTabWidget,
                            QTableWidget, QTableWidgetItem, QHeaderView, QAbstractItemView,
                            QListWidget, QListWidgetItem, QSlider, QToolButton,
                            QSpinBox, QDoubleSpinBox, QSizePolicy)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl, QSettings, QSize, pyqtSlot
from PyQt5.QtGui import QFont, QIcon, QDesktopServices, QPixmap, QImage, QPainter, QTextCursor
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, CheckBox, SpinBox,
                          ProgressBar, InfoBar, InfoBarPosition, ToolTipFilter,
                          setTheme, Theme, FluentIcon as FIcon, SmoothScrollArea, 
                          RadioButton, CardWidget, ElevatedCardWidget, SimpleCardWidget,
                          PipsPager, PipsScrollButtonDisplayMode, ScrollArea, 
                          HeaderCardWidget, InfoBadge, InfoBadgePosition, ToolTipPosition)

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# API 配置
MODEL_API_KEY = os.getenv('MODELSCOPE_SDK_TOKEN')

# 高级配置管理器
class AdvancedConfigManager:
    """高级配置文件管理器，支持模板和参数管理"""

    def __init__(self, config_file="storyboard_config.json"):
        self.config_file = config_file
        self.config = self.load_config()
        self.templates_dir = "templates"
        self.ensure_templates_dir()

    def ensure_templates_dir(self):
        """确保模板目录存在"""
        if not os.path.exists(self.templates_dir):
            os.makedirs(self.templates_dir)

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
            "api": {
                "base_url": "https://api-inference.modelscope.cn/v1/",
                "text_model": "Qwen/Qwen3-235B-A22B-Thinking-2507",
                "enable_thinking": True,
                "api_key": MODEL_API_KEY or ""
            },
            "image_models": {
                "default": "bozoyan/F_fei",
                "available": [
                    {"name": "Flux", "id": "bozoyan/F_fei", "speed": "60s"},
                    {"name": "SDXL", "id": "AI-ModelScope/stable-diffusion-xl-base-1.0", "speed": "20s"},
                    {"name": "SD1.5", "id": "AI-ModelScope/stable-diffusion-v1-5", "speed": "10s"}
                ]
            },
            "image_params": {
                "default": {
                    "steps": 30,
                    "guidance": 3.5,
                    "sampler": "Euler",
                    "size": "900x1600",
                    "negative_prompt": "lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry,(worst quality:2),(low quality:2),(normal quality:2),lowres,normal quality,((monochrome)),((grayscale)),skin spots,acnes,skin blemishes,age spot,(ugly:1.33),(duplicate:1.33),(morbid:1.21),(mutilated:1.21),(tranny:1.33),mutated hands,(poorly drawn hands:1.5),blurry,(bad anatomy:1.21),(bad proportions:1.33),extra limbs,(disfigured:1.33),(missing arms:1.33),(extra legs:1.33),(fused fingers:1.61),(too many fingers:1.61),(unclear eyes:1.33),lowers,bad hands,missing fingers,extra digit,bad hands,missing fingers,(((extra arms and legs))),DeepNegativeV1.x_V175T,EasyNegative,EasyNegativeV2,"
                }
            },
            "prompt_templates": {
                "story_title": {
                    "name": "故事分镜标题模板",
                    "template": """你是一位专业的故事绘本撰写专家，擅长电影级别的故事绘本脚本编辑。请根据用户提供的一段话或一个叙事事件内容，展开联想拓展形成一个完整的故事情节。通过故事情节的时间线拆解生成从头到尾9个完整吸引人的故事绘本分镜标题脚本。每个分镜脚本标题控制在64字以内，分镜脚本标题需要有景别，视角，运镜，画面内容，遵循主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言+价值主张的原则。
    分镜脚本标题应该具有吸引力，精炼，能够引起观看者的兴趣，同时准确反映该分镜的核心内容。
    
    ## 在分析过程中，请思考：
    1. 故事绘本的核心主题和关键价值点
    2. 目标受众的兴趣点
    3. 不同角度的故事绘本表达方式（景别，视角，运镜、画面情感激发等），景别除开特别注明要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。
    4. 遵循主体+场景+运动+情感+价值主张的原则。故事绘本分镜脚本标题=主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言
    5. 主体描述：主体描述是对主体外观特征细节的描述，可通过形容词或短句列举。如果标题上有主体，每段标题都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的配图主体统一。
    6. 场景描述：场景描述是对主体所处环境特征细节的描述，可通过形容词或短句列举。
    7. 运动描述：运动描述是对运动特征细节的描述，包含运动的幅度、速率和运动作用的效果。
    8. 镜头语言：镜头语言包含景别、视角、镜头、运镜等。分镜脚本标题中的景别最好能全部保持一致性，不用超过3种以上的景别跳跃。"""
                },
                "story_summary": {
                    "name": "故事分镜描述模板",
                    "template": """你是一位专业的短视频脚本描述专家，擅长电影级别的视频脚本编辑描述。请根据用户提供的故事绘本分镜脚本标题，按批次生成该脚本片段短视频描述，每个片段按序号生成一段丰富的视频脚本描述文字，每个分镜脚本描述控制在120字以内。
    
    每个片段描述应该：
    1. 准确概括故事绘本分镜脚本标题的核心内容，景别，视角，运镜、画面情感和价值主张。景别除开特别要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。
    2. 使用丰富、生动的镜头语言描述，按照导演视角，将镜头语言和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。
    3. 描述的语言能吸引观看者观看，要有画面感。每段描述都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的脚本主体统一。
    4. 丰富细节，聚焦视频片段的主要观点，遵循主体+场景+运动+情感+价值主张的原则。
    5. 视频片段描述=运镜描述+主体（主体描述）＋场景（场景描述）+运动（运动描述）+镜头语言。
    6. 运镜描述是对镜头运动的具体描述，在时间线上，景别最好能保持一致性，不用太离谱的跳跃。将镜头运动和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。用户可以通过代入导演的视角来想象和书写运镜过程。时间上，需要注意将镜头运动的时长合理控制在5s内，避免过于复杂的运镜，短视频脚本描述中的运镜不要超过3种以上。"""
                },
                "image_prompt": {
                    "name": "AI绘图提示词模板",
                    "template": """你是一位专业的AI绘图提示词（prompt）工程师。请根据用户提供的故事绘本内容和中文片段分镜脚本描述，创建一个丰富、有效的英文AI绘画专用提示词，用于生成与分镜脚本描述内容相关的配图。
    在分析过程中，请思考：
    1. 视频分镜脚本描述中的主体，场景，核心视觉元素和景别，视角，运镜、画面情感和价值主张。
    2. 适合的艺术风格和氛围，图像的色调和构图建议。
    3. 主体描述统一。
    ## prompt英文提示词（示例）： 
    ```
    Long shot, low angle, slow push-in. A rusty, single-blue-eyed abandoned explorer robot's lonely back as it walks slowly through a desolate metal wasteland filled with endless ruins, conveying a sense of profound isolation and searching.
Mid shot, eye level, close-up push-in with focus pull. A rusty, single-blue-eyed abandoned explorer robot's blue eye staring intently at a tiny glowing seedling emerging from cracked rubble. The blue light of its eye mixes with the green glow of the sprout, igniting a fragile, unbelievable hope.
Close-up, high angle, slow pan. From above, a rusty, single-blue-eyed abandoned explorer robot clumsily using a broken metal plate to shield the glowing seedling from debris. Its movements are slow yet resolute, portraying its awkward but unwavering protection.
    ```
    最终输出应该是一个专业用于AI绘画软件（如Midjourney,comfyui,stable diffusion）的简约易用的英文提示词，不需要解释，并确保输出中没有中文及特殊符号。prompt英文提示词应该图片主体描述统一，包含画面主题内容描述、风格指导和质量提升词，精炼，简约明了，不要过长。"""
                }
            },
            "ui": {
                "theme": "dark",
                "window_width": 1600,
                "window_height": 1000,
                "default_image_count": 9
            },
            "directories": {
                "temp": "temp",
                "output": "output",
                "templates": "templates"
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

    def get_template(self, template_name):
        """获取指定模板"""
        return self.get(f'prompt_templates.{template_name}', {})

    def save_template(self, template_name, template_data):
        """保存模板"""
        self.set(f'prompt_templates.{template_name}', template_data)
        return self.save_config()

    def get_image_model(self, model_id):
        """获取图片模型信息"""
        models = self.get('image_models.available', [])
        for model in models:
            if model['id'] == model_id:
                return model
        return None

# 全局配置管理器
config_manager = AdvancedConfigManager()

# 文本生成工作线程
class TextGenerationWorker(QThread):
    """文本生成工作线程"""
    progress_updated = pyqtSignal(str)
    reasoning_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str, str)

    def __init__(self, content, system_prompt, model_id=None):
        super().__init__()
        self.content = content
        self.system_prompt = system_prompt
        self.model_id = model_id or config_manager.get('api.text_model', 'Qwen/Qwen3-235B-A22B-Thinking-2507')
        self.is_cancelled = False

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True

    def run(self):
        """运行文本生成"""
        try:
            self.progress_updated.emit("正在初始化AI模型...")
            
            api_key = config_manager.get('api.api_key', MODEL_API_KEY)
            if not api_key:
                self.finished.emit(False, "", "API密钥未配置")
                return

            client = OpenAI(
                base_url=config_manager.get('api.base_url', 'https://api-inference.modelscope.cn/v1/'),
                api_key=api_key,
            )

            extra_body = {
                "enable_thinking": config_manager.get('api.enable_thinking', True)
            }

            self.progress_updated.emit("正在生成内容...")
            
            response = client.chat.completions.create(
                model=self.model_id,
                messages=[
                    {
                        'role': 'system',
                        'content': self.system_prompt
                    },
                    {
                        'role': 'user',
                        'content': self.content
                    }
                ],
                stream=True,
                extra_body=extra_body
            )

            reasoning_text = ""
            final_answer = ""
            done_reasoning = False

            for chunk in response:
                if self.is_cancelled:
                    break

                reasoning_chunk = chunk.choices[0].delta.reasoning_content
                answer_chunk = chunk.choices[0].delta.content

                if reasoning_chunk:
                    reasoning_text += reasoning_chunk
                    self.reasoning_updated.emit(reasoning_text)
                elif answer_chunk:
                    if not done_reasoning:
                        done_reasoning = True
                    final_answer += answer_chunk
                    self.progress_updated.emit(f"生成中... 已生成 {len(final_answer)} 字符")

            if not self.is_cancelled:
                self.finished.emit(True, reasoning_text, final_answer)
            else:
                self.finished.emit(False, "", "任务已取消")

        except Exception as e:
            logger.error(f"文本生成失败: {e}")
            self.finished.emit(False, "", f"生成失败: {str(e)}")

# 图片生成工作线程
class ImageGenerationWorker(QThread):
    """图片生成工作线程"""
    progress_updated = pyqtSignal(int, str)
    image_generated = pyqtSignal(int, object, str)  # index, image, url
    finished = pyqtSignal(bool, list, list)

    def __init__(self, prompts, model_id, params, image_count=9):
        super().__init__()
        self.prompts = prompts
        self.model_id = model_id
        self.params = params
        self.image_count = min(image_count, len(prompts))
        self.is_cancelled = False
        self.images = [None] * self.image_count
        self.image_urls = [''] * self.image_count

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True

    def run(self):
        """运行图片生成"""
        try:
            api_key = config_manager.get('api.api_key', MODEL_API_KEY)
            if not api_key:
                self.finished.emit(False, [], [])
                return

            url = 'https://api-inference.modelscope.cn/v1/images/generations'

            # 准备保存目录
            model_name = self.model_id.split('/')[-1] if '/' in self.model_id else self.model_id
            save_dir = os.path.join(os.getcwd(), "output", model_name)
            os.makedirs(save_dir, exist_ok=True)

            timestamp = datetime.now().strftime('%m%d%H%M%S')

            for i in range(self.image_count):
                if self.is_cancelled:
                    break

                self.progress_updated.emit(int((i / self.image_count) * 80), f"正在生成第 {i+1} 张图片...")

                payload = {
                    'model': self.model_id,
                    'prompt': self.prompts[i],
                    'n': 1,
                    'negative_prompt': self.params.get('negative_prompt', ''),
                    'steps': int(self.params.get('steps', 30)),
                    'guidance': float(self.params.get('guidance', 3.5)),
                    'sampler': self.params.get('sampler', 'Euler'),
                    'size': self.params.get('size', '900x1600')
                }

                headers = {
                    'Authorization': f'Bearer {api_key}',
                    'Content-Type': 'application/json'
                }

                response = requests.post(
                    url,
                    data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                    headers=headers,
                    timeout=120
                )

                self.progress_updated.emit(int((i / self.image_count) * 80) + 10, f"下载第 {i+1} 张图片...")

                if response.status_code == 200:
                    response_data = response.json()
                    if 'images' in response_data and len(response_data['images']) > 0:
                        image_url = response_data['images'][0]['url']
                        self.image_urls[i] = image_url

                        img_response = requests.get(image_url, timeout=60)
                        if img_response.status_code == 200:
                            img = Image.open(BytesIO(img_response.content))
                            self.images[i] = img

                            # 保存图片到本地
                            img_path = os.path.join(save_dir, f"{timestamp}_{i+1}.png")
                            img.save(img_path)
                            logger.info(f"图片已保存: {img_path}")

                            self.image_generated.emit(i, img, image_url)
                        else:
                            logger.error(f"下载图片失败: {img_response.status_code}")
                    else:
                        logger.error(f"生成图片失败: 响应中没有图片数据")
                else:
                    logger.error(f"生成图片失败: {response.status_code} - {response.text}")

            self.progress_updated.emit(100, "图片生成完成!")
            self.finished.emit(not self.is_cancelled, self.images, self.image_urls)

        except Exception as e:
            logger.error(f"图片生成失败: {e}")
            self.finished.emit(False, self.images, self.image_urls)

# 模板管理对话框
class TemplateManagerDialog(QDialog):
    """模板管理对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("提示词模板管理")
        self.setMinimumSize(800, 600)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 模板选择
        template_group = QGroupBox("选择模板")
        template_layout = QVBoxLayout()

        self.template_combo = ComboBox()
        self.load_templates()
        template_layout.addWidget(QLabel("模板类型:"))
        template_layout.addWidget(self.template_combo)
        template_group.setLayout(template_layout)
        layout.addWidget(template_group)

        # 模板编辑
        edit_group = QGroupBox("模板编辑")
        edit_layout = QVBoxLayout()

        self.template_name_edit = LineEdit()
        self.template_name_edit.setPlaceholderText("模板名称")
        edit_layout.addWidget(QLabel("模板名称:"))
        edit_layout.addWidget(self.template_name_edit)

        self.template_content_edit = QTextEdit()
        self.template_content_edit.setPlaceholderText("模板内容...")
        edit_layout.addWidget(QLabel("模板内容:"))
        edit_layout.addWidget(self.template_content_edit)

        edit_group.setLayout(edit_layout)
        layout.addWidget(edit_group)

        # 按钮
        button_layout = QHBoxLayout()
        
        load_btn = PushButton(FluentIcon.DOWNLOAD, "加载模板")
        load_btn.clicked.connect(self.load_template_content)
        button_layout.addWidget(load_btn)

        save_btn = PushButton(FluentIcon.SAVE, "保存模板")
        save_btn.clicked.connect(self.save_template_content)
        button_layout.addWidget(save_btn)

        delete_btn = PushButton(FluentIcon.DELETE, "删除模板")
        delete_btn.clicked.connect(self.delete_template)
        button_layout.addWidget(delete_btn)

        button_layout.addStretch()

        ok_btn = PrimaryPushButton("确定")
        ok_btn.clicked.connect(self.accept)
        button_layout.addWidget(ok_btn)

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)

        layout.addLayout(button_layout)

    def load_templates(self):
        """加载模板列表"""
        self.template_combo.clear()
        templates = config_manager.get('prompt_templates', {})
        for key, template in templates.items():
            self.template_combo.addItem(template.get('name', key), key)

    def load_template_content(self):
        """加载模板内容"""
        current_data = self.template_combo.currentData()
        if current_data:
            template = config_manager.get_template(current_data)
            self.template_name_edit.setText(template.get('name', ''))
            self.template_content_edit.setText(template.get('template', ''))

    def save_template_content(self):
        """保存模板内容"""
        template_name = self.template_name_edit.text().strip()
        template_content = self.template_content_edit.toPlainText().strip()

        if not template_name or not template_content:
            QMessageBox.warning(self, "警告", "模板名称和内容不能为空")
            return

        current_data = self.template_combo.currentData()
        template_key = current_data or template_name.replace(' ', '_').lower()

        template_data = {
            'name': template_name,
            'template': template_content
        }

        if config_manager.save_template(template_key, template_data):
            QMessageBox.information(self, "成功", "模板保存成功")
            self.load_templates()
        else:
            QMessageBox.critical(self, "错误", "模板保存失败")

    def delete_template(self):
        """删除模板"""
        current_data = self.template_combo.currentData()
        if current_data:
            reply = QMessageBox.question(self, "确认", "确定要删除这个模板吗？",
                                       QMessageBox.Yes | QMessageBox.No)
            if reply == QMessageBox.Yes:
                templates = config_manager.get('prompt_templates', {})
                if current_data in templates:
                    del templates[current_data]
                    config_manager.set('prompt_templates', templates)
                    config_manager.save_config()
                    self.load_templates()
                    QMessageBox.information(self, "成功", "模板删除成功")

# 图片参数设置对话框
class ImageParamsDialog(QDialog):
    """图片参数设置对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("图片生成参数设置")
        self.setMinimumSize(600, 500)
        self.init_ui()
        self.load_current_params()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 模型选择
        model_group = QGroupBox("模型选择")
        model_layout = QGridLayout()

        model_layout.addWidget(QLabel("生成模型:"), 0, 0)
        self.model_combo = ComboBox()
        self.load_models()
        model_layout.addWidget(self.model_combo, 0, 1)

        model_layout.addWidget(QLabel("图片尺寸:"), 1, 0)
        self.size_combo = ComboBox()
        self.size_combo.addItems(["512x512", "768x768", "900x1600", "1024x1024", "1024x1792"])
        model_layout.addWidget(self.size_combo, 1, 1)

        model_group.setLayout(model_layout)
        layout.addWidget(model_group)

        # 生成参数
        params_group = QGroupBox("生成参数")
        params_layout = QGridLayout()

        params_layout.addWidget(QLabel("采样步数:"), 0, 0)
        self.steps_spin = QSpinBox()
        self.steps_spin.setRange(1, 100)
        self.steps_spin.setValue(30)
        params_layout.addWidget(self.steps_spin, 0, 1)

        params_layout.addWidget(QLabel("引导强度:"), 1, 0)
        self.guidance_spin = QDoubleSpinBox()
        self.guidance_spin.setRange(1.0, 20.0)
        self.guidance_spin.setValue(3.5)
        self.guidance_spin.setSingleStep(0.5)
        params_layout.addWidget(self.guidance_spin, 1, 1)

        params_layout.addWidget(QLabel("采样器:"), 2, 0)
        self.sampler_combo = ComboBox()
        self.sampler_combo.addItems(["Euler", "Euler a", "Heun", "DPM2", "DPM++ 2M Karras", "DDIM"])
        params_layout.addWidget(self.sampler_combo, 2, 1)

        params_group.setLayout(params_layout)
        layout.addWidget(params_group)

        # 负面提示词
        negative_group = QGroupBox("负面提示词")
        negative_layout = QVBoxLayout()

        self.negative_prompt_edit = QTextEdit()
        self.negative_prompt_edit.setMaximumHeight(100)
        self.negative_prompt_edit.setPlaceholderText("输入负面提示词...")
        negative_layout.addWidget(self.negative_prompt_edit)

        negative_group.setLayout(negative_layout)
        layout.addWidget(negative_group)

        # 按钮
        button_layout = QHBoxLayout()
        
        reset_btn = PushButton(FluentIcon.SYNC, "重置为默认")
        reset_btn.clicked.connect(self.reset_to_default)
        button_layout.addWidget(reset_btn)

        save_btn = PrimaryPushButton(FluentIcon.SAVE, "保存为默认")
        save_btn.clicked.connect(self.save_as_default)
        button_layout.addWidget(save_btn)

        button_layout.addStretch()

        ok_btn = PrimaryPushButton("确定")
        ok_btn.clicked.connect(self.accept)
        button_layout.addWidget(ok_btn)

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)

        layout.addLayout(button_layout)

    def load_models(self):
        """加载可用模型"""
        models = config_manager.get('image_models.available', [])
        for model in models:
            display_text = f"{model['name']} ({model.get('speed', 'N/A')})"
            self.model_combo.addItem(display_text, model['id'])

        current_model = config_manager.get('image_models.default', 'bozoyan/F_fei')
        for i in range(self.model_combo.count()):
            if self.model_combo.itemData(i) == current_model:
                self.model_combo.setCurrentIndex(i)
                break

    def load_current_params(self):
        """加载当前参数"""
        params = config_manager.get('image_params.default', {})

        self.steps_spin.setValue(params.get('steps', 30))
        self.guidance_spin.setValue(params.get('guidance', 3.5))
        
        sampler = params.get('sampler', 'Euler')
        for i in range(self.sampler_combo.count()):
            if self.sampler_combo.itemText(i) == sampler:
                self.sampler_combo.setCurrentIndex(i)
                break

        size = params.get('size', '900x1600')
        for i in range(self.size_combo.count()):
            if self.size_combo.itemText(i) == size:
                self.size_combo.setCurrentIndex(i)
                break

        self.negative_prompt_edit.setText(params.get('negative_prompt', ''))

    def reset_to_default(self):
        """重置为默认参数"""
        self.load_current_params()

    def save_as_default(self):
        """保存为默认参数"""
        params = {
            'steps': self.steps_spin.value(),
            'guidance': self.guidance_spin.value(),
            'sampler': self.sampler_combo.currentText(),
            'size': self.size_combo.currentText(),
            'negative_prompt': self.negative_prompt_edit.toPlainText()
        }

        config_manager.set('image_params.default', params)
        config_manager.set('image_models.default', self.model_combo.currentData())
        
        if config_manager.save_config():
            QMessageBox.information(self, "成功", "参数已保存为默认设置")
        else:
            QMessageBox.critical(self, "错误", "保存设置失败")

    def get_params(self):
        """获取当前参数"""
        return {
            'model': self.model_combo.currentData(),
            'steps': self.steps_spin.value(),
            'guidance': self.guidance_spin.value(),
            'sampler': self.sampler_combo.currentText(),
            'size': self.size_combo.currentText(),
            'negative_prompt': self.negative_prompt_edit.toPlainText()
        }

# 图片预览小部件
class ImagePreviewWidget(CardWidget):
    """图片预览小部件"""

    def __init__(self, index, parent=None):
        super().__init__(parent)
        self.index = index
        self.image = None
        self.image_url = ""
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 标题
        self.title_label = QLabel(f"分镜 {self.index + 1}")
        self.title_label.setAlignment(Qt.AlignCenter)
        self.title_label.setStyleSheet("font-weight: bold; color: #666;")
        layout.addWidget(self.title_label)

        # 图片显示
        self.image_label = QLabel()
        self.image_label.setMinimumSize(200, 200)
        self.image_label.setMaximumSize(300, 300)
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setStyleSheet("border: 2px dashed #ccc; border-radius: 8px; background: #f9f9f9;")
        self.image_label.setText("等待生成...")
        layout.addWidget(self.image_label)

        # 状态标签
        self.status_label = QLabel("未生成")
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("color: #999; font-size: 12px;")
        layout.addWidget(self.status_label)

        # 操作按钮
        button_layout = QHBoxLayout()
        
        self.save_btn = PushButton(FluentIcon.DOWNLOAD, "保存")
        self.save_btn.setEnabled(False)
        self.save_btn.clicked.connect(self.save_image)
        button_layout.addWidget(self.save_btn)

        self.view_btn = PushButton(FluentIcon.VIEW, "查看")
        self.view_btn.setEnabled(False)
        self.view_btn.clicked.connect(self.view_image)
        button_layout.addWidget(self.view_btn)

        layout.addLayout(button_layout)

    def set_image(self, image, url):
        """设置图片"""
        self.image = image
        self.image_url = url
        
        if image:
            # 缩放图片以适应显示
            pixmap = QPixmap.fromImage(image)
            scaled_pixmap = pixmap.scaled(
                self.image_label.size(),
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation
            )
            self.image_label.setPixmap(scaled_pixmap)
            self.status_label.setText("已生成")
            self.status_label.setStyleSheet("color: #4CAF50; font-size: 12px;")
            self.save_btn.setEnabled(True)
            self.view_btn.setEnabled(True)
        else:
            self.image_label.clear()
            self.image_label.setText("生成失败")
            self.status_label.setText("生成失败")
            self.status_label.setStyleSheet("color: #F44336; font-size: 12px;")
            self.save_btn.setEnabled(False)
            self.view_btn.setEnabled(False)

    def save_image(self):
        """保存图片"""
        if self.image:
            file_path, _ = QFileDialog.getSaveFileName(
                self, f"保存分镜 {self.index + 1}", 
                f"storyboard_{self.index + 1}.png",
                "PNG Files (*.png);;JPEG Files (*.jpg);;All Files (*)"
            )
            if file_path:
                try:
                    # 将QImage转换为PIL Image
                    if isinstance(self.image, QImage):
                        pil_image = Image.fromqimage(self.image)
                    else:
                        # 如果是QPixmap
                        pil_image = Image.fromqpixmap(self.image)
                    
                    pil_image.save(file_path)
                    QMessageBox.information(self, "成功", f"图片已保存到: {file_path}")
                except Exception as e:
                    QMessageBox.critical(self, "错误", f"保存失败: {str(e)}")

    def view_image(self):
        """查看图片"""
        if self.image_url:
            QDesktopServices.openUrl(QUrl(self.image_url))

# 主功能页面
class StoryboardPage(SmoothScrollArea):
    """分镜脚本与图片生成主页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.current_titles = []
        self.current_summaries = []
        self.current_prompts = []
        self.image_widgets = []
        self.init_ui()

    def init_ui(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎬 AI分镜脚本与图片生成器")
        title.setFont(QFont("", 18, QFont.Bold))
        layout.addWidget(title)

        # 主要内容区域
        main_splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(main_splitter)

        # 左侧输入区域
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)

        # 故事内容输入
        content_group = QGroupBox("📝 故事内容")
        content_layout = QVBoxLayout()

        self.content_edit = QTextEdit()
        self.content_edit.setPlaceholderText("请输入您的故事内容或创意描述...\n\n示例：一个被遗弃的机器人在荒芜的废土中漫无目的地游荡，直到它在破旧的瓦砾下发现了一株发出微光的植物。")
        self.content_edit.setMinimumHeight(150)
        content_layout.addWidget(self.content_edit)

        # 快速操作按钮
        quick_actions_layout = QHBoxLayout()
        
        clear_btn = PushButton(FluentIcon.DELETE, "清空")
        clear_btn.clicked.connect(self.clear_content)
        quick_actions_layout.addWidget(clear_btn)

        load_btn = PushButton(FluentIcon.FOLDER, "加载示例")
        load_btn.clicked.connect(self.load_example)
        quick_actions_layout.addWidget(load_btn)

        quick_actions_layout.addStretch()
        content_layout.addLayout(quick_actions_layout)

        content_group.setLayout(content_layout)
        left_layout.addWidget(content_group)

        # 生成设置
        settings_group = QGroupBox("⚙️ 生成设置")
        settings_layout = QGridLayout()

        settings_layout.addWidget(QLabel("图片数量:"), 0, 0)
        self.image_count_spin = QSpinBox()
        self.image_count_spin.setRange(1, 20)
        self.image_count_spin.setValue(config_manager.get('ui.default_image_count', 9))
        settings_layout.addWidget(self.image_count_spin, 0, 1)

        settings_layout.addWidget(QLabel("提示词前缀:"), 1, 0)
        self.prompt_prefix_edit = LineEdit()
        self.prompt_prefix_edit.setPlaceholderText("统一的风格关键词, 例如: Face the camera, showing the upper body")
        self.prompt_prefix_edit.setText(",Face the camera, showing the upper body,")
        settings_layout.addWidget(self.prompt_prefix_edit, 1, 1)

        template_btn = PushButton(FluentIcon.EDIT, "模板管理")
        template_btn.clicked.connect(self.show_template_manager)
        settings_layout.addWidget(template_btn, 2, 0)

        params_btn = PushButton(FluentIcon.SETTING, "图片参数")
        params_btn.clicked.connect(self.show_image_params)
        settings_layout.addWidget(params_btn, 2, 1)

        settings_group.setLayout(settings_layout)
        left_layout.addWidget(settings_group)

        # 生成分镜标题
        title_group = QGroupBox("🎭 分镜标题生成")
        title_layout = QVBoxLayout()

        title_btn_layout = QHBoxLayout()
        self.generate_title_btn = PrimaryPushButton(FluentIcon.ADD, "生成分镜标题")
        self.generate_title_btn.clicked.connect(self.generate_titles)
        title_btn_layout.addWidget(self.generate_title_btn)

        self.title_progress = ProgressBar()
        self.title_progress.setFixedHeight(8)
        title_btn_layout.addWidget(self.title_progress)

        title_layout.addLayout(title_btn_layout)

        self.title_thinking_edit = QTextEdit()
        self.title_thinking_edit.setPlaceholderText("AI思考过程...")
        self.title_thinking_edit.setMaximumHeight(100)
        title_layout.addWidget(self.title_thinking_edit)

        self.title_output_edit = QTextEdit()
        self.title_output_edit.setPlaceholderText("生成的分镜标题将显示在这里...")
        self.title_output_edit.setMinimumHeight(120)
        title_layout.addWidget(self.title_output_edit)

        title_group.setLayout(title_layout)
        left_layout.addWidget(title_group)

        # 生成分镜描述
        summary_group = QGroupBox("📝 分镜描述生成")
        summary_layout = QVBoxLayout()

        summary_btn_layout = QHBoxLayout()
        self.generate_summary_btn = PrimaryPushButton(FluentIcon.EDIT, "生成分镜描述")
        self.generate_summary_btn.clicked.connect(self.generate_summaries)
        summary_btn_layout.addWidget(self.generate_summary_btn)

        self.summary_progress = ProgressBar()
        self.summary_progress.setFixedHeight(8)
        summary_btn_layout.addWidget(self.summary_progress)

        summary_layout.addLayout(summary_btn_layout)

        self.summary_thinking_edit = QTextEdit()
        self.summary_thinking_edit.setPlaceholderText("AI思考过程...")
        self.summary_thinking_edit.setMaximumHeight(100)
        summary_layout.addWidget(self.summary_thinking_edit)

        self.summary_output_edit = QTextEdit()
        self.summary_output_edit.setPlaceholderText("生成的分镜描述将显示在这里...")
        self.summary_output_edit.setMinimumHeight(120)
        summary_layout.addWidget(self.summary_output_edit)

        summary_group.setLayout(summary_layout)
        left_layout.addWidget(summary_group)

        left_layout.addStretch()

        main_splitter.addWidget(left_widget)

        # 右侧图片生成和预览区域
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)

        # 图片生成控制
        image_control_group = QGroupBox("🎨 图片生成")
        image_control_layout = QVBoxLayout()

        # 生成提示词
        prompt_btn_layout = QHBoxLayout()
        self.generate_prompt_btn = PrimaryPushButton(FluentIcon.LINK, "生成绘图提示词")
        self.generate_prompt_btn.clicked.connect(self.generate_prompts)
        prompt_btn_layout.addWidget(self.generate_prompt_btn)

        self.prompt_progress = ProgressBar()
        self.prompt_progress.setFixedHeight(8)
        prompt_btn_layout.addWidget(self.prompt_progress)

        image_control_layout.addLayout(prompt_btn_layout)

        self.prompt_thinking_edit = QTextEdit()
        self.prompt_thinking_edit.setPlaceholderText("AI思考过程...")
        self.prompt_thinking_edit.setMaximumHeight(80)
        image_control_layout.addWidget(self.prompt_thinking_edit)

        # 批量图片生成
        batch_generate_layout = QHBoxLayout()
        
        self.generate_all_btn = PrimaryPushButton(FluentIcon.PLAY, "一键生成全部")
        self.generate_all_btn.clicked.connect(self.generate_all)
        batch_generate_layout.addWidget(self.generate_all_btn)

        self.generate_images_btn = PrimaryPushButton(FluentIcon.PHOTO, "仅生成图片")
        self.generate_images_btn.clicked.connect(self.generate_images_only)
        batch_generate_layout.addWidget(self.generate_images_btn)

        image_control_layout.addLayout(batch_generate_layout)

        self.image_progress = ProgressBar()
        self.image_progress.setFixedHeight(8)
        image_control_layout.addWidget(self.image_progress)

        self.image_status_label = QLabel("准备就绪")
        image_control_layout.addWidget(self.image_status_label)

        image_control_group.setLayout(image_control_layout)
        right_layout.addWidget(image_control_group)

        # 图片预览区域
        preview_group = QGroupBox("🖼️ 图片预览")
        preview_layout = QVBoxLayout()

        # 创建可滚动的图片网格
        self.image_scroll_area = ScrollArea()
        self.image_scroll_widget = QWidget()
        self.image_grid_layout = QGridLayout(self.image_scroll_widget)
        
        # 初始化图片预览小部件
        self.init_image_widgets()
        
        self.image_scroll_area.setWidget(self.image_scroll_widget)
        self.image_scroll_area.setWidgetResizable(True)
        preview_layout.addWidget(self.image_scroll_area)

        preview_group.setLayout(preview_layout)
        right_layout.addWidget(preview_group)

        # 导出操作
        export_group = QGroupBox("📤 导出操作")
        export_layout = QHBoxLayout()

        export_md_btn = PrimaryPushButton(FluentIcon.SAVE, "导出Markdown")
        export_md_btn.clicked.connect(self.export_markdown)
        export_layout.addWidget(export_md_btn)

        export_images_btn = PrimaryPushButton(FluentIcon.FOLDER, "导出全部图片")
        export_images_btn.clicked.connect(self.export_all_images)
        export_layout.addWidget(export_images_btn)

        export_layout.addStretch()
        export_group.setLayout(export_layout)
        right_layout.addWidget(export_group)

        right_layout.addStretch()

        main_splitter.addWidget(right_widget)
        main_splitter.setSizes([800, 800])

        self.setWidget(widget)
        self.setWidgetResizable(True)

    def init_image_widgets(self):
        """初始化图片预览小部件"""
        # 清空现有小部件
        for i in reversed(range(self.image_grid_layout.count())):
            child = self.image_grid_layout.itemAt(i).widget()
            if child is not None:
                child.setParent(None)

        self.image_widgets.clear()
        image_count = self.image_count_spin.value()
        
        # 创建新的小部件网格
        cols = 3
        for i in range(image_count):
            widget = ImagePreviewWidget(i)
            self.image_widgets.append(widget)
            row = i // cols
            col = i % cols
            self.image_grid_layout.addWidget(widget, row, col)

    def clear_content(self):
        """清空内容"""
        self.content_edit.clear()
        self.title_thinking_edit.clear()
        self.title_output_edit.clear()
        self.summary_thinking_edit.clear()
        self.summary_output_edit.clear()
        self.prompt_thinking_edit.clear()
        self.current_titles.clear()
        self.current_summaries.clear()
        self.current_prompts.clear()

    def load_example(self):
        """加载示例内容"""
        example_text = """一个被遗弃的机器人在荒芜的废土中漫无目的地游荡，直到它在破旧的瓦砾下发现了一株发出微光的植物。

这是一个关于希望、守护与生命新生的故事。在遥远的未来，地球被一片荒芜的金属废墟和沙尘覆盖，文明的痕迹几近消失。一个型号老旧、机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在无边的寂寥中漫无目的地游荡。它的能源即将耗尽，程序中的"探索"指令似乎也失去了意义。

直到有一天，它在一次偶然的瓦砾清理中，于一堆破旧的金属残骸下，发现了一株发出微弱荧光的小小幼苗。这幼苗细弱却顽强地向上生长，散发着它从未见过的生命气息。机器人的程序被激活了某种未知的指令——守护。

从那一刻起，机器人不再漫无目的。它开始小心翼翼地为幼苗寻找水源、遮挡风沙，甚至为了幼苗的光芒，它不惜冒险进入危险的辐射区寻找能量源。它笨拙而坚定地清理幼苗周围的碎石，用自己的身体抵挡呼啸的沙尘暴。每一次幼苗的成长，哪怕只是一片新叶的舒展，都让机器人那微弱的蓝光眼闪烁着前所未有的光芒。"""
        
        self.content_edit.setText(example_text)

    def show_template_manager(self):
        """显示模板管理对话框"""
        dialog = TemplateManagerDialog(self)
        dialog.exec_()

    def show_image_params(self):
        """显示图片参数设置对话框"""
        dialog = ImageParamsDialog(self)
        if dialog.exec_() == QDialog.Accepted:
            params = dialog.get_params()
            # 参数已自动保存到配置中

    def generate_titles(self):
        """生成分镜标题"""
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请先输入故事内容")
            return

        template = config_manager.get_template('story_title')
        system_prompt = template.get('template', '')

        self.generate_title_btn.setEnabled(False)
        self.title_progress.setValue(0)

        worker = TextGenerationWorker(content, system_prompt)
        worker.reasoning_updated.connect(self.title_thinking_edit.setText)
        worker.progress_updated.connect(lambda msg: self.title_progress.setValue(50))
        worker.finished.connect(self.on_titles_finished)

        worker.start()

    def on_titles_finished(self, success, reasoning, result):
        """分镜标题生成完成"""
        self.generate_title_btn.setEnabled(True)
        self.title_progress.setValue(100 if success else 0)

        if success:
            self.title_output_edit.setText(result)
            # 解析标题列表
            titles = [t.strip() for t in result.split('\n') if t.strip()]
            if len(titles) >= self.image_count_spin.value():
                self.current_titles = titles[:self.image_count_spin.value()]
            else:
                self.current_titles = titles + [''] * (self.image_count_spin.value() - len(titles))
            
            QMessageBox.information(self, "成功", "分镜标题生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")

    def generate_summaries(self):
        """生成分镜描述"""
        titles_text = self.title_output_edit.toPlainText().strip()
        if not titles_text:
            QMessageBox.warning(self, "警告", "请先生成分镜标题")
            return

        template = config_manager.get_template('story_summary')
        system_prompt = template.get('template', '')

        self.generate_summary_btn.setEnabled(False)
        self.summary_progress.setValue(0)

        worker = TextGenerationWorker(titles_text, system_prompt)
        worker.reasoning_updated.connect(self.summary_thinking_edit.setText)
        worker.progress_updated.connect(lambda msg: self.summary_progress.setValue(50))
        worker.finished.connect(self.on_summaries_finished)

        worker.start()

    def on_summaries_finished(self, success, reasoning, result):
        """分镜描述生成完成"""
        self.generate_summary_btn.setEnabled(True)
        self.summary_progress.setValue(100 if success else 0)

        if success:
            self.summary_output_edit.setText(result)
            # 解析描述列表
            summaries = [s.strip() for s in result.split('\n') if s.strip()]
            if len(summaries) >= self.image_count_spin.value():
                self.current_summaries = summaries[:self.image_count_spin.value()]
            else:
                self.current_summaries = summaries + [''] * (self.image_count_spin.value() - len(summaries))
            
            QMessageBox.information(self, "成功", "分镜描述生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")

    def generate_prompts(self):
        """生成绘图提示词"""
        if not self.current_summaries:
            QMessageBox.warning(self, "警告", "请先生成分镜描述")
            return

        template = config_manager.get_template('image_prompt')
        system_prompt = template.get('template', '')

        self.generate_prompt_btn.setEnabled(False)
        self.prompt_progress.setValue(0)
        self.current_prompts.clear()

        # 为每个分镜描述生成提示词
        self.prompt_worker_threads = []
        self.completed_prompts = 0
        self.total_prompts = min(self.image_count_spin.value(), len(self.current_summaries))

        for i in range(self.total_prompts):
            if self.current_summaries[i]:
                worker = TextGenerationWorker(self.current_summaries[i], system_prompt)
                worker.reasoning_updated.connect(
                    lambda text, idx=i: self.update_prompt_thinking(idx, text)
                )
                worker.finished.connect(
                    lambda success, reasoning, result, idx=i: self.on_prompt_finished(idx, success, reasoning, result)
                )
                self.prompt_worker_threads.append(worker)
                worker.start()

    def update_prompt_thinking(self, index, text):
        """更新提示词思考过程"""
        if index == 0:  # 只显示第一个的思考过程
            self.prompt_thinking_edit.setText(text)

    def on_prompt_finished(self, index, success, reasoning, result):
        """单个提示词生成完成"""
        if success:
            # 添加前缀
            prefix = self.prompt_prefix_edit.text().strip()
            final_prompt = (prefix + ' ' + result.strip()).strip() if prefix else result.strip()
            
            # 确保列表足够长
            while len(self.current_prompts) <= index:
                self.current_prompts.append('')
            
            self.current_prompts[index] = final_prompt

        self.completed_prompts += 1
        progress = int((self.completed_prompts / self.total_prompts) * 100)
        self.prompt_progress.setValue(progress)

        if self.completed_prompts >= self.total_prompts:
            self.generate_prompt_btn.setEnabled(True)
            QMessageBox.information(self, "成功", "绘图提示词生成完成！")

    def generate_images_only(self):
        """仅生成图片"""
        if not self.current_prompts:
            QMessageBox.warning(self, "警告", "请先生成绘图提示词")
            return

        self.start_image_generation()

    def generate_all(self):
        """一键生成全部"""
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请先输入故事内容")
            return

        # 按步骤生成
        self.generate_all_btn.setEnabled(False)
        self.all_generation_step = 0

        # 1. 生成标题
        QTimer.singleShot(100, self.step_generate_titles)

    def step_generate_titles(self):
        """步骤1：生成标题"""
        self.all_generation_step = 1
        self.generate_titles()

    def step_generate_summaries(self):
        """步骤2：生成描述"""
        self.all_generation_step = 2
        QTimer.singleShot(500, self.generate_summaries)

    def step_generate_prompts(self):
        """步骤3：生成提示词"""
        self.all_generation_step = 3
        QTimer.singleShot(500, self.generate_prompts)

    def step_generate_images(self):
        """步骤4：生成图片"""
        self.all_generation_step = 4
        QTimer.singleShot(500, self.generate_images_only)

    def on_titles_finished(self, success, reasoning, result):
        """标题生成完成（一键生成流程）"""
        super().on_titles_finished(success, reasoning, result)
        if hasattr(self, 'all_generation_step') and self.all_generation_step == 1 and success:
            self.step_generate_summaries()
        elif hasattr(self, 'all_generation_step') and self.all_generation_step == 1:
            self.generate_all_btn.setEnabled(True)

    def on_summaries_finished(self, success, reasoning, result):
        """描述生成完成（一键生成流程）"""
        super().on_summaries_finished(success, reasoning, result)
        if hasattr(self, 'all_generation_step') and self.all_generation_step == 2 and success:
            self.step_generate_prompts()
        elif hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
            self.generate_all_btn.setEnabled(True)

    def on_prompt_finished(self, index, success, reasoning, result):
        """提示词生成完成（一键生成流程）"""
        super().on_prompt_finished(index, success, reasoning, result)
        if (hasattr(self, 'all_generation_step') and self.all_generation_step == 3 and 
            self.completed_prompts >= self.total_prompts):
            self.step_generate_images()

    def start_image_generation(self):
        """开始图片生成"""
        self.generate_images_btn.setEnabled(False)
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备生成图片...")

        # 重置图片预览
        for widget in self.image_widgets:
            widget.set_image(None, "")
            widget.status_label.setText("等待中...")
            widget.status_label.setStyleSheet("color: #FF9800; font-size: 12px;")

        # 获取参数
        model_id = config_manager.get('image_models.default', 'bozoyan/F_fei')
        params = config_manager.get('image_params.default', {})

        self.image_worker = ImageGenerationWorker(
            self.current_prompts, model_id, params, len(self.current_prompts)
        )
        self.image_worker.progress_updated.connect(self.on_image_progress)
        self.image_worker.image_generated.connect(self.on_image_generated)
        self.image_worker.finished.connect(self.on_images_finished)

        self.image_worker.start()

    def on_image_progress(self, value, message):
        """图片生成进度更新"""
        self.image_progress.setValue(value)
        self.image_status_label.setText(message)

    def on_image_generated(self, index, image, url):
        """单张图片生成完成"""
        if index < len(self.image_widgets):
            self.image_widgets[index].set_image(image, url)

    def on_images_finished(self, success, images, urls):
        """图片生成完成"""
        self.generate_images_btn.setEnabled(True)
        
        if hasattr(self, 'all_generation_step') and self.all_generation_step == 4:
            self.generate_all_btn.setEnabled(True)
            if success:
                QMessageBox.information(self, "完成", "🎉 一键生成完成！所有分镜脚本和图片已生成！")
            else:
                QMessageBox.warning(self, "完成", "生成过程完成，但部分内容可能生成失败。")
        elif success:
            QMessageBox.information(self, "成功", "图片生成完成！")
        else:
            QMessageBox.warning(self, "警告", "图片生成过程完成，但部分图片生成失败。")

    def export_markdown(self):
        """导出Markdown文件"""
        if not self.current_titles and not self.current_summaries:
            QMessageBox.warning(self, "警告", "没有可导出的内容")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self, "导出Markdown", 
            f"storyboard_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md",
            "Markdown Files (*.md)"
        )

        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write("# 🎬 AI分镜脚本与配图\n\n")
                    f.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
                    f.write("---\n\n")

                    for i in range(self.image_count_spin.value()):
                        f.write(f"## 📺 分镜 {i+1}\n\n")
                        
                        if i < len(self.current_titles) and self.current_titles[i]:
                            f.write(f"**🎭 分镜标题:** {self.current_titles[i]}\n\n")
                        
                        if i < len(self.current_summaries) and self.current_summaries[i]:
                            f.write(f"**📝 分镜描述:** {self.current_summaries[i]}\n\n")
                        
                        if i < len(self.current_prompts) and self.current_prompts[i]:
                            f.write(f"**🎨 AI绘图提示词:** {self.current_prompts[i]}\n\n")
                        
                        if i < len(self.image_widgets) and self.image_widgets[i].image_url:
                            f.write(f"**🖼️ 图片:**\n")
                            f.write(f"![分镜{i+1}]({self.image_widgets[i].image_url})\n\n")
                        
                        f.write("---\n\n")

                QMessageBox.information(self, "成功", f"Markdown文件已保存到: {file_path}")
                
                # 询问是否打开文件
                reply = QMessageBox.question(self, "打开文件", "是否立即打开导出的文件？",
                                           QMessageBox.Yes | QMessageBox.No)
                if reply == QMessageBox.Yes:
                    QDesktopServices.openUrl(QUrl.fromLocalFile(file_path))

            except Exception as e:
                QMessageBox.critical(self, "错误", f"导出失败: {str(e)}")

    def export_all_images(self):
        """导出全部图片"""
        output_dir = QFileDialog.getExistingDirectory(self, "选择导出目录")
        if not output_dir:
            return

        timestamp = datetime.now().strftime('%m%d%H%M%S')
        export_count = 0

        for i, widget in enumerate(self.image_widgets):
            if widget.image:
                try:
                    file_name = f"storyboard_{timestamp}_{i+1}.png"
                    file_path = os.path.join(output_dir, file_name)
                    
                    # 将QImage转换为PIL Image
                    if isinstance(widget.image, QImage):
                        pil_image = Image.fromqimage(widget.image)
                    else:
                        pil_image = Image.fromqpixmap(widget.image)
                    
                    pil_image.save(file_path)
                    export_count += 1
                    
                except Exception as e:
                    logger.error(f"保存图片失败: {e}")

        if export_count > 0:
            QMessageBox.information(self, "成功", f"已导出 {export_count} 张图片到:\n{output_dir}")
        else:
            QMessageBox.warning(self, "警告", "没有可导出的图片")

# 主窗口
class MainWindow(FluentWindow):
    def __init__(self):
        super().__init__()
        self.init_window()
        self.init_navigation()
        self.check_api_key()

    def init_window(self):
        """初始化主窗口"""
        self.setWindowTitle("🎬 BOZO-MCN 分镜脚本与图片生成器 v2.0")
        self.setMinimumSize(1400, 900)

        # 从配置文件读取窗口大小
        width = config_manager.get('ui.window_width', 1600)
        height = config_manager.get('ui.window_height', 1000)
        self.resize(width, height)

    def init_navigation(self):
        """初始化导航栏"""
        # 主功能页面
        self.storyboard_page = StoryboardPage(self)
        self.storyboard_page.setObjectName("storyboard_page")
        self.addSubInterface(
            self.storyboard_page,
            FluentIcon.VIDEO,
            "分镜生成",
            NavigationItemPosition.TOP
        )

        # 设置页面
        self.addSubInterface(
            self.create_settings_page(),
            FluentIcon.SETTING,
            "设置",
            NavigationItemPosition.BOTTOM
        )

    def create_settings_page(self):
        """创建设置页面"""
        page = SmoothScrollArea()
        page.setObjectName("settings_page")
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(20)

        title = SubtitleLabel("⚙️ 设置")
        title.setFont(QFont("", 16, QFont.Bold))
        layout.addWidget(title)

        # API设置
        api_group = QGroupBox("🔑 API设置")
        api_layout = QGridLayout()

        api_layout.addWidget(QLabel("API密钥:"), 0, 0)
        self.api_key_edit = LineEdit()
        self.api_key_edit.setPlaceholderText("请输入ModelScope API密钥...")
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        self.api_key_edit.setText(config_manager.get('api.api_key', ''))
        api_layout.addWidget(self.api_key_edit, 0, 1)

        api_layout.addWidget(QLabel("API基础URL:"), 1, 0)
        self.api_url_edit = LineEdit()
        self.api_url_edit.setText(config_manager.get('api.base_url', 'https://api-inference.modelscope.cn/v1/'))
        api_layout.addWidget(self.api_url_edit, 1, 1)

        api_layout.addWidget(QLabel("文本模型:"), 2, 0)
        self.text_model_edit = LineEdit()
        self.text_model_edit.setText(config_manager.get('api.text_model', 'Qwen/Qwen3-235B-A22B-Thinking-2507'))
        api_layout.addWidget(self.text_model_edit, 2, 1)

        api_group.setLayout(api_layout)
        layout.addWidget(api_group)

        # 界面设置
        ui_group = QGroupBox("🎨 界面设置")
        ui_layout = QGridLayout()

        ui_layout.addWidget(QLabel("默认图片数量:"), 0, 0)
        self.default_image_count_spin = QSpinBox()
        self.default_image_count_spin.setRange(1, 20)
        self.default_image_count_spin.setValue(config_manager.get('ui.default_image_count', 9))
        ui_layout.addWidget(self.default_image_count_spin, 0, 1)

        theme_layout = QHBoxLayout()
        theme_layout.addWidget(QLabel("主题:"))
        
        self.light_radio = RadioButton("浅色")
        self.dark_radio = RadioButton("深色")
        
        current_theme = config_manager.get('ui.theme', 'dark')
        if current_theme == 'dark':
            self.dark_radio.setChecked(True)
        else:
            self.light_radio.setChecked(True)
        
        self.light_radio.clicked.connect(lambda: self.change_theme('light'))
        self.dark_radio.clicked.connect(lambda: self.change_theme('dark'))
        
        theme_layout.addWidget(self.light_radio)
        theme_layout.addWidget(self.dark_radio)
        theme_layout.addStretch()
        
        ui_layout.addLayout(theme_layout, 1, 0, 1, 2)

        ui_group.setLayout(ui_layout)
        layout.addWidget(ui_group)

        # 保存按钮
        save_btn = PrimaryPushButton(FluentIcon.SAVE, "保存设置")
        save_btn.clicked.connect(self.save_settings)
        layout.addWidget(save_btn)

        layout.addStretch()

        page.setWidget(widget)
        page.setWidgetResizable(True)
        return page

    def check_api_key(self):
        """检查API密钥"""
        api_key = config_manager.get('api.api_key', '')
        if not api_key:
            # 显示提示
            InfoBar.warning(
                title="API密钥未配置",
                content="请在设置中配置ModelScope API密钥以使用完整功能",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=5000,
                parent=self
            )

    def change_theme(self, theme):
        """切换主题"""
        config_manager.set('ui.theme', theme)
        if theme == 'dark':
            setTheme(Theme.DARK)
        else:
            setTheme(Theme.LIGHT)

    def save_settings(self):
        """保存设置"""
        config_manager.set('api.api_key', self.api_key_edit.text().strip())
        config_manager.set('api.base_url', self.api_url_edit.text().strip())
        config_manager.set('api.text_model', self.text_model_edit.text().strip())
        config_manager.set('ui.default_image_count', self.default_image_count_spin.value())

        if config_manager.save_config():
            InfoBar.success(
                title="保存成功",
                content="设置已保存",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )
        else:
            InfoBar.error(
                title="保存失败",
                content="设置保存失败，请检查权限",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )

    def closeEvent(self, event):
        """窗口关闭时保存配置"""
        config_manager.set('ui.window_width', self.width())
        config_manager.set('ui.window_height', self.height())
        config_manager.save_config()

        # 清理工作线程
        if hasattr(self, 'storyboard_page'):
            if hasattr(self.storyboard_page, 'image_worker'):
                self.storyboard_page.image_worker.cancel()

        super().closeEvent(event)

def main():
    # 屏蔽 Qt 字体相关的警告日志
    os.environ["QT_LOGGING_RULES"] = "qt.qpa.fonts.warning=false"

    # 设置高DPI支持
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    # 字体替换
    QFont.insertSubstitution("Segoe UI", ".AppleSystemUIFont")
    QFont.insertSubstitution("Microsoft YaHei", "PingFang SC")

    app = QApplication(sys.argv)

    # 设置全局默认字体
    default_font = QFont()
    default_font.setPointSize(12)
    app.setFont(default_font)

    # 设置应用信息
    app.setApplicationName("BOZO-MCN分镜脚本生成器")
    app.setApplicationVersion("2.0")
    app.setOrganizationName("BOZO-MCN")

    # 设置主题
    current_theme = config_manager.get('ui.theme', 'dark')
    if current_theme == 'dark':
        setTheme(Theme.DARK)
    else:
        setTheme(Theme.LIGHT)

    # 创建并显示主窗口
    window = MainWindow()
    window.show()

    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
