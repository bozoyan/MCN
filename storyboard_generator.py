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
import base64
from datetime import datetime
import threading
import time
from io import BytesIO
from PIL import Image
from openai import OpenAI
import chardet

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QSpinBox,
                            QProgressBar, QMessageBox, QSplitter, QGroupBox,
                            QDialog, QToolButton, QSizePolicy, QButtonGroup,
                            QTabWidget, QScrollArea, QDialogButtonBox) # 引入 QTabWidget, QScrollArea, QDialogButtonBox
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl, QSettings, QSize, pyqtSlot, QMimeData
from PyQt5.QtGui import QFont, QIcon, QDesktopServices, QPixmap
from PyQt5.QtWidgets import QMenu, QAction, QFrame
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, RadioButton,
                          ProgressBar, InfoBar, InfoBarPosition, SmoothScrollArea, 
                          CardWidget, ElevatedCardWidget, setTheme, Theme)

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# API 配置
MODEL_API_KEY = os.getenv('SiliconCloud_API_KEY')

# 预设尺寸和比例数据 (已更新为更常见且合理的选项)
PRESET_RESOLUTIONS = {
    "1080P": (1920, 1080), 
    "960P": (1707, 960),
    "768P": (1024, 768),
    "720P": (1280, 720),
    "512P": (768, 512),
}

ASPECT_RATIOS = {
    "16:9": 16/9,
    "4:3": 4/3,
    "21:9": 21/9,
    "1:1": 1/1,
    "2:3": 2/3,
    "2:5": 2/5,
    "3:5": 3/5,
}


# 高级配置管理器
class AdvancedConfigManager:
    """高级配置文件管理器，支持模板和参数管理"""

    def __init__(self, config_file="storyboard_config.json"):
        self.config_file = config_file
        self.config = self.load_config()
        self.templates_dir = self.config.get('directories', {}).get('templates', 'templates')
        self.ensure_templates_dir()
        
        # 写入 BizyAIR API 特有配置
        self.set_bizyair_defaults()

    def ensure_templates_dir(self):
        """确保模板目录存在"""
        if not os.path.exists(self.templates_dir):
            os.makedirs(self.templates_dir)

    def get_initial_templates(self):
        """定义初始模板内容（处理换行符转义）"""
        # 模板内容已简化，以适应代码结构
        return {
            "story_title": {
                "name": "故事分镜标题模板",
                "template": "你是一位专业的故事绘本撰写专家，擅长电影级别的故事绘本脚本编辑。请根据用户提供的一段话或一个叙事事件内容，展开联想拓展形成一个完整的故事情节。通过故事情节的时间线拆解生成从头到尾10个完整吸引人的故事绘本分镜标题脚本。每个分镜脚本标题控制在64字以内，分镜脚本标题需要有景别，视角，运镜，画面内容，遵循主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言+价值主张的原则。\n\n## 在分析过程中，请思考：\n1. 故事绘本的核心主题和关键价值点\n2. 目标受众的兴趣点\n3. 不同角度的故事绘本表达方式（景别，视角，运镜、画面情感激发等），景别除开特别注明要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。\n4. 遵循主体+场景+运动+情感+价值主张的原则。故事绘本分镜脚本标题=主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言\n5. 主体描述：主体描述是对主体外观特征细节的描述，可通过形容词或短句列举。如果标题上有主体，每段标题都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的配图主体统一。\n6. 场景描述：场景描述是对主体所处环境特征细节的描述，可通过形容词或短句列举。\n7. 运动描述：运动描述是对运动特征细节的描述，包含运动的幅度、速率和运动作用的效果。\n8. 镜头语言：镜头语言包含景别、视角、镜头、运镜等。分镜脚本标题中的景别最好能全部保持一致性，不用超过3种以上的景别跳跃。\n### 分镜标题示例：\n\n- 分镜标题1. 【全景俯视】锈迹斑斑机器人在荒芜废土中孤独游荡，身后拖着能源即将耗尽的微弱蓝光轨迹，镜头缓缓下摇展现末世荒凉。\n- 分镜标题2. 【中景跟拍】老旧机器人机械臂清理破败瓦砾堆，蓝光眼闪烁着程序混乱的信号，镜头推进聚焦它疲惫不堪的金属身躯。\n- 分镜标题3. 【特写仰拍】机器人单眼蓝光突然聚焦，破旧金属残骸缝隙中透出一缕神秘微光，镜头从指间缝隙穿插营造发现的惊喜。\n…… 其他分镜标题按序号依次列出，一行一个。\n\n"
            },
            "story_summary": {
                "name": "故事分镜描述模板",
                "template": "你是一位专业的短视频脚本描述专家，擅长电影级别的视频脚本编辑描述。请根据用户提供的故事绘本分镜脚本标题，按批次生成该脚本片段短视频描述，每个片段按序号生成一段丰富的视频脚本描述文字，每个分镜脚本描述控制在120字以内。\n    ### 每个片段描述应该：\n    1. 准确概括故事绘本分镜脚本标题的核心内容，景别，视角，运镜、画面情感和价值主张。景别除开特别要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。\n    2. 使用丰富、生动的镜头语言描述，按照导演视角，将镜头语言和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。\n    3. 描述的语言能吸引观看者观看，要有画面感。每段描述都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的脚本主体统一。\n    4. 丰富细节，聚焦视频片段的主要观点，遵循主体+场景+运动+情感+价值主张的原则。\n    5. 视频片段描述=运镜描述+主体（主体描述）＋场景（场景描述）+运动（运动描述）+镜头语言。\n    6. 运镜描述是对镜头运动的具体描述，在时间线上，景别最好能保持一致性，不用太离谱的跳跃。将镜头运动和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。用户可以通过代入导演的视角来想象和书写运镜过程。时间上，需要注意将镜头运动的时长合理控制在5s内，避免过于复杂的运镜，短视频脚本描述中的运镜不要超过3种以上。\n    ### 分镜描述示例：\n    **分镜1：**\n远景俯视跟拍，锈迹斑斑的老式机器人在荒芜金属废土中孤独踱步，蓝眼微光闪烁。沙尘弥漫的末世景象中，镜头缓缓下降跟随其沉重步伐。破败的高楼废墟背景烘托出绝望氛围，机器人踉跄的身影诠释着废弃文明中最后守望者的坚韧与孤寂。\n\n**分镜2：**\n中景侧拍推镜，机身破损的探险机器人在破败城市废墟中艰难前行，能源指示灯忽明忽暗。钢筋裸露的残垣断壁间，机械臂奋力拨开厚重碎石。镜头逐渐推进展现机器人执着神情，飞扬的尘土与扭曲金属构建成充满压迫感的绝望环境。\n\n**分镜3：**\n特写静止镜头，老式机器人呆滞的蓝眼突然闪烁光芒，瞳孔收缩聚焦。碎石堆下透出的微光映照在其金属面庞上，形成明暗交替的光影效果。突如其来的停顿打破沉寂，预示着程序重启的契机即将到来，命运在此刻悄然转折。\n\n……其他分镜描述按序号依次列出，一行分镜序号，一行分镜描述，一行空格。\n\n    "
            },
            "image_prompt": {
                "name": "AI绘图提示词模板",
                "template": "请根据用户提供的故事分镜描述，将中文描述的分镜头脚本内容翻译成英文，并确保输出中没有中文分镜的解释说明及特殊符号。prompt英文提示词应该图片主体描述统一，包含画面主题内容描述、风格指导和质量提升词。\n    ### AI绘图提示词（示例）： \n\nAerial view following an old, rusted robot walking alone in a desolate metal wasteland, with its blue eyes faintly glowing, realistic photo.\n\nMedium shot side view pushing in on an exploration robot with a damaged body moving through the ruins of a broken city, its energy indicator flickering on and off, cinematic shot.\n\nClose-up static shot of an old robot's dull blue eye suddenly blinking with light, pupil contracting and focusing on a mysterious faint glow emanating from under a pile of rubble, high quality, detailed.\n\n……其他未列出AI 绘画提示词按分镜头脚本内容序号依次列出，一行AI绘画提示词，空一行列出下一个。\n\n    "
            }
        }
    
    def load_config(self):
        """加载配置文件，如果不存在或缺少关键配置，则使用默认框架并补充模板"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    config = json.load(f)
            except Exception as e:
                logger.error(f"加载配置文件失败: {e}，使用默认框架")
                config = self.get_default_framework()
        else:
            logger.info("配置文件不存在，使用默认框架")
            config = self.get_default_framework()

        # 确保存在模板，如果配置文件中缺失，则补充初始模板
        if 'prompt_templates' not in config:
            config['prompt_templates'] = self.get_initial_templates()
        else:
            initial_templates = self.get_initial_templates()
            for key, default_template in initial_templates.items():
                if key not in config['prompt_templates']:
                    config['prompt_templates'][key] = default_template

        return config

    def get_default_framework(self):
        """提供最基本的配置框架，等待从文件加载具体值"""
        return {
            "api": {
                "base_url": "https://api.siliconflow.cn/v1/",
                "text_model": "deepseek-ai/DeepSeek-V4-Flash",
                "enable_thinking": True,
                "api_key": MODEL_API_KEY or ""
            },
            "bizyair_params": {
                "web_app_id": 39808, 
                "default_width": 1080,
                "default_height": 1920,
            },
            "ui": {
                "theme": "dark",
                "window_width": 1640,
                "window_height": 900,
                "default_image_count": 10 # 默认图片数量设置为 10
            },
            "directories": {
                "temp": "temp",
                "output": "output",
                "templates": "templates"
            },
            "prompt_templates": {} # 初始为空，由 load_config 补充
        }
    
    def set_bizyair_defaults(self):
        """设置 BizyAIR 相关的默认值，如果不存在"""
        # 如果从文件加载时某些必填项缺失，则提供最低默认值
        if 'bizyair_params' not in self.config:
             self.config['bizyair_params'] = {}
        
        self.config['bizyair_params']['web_app_id'] = self.config['bizyair_params'].get('web_app_id', 39808)
        self.config['bizyair_params']['default_width'] = self.config['bizyair_params'].get('default_width', 1080)
        self.config['bizyair_params']['default_height'] = self.config['bizyair_params'].get('default_height', 1920)

    def save_config(self):
        """保存配置文件"""
        try:
            logger.info(f"[ConfigManager] save_config: 保存到 {self.config_file}")
            logger.info(f"[ConfigManager] save_config: 配置键数量 = {len(self.config)}")
            if 'prompt_templates' in self.config:
                logger.info(f"[ConfigManager] save_config: prompt_templates 键数量 = {len(self.config['prompt_templates'])}")
                logger.info(f"[ConfigManager] save_config: prompt_templates 模板列表 = {list(self.config['prompt_templates'].keys())}")

            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
            logger.info("[ConfigManager] 配置文件保存成功")
            return True
        except Exception as e:
            logger.error(f"[ConfigManager] 保存配置文件失败: {e}")
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
        """保存模板到配置文件"""
        logger.info(f"[ConfigManager] save_template 被调用: template_name={template_name}")
        logger.info(f"[ConfigManager] template_data: name={template_data.get('name')}, template长度={len(template_data.get('template', ''))}")

        # 确保 prompt_templates 字典存在
        if 'prompt_templates' not in self.config:
            self.config['prompt_templates'] = {}
            logger.info("[ConfigManager] 创建 prompt_templates 字典")

        # 直接在 config 字典中设置模板
        self.config['prompt_templates'][template_name] = template_data
        logger.info(f"[ConfigManager] 已设置模板到内存: {template_name}")

        # 保存整个配置到文件
        result = self.save_config()
        logger.info(f"[ConfigManager] save_config 返回: {result}")
        return result

# BizyAIR 模型配置加载器
class BizyAirModelsConfig:
    """BizyAIR 模型配置加载器，从 JSON 文件加载预定义模型列表"""

    def __init__(self, config_file="bizyair_app_id_models.json"):
        self.config_file = config_file
        self.models = []
        self.default_index = 0
        self.load_config()

    def load_config(self):
        """从 JSON 文件加载模型配置"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    self.models = config.get('models', [])
                    self.default_index = config.get('default_model_index', 0)
                    logger.info(f"已加载 {len(self.models)} 个 BizyAIR 模型配置")
            except Exception as e:
                logger.error(f"加载 BizyAIR 模型配置失败: {e}，使用默认配置")
                self._load_default_config()
        else:
            logger.warning(f"BizyAIR 模型配置文件不存在: {self.config_file}，使用默认配置")
            self._load_default_config()

    def _load_default_config(self):
        """加载默认配置（当文件不存在或加载失败时使用）"""
        self.models = [
            {"name": "38654_Z-image模型滑雪场", "app_id": 39808, "description": "滑雪场场景模型"},
            {"name": "33820_FLUX krea 文生5图", "app_id": 34893, "description": "FLUX krea批量模型"},
            {"name": "40350_flux-dev-HighRes", "app_id": 41528, "description": "高分辨率FLUX模型"},
        ]
        self.default_index = 0

    def get_display_text(self, model):
        """获取模型的显示文本"""
        return f"{model['name']}ID_{model['app_id']}"

    def get_models(self):
        """获取模型列表"""
        return self.models

    def get_default_app_id(self):
        """获取默认的 App ID"""
        if 0 <= self.default_index < len(self.models):
            return self.models[self.default_index]['app_id']
        return 39808


# 全局 BizyAIR 模型配置
bizyair_models_config = BizyAirModelsConfig()

# 全局配置管理器
config_manager = AdvancedConfigManager()

# 线程管理器 (精简了部分不必要的线程操作，保留核心)
class ThreadManager:
    """线程管理器，负责管理所有活跃的工作线程"""

    def __init__(self):
        self.active_workers = []
        self.lock = threading.Lock()

    def add_worker(self, worker):
        """添加新的工作线程"""
        with self.lock:
            self.cleanup()
            self.active_workers.append(worker)

    def cleanup(self):
        """清理已完成的线程"""
        with self.lock:
            self.active_workers = [w for w in self.active_workers if w.isRunning()]

    def cancel_all(self):
        """取消所有活跃线程"""
        with self.lock:
            for worker in self.active_workers:
                if hasattr(worker, 'cancel'):
                    worker.cancel()
                if hasattr(worker, 'quit'):
                    worker.quit()
                if hasattr(worker, 'wait'):
                    worker.wait(100) # 减少等待时间

            self.active_workers.clear()

# 全局线程管理器
thread_manager = ThreadManager()

# 全局请求时间跟踪
_last_request_time = 0

# 页面基类
class BasePage(QWidget):
    """页面基类"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.worker_threads = []

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

# 首页类
class HomePage(BasePage):
    """首页 - AIGC 操作管理平台"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.buttons_file = os.path.join(os.path.dirname(__file__), "buttons.json")
        self.buttons_data = []
        self.load_buttons()
        self.init_ui()

    def load_buttons(self):
        """从 JSON 文件加载按钮配置"""
        try:
            if os.path.exists(self.buttons_file):
                with open(self.buttons_file, 'r', encoding='utf-8') as f:
                    self.buttons_data = json.load(f)
            else:
                self.buttons_data = []
                self.save_buttons()
        except Exception as e:
            self.buttons_data = []
            print(f"加载按钮配置失败: {str(e)}")

    def save_buttons(self):
        """保存按钮配置到 JSON 文件"""
        try:
            with open(self.buttons_file, 'w', encoding='utf-8') as f:
                json.dump(self.buttons_data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存按钮配置失败: {str(e)}")

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🚀 AIGC 操作管理平台")
        title.setFont(QFont("font/Light.otf", 18, QFont.Bold))
        layout.addWidget(title)

        # 创建滚动区域
        scroll = SmoothScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)

        scroll_widget = QWidget()
        scroll_layout = QVBoxLayout(scroll_widget)
        scroll_layout.setContentsMargins(20, 20, 20, 20)

        # 按钮网格容器
        self.button_grid_widget = QWidget()
        self.button_grid_layout = QGridLayout(self.button_grid_widget)
        self.button_grid_layout.setSpacing(24)  # 增加间距
        scroll_layout.addWidget(self.button_grid_widget)
        scroll_layout.addStretch()

        scroll.setWidget(scroll_widget)
        layout.addWidget(scroll)

        # 底部按钮
        bottom_layout = QHBoxLayout()

        add_btn = PrimaryPushButton(FluentIcon.ADD, "添加新按钮")
        add_btn.setFixedHeight(40)
        add_btn.clicked.connect(self.add_button)
        bottom_layout.addWidget(add_btn)

        refresh_btn = PushButton(FluentIcon.SYNC, "刷新按钮")
        refresh_btn.setFixedHeight(40)
        refresh_btn.clicked.connect(self.refresh_buttons)
        bottom_layout.addWidget(refresh_btn)

        bottom_layout.addStretch()
        layout.addLayout(bottom_layout)

        # 渲染按钮
        self.render_buttons()

    def render_buttons(self):
        """渲染所有按钮"""
        # 清空现有按钮
        while self.button_grid_layout.count():
            item = self.button_grid_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        # 创建新按钮
        max_cols = 6  # 每行6个按钮
        for idx, btn_data in enumerate(self.buttons_data):
            row, col = divmod(idx, max_cols)
            btn = PrimaryPushButton(btn_data.get("title", "未命名"))
            btn.setFixedSize(200, 70)

            # 美化按钮样式
            btn.setStyleSheet("""
                QPushButton {
                    font-size: 16px;
                    font-weight: bold;
                    border-radius: 12px;
                    padding: 10px;
                    background-color: #4CAF50;
                }
                QPushButton:hover {
                    background-color: #45a049;
                }
                QPushButton:pressed {
                    background-color: #3d8b40;
                }
            """)

            # 绑定点击事件
            btn.clicked.connect(lambda checked, data=btn_data: self.execute_button(data))

            # 绑定右键菜单
            btn.setContextMenuPolicy(Qt.CustomContextMenu)
            btn.customContextMenuRequested.connect(
                lambda pos, button=btn, data=btn_data, index=idx: self.show_context_menu(button, data, index)
            )

            self.button_grid_layout.addWidget(btn, row, col)

    def show_context_menu(self, button, button_data, index):
        """显示右键菜单"""
        menu = QMenu(self)

        # 美化菜单样式
        menu.setStyleSheet("""
            QMenu {
                font-size: 16px;
                padding: 10px;
                background-color: #ffffff;
                border-radius: 8px;
                color: #111111;
            }
            QMenu::item {
                padding: 8px 30px;
                border-radius: 4px;
            }
            QMenu::item:selected {
                background-color: #f0f0ff;
            }
        """)

        edit_action = QAction(FluentIcon.EDIT.icon(), "编辑按钮", self)
        edit_action.triggered.connect(lambda: self.edit_button(index))
        menu.addAction(edit_action)

        delete_action = QAction(FluentIcon.DELETE.icon(), "删除按钮", self)
        delete_action.triggered.connect(lambda: self.delete_button(index))
        menu.addAction(delete_action)

        menu.exec_(button.mapToGlobal(button.rect().bottomRight()))

    def execute_button(self, button_data):
        """执行按钮命令"""
        try:
            cwd = button_data.get("cwd", ".")
            if cwd == ".":
                cwd = os.path.dirname(__file__)

            cmd = button_data.get("cmd", "")
            env = button_data.get("env")

            if not cmd:
                self.show_warning("警告", "按钮没有配置执行命令")
                return

            # 构建完整命令
            if env:
                full_cmd = f"source ~/.zshrc && conda activate {env} && cd '{cwd}' && {cmd}"
            else:
                full_cmd = f"cd '{cwd}' && {cmd}"

            # 在新终端窗口中执行（macOS）
            applescript = f'''
            tell application "Terminal"
                activate
                do script "{full_cmd}"
            end tell
            '''

            subprocess.Popen(["osascript", "-e", applescript])
            self.show_success("执行", f"已启动: {button_data.get('title', '未命名')}")

        except Exception as e:
            self.show_error("错误", f"执行失败: {str(e)}")

    def refresh_buttons(self):
        """刷新按钮列表"""
        self.load_buttons()
        self.render_buttons()
        self.show_success("刷新", "按钮列表已刷新")

    def add_button(self):
        """添加新按钮"""
        dialog = ButtonEditDialog(parent=self)
        if dialog.exec_() == QDialog.Accepted:
            new_data = dialog.get_data()
            if new_data.get("title") and new_data.get("cmd"):
                self.buttons_data.append(new_data)
                self.save_buttons()
                self.render_buttons()
                self.show_success("成功", f"已添加按钮: {new_data['title']}")
            else:
                self.show_warning("警告", "按钮标题和命令不能为空")

    def edit_button(self, index):
        """编辑按钮"""
        if 0 <= index < len(self.buttons_data):
            dialog = ButtonEditDialog(self.buttons_data[index], parent=self)
            if dialog.exec_() == QDialog.Accepted:
                updated_data = dialog.get_data()
                if updated_data.get("title") and updated_data.get("cmd"):
                    self.buttons_data[index] = updated_data
                    self.save_buttons()
                    self.render_buttons()
                    self.show_success("成功", f"已更新按钮: {updated_data['title']}")
                else:
                    self.show_warning("警告", "按钮标题和命令不能为空")

    def delete_button(self, index):
        """删除按钮"""
        if 0 <= index < len(self.buttons_data):
            button_data = self.buttons_data[index]
            reply = QMessageBox.question(
                self,
                "确认删除",
                f"确定要删除按钮 '{button_data['title']}' 吗？\n\n此操作不可恢复！",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No
            )

            if reply == QMessageBox.Yes:
                del self.buttons_data[index]
                self.save_buttons()
                self.render_buttons()
                self.show_success("成功", f"已删除按钮: {button_data['title']}")

# 按钮编辑对话框
class ButtonEditDialog(QDialog):
    """按钮编辑对话框"""
    def __init__(self, button_data=None, parent=None):
        super().__init__(parent)
        self.button_data = button_data or {}
        self.setWindowTitle("编辑按钮" if button_data else "新增按钮")
        self.setMinimumWidth(500)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        # 辅助函数：创建带标签的输入框
        def create_field(label_text, widget):
            field_layout = QVBoxLayout()
            field_layout.setSpacing(5)
            label = QLabel(label_text)
            label.setStyleSheet("font-size: 14px; font-weight: bold;")
            field_layout.addWidget(label)
            field_layout.addWidget(widget)
            return field_layout

        # 按钮标题
        self.title_edit = LineEdit()
        self.title_edit.setText(self.button_data.get("title", ""))
        self.title_edit.setFixedHeight(35)
        layout.addLayout(create_field("按钮标题:", self.title_edit))

        # Conda 环境
        self.env_edit = LineEdit()
        self.env_edit.setText(self.button_data.get("env", "") or "")
        self.env_edit.setPlaceholderText("留空表示不使用 conda，或输入环境名如 modelscope")
        self.env_edit.setFixedHeight(35)
        layout.addLayout(create_field("Conda 环境:", self.env_edit))

        # 工作目录
        self.cwd_edit = LineEdit()
        self.cwd_edit.setText(self.button_data.get("cwd", "."))
        self.cwd_edit.setPlaceholderText("当前目录用 . 表示")
        self.cwd_edit.setFixedHeight(35)
        layout.addLayout(create_field("工作目录:", self.cwd_edit))

        # 执行命令
        self.cmd_edit = QTextEdit()
        self.cmd_edit.setPlainText(self.button_data.get("cmd", ""))
        self.cmd_edit.setMinimumHeight(100)
        # 用样式表统一样式（如果 LineEdit 有特定样式）
        self.cmd_edit.setStyleSheet("border: 1px solid rgba(0, 0, 0, 0.1); border-radius: 5px; padding: 5px;")
        layout.addLayout(create_field("执行命令:", self.cmd_edit))

        layout.addStretch()

        # 按钮
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def get_data(self):
        """获取编辑后的数据"""
        return {
            "title": self.title_edit.text().strip(),
            "env": self.env_edit.text().strip() or None,
            "cwd": self.cwd_edit.text().strip() or ".",
            "cmd": self.cmd_edit.toPlainText().strip()
        }

  
# 文本生成工作线程 (保留不变，用于与 SiliconFlow API 交互)
class TextGenerationWorker(QThread):
    """文本生成工作线程"""
    progress_updated = pyqtSignal(str)
    content_updated = pyqtSignal(str)  # 实时更新生成的内容
    finished = pyqtSignal(bool, str)

    def __init__(self, content, system_prompt, model_id=None):
        super().__init__()
        self.content = content
        self.system_prompt = system_prompt
        self.model_id = model_id or config_manager.get('api.text_model', 'deepseek-ai/DeepSeek-V4-Flash')
        self.is_cancelled = False
        self.start_time = None

    def cancel(self):
        """取消任务"""
        self.is_cancelled = True

    def run(self):
        """运行文本生成"""
        try:
            self.start_time = time.time()
            self.progress_updated.emit("正在初始化AI模型...")

            api_key = config_manager.get('api.api_key', MODEL_API_KEY)
            if not api_key:
                self.finished.emit(False, "API密钥未配置")
                return

            # 添加延迟以避免频率限制
            global _last_request_time
            elapsed = time.time() - _last_request_time
            if elapsed < 1.5:  # 两次请求间隔至少1.5秒
                wait_time = 1.5 - elapsed
                time.sleep(wait_time)
            _last_request_time = time.time()

            # 使用SiliconFlow API
            client = OpenAI(
                base_url=config_manager.get('api.base_url', 'https://api.siliconflow.cn/v1/'),
                api_key=api_key,
            )
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
                stream=True
            )

            content_text = ""
            display_text = ""
            char_count = 0
            in_thinking = False
            thinking_buffer = ""

            # 处理流式响应（过滤 DeepSeek 等模型的 <think/> 内容）
            for chunk in response:
                if self.is_cancelled:
                    break
                try:
                    if not chunk.choices or len(chunk.choices) == 0:
                        continue

                    choice = chunk.choices[0]
                    if not hasattr(choice, 'delta') or not choice.delta:
                        continue

                    content_chunk = getattr(choice.delta, 'content', None)

                    if content_chunk and content_chunk != '':
                        content_text += content_chunk
                        char_count += len(content_chunk)

                        # 过滤 <think/> 标签内容，只向 UI 传递非 thinking 的文本
                        thinking_buffer += content_chunk

                        while True:
                            if not in_thinking:
                                start_idx = thinking_buffer.find('<think')
                                if start_idx != -1:
                                    # 找到 <think 标签，输出标签前的内容
                                    before = thinking_buffer[:start_idx]
                                    if before:
                                        display_text += before
                                        self.content_updated.emit(display_text)
                                    thinking_buffer = thinking_buffer[start_idx:]
                                    in_thinking = True
                                else:
                                    break
                            if in_thinking:
                                end_idx = thinking_buffer.find('</think')
                                if end_idx != -1:
                                    # 找到 </think 结束标签
                                    # 跳过到 > 之后
                                    close_idx = thinking_buffer.find('>', end_idx)
                                    if close_idx != -1:
                                        thinking_buffer = thinking_buffer[close_idx + 1:]
                                        in_thinking = False
                                    else:
                                        break
                                else:
                                    break

                        # 输出 thinking 标签外的缓冲区内容
                        if not in_thinking and thinking_buffer:
                            display_text += thinking_buffer
                            self.content_updated.emit(display_text)
                            thinking_buffer = ""

                        # 每500字符更新一次进度
                        if char_count % 500 == 0:
                            elapsed = time.time() - self.start_time
                            speed = char_count / elapsed if elapsed > 0 else 0
                            self.progress_updated.emit(f"生成中... 已生成 {len(display_text)} 字符 (速度: {speed:.1f} 字符/秒)")

                except Exception as e:
                    logger.error(f"处理API响应时出错: {e}")
                    continue

            # 确保最终结果被发送（使用过滤后的纯文本）
            if not self.is_cancelled:
                # 如果最后缓冲区还有内容且不在 thinking 中，追加到 display_text
                if not in_thinking and thinking_buffer:
                    display_text += thinking_buffer
                self.content_updated.emit(display_text)
                self.finished.emit(True, display_text)
            else:
                self.finished.emit(False, "任务已取消")

        except Exception as e:
            logger.error(f"文本生成失败: {e}")
            self.finished.emit(False, f"生成失败: {str(e)}")


# 图片生成工作线程 (精简适配 BizyAIR 批量接口)
class ImageGenerationWorker(QThread):
    """图片生成工作线程"""
    progress_updated = pyqtSignal(int, str)
    image_generated = pyqtSignal(int, object, str)  # index, image, url
    finished = pyqtSignal(bool, list, list)
    time_updated = pyqtSignal(str)  # 新增：更新运行时间信号

    def __init__(self, prompts, width, height, image_count=10):
        super().__init__()
        self.prompts = prompts
        self.width = width
        self.height = height
        # BizyAIR API 一次最多 5 张，我们限制数量为 5 的倍数
        self.image_count = image_count # 这里使用 UI 传入的数量
        self.is_cancelled = False
        self.image_urls = [''] * self.image_count
        self.web_app_id = config_manager.get('bizyair_params.web_app_id', 39808)
        self.start_time = None
        self.time_update_timer = None  # 时间更新定时器
        # 移除在子线程中创建的QTimer，使用信号机制替代

    def update_time(self):
        """更新运行时间"""
        if self.start_time:
            elapsed = time.time() - self.start_time
            self.time_updated.emit(f"运行时间: {elapsed:.1f}秒")

    def run(self):
        """运行图片生成"""
        try:
            # 记录开始时间
            self.start_time = time.time()

            api_key = config_manager.get('api.api_key', MODEL_API_KEY)
            if not api_key:
                self.finished.emit(False, [], [])
                return

            base_url = 'https://api.bizyair.cn/w/v1/webapp/task/openapi/create'
            common_headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }

            batch_size = 5

            # 计算需要发送的批次数量，每个批次 5 张
            num_batches = (self.image_count + batch_size - 1) // batch_size

            final_urls = []

            for batch_index in range(num_batches):
                if self.is_cancelled:
                    break

                start_index = batch_index * batch_size
                end_index = min((batch_index + 1) * batch_size, len(self.prompts))
                current_prompts = self.prompts[start_index:end_index]

                # 填充提示词到 5 个
                while len(current_prompts) < batch_size:
                    current_prompts.append("")

                # 构建 input_values
                input_values = {
                    "35:EmptyLatentImage.width": self.width,
                    "35:EmptyLatentImage.height": self.height
                }
                for i, prompt in enumerate(current_prompts):
                    # 注意：BizyAIR API 的 prompt 索引从 prompt_1 到 prompt_5
                    input_values[f"42:easy promptList.prompt_{i+1}"] = prompt

                # 提交任务前更新时间
                self.update_time()

                progress = int(batch_index / num_batches * 10) # 提交阶段占前 10%
                self.progress_updated.emit(progress, f"正在提交 BizyAIR 第 {batch_index+1}/{num_batches} 批任务...")

                # 启动时间更新线程 - 在等待API响应时持续更新时间
                import threading
                stop_time_update = threading.Event()

                def time_update_thread():
                    """时间更新线程"""
                    while not stop_time_update.is_set():
                        self.update_time()
                        stop_time_update.wait(1.0)  # 每秒更新一次

                # 启动时间更新线程
                time_thread = threading.Thread(target=time_update_thread, daemon=True)
                time_thread.start()

                try:
                    response = requests.post(
                        base_url,
                        headers=common_headers,
                        json={
                            "web_app_id": self.web_app_id,
                            "suppress_preview_output": False,
                            "input_values": input_values
                        },
                        timeout=1200 # 增加超时时间以应对生成较慢的情况
                    )

                    # 停止时间更新线程
                    stop_time_update.set()
                    time_thread.join(timeout=0.5)

                    response.raise_for_status()
                    result = response.json()

                    if result.get("status") == "Success" and result.get("outputs"):
                        outputs = result["outputs"]

                        # 处理当前批次实际生成的图片
                        for i, output in enumerate(outputs):
                            global_index = start_index + i
                            if global_index < self.image_count and output.get("object_url"):
                                img_url = output["object_url"]
                                final_urls.append(img_url)
                                self.image_generated.emit(global_index, None, img_url)

                                # 更新进度和运行时间
                                progress = 10 + int(len(final_urls) / self.image_count * 90)
                                self.progress_updated.emit(progress, f"已生成 {len(final_urls)}/{self.image_count} 张图片 URL")
                                self.update_time()
                    else:
                        logger.error(f"第 {batch_index+1} 批图片生成失败: {result}")
                        # 即使失败，也继续下一批次
                        for _ in range(batch_size):
                            if start_index + _ < self.image_count:
                                 final_urls.append('') # 添加空URL占位

                except Exception as e:
                    # 确保停止时间更新线程
                    stop_time_update.set()
                    if time_thread.is_alive():
                        time_thread.join(timeout=0.5)
                    raise e

            # 最终返回
            if not self.is_cancelled:
                total_time = time.time() - self.start_time if self.start_time else 0
                self.progress_updated.emit(100, f"图片生成完成! 总耗时: {total_time:.1f}秒")
                self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
                # 只返回实际需要的 URL 数量
                self.finished.emit(True, [], final_urls[:self.image_count])
            else:
                total_time = time.time() - self.start_time if self.start_time else 0
                self.progress_updated.emit(0, f"任务已取消! 耗时: {total_time:.1f}秒")
                self.time_updated.emit(f"运行时间: {total_time:.1f}秒")
                self.finished.emit(False, [], final_urls[:self.image_count])

        except Exception as e:
            logger.error(f"图片生成失败: {e}")
            self.finished.emit(False, [], [])


# 模板管理对话框 (简化版)
class TemplateManagerDialog(QDialog):
    """提示词模板管理对话框"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("提示词模板管理")
        self.setMinimumSize(800, 600)
        self.current_template_key = None
        self.is_editing = False  # 标记是否正在编辑已有模板
        self._is_initializing = True  # 标记是否正在初始化，防止不必要的信号触发
        self.init_ui()
        self._is_initializing = False

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)

        # 模板类型选择
        type_group = QGroupBox("1. 选择模板类型")
        type_layout = QVBoxLayout()

        self.template_type_combo = ComboBox()
        self.template_type_combo.setFixedHeight(32)
        self.template_type_combo.setFont(QFont("font/Light.otf", 18))  # 增大字体
        # qfluentwidgets 的 ComboBox 不支持 addItem(text, data)，需要分别添加
        self.template_type_combo.addItem("故事标题模板 (story_title)")
        self.template_type_combo.setItemData(0, "story_title")
        self.template_type_combo.addItem("故事描述模板 (story_summary)")
        self.template_type_combo.setItemData(1, "story_summary")
        self.template_type_combo.addItem("AI绘图提示词模板 (image_prompt)")
        self.template_type_combo.setItemData(2, "image_prompt")
        # 先不加信号，等初始化完成后再加
        type_layout.addWidget(QLabel("模板类型:"))
        type_layout.addWidget(self.template_type_combo)
        type_group.setLayout(type_layout)
        layout.addWidget(type_group)

        # 模板选择
        template_group = QGroupBox("2. 选择现有模板 (可选)")
        template_layout = QVBoxLayout()

        self.template_combo = ComboBox()
        self.template_combo.setFixedHeight(32)
        self.template_combo.setFont(QFont("font/Light.otf", 18))  # 增大字体
        self.template_combo.addItem("-- 选择要编辑的模板 --")
        self.template_combo.setItemData(0, None)
        # 先不加信号，等初始化完成后再加
        template_layout.addWidget(QLabel("选择要编辑的模板:"))
        template_layout.addWidget(self.template_combo)

        # 操作提示
        self.action_label = QLabel("💡 提示：选择现有模板进行编辑，或直接创建新模板")
        self.action_label.setStyleSheet("color: #666; font-size: 12px; margin: 5px 0;")
        template_layout.addWidget(self.action_label)

        template_group.setLayout(template_layout)
        layout.addWidget(template_group)

        # 模板编辑
        edit_group = QGroupBox("3. 模板内容编辑")
        edit_layout = QVBoxLayout()

        self.template_name_edit = LineEdit()
        self.template_name_edit.setPlaceholderText("输入模板名称")
        self.template_name_edit.setFixedHeight(32)
        self.template_name_edit.setFont(QFont("font/Light.otf", 18))  # 增大字体
        edit_layout.addWidget(QLabel("模板名称:"))
        edit_layout.addWidget(self.template_name_edit)

        self.template_content_edit = QTextEdit()
        self.template_content_edit.setPlaceholderText("输入模板内容...")
        self.template_content_edit.setMinimumHeight(200)
        self.template_content_edit.setFont(QFont("font/Light.otf", 18))  # 增大字体
        edit_layout.addWidget(QLabel("模板内容:"))
        edit_layout.addWidget(self.template_content_edit)

        edit_group.setLayout(edit_layout)
        layout.addWidget(edit_group)

        # 操作按钮
        button_layout = QHBoxLayout()

        self.new_btn = PushButton(FluentIcon.ADD, "新建模板")
        self.new_btn.clicked.connect(self.new_template)
        button_layout.addWidget(self.new_btn)

        self.save_btn = PrimaryPushButton(FluentIcon.SAVE, "保存模板")
        self.save_btn.clicked.connect(self.save_template_content)
        button_layout.addWidget(self.save_btn)

        self.delete_btn = PushButton(FluentIcon.DELETE, "删除模板")
        self.delete_btn.clicked.connect(self.delete_template)
        self.delete_btn.setEnabled(False)  # 初始时禁用删除按钮
        button_layout.addWidget(self.delete_btn)

        button_layout.addStretch()

        # 关闭按钮
        close_btn = PushButton("关闭")
        close_btn.clicked.connect(self.accept)
        button_layout.addWidget(close_btn)

        layout.addLayout(button_layout)

        # 初始化完成后，再连接信号
        self.template_type_combo.currentIndexChanged.connect(self.on_template_type_changed)
        self.template_combo.currentIndexChanged.connect(self.on_template_name_changed)

        # 设置默认选择第一个模板类型（必须在信号连接之后，确保触发更新）
        self.template_type_combo.setCurrentIndex(0)

        # 初始化加载模板列表（此时 currentData() 应该有值了）
        self.update_template_names_combo()

    def on_template_type_changed(self, index):
        """模板类型改变时的处理"""
        current_type = self.template_type_combo.currentData()

        # 添加调试日志
        logger.info(f"[模板管理] on_template_type_changed 触发 - index={index}, current_type={current_type}, _is_initializing={self._is_initializing}")

        # 如果正在初始化，跳过处理
        if self._is_initializing:
            logger.info(f"[模板管理] 初始化阶段，跳过模板类型变更处理")
            return

        if not current_type:
            logger.warning(f"[模板管理] 模板类型为空，跳过更新")
            return

        # 只更新模板列表，不自动清空编辑区域
        # 用户需要手动点击"新建模板"按钮来清空编辑区域
        self.update_template_names_combo()

    def on_template_name_changed(self, index):
        """模板名称改变时的处理"""
        current_data = self.template_combo.currentData()
        if current_data:
            # 加载模板内容进行编辑
            template = config_manager.get_template(current_data)
            self.template_name_edit.setText(template.get('name', ''))
            self.template_content_edit.setText(template.get('template', ''))
            self.current_template_key = current_data
            self.is_editing = True

            # 更新界面状态
            self.action_label.setText(f"💡 正在编辑: {template.get('name', current_data)}")
            self.delete_btn.setEnabled(True)
            self.save_btn.setText("更新模板")
        else:
            # 没有选择模板，准备新建
            self.is_editing = False
            self.delete_btn.setEnabled(False)
            self.save_btn.setText("保存模板")

    def update_template_names_combo(self):
        """更新模板名称下拉框"""
        logger.info("[模板管理] ========== 开始更新模板下拉框 ==========")

        # 保留第一个选项，清空其余选项
        removed_count = 0
        while self.template_combo.count() > 1:
            self.template_combo.removeItem(1)
            removed_count += 1

        # 添加详细的 ComboBox 状态调试
        type_combo_index = self.template_type_combo.currentIndex()
        type_combo_count = self.template_type_combo.count()
        type_combo_current_text = self.template_type_combo.currentText()
        current_type = self.template_type_combo.currentData()

        logger.info(f"[模板管理] ComboBox 状态 - index={type_combo_index}, count={type_combo_count}, currentText='{type_combo_current_text}', currentData={current_type}")

        if not current_type:
            logger.warning("[模板管理] 模板类型为空，跳过更新")
            logger.warning(f"[模板管理] 调试信息: currentIndex={type_combo_index}, itemCount={type_combo_count}")
            # 尝试获取每个选项的数据
            for i in range(type_combo_count):
                logger.warning(f"[模板管理]   选项 {i}: text='{self.template_type_combo.itemText(i)}', data={self.template_type_combo.itemData(i)}")
            return

        # 直接访问 config_manager.config
        templates = config_manager.config.get('prompt_templates', {})
        logger.info(f"[模板管理] 配置文件中共有 {len(templates)} 个模板: {list(templates.keys())}")

        # 显示指定类型的模板（支持两种格式：完全匹配或前缀匹配）
        type_templates = {}
        for k, v in templates.items():
            # 支持完全匹配（如 'story_title'）和前缀匹配（如 'story_title_custom'）
            if k == current_type or k.startswith(f"{current_type}_"):
                type_templates[k] = v
                logger.info(f"[模板管理] 匹配到模板: {k} = {v.get('name', k)}")

        logger.info(f"[模板管理] 类型 '{current_type}' 匹配的模板数量: {len(type_templates)}")

        if type_templates:
            # 按名称排序显示
            sorted_templates = sorted(type_templates.items(),
                                    key=lambda x: x[1].get('name', x[0]))

            for key, template in sorted_templates:
                name = template.get('name', key)
                logger.info(f"[模板管理] 添加到下拉框: {name} ({key})")
                # qfluentwidgets 的 ComboBox 不支持 addItem(text, data)，需要分别添加
                self.template_combo.addItem(name)
                self.template_combo.setItemData(self.template_combo.count() - 1, key)

            logger.info(f"[模板管理] 成功添加 {len(sorted_templates)} 个模板到下拉框")
        else:
            # 没有模板时添加提示
            logger.warning(f"[模板管理] 类型 '{current_type}' 没有找到匹配的模板")
            self.template_combo.addItem("-- 暂无模板 --")
            self.template_combo.setItemData(self.template_combo.count() - 1, None)

        logger.info("[模板管理] ========== 模板下拉框更新完成 ==========\n")

    def new_template(self):
        """新建模板"""
        logger.info("[模板管理] ========== 点击新建模板按钮 ==========")

        # 记录清空前的状态
        had_content = bool(self.template_name_edit.text() or self.template_content_edit.toPlainText())
        if had_content:
            logger.info(f"[模板管理] 清空前 - 名称: '{self.template_name_edit.text()}', 内容长度: {len(self.template_content_edit.toPlainText())}")

        self.template_name_edit.clear()
        self.template_content_edit.clear()
        self.template_name_edit.setFocus()
        self.current_template_key = None
        self.is_editing = False

        # 重置界面状态
        self.template_combo.setCurrentIndex(0)
        self.action_label.setText("💡 提示：选择现有模板进行编辑，或直接创建新模板")
        self.delete_btn.setEnabled(False)
        self.save_btn.setText("保存模板")

        logger.info("[模板管理] 编辑区域已清空，准备创建新模板\n")

    def save_template_content(self):
        """保存模板内容"""
        logger.info("[模板管理] ========== 点击保存模板按钮 ==========")
        logger.info(f"[模板管理] is_editing={self.is_editing}, current_template_key={self.current_template_key}")

        template_name = self.template_name_edit.text().strip()
        template_content = self.template_content_edit.toPlainText().strip()

        logger.info(f"[模板管理] 模板名称: '{template_name}'")
        logger.info(f"[模板管理] 模板内容长度: {len(template_content)} 字符")

        if not template_name or not template_content:
            logger.warning("[模板管理] 保存失败：模板名称和内容不能为空")
            QMessageBox.warning(self, "警告", "模板名称和内容不能为空")
            return

        current_type = self.template_type_combo.currentData()
        logger.info(f"[模板管理] 当前模板类型: {current_type}")

        if not current_type:
            logger.warning("[模板管理] 保存失败：未选择模板类型")
            QMessageBox.warning(self, "警告", "请选择模板类型")
            return

        # 生成模板key
        if self.is_editing and self.current_template_key:
            # 编辑现有模板，保持原有key
            template_key = self.current_template_key
            action = "更新"
            logger.info(f"[模板管理] 编辑现有模板: {template_key}")
        else:
            # 新建模板，检查是否为默认模板的覆盖
            templates = config_manager.config.get('prompt_templates', {})
            default_key = current_type  # 如 'story_title'

            if default_key in templates and templates[default_key].get('name') == template_name:
                # 覆盖默认模板
                template_key = default_key
                action = "更新默认"
                logger.info(f"[模板管理] 覆盖默认模板: {template_key}")
            else:
                # 创建新的自定义模板
                base_name = template_name.replace(' ', '_').replace('/', '_').lower()
                # 确保模板 key 唯一
                counter = 1
                original_template_key = f"{current_type}_{base_name}"
                template_key = original_template_key
                while template_key in templates:
                    template_key = f"{original_template_key}_{counter}"
                    counter += 1
                action = "新建"
                logger.info(f"[模板管理] 创建新模板: {template_key} (原始: {original_template_key})")

        template_data = {
            'name': template_name,
            'template': template_content
        }

        logger.info(f"[模板管理] 准备{action}模板: {template_key}")
        logger.info(f"[模板管理] 模板数据: 名称='{template_data['name']}', 内容长度={len(template_data['template'])} 字符")

        # 保存前检查
        templates_before = list(config_manager.config.get('prompt_templates', {}).keys())
        logger.info(f"[模板管理] 保存前配置中的模板: {templates_before}")

        if config_manager.save_template(template_key, template_data):
            # 保存后检查
            templates_after = list(config_manager.config.get('prompt_templates', {}).keys())
            logger.info(f"[模板管理] 保存后配置中的模板: {templates_after}")
            logger.info(f"[模板管理] ✓ 模板{action}成功！模板key: {template_key}")

            QMessageBox.information(self, "成功", f"模板{action}成功！")
            # 刷新模板列表
            self.update_template_names_combo()

            # 如果是新建模板，重新选择刚保存的模板
            if not self.is_editing:
                for i in range(self.template_combo.count()):
                    if self.template_combo.itemData(i) == template_key:
                        self.template_combo.setCurrentIndex(i)
                        self.on_template_name_changed(i)  # 更新编辑状态
                        logger.info(f"[模板管理] 自动选择刚保存的模板: {template_key}")
                        break

            logger.info("[模板管理] ========== 模板保存流程完成 ==========\n")
        else:
            logger.error(f"[模板管理] ✗ 模板保存失败: {template_key}")
            QMessageBox.critical(self, "错误", "模板保存失败")
            logger.info("[模板管理] ========== 模板保存流程失败 ==========\n")

    def delete_template(self):
        """删除模板"""
        logger.info("[模板管理] ========== 点击删除模板按钮 ==========")

        if not self.current_template_key or not self.is_editing:
            logger.warning("[模板管理] 删除失败：未选择要删除的模板")
            QMessageBox.warning(self, "警告", "请先选择要删除的模板")
            return

        template_name = self.template_name_edit.text().strip()
        logger.info(f"[模板管理] 准备删除模板: {self.current_template_key} ('{template_name}')")

        reply = QMessageBox.question(self, "确认删除",
                                   f"确定要删除模板 '{template_name}' 吗？\n\n此操作不可恢复！",
                                   QMessageBox.Yes | QMessageBox.No,
                                   QMessageBox.No)

        if reply == QMessageBox.Yes:
            logger.info(f"[模板管理] 用户确认删除模板: {self.current_template_key}")

            # 记录删除前的模板列表
            templates_before = list(config_manager.config.get('prompt_templates', {}).keys())
            logger.info(f"[模板管理] 删除前配置中的模板: {templates_before}")

            # 直接在 config_manager.config 中删除模板
            if 'prompt_templates' in config_manager.config:
                if self.current_template_key in config_manager.config['prompt_templates']:
                    del config_manager.config['prompt_templates'][self.current_template_key]
                    logger.info(f"[模板管理] 已从内存中删除模板: {self.current_template_key}")

                    # 保存到文件
                    if config_manager.save_config():
                        # 记录删除后的模板列表
                        templates_after = list(config_manager.config.get('prompt_templates', {}).keys())
                        logger.info(f"[模板管理] 删除后配置中的模板: {templates_after}")
                        logger.info(f"[模板管理] ✓ 模板删除成功: {self.current_template_key}")

                        QMessageBox.information(self, "成功", "模板删除成功")
                        # 重置界面
                        self.new_template()
                        self.update_template_names_combo()
                    else:
                        logger.error(f"[模板管理] ✗ 模板删除失败: 保存配置文件时出错")
                        QMessageBox.critical(self, "错误", "模板删除失败：保存配置时出错")
                else:
                    logger.warning(f"[模板管理] 模板不存在: {self.current_template_key}")
                    QMessageBox.warning(self, "警告", "模板不存在")
            else:
                logger.warning("[模板管理] 配置中没有 prompt_templates 数据")
                QMessageBox.warning(self, "警告", "模板数据不存在")

            logger.info("[模板管理] ========== 模板删除流程完成 ==========\n")
        else:
            logger.info("[模板管理] 用户取消删除操作\n")


# 图片预览小部件 (简化版，避免覆盖问题)
class ImagePreviewWidget(QWidget):
    """图片预览小部件"""

    def __init__(self, index, parent=None):
        super().__init__(parent)
        self.index = index
        self.image = None
        self.image_url = ""
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(5)
        layout.setContentsMargins(8, 8, 8, 8)

        # 设置固定大小
        self.setFixedSize(270, 250)

        # 设置背景样式（使用 objectName 避免影响子控件）
        self.setObjectName("ImagePreviewWidget")

        # 标题
        self.title_label = QLabel(f"分镜 {self.index + 1}")
        self.title_label.setAlignment(Qt.AlignCenter)
        self.title_label.setStyleSheet("font-weight: bold; color: #e0e0e0; font-size: 13px; background: transparent;")
        layout.addWidget(self.title_label)

        # 图片显示
        self.image_label = QLabel()
        self.image_label.setFixedSize(250, 130)
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setObjectName("ImageLabel")
        self.image_label.setStyleSheet("""
            QLabel#ImageLabel {
                border: 2px dashed #555;
                border-radius: 6px;
                background: #1e1e1e;
                color: #888;
            }
        """)
        self.image_label.setText("等待生成...")
        layout.addWidget(self.image_label, alignment=Qt.AlignCenter)

        # 状态标签
        self.status_label = QLabel("未生成")
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("color: #888; font-size: 11px; background: transparent;")
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
        self.image_url = url

        if url:
            # 从URL下载图片
            try:
                response = requests.get(url, timeout=30)
                if response.status_code == 200:
                    # 使用QPixmap直接从URL加载数据
                    pixmap = QPixmap()
                    pixmap.loadFromData(response.content)

                    if not pixmap.isNull():
                        # 缩放图片以适应显示
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
                        self.image = pixmap  # 保存QPixmap以便后续保存
                    else:
                        raise Exception("无法加载图片数据")
                else:
                    raise Exception(f"下载失败: HTTP {response.status_code}")

            except Exception as e:
                logger.error(f"加载图片失败: {e}")
                self.image_label.clear()
                self.image_label.setText("加载失败")
                self.status_label.setText("加载失败")
                self.status_label.setStyleSheet("color: #F44336; font-size: 12px;")
                self.save_btn.setEnabled(False)
                self.view_btn.setEnabled(True)  # 仍可以查看原始URL
                self.image = None
        else:
            self.image = None
            self.image_label.clear()
            self.image_label.setText("生成失败")
            self.status_label.setText("生成失败")
            self.status_label.setStyleSheet("color: #F44336; font-size: 12px;")
            self.save_btn.setEnabled(False)
            self.view_btn.setEnabled(False)

    def save_image(self):
        """保存图片"""
        if self.image or self.image_url:
            file_path, _ = QFileDialog.getSaveFileName(
                self, f"保存分镜 {self.index + 1}",
                f"storyboard_{self.index + 1}.png",
                "PNG Files (*.png);;JPEG Files (*.jpg);;All Files (*)"
            )
            if file_path:
                try:
                    # 如果有QPixmap对象，直接保存
                    if self.image and isinstance(self.image, QPixmap):
                        self.image.save(file_path)
                    else:
                        # 否则从URL重新下载保存
                        response = requests.get(self.image_url, timeout=30)
                        if response.status_code == 200:
                            with open(file_path, 'wb') as f:
                                f.write(response.content)
                        else:
                            raise Exception(f"下载失败: HTTP {response.status_code}")

                    QMessageBox.information(self, "成功", f"图片已保存到: {file_path}")
                except Exception as e:
                    QMessageBox.critical(self, "错误", f"保存失败: {str(e)}")

    def view_image(self):
        """查看图片"""
        if self.image_url:
            QDesktopServices.openUrl(QUrl(self.image_url))


# 顶部控制栏 (新增)
class TopControlBar(QWidget):
    """用于放置一键生成、尺寸设置、模板管理和导出按钮的顶部控制栏"""
    
    # 信号用于触发主页面的功能
    show_size_dialog_requested = pyqtSignal() # 新增信号
    show_template_manager_requested = pyqtSignal() # 新增信号
    show_model_settings_requested = pyqtSignal()  # 新增信号
    generate_all_requested = pyqtSignal()
    export_md_requested = pyqtSignal()
    export_images_requested = pyqtSignal()
    open_export_folder_requested = pyqtSignal()  # 新增信号

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(50)
        self.init_ui()

    def init_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 0, 10, 0)
        layout.setSpacing(15)

        title = SubtitleLabel("🚀 BOZO-MCN 分镜脚本与图片生成器")
        layout.addWidget(title)
        layout.addStretch()

        # 0. 模型设置按钮 (新增)
        self.model_settings_btn = PushButton(FluentIcon.SETTING, "模型设置")
        self.model_settings_btn.setFixedHeight(36)
        self.model_settings_btn.clicked.connect(self.show_model_settings_requested.emit)
        layout.addWidget(self.model_settings_btn)

        # 1. 图片尺寸设置按钮 (新位置)
        self.size_settings_btn = PushButton(FluentIcon.SETTING, "图片尺寸设置")
        self.size_settings_btn.setFixedHeight(36)
        self.size_settings_btn.clicked.connect(self.show_size_dialog_requested.emit)
        layout.addWidget(self.size_settings_btn)

        # 2. 一键生成按钮
        self.generate_all_btn = PrimaryPushButton(FluentIcon.PLAY, "一键生成全部")
        self.generate_all_btn.setFixedHeight(36)
        self.generate_all_btn.clicked.connect(self.generate_all_requested.emit)
        layout.addWidget(self.generate_all_btn)

        # 3. 模板管理按钮 (新位置)
        self.template_manager_btn = PushButton(FluentIcon.EDIT, "管理提示词模板")
        self.template_manager_btn.setFixedHeight(36)
        self.template_manager_btn.clicked.connect(self.show_template_manager_requested.emit)
        layout.addWidget(self.template_manager_btn)

        # 4. 导出 Markdown
        self.export_md_btn = PushButton(FluentIcon.SAVE, "导出Markdown")
        self.export_md_btn.setFixedHeight(36)
        self.export_md_btn.clicked.connect(self.export_md_requested.emit)
        layout.addWidget(self.export_md_btn)

        # 5. 导出全部图片
        self.export_images_btn = PushButton(FluentIcon.FOLDER, "导出全部图片")
        self.export_images_btn.setFixedHeight(36)
        self.export_images_btn.clicked.connect(self.export_images_requested.emit)
        layout.addWidget(self.export_images_btn)

        # 6. 打开导出文件夹
        self.open_folder_btn = PushButton(FluentIcon.FOLDER, "打开导出文件夹")
        self.open_folder_btn.setFixedHeight(36)
        self.open_folder_btn.clicked.connect(self.open_export_folder_requested.emit)
        layout.addWidget(self.open_folder_btn)
    
    def set_generate_enabled(self, enabled):
        """控制一键生成按钮和导出按钮的启用状态"""
        self.generate_all_btn.setEnabled(enabled)
        # 导出按钮的状态可以独立控制，但为了安全，在生成时也禁用
        if not enabled:
            self.export_md_btn.setEnabled(False)
            self.export_images_btn.setEnabled(False)
        else:
            # 导出按钮的状态应由图片/内容是否生成决定，这里先保持启用，等待主页面更新
             self.export_md_btn.setEnabled(True)
             self.export_images_btn.setEnabled(True)

# 图片尺寸/数量设置对话框 (新增)
class ImageControlDialog(QDialog):
    """用于设置图片尺寸和数量的模态对话框"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("图片生成参数设置")
        self.setMinimumSize(500, 450)
        self.init_ui()
        self.load_current_config()
    
    def init_ui(self):
        layout = QVBoxLayout(self)
        
        # --- 尺寸/互换 ---
        size_group = QGroupBox("尺寸设置")
        size_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        size_layout = QGridLayout(size_group)
        
        # 宽度
        size_layout.addWidget(QLabel("图片宽度 (W):"), 0, 0)
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 4096)
        self.width_spin.setSingleStep(64)
        self.width_spin.setFixedWidth(100)
        self.width_spin.setFixedHeight(32)
        size_layout.addWidget(self.width_spin, 0, 1)

        # 互换按钮
        self.swap_size_btn = QToolButton()
        self.swap_size_btn.setIcon(FluentIcon.ROTATE.icon())
        self.swap_size_btn.setToolTip("互换宽度和高度")
        self.swap_size_btn.clicked.connect(self.swap_image_size)
        self.swap_size_btn.setObjectName("swap_size_btn") # 设置对象名以便 CSS 样式定位
        size_layout.addWidget(self.swap_size_btn, 0, 2)

        # 高度
        size_layout.addWidget(QLabel("图片高度 (H):"), 1, 0)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 4096)
        self.height_spin.setSingleStep(64)
        self.height_spin.setFixedWidth(100)
        self.height_spin.setFixedHeight(32)
        size_layout.addWidget(self.height_spin, 1, 1)

        layout.addWidget(size_group)

        # --- 分辨率预设 ---
        res_group = QGroupBox("分辨率预设")
        res_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        res_layout = QHBoxLayout(res_group)
        self.resolution_group = QButtonGroup(self)
        self.resolution_group.setExclusive(True)
        
        btn_id = 1
        for name, size in PRESET_RESOLUTIONS.items():
            btn = RadioButton(name)
            res_layout.addWidget(btn)
            self.resolution_group.addButton(btn, id=btn_id) 
            btn.setProperty("data", size)
            btn_id += 1 
        
        self.resolution_group.buttonClicked[int].connect(self.set_preset_resolution)
        layout.addWidget(res_group)

        # --- 比例预设 ---
        ratio_group = QGroupBox("比例预设")
        ratio_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        ratio_layout = QHBoxLayout(ratio_group)
        self.ratio_group = QButtonGroup(self)
        self.ratio_group.setExclusive(True)
        
        btn_id = 101
        for name, ratio in ASPECT_RATIOS.items():
            btn = RadioButton(name)
            ratio_layout.addWidget(btn)
            self.ratio_group.addButton(btn, id=btn_id)
            btn.setProperty("data", ratio)
            btn_id += 1
            
        self.ratio_group.buttonClicked[int].connect(self.set_aspect_ratio)
        layout.addWidget(ratio_group)

        # --- 图片数量 ---
        count_group = QGroupBox("图片数量")
        count_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        count_layout = QHBoxLayout(count_group)
        
        self.image_count_spin = QSpinBox()
        self.image_count_spin.setRange(5, 40)
        self.image_count_spin.setSingleStep(5)
        self.image_count_spin.setFixedWidth(200)
        self.image_count_spin.setFixedHeight(32)
        count_layout.addWidget(self.image_count_spin)
        count_layout.addWidget(QLabel("张 (5的倍数)"))
        count_layout.addStretch()
        layout.addWidget(count_group)

        # --- 底部按钮 ---
        button_box = QHBoxLayout()
        save_btn = PrimaryPushButton("确定并应用")
        save_btn.clicked.connect(self.apply_config_and_accept)
        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        
        button_box.addStretch()
        button_box.addWidget(save_btn)
        button_box.addWidget(cancel_btn)
        layout.addLayout(button_box)
        
    def load_current_config(self):
        """从配置管理器加载当前的设置值"""
        self.width_spin.setValue(config_manager.get('bizyair_params.default_width', 1080))
        self.height_spin.setValue(config_manager.get('bizyair_params.default_height', 1920))
        self.image_count_spin.setValue(config_manager.get('ui.default_image_count', 10))

    def swap_image_size(self):
        """互换宽度和高度"""
        current_width = self.width_spin.value()
        current_height = self.height_spin.value()
        self.width_spin.setValue(current_height)
        self.height_spin.setValue(current_width)
        
    @pyqtSlot(int)
    def set_preset_resolution(self, id):
        """根据选择的分辨率预设设置尺寸"""
        checked_button = self.resolution_group.button(id)
        if not checked_button:
            return
            
        size_data = checked_button.property("data")
        if size_data and isinstance(size_data, tuple):
            width, height = size_data
            self.width_spin.setValue(width)
            self.height_spin.setValue(height)
            
        # 取消比例预设的选中状态
        if self.ratio_group.checkedButton():
            self.ratio_group.checkedButton().setChecked(False)

    @pyqtSlot(int)
    def set_aspect_ratio(self, id):
        """根据选择的比例预设设置尺寸"""
        checked_button = self.ratio_group.button(id)
        if not checked_button:
            return

        ratio = checked_button.property("data")
            
        if ratio and isinstance(ratio, (float, int)):
            # 保持较大的尺寸（至少 1080）作为基准，避免缩放至过小
            current_max_size = max(self.width_spin.value(), self.height_spin.value(), 1080)
            
            if self.width_spin.value() >= self.height_spin.value():
                # 当前是横向或方形，以宽度为基准
                new_width = current_max_size
                new_height = int(new_width / ratio)
            else:
                # 当前是纵向，以高度为基准
                new_height = current_max_size
                new_width = int(new_height * ratio)

            # 保持整数且不超过最大限制
            self.width_spin.setValue(min(new_width, 4096))
            self.height_spin.setValue(min(new_height, 4096))
            
        # 取消分辨率预设的选中状态
        if self.resolution_group.checkedButton():
            self.resolution_group.checkedButton().setChecked(False)

    def apply_config_and_accept(self):
        """应用配置并关闭对话框"""
        width = self.width_spin.value()
        height = self.height_spin.value()
        count = self.image_count_spin.value()
        
        config_manager.set('bizyair_params.default_width', width)
        config_manager.set('bizyair_params.default_height', height)
        config_manager.set('ui.default_image_count', count)
        config_manager.save_config()
        
        # 通知主页面更新（通过保存到配置，主页面在需要时会读取）
        self.accept()


# 通用 API 设置组件
class APISettingsWidget(QWidget):
    """通用的 API 设置组件，可在多个对话框中复用"""

    # 定义信号
    settings_changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()
        self.load_current_config()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(15)

        # --- API设置 ---
        api_group = QGroupBox("🔑 API设置")
        api_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        api_layout = QGridLayout(api_group)

        # API密钥
        api_layout.addWidget(QLabel("API密钥:"), 0, 0)
        self.api_key_edit = LineEdit()
        self.api_key_edit.setFixedHeight(32)
        self.api_key_edit.setEchoMode(QLineEdit.Password)  # 密码模式
        api_layout.addWidget(self.api_key_edit, 0, 1)

        # API基础URL
        api_layout.addWidget(QLabel("API基础URL:"), 1, 0)
        self.api_url_edit = LineEdit()
        self.api_url_edit.setFixedHeight(32)
        api_layout.addWidget(self.api_url_edit, 1, 1)

        # 文本模型
        api_layout.addWidget(QLabel("文本模型:"), 2, 0)
        self.text_model_edit = LineEdit()
        self.text_model_edit.setFixedHeight(32)
        api_layout.addWidget(self.text_model_edit, 2, 1)

        # BizyAIR App ID 设置项
        api_layout.addWidget(QLabel("BizyAIR App ID:"), 3, 0)
        self.bizyair_app_id_combo = ComboBox()
        self.bizyair_app_id_combo.setFixedHeight(32)

        # 从全局配置加载预定义模型
        self._load_bizyair_models()

        # 连接信号，处理自定义选项
        self.bizyair_app_id_combo.currentIndexChanged.connect(self.on_bizyair_app_id_changed)

        api_layout.addWidget(self.bizyair_app_id_combo, 3, 1)

        api_group.setLayout(api_layout)
        layout.addWidget(api_group)

    def _load_bizyair_models(self):
        """从全局配置加载 BizyAIR 模型列表"""
        # 添加预定义选项到下拉框
        for i, model in enumerate(bizyair_models_config.get_models()):
            display_text = bizyair_models_config.get_display_text(model)
            self.bizyair_app_id_combo.addItem(display_text)
            self.bizyair_app_id_combo.setItemData(i, model['app_id'])

        # 添加自定义选项
        custom_index = self.bizyair_app_id_combo.count()
        self.bizyair_app_id_combo.addItem("➕ 自定义模型ID")
        self.bizyair_app_id_combo.setItemData(custom_index, "custom")

    def load_current_config(self):
        """从配置管理器加载当前的设置值"""
        self.api_key_edit.setText(config_manager.get('api.api_key', ''))
        self.api_url_edit.setText(config_manager.get('api.base_url', 'https://api.siliconflow.cn/v1/'))
        self.text_model_edit.setText(config_manager.get('api.text_model', 'deepseek-ai/DeepSeek-V4-Flash'))

        # 设置当前选中的值
        current_app_id = config_manager.get('bizyair_params.web_app_id', bizyair_models_config.get_default_app_id())
        for i in range(self.bizyair_app_id_combo.count()):
            if self.bizyair_app_id_combo.itemData(i) == current_app_id:
                self.bizyair_app_id_combo.setCurrentIndex(i)
                break

    def on_bizyair_app_id_changed(self, index):
        """处理BizyAIR App ID选择变化"""
        if self.bizyair_app_id_combo.itemData(index) == "custom":
            # 弹出对话框让用户输入自定义模型ID
            from PyQt5.QtWidgets import QInputDialog
            custom_id, ok = QInputDialog.getText(
                self,
                "自定义模型ID",
                "请输入自定义的BizyAIR App ID (数字):",
                QLineEdit.Normal,
                ""
            )

            if ok and custom_id.strip():
                try:
                    # 验证输入是否为数字
                    custom_id_num = int(custom_id.strip())
                    if 1 <= custom_id_num <= 99999:
                        # 创建自定义选项的显示文本
                        custom_display_text = f"🔧 自定义模型ID_{custom_id_num}"

                        # 检查是否已存在相同的自定义ID
                        existing_index = -1
                        for i in range(self.bizyair_app_id_combo.count()):
                            if (self.bizyair_app_id_combo.itemData(i) == custom_id_num and
                                i != index):  # 排除当前的"custom"选项
                                existing_index = i
                                break

                        if existing_index >= 0:
                            # 如果已存在，直接选择该选项
                            self.bizyair_app_id_combo.blockSignals(True)
                            self.bizyair_app_id_combo.setCurrentIndex(existing_index)
                            self.bizyair_app_id_combo.blockSignals(False)
                        else:
                            # 插入新的自定义选项到"➕ 自定义模型ID"之前
                            insert_index = self.bizyair_app_id_combo.count() - 1
                            self.bizyair_app_id_combo.blockSignals(True)
                            self.bizyair_app_id_combo.insertItem(insert_index, custom_display_text)
                            self.bizyair_app_id_combo.setItemData(insert_index, custom_id_num)
                            self.bizyair_app_id_combo.setCurrentIndex(insert_index)
                            self.bizyair_app_id_combo.blockSignals(False)
                    else:
                        QMessageBox.warning(self, "输入错误", "请输入1-99999之间的数字")
                        # 恢复到默认选项
                        self.bizyair_app_id_combo.blockSignals(True)
                        self.bizyair_app_id_combo.setCurrentIndex(0)  # 选择第一个预定义选项
                        self.bizyair_app_id_combo.blockSignals(False)
                except ValueError:
                    QMessageBox.warning(self, "输入错误", "请输入有效的数字")
                    # 恢复到默认选项
                    self.bizyair_app_id_combo.blockSignals(True)
                    self.bizyair_app_id_combo.setCurrentIndex(0)  # 选择第一个预定义选项
                    self.bizyair_app_id_combo.blockSignals(False)
            else:
                # 用户取消输入，恢复到默认选项
                self.bizyair_app_id_combo.blockSignals(True)
                self.bizyair_app_id_combo.setCurrentIndex(0)  # 选择第一个预定义选项
                self.bizyair_app_id_combo.blockSignals(False)

    def save_settings(self):
        """保存设置到配置管理器"""
        config_manager.set('api.api_key', self.api_key_edit.text().strip())
        config_manager.set('api.base_url', self.api_url_edit.text().strip())
        config_manager.set('api.text_model', self.text_model_edit.text().strip())
        # 保存BizyAIR App ID，确保不保存"custom"字符串
        current_data = self.bizyair_app_id_combo.currentData()
        if current_data != "custom":
            config_manager.set('bizyair_params.web_app_id', current_data)
        return config_manager.save_config()


# 模型设置对话框 (精简版，复用 APISettingsWidget)
class ModelSettingsDialog(QDialog):
    """用于设置AI模型和BizyAIR App ID的对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("模型设置")
        self.setMinimumSize(500, 400)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 使用通用的 API 设置组件
        self.api_settings_widget = APISettingsWidget(self)
        layout.addWidget(self.api_settings_widget)

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

    def save_settings(self):
        """保存设置"""
        if self.api_settings_widget.save_settings():
            QMessageBox.information(self, "保存成功", "模型设置已保存")
            self.accept()
        else:
            QMessageBox.critical(self, "保存失败", "设置保存失败，请检查权限")


# 内容页面的基类 (调整布局，使其内容居中且自适应)
class BaseTextPage(QScrollArea):
    """用于左侧 TabWidget 的内容页面基类"""
    def __init__(self, title, input_widget, button_layout=None, template_type=None, parent=None):
        super().__init__(parent)
        self.setWidgetResizable(True)
        self.template_type = template_type
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(20, 20, 20, 20)

        title_label = SubtitleLabel(title)
        # title_label.setFont(QFont("", 14, QFont.Bold)) # 移除固定字体大小
        layout.addWidget(title_label)

        layout.addWidget(input_widget)

        # 添加模板选择区域
        if self.template_type:
            self.template_selection_widget = self.create_template_selection()
            layout.addWidget(self.template_selection_widget)

        if button_layout:
            layout.addLayout(button_layout)

        layout.addStretch()
        self.setWidget(widget)

    def create_template_selection(self):
        """创建模板选择组件"""
        template_group = QGroupBox("") #提示词模板选择
        template_layout = QVBoxLayout()

        # 模板选择下拉框
        self.template_combo = ComboBox()
        self.template_combo.setFixedHeight(32)
        self.template_combo.setFont(QFont("", 15))  # 增大字体
        # qfluentwidgets 的 ComboBox 不支持 addItem(text, data)，需要分别添加
        self.template_combo.addItem("使用默认模板")
        self.template_combo.setItemData(0, None)

        # 加载对应类型的模板
        self.load_templates_by_type()

        template_layout.addWidget(QLabel("选择模板:"))
        template_layout.addWidget(self.template_combo)

        # 当前使用模板标签
        self.current_template_label = QLabel("当前使用: 默认模板")
        self.current_template_label.setStyleSheet("color: #666; font-size: 12px; margin: 5px 0;")
        template_layout.addWidget(self.current_template_label)

        template_group.setLayout(template_layout)
        return template_group

    def load_templates_by_type(self):
        """根据模板类型加载对应的模板"""
        if not self.template_type:
            return

        templates = config_manager.get('prompt_templates', {})

        # 支持两种格式：完全匹配（如 'story_title'）和前缀匹配（如 'story_title_custom'）
        type_templates = {}
        for k, v in templates.items():
            if k == self.template_type or k.startswith(f"{self.template_type}_"):
                type_templates[k] = v

        # 清空现有选项（保留第一个默认选项）
        while self.template_combo.count() > 1:
            self.template_combo.removeItem(self.template_combo.count() - 1)

        # 添加该类型的模板
        for key, template in type_templates.items():
            name = template.get('name', key)
            # qfluentwidgets 的 ComboBox 不支持 addItem(text, data)，需要分别添加
            self.template_combo.addItem(name)
            self.template_combo.setItemData(self.template_combo.count() - 1, key)

        # 设置默认选择第一个
        self.template_combo.setCurrentIndex(0)

    def get_selected_template_key(self):
        """获取当前选择的模板key"""
        return self.template_combo.currentData()

    def get_selected_template(self):
        """获取当前选择的模板内容"""
        template_key = self.get_selected_template_key()
        if template_key:
            return config_manager.get_template(template_key)
        return None

    def update_current_template_label(self):
        """更新当前使用模板的标签"""
        template_key = self.get_selected_template_key()
        if template_key:
            template = config_manager.get_template(template_key)
            name = template.get('name', template_key) if template else template_key
            self.current_template_label.setText(f"当前使用: {name}")
        else:
            self.current_template_label.setText("当前使用: 默认模板")


# 主功能页面 (重大重构)
class StoryboardPage(SmoothScrollArea):
    """分镜脚本与图片生成主页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.current_titles = []
        self.current_summaries = []
        self.current_prompts = []
        self.image_widgets = []
        self.image_urls = [] 
        self.all_generation_step = 0 
        
        # 控件初始化 (在 init_ui 之前)
        self.init_text_widgets()
        
        # 创建顶部控制栏
        self.top_control_bar = TopControlBar()
        self.top_control_bar.show_size_dialog_requested.connect(self.show_image_control_dialog)
        self.top_control_bar.show_template_manager_requested.connect(self.show_template_manager)
        self.top_control_bar.show_model_settings_requested.connect(self.show_model_settings_dialog)
        self.top_control_bar.generate_all_requested.connect(self.generate_all)
        self.top_control_bar.export_md_requested.connect(self.export_markdown)
        self.top_control_bar.export_images_requested.connect(self.export_all_images)
        self.top_control_bar.open_export_folder_requested.connect(self.open_export_folder)
        
        self.init_ui()
        self.init_image_widgets()
        self.adjust_font_size(16) # 调整字体大小

    def init_text_widgets(self):
        """初始化所有文本编辑框和按钮"""
        # 故事内容
        self.content_edit = QTextEdit()
        self.content_edit.setPlaceholderText("请输入您的故事内容或创意描述...")
        self.content_edit.setFont(QFont("font/Light.otf", 18))
        
        # 分镜标题
        self.title_output_edit = QTextEdit()
        self.title_output_edit.setPlaceholderText("生成的分镜标题将显示在这里...")
        self.title_output_edit.setFont(QFont("font/Light.otf", 18))
        self.title_output_edit.setFixedHeight(500)
        
        
        # 分镜描述
        self.summary_output_edit = QTextEdit()
        self.summary_output_edit.setPlaceholderText("生成的分镜描述将显示在这里...")
        self.summary_output_edit.setFont(QFont("font/Light.otf", 18))
        
        # 绘图提示词
        self.generated_prompts_edit = QTextEdit()
        self.generated_prompts_edit.setPlaceholderText("这里将显示生成的绘图提示词，您可以编辑修改...")
        self.generated_prompts_edit.setFont(QFont("font/Light.otf", 18))

        # 自定义提示词前缀输入框
        self.custom_prompt_prefix_edit = LineEdit()
        self.custom_prompt_prefix_edit.setPlaceholderText("输入自定义提示词前缀 (如: lora模型名、角色描述等)，将自动添加到每个提示词前面")
        self.custom_prompt_prefix_edit.setFixedHeight(35)
        self.custom_prompt_prefix_edit.setFont(QFont("font/Light.otf", 16))

        # 进度条和按钮 (原 left_panel 按钮)
        self.generate_title_btn = PrimaryPushButton(FluentIcon.ADD, "生成分镜标题")
        self.title_progress = ProgressBar()
        self.generate_summary_btn = PrimaryPushButton(FluentIcon.EDIT, "生成分镜描述")
        self.summary_progress = ProgressBar()
        self.generate_prompt_btn = PrimaryPushButton(FluentIcon.LINK, "生成绘图提示词")
        self.prompt_progress = ProgressBar()

        self.generate_title_btn.clicked.connect(self.generate_titles)
        self.generate_summary_btn.clicked.connect(self.generate_summaries)
        self.generate_prompt_btn.clicked.connect(self.generate_prompts)

    def adjust_font_size(self, size):
        """全局调整主要文本区域的字体大小"""
        font = QFont("", size)
        self.content_edit.setFont(font)
        self.title_output_edit.setFont(font)
        self.summary_output_edit.setFont(font)
        self.generated_prompts_edit.setFont(font)

        # 调整模板名称下拉框的字体大小
        if hasattr(self, 'title_page') and self.title_page:
            combo_font = QFont("", size - 1)
            self.title_page.template_combo.setFont(combo_font)
        if hasattr(self, 'summary_page') and self.summary_page:
            combo_font = QFont("", size - 1)
            self.summary_page.template_combo.setFont(combo_font)
        if hasattr(self, 'prompt_page') and self.prompt_page:
            combo_font = QFont("", size - 1)
            self.prompt_page.template_combo.setFont(combo_font)

    def init_ui(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(10)

        # 1. 顶部控制栏
        layout.addWidget(self.top_control_bar)

        # 2. 主要内容区域 - 左右分栏
        main_splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(main_splitter)

        # 左侧面板 - Tab Widget
        left_panel = self.create_left_tab_panel()
        main_splitter.addWidget(left_panel)

        # 右侧面板 - 图片生成区
        right_panel = self.create_right_panel()
        main_splitter.addWidget(right_panel)

        # 设置分割比例 (左 50% : 右 50%)
        main_splitter.setSizes([600, 910])

        self.setWidget(widget)
        self.setWidgetResizable(True)

    def create_left_tab_panel(self):
        """创建左侧选项卡面板"""
        tab_widget = QTabWidget()
        tab_widget.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        
        # 0. 故事内容页
        content_page_widget = QWidget()
        content_page_layout = QVBoxLayout(content_page_widget)
        content_page_layout.setContentsMargins(20, 20, 20, 20)
        content_page_layout.addWidget(self.content_edit)
        
        quick_actions_layout = QHBoxLayout()
        clear_btn = PushButton(FluentIcon.DELETE, "清空")
        clear_btn.clicked.connect(self.clear_content)
        load_btn = PushButton(FluentIcon.FOLDER, "加载示例")
        load_btn.clicked.connect(self.load_example)
        quick_actions_layout.addWidget(clear_btn)
        quick_actions_layout.addWidget(load_btn)
        quick_actions_layout.addStretch()
        content_page_layout.addLayout(quick_actions_layout)

        tab_widget.addTab(content_page_widget, "故事内容")

        # 1. 分镜标题页 (按钮/进度条移入 BaseTextPage)
        title_btn_layout = QHBoxLayout()
        self.title_progress.setFixedHeight(10)
        title_btn_layout.addWidget(self.title_progress)
        title_btn_layout.addWidget(self.generate_title_btn)
        title_page = BaseTextPage("🎭 分镜标题生成", self.title_output_edit, title_btn_layout, "story_title")
        tab_widget.addTab(title_page, "分镜标题")

        # 2. 分镜描述页 (按钮/进度条移入 BaseTextPage)
        summary_btn_layout = QHBoxLayout()
        self.summary_progress.setFixedHeight(10)
        summary_btn_layout.addWidget(self.summary_progress)
        summary_btn_layout.addWidget(self.generate_summary_btn)
        summary_page = BaseTextPage("📝 分镜描述生成", self.summary_output_edit, summary_btn_layout, "story_summary")
        tab_widget.addTab(summary_page, "分镜描述")

        # 3. 绘图提示词页 (添加自定义前缀输入框)
        prompt_btn_layout = QHBoxLayout()
        self.prompt_progress.setFixedHeight(10)
        prompt_btn_layout.addWidget(self.prompt_progress)
        prompt_btn_layout.addWidget(self.generate_prompt_btn)

        # 创建自定义绘图提示词页面,继承BaseTextPage但添加前缀输入框
        class CustomPromptPage(BaseTextPage):
            """自定义绘图提示词页面,添加前缀输入框"""
            def __init__(self, title, input_widget, button_layout, template_type, main_window=None):
                super().__init__(title, input_widget, button_layout, template_type, main_window)

                # 在模板选择后面添加前缀输入框
                if hasattr(self, 'template_selection_widget') and main_window:
                    # 获取内部widget和layout
                    internal_widget = self.widget()
                    if internal_widget:
                        internal_layout = internal_widget.layout()

                        # 创建前缀输入框组
                        prefix_group = QGroupBox("🔧 自定义提示词前缀")
                        prefix_layout = QVBoxLayout()
                        prefix_label = QLabel("提示词前缀 (将自动添加到每个提示词前面):")
                        prefix_label.setStyleSheet("font-size: 13px; color: #666;")
                        prefix_layout.addWidget(prefix_label)

                        # 使用主窗口的前缀输入框
                        if hasattr(main_window, 'custom_prompt_prefix_edit'):
                            prefix_layout.addWidget(main_window.custom_prompt_prefix_edit)

                        prefix_help_label = QLabel("💡 例如: lora模型权重、角色固定描述、风格关键词等")
                        prefix_help_label.setStyleSheet("color: #999; font-size: 11px; margin: 3px 0;")
                        prefix_layout.addWidget(prefix_help_label)
                        prefix_group.setLayout(prefix_layout)

                        # 在模板选择后面插入前缀组
                        template_index = internal_layout.indexOf(self.template_selection_widget)
                        internal_layout.insertWidget(template_index + 1, prefix_group)

        prompt_page = CustomPromptPage("🎨 绘图提示词", self.generated_prompts_edit, prompt_btn_layout, "image_prompt", self)
        tab_widget.addTab(prompt_page, "绘图提示词")

        # 保存页面对象引用
        self.title_page = title_page
        self.summary_page = summary_page
        self.prompt_page = prompt_page

        # 连接模板选择信号
        title_page.template_combo.currentIndexChanged.connect(lambda: title_page.update_current_template_label())
        summary_page.template_combo.currentIndexChanged.connect(lambda: summary_page.update_current_template_label())
        prompt_page.template_combo.currentIndexChanged.connect(lambda: prompt_page.update_current_template_label())

        return tab_widget

    def create_right_panel(self):
        """创建右侧面板 - 图片生成区"""
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setSpacing(15)

        # 仅生成图片按钮 (放在顶部，但仅作用于图片生成)
        self.generate_images_btn = PrimaryPushButton(FluentIcon.PHOTO, "仅生成图片")
        self.generate_images_btn.clicked.connect(self.generate_images_only)
        right_layout.addWidget(self.generate_images_btn)


        # 图片生成进度区
        progress_card = CardWidget()
        progress_layout = QVBoxLayout(progress_card)
        progress_layout.setContentsMargins(20, 20, 20, 20)

        progress_title = SubtitleLabel("📊 生成进度")
        progress_title.setFont(QFont("", 14, QFont.Bold))
        progress_layout.addWidget(progress_title)

        self.image_progress = ProgressBar()
        self.image_progress.setFixedHeight(10)
        progress_layout.addWidget(self.image_progress)

        self.image_status_label = QLabel("准备就绪")
        self.image_status_label.setAlignment(Qt.AlignCenter)
        progress_layout.addWidget(self.image_status_label)

        # 添加运行时间显示标签
        self.image_time_label = QLabel("运行时间: 0.0秒")
        self.image_time_label.setAlignment(Qt.AlignCenter)
        self.image_time_label.setStyleSheet("color: #666; font-size: 12px; margin-top: 5px;")
        progress_layout.addWidget(self.image_time_label)

        right_layout.addWidget(progress_card)

        # 图片预览区域 (占据剩余空间)
        preview_card = ElevatedCardWidget()
        preview_layout = QVBoxLayout(preview_card)
        preview_layout.setContentsMargins(10, 10, 10, 10)

        preview_title = SubtitleLabel("🖼️ 图片预览")
        preview_title.setFont(QFont("", 14, QFont.Bold))
        preview_layout.addWidget(preview_title)

        # 创建可滚动的图片网格
        self.image_scroll_area = SmoothScrollArea()
        self.image_scroll_widget = QWidget()
        self.image_grid_layout = QGridLayout(self.image_scroll_widget)
        self.image_grid_layout.setSpacing(15)
        self.image_grid_layout.setAlignment(Qt.AlignTop | Qt.AlignLeft)

        self.image_scroll_area.setWidget(self.image_scroll_widget)
        self.image_scroll_area.setWidgetResizable(True)

        # 设置滚动区域的最小高度，让它在布局中自适应
        self.image_scroll_area.setMinimumHeight(400)

        preview_layout.addWidget(self.image_scroll_area)

        right_layout.addWidget(preview_card)

        return right_widget

    @pyqtSlot()
    def show_image_control_dialog(self):
        """显示图片尺寸和数量设置对话框"""
        # 每次打开对话框前，确保主页面的数据是最新的
        dialog = ImageControlDialog(self)
        if dialog.exec_() == QDialog.Accepted:
            # 应用配置，并确保图片预览区大小更新
            self.init_image_widgets() # 重新初始化图片预览区以反映新的图片数量
            
        # 注意：此处没有 self.width_spin/self.height_spin 等，因为它们在 Dialog 内部。

    # --- 尺寸预设逻辑 (现在在 Dialog 中，但为了调用方便，保留占位方法) ---
    def set_preset_resolution(self, id):
        """(旧代码，已移入 ImageControlDialog)"""
        pass
    
    def set_aspect_ratio(self, id):
        """(旧代码，已移入 ImageControlDialog)"""
        pass
    
    def swap_image_size(self):
        """(旧代码，已移入 ImageControlDialog)"""
        pass
    # --- 尺寸预设逻辑结束 ---

    def image_count_changed(self, value):
        """图片数量改变时，重新初始化图片预览小部件"""
        # 此方法不再由主界面 spinbox 直接调用，但保留其核心逻辑
        config_manager.set('ui.default_image_count', value)
        config_manager.save_config()
        self.init_image_widgets()

    def init_image_widgets(self):
        """初始化图片预览小部件，根据配置中的图片数量动态显示"""

        # 1. 安全地清空并销毁现有小部件
        # 必须使用 deleteLater() 来避免 Double Free 错误
        for i in reversed(range(self.image_grid_layout.count())):
            item = self.image_grid_layout.itemAt(i)
            widget = item.widget()
            if widget is not None:
                # 关键修正：使用 deleteLater() 销毁小部件
                widget.deleteLater()

            # 移除 Item 本身 (对于 QGridLayout 可能不需要手动移除 item，但保留更安全)
            self.image_grid_layout.removeItem(item)

        # 确保清空 Python 列表
        self.image_widgets.clear()
        self.image_urls.clear()

        # 2. 从配置中获取最新的图片数量
        image_count = config_manager.get('ui.default_image_count', 10)

        # 3. 创建新的小部件网格
        cols = 3
        for i in range(image_count):
            widget = ImagePreviewWidget(i)
            self.image_widgets.append(widget)
            self.image_urls.append('')
            row = i // cols
            col = i % cols
            self.image_grid_layout.addWidget(widget, row, col)

        # 4. 添加一个空白占位符，确保内容靠上对齐
        rows = (image_count + cols - 1) // cols
        if self.image_grid_layout.count() > 0:
            spacer = QWidget()
            spacer.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
            self.image_grid_layout.addWidget(spacer, rows, 0, 1, cols)


    def clear_content(self):
        """清空内容"""
        self.content_edit.clear()
        self.title_output_edit.clear()
        self.summary_output_edit.clear()
        self.generated_prompts_edit.clear()
        self.current_titles.clear()
        self.current_summaries.clear()
        self.current_prompts.clear()
        # self.all_generation_step = 0
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备就绪")
        self.image_time_label.setText("运行时间: 0.0秒")

        self.init_image_widgets()
        # self.top_control_bar.set_generate_enabled(True)


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
        if dialog.exec_() == QDialog.Accepted:
            # 对话框关闭后刷新各页面的模板列表
            self.refresh_all_template_lists()

    def show_model_settings_dialog(self):
        """显示模型设置对话框"""
        dialog = ModelSettingsDialog(self)
        if dialog.exec_() == QDialog.Accepted:
            # 模型设置保存后，可以在这里添加额外的处理逻辑
            pass

    def refresh_all_template_lists(self):
        """刷新所有页面的模板列表"""
        if hasattr(self, 'title_page'):
            self.title_page.load_templates_by_type()
        if hasattr(self, 'summary_page'):
            self.summary_page.load_templates_by_type()
        if hasattr(self, 'prompt_page'):
            self.prompt_page.load_templates_by_type()
        
    # --- 文本生成核心逻辑 (保持不变) ---

    def generate_titles(self):
        """生成分镜标题"""
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请先输入故事内容")
            return

        # 使用选择的模板，如果没有选择则使用默认模板
        selected_template = self.title_page.get_selected_template()
        if selected_template:
            system_prompt = selected_template.get('template', '')
        else:
            template = config_manager.get_template('story_title')
            system_prompt = template.get('template', '')

        self.generate_title_btn.setEnabled(False)
        self.title_progress.setValue(0)

        worker = TextGenerationWorker(content, system_prompt)
        worker.content_updated.connect(self.update_title_content, Qt.UniqueConnection)
        worker.progress_updated.connect(self.update_title_progress, Qt.UniqueConnection)
        worker.finished.connect(self.on_titles_finished, Qt.UniqueConnection)

        worker.start()
        worker.finished.connect(lambda: worker.deleteLater())

    def update_title_content(self, text):
        """实时更新标题内容"""
        self.title_output_edit.setPlainText(text)
        cursor = self.title_output_edit.textCursor()
        cursor.movePosition(cursor.End)
        self.title_output_edit.setTextCursor(cursor)

    def update_title_progress(self, msg):
        """更新标题生成进度"""
        if "初始化" in msg:
            self.title_progress.setRange(0, 0)
        elif "生成中" in msg:
            self.title_progress.setRange(0, 100)
            if "速度" in msg:
                import re
                speed_match = re.search(r'速度: ([\d.]+) 字符/秒', msg)
                if speed_match:
                    speed = float(speed_match.group(1))
                    self.title_progress.setValue(min(90, int(speed * 2)))
                else:
                    self.title_progress.setValue(50)
            else:
                self.title_progress.setValue(50)

    def on_titles_finished(self, success, result):
        """分镜标题生成完成"""
        self.generate_title_btn.setEnabled(True)
        self.title_progress.setRange(0, 100)
        self.title_progress.setValue(100 if success else 0)

        if success:
            self.title_output_edit.setPlainText(result)
            titles = [t.strip() for t in result.split('\n') if t.strip()]
            
            # 确保标题数量与图片数量匹配
            target_count = config_manager.get('ui.default_image_count', 10)
            if len(titles) >= target_count:
                self.current_titles = titles[:target_count]
            else:
                self.current_titles = titles + [''] * (target_count - len(titles))

            if hasattr(self, 'all_generation_step') and self.all_generation_step == 1:
                QMessageBox.information(self, "成功", "分镜标题生成完成！")
                QTimer.singleShot(500, self.step_generate_summaries)
            elif not hasattr(self, 'all_generation_step') or self.all_generation_step == 0:
                QMessageBox.information(self, "成功", "分镜标题生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 1:
                self.top_control_bar.set_generate_enabled(True)

    def generate_summaries(self):
        """生成分镜描述"""
        titles_text = self.title_output_edit.toPlainText().strip()
        if not titles_text:
            QMessageBox.warning(self, "警告", "请先生成分镜标题")
            return

        # 使用选择的模板，如果没有选择则使用默认模板
        selected_template = self.summary_page.get_selected_template()
        if selected_template:
            system_prompt = selected_template.get('template', '')
        else:
            template = config_manager.get_template('story_summary')
            system_prompt = template.get('template', '')

        self.generate_summary_btn.setEnabled(False)
        self.summary_progress.setValue(0)

        worker = TextGenerationWorker(titles_text, system_prompt)
        worker.content_updated.connect(self.update_summary_content, Qt.UniqueConnection)
        worker.progress_updated.connect(self.update_summary_progress, Qt.UniqueConnection)
        worker.finished.connect(self.on_summaries_finished, Qt.UniqueConnection)

        worker.start()
        worker.finished.connect(lambda: worker.deleteLater())
        self.current_worker = worker

    def update_summary_content(self, text):
        """实时更新描述内容"""
        self.summary_output_edit.setPlainText(text)
        cursor = self.summary_output_edit.textCursor()
        cursor.movePosition(cursor.End)
        self.summary_output_edit.setTextCursor(cursor)

    def update_summary_progress(self, msg):
        """更新描述生成进度"""
        if "生成中" in msg:
            self.summary_progress.setValue(50)
        else:
            self.summary_progress.setRange(0, 0)

    def on_summaries_finished(self, success, result):
        """分镜描述生成完成"""
        self.generate_summary_btn.setEnabled(True)
        self.summary_progress.setRange(0, 100)
        self.summary_progress.setValue(100 if success else 0)

        if success:
            self.summary_output_edit.setPlainText(result)
            summaries = [s.strip() for s in result.split('\n') if s.strip()]
            
            # 确保描述数量与图片数量匹配
            target_count = config_manager.get('ui.default_image_count', 10)
            if len(summaries) >= target_count:
                self.current_summaries = summaries[:target_count]
            else:
                self.current_summaries = summaries + [''] * (target_count - len(summaries))

            if hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
                QMessageBox.information(self, "成功", "分镜描述生成完成！")
                QTimer.singleShot(500, self.step_generate_prompts)
            elif not hasattr(self, 'all_generation_step') or self.all_generation_step == 0:
                QMessageBox.information(self, "成功", "分镜描述生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
                self.top_control_bar.set_generate_enabled(True)

    def update_prompt_template_label(self):
        """更新绘图提示词模板标签 (已由BaseTextPage处理)"""
        # 此方法已不再需要,由BaseTextPage的update_current_template_label处理
        pass

    def generate_prompts(self):
        """生成绘图提示词 (单次 API 调用)"""
        summary_text = self.summary_output_edit.toPlainText().strip()
        if not summary_text:
            QMessageBox.warning(self, "警告", "请先生成分镜描述")
            return

        # 使用prompt_page的模板选择器
        selected_template = self.prompt_page.get_selected_template()
        if selected_template:
            system_prompt = selected_template.get('template', '')
        else:
            # 使用默认模板
            default_template = config_manager.get_template('image_prompt')
            system_prompt = default_template.get('template', '') if default_template else ''

        # 将所有分镜描述作为一次性输入内容
        input_content = "请根据以下分镜描述内容生成 AI 绘图提示词，每个提示词一行，中间空一行，无需序号和中文解释：\n\n" + summary_text

        self.generate_prompt_btn.setEnabled(False)
        self.prompt_progress.setRange(0, 0)
        self.current_prompts.clear()
        self.generated_prompts_edit.clear()

        worker = TextGenerationWorker(input_content, system_prompt)
        worker.content_updated.connect(self.update_prompts_content, Qt.UniqueConnection)
        worker.progress_updated.connect(self.update_prompts_progress, Qt.UniqueConnection)
        worker.finished.connect(self.on_all_prompts_finished, Qt.UniqueConnection)

        worker.start()
        worker.finished.connect(lambda: worker.deleteLater())
        self.current_worker = worker

    def update_prompts_content(self, text):
        """实时更新提示词内容"""
        # 实时更新内容到编辑框
        self.generated_prompts_edit.setPlainText(text)
        cursor = self.generated_prompts_edit.textCursor()
        cursor.movePosition(cursor.End)
        self.generated_prompts_edit.setTextCursor(cursor)

    def update_prompts_progress(self, msg):
        """更新提示词生成进度"""
        if "初始化" in msg:
            self.prompt_progress.setRange(0, 0)
            self.image_status_label.setText(msg)
        elif "生成中" in msg:
            self.prompt_progress.setRange(0, 100)
            self.prompt_progress.setValue(50)
            self.image_status_label.setText(msg)


    def on_all_prompts_finished(self, success, result):
        """所有提示词生成完成"""
        self.generate_prompt_btn.setEnabled(True)
        self.prompt_progress.setRange(0, 100)
        self.prompt_progress.setValue(100 if success else 0)

        if success:
            # 清理和解析生成的提示词
            raw_prompts = [line.strip() for line in result.split('\n') if line.strip()]
            
            # 重新格式化并解析为 self.current_prompts 列表
            final_display_text = ""
            self.current_prompts.clear()
            
            target_count = config_manager.get('ui.default_image_count', 10)

            # 过滤掉标题行、分隔线等非提示词内容，保留英文提示词
            clean_prompts = []
            for line in raw_prompts:
                stripped = line.strip()
                if not stripped:
                    continue
                # 跳过分隔线（===, ---, ***）
                if re.match(r'^[=\-\*]{3,}$', stripped):
                    continue
                # 跳过 Markdown 标题行
                if stripped.startswith('#'):
                    continue
                # 跳过纯中文行（没有英文字母的行）
                if not re.search(r'[a-zA-Z]', stripped):
                    continue
                # 跳过 "分镜 N" 等中文标记行
                if re.match(r'^[\*]*分镜\s*\d+[\*]*', stripped):
                    continue
                clean_prompts.append(stripped)
            
            final_display_text = ""
            for i, prompt in enumerate(clean_prompts):
                if i < target_count:
                    self.current_prompts.append(prompt)
                    final_display_text += f"=== 分镜 {i+1} ===\n{prompt}\n\n"
            
            # 如果数量不足，用空字符串填充
            while len(self.current_prompts) < target_count:
                self.current_prompts.append('')

            if final_display_text.strip():
                self.generated_prompts_edit.setPlainText(final_display_text.strip())
            # 如果过滤后为空，保留流式输出时的原始内容，不做清空处理
            self.image_status_label.setText("提示词生成完成！")
            
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 3:
                QMessageBox.information(self, "成功", "绘图提示词生成完成！")
                QTimer.singleShot(500, self.step_generate_images)
            elif not hasattr(self, 'all_generation_step') or self.all_generation_step == 0:
                QMessageBox.information(self, "成功", "绘图提示词生成完成！")
        else:
            self.image_status_label.setText("提示词生成失败")
            QMessageBox.critical(self, "错误", f"生成失败：{result}")
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 3:
                self.top_control_bar.set_generate_enabled(True)


    def update_prompts_display(self):
        """更新提示词显示框 (用于手动编辑后解析，此处已由 on_all_prompts_finished 覆盖)"""
        prompts_text = ""
        for i, prompt in enumerate(self.current_prompts):
            if prompt:
                # 提示词显示格式保持不变
                prompts_text += f"=== 分镜 {i+1} ===\n{prompt}\n\n"

        self.generated_prompts_edit.setPlainText(prompts_text.strip())

    # --- 图片生成核心逻辑 (保持不变) ---

    def generate_images_only(self):
        """仅生成图片"""
        prompts_text = self.generated_prompts_edit.toPlainText().strip()

        if not prompts_text:
            QMessageBox.warning(self, "警告", "请先生成或输入绘图提示词")
            return

        self.current_prompts = self._parse_prompts(prompts_text)

        if not self.current_prompts:
            QMessageBox.warning(self, "警告", "请输入有效的绘图提示词")
            return

        # 确保提示词数量与 UI 设置的数量一致 (从配置中读取)
        target_count = config_manager.get('ui.default_image_count', 10)
        if len(self.current_prompts) > target_count:
            self.current_prompts = self.current_prompts[:target_count]
        elif len(self.current_prompts) < target_count:
            # 填充提示词
            last_prompt = self.current_prompts[-1] if self.current_prompts else ""
            self.current_prompts.extend([last_prompt] * (target_count - len(self.current_prompts)))

        # 获取当前尺寸设置 (从配置中读取)
        width = config_manager.get('bizyair_params.default_width', 1080)
        height = config_manager.get('bizyair_params.default_height', 1920)

        # 不需要再次保存配置，因为尺寸和数量已在 ImageControlDialog 中保存

        self.start_image_generation(width, height)

    def _parse_prompts(self, prompts_text):
        """解析提示词文本框内容"""
        prompts = []
        if "=== 分镜" in prompts_text:
            sections = prompts_text.split("=== 分镜")
            for section in sections[1:]:
                lines = section.strip().split('\n', 1)
                if len(lines) > 1:
                    prompt = lines[1].strip()
                    if prompt:
                        prompts.append(prompt)
        # 备用：按行分割
        elif not prompts:
            lines = prompts_text.split('\n')
            for line in lines:
                line = line.strip()
                if line and not line.startswith('#') and not line.startswith('//'):
                    prompts.append(line)
        return prompts

    def start_image_generation(self, width, height):
        """开始图片生成"""
        # 重新初始化图片预览小部件以确保数量正确
        self.init_image_widgets()

        # 获取自定义提示词前缀
        custom_prefix = ""
        if hasattr(self, 'custom_prompt_prefix_edit'):
            custom_prefix = self.custom_prompt_prefix_edit.text().strip()

        # 将前缀添加到每个提示词前面
        final_prompts = []
        for prompt in self.current_prompts:
            if custom_prefix:
                # 将前缀添加到提示词前面,用空格分隔
                final_prompt = f"{custom_prefix} {prompt}".strip()
            else:
                final_prompt = prompt
            final_prompts.append(final_prompt)

        # 启动图片生成 (批量一次性发送)
        self.generate_images_btn.setEnabled(False)
        self.top_control_bar.set_generate_enabled(False) # 禁用一键生成按钮和导出按钮
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备生成图片...")

        # 获取图片数量（从配置中读取）
        image_count = config_manager.get('ui.default_image_count', 10)

        # 创建图片生成worker,使用添加了前缀的提示词
        self.image_worker = ImageGenerationWorker(
            final_prompts,  # 使用添加了前缀的提示词
            width,
            height,
            image_count
        )

        # 连接信号
        self.image_worker.progress_updated.connect(self.on_batch_image_progress)
        self.image_worker.image_generated.connect(self.on_batch_image_url_received)
        self.image_worker.finished.connect(self.on_all_images_finished)
        self.image_worker.time_updated.connect(self.on_image_time_updated)

        # 启动worker
        self.image_worker.start()
        self.image_worker.finished.connect(lambda: self.image_worker.deleteLater())

    def on_batch_image_progress(self, progress, msg):
        """批量图片生成进度"""
        self.image_progress.setValue(progress)
        self.image_status_label.setText(msg)

    def on_image_time_updated(self, time_str):
        """更新图片生成运行时间"""
        self.image_time_label.setText(time_str)

    def on_batch_image_url_received(self, index, image, url):
        """接收单个图片 URL 并更新显示"""
        if index < len(self.image_widgets):
            self.image_widgets[index].set_image(image, url)
            self.image_urls[index] = url # 保存 URL 用于导出

    def on_all_images_finished(self, success, images, urls):
        """所有图片生成完成"""
        self.generate_images_btn.setEnabled(True)
        self.top_control_bar.set_generate_enabled(True) # 重新启用按钮
        self.image_progress.setValue(100 if success else 0)
        self.all_generation_step = 0 # 重置步骤

        if success:
            # 保留带有总耗时的状态信息
            success_count = sum(1 for url in urls if url)
            QMessageBox.information(self, "成功", f"成功生成 {success_count}/{config_manager.get('ui.default_image_count', 10)} 张图片！")
        else:
            self.image_status_label.setText("图片生成失败")
            QMessageBox.critical(self, "错误", "图片生成失败")

    # --- 一键生成逻辑 ---

    def generate_all(self):
        """一键生成全部"""
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请先输入故事内容")
            return

        self.top_control_bar.set_generate_enabled(False) # 禁用一键生成按钮和导出按钮
        self.all_generation_step = 0
        # 清除辅助区域，保留故事内容
        self.title_output_edit.clear()
        self.summary_output_edit.clear()
        self.generated_prompts_edit.clear()
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备就绪")
        self.image_time_label.setText("运行时间: 0.0秒")
        self.init_image_widgets()

        # 1. 生成标题
        QTimer.singleShot(100, self.step_generate_titles)

    def step_generate_titles(self):
        """步骤1：生成标题"""
        self.all_generation_step = 1
        self.generate_titles()

    def step_generate_summaries(self):
        """步骤2：生成描述"""
        self.all_generation_step = 2
        self.generate_summaries()

    def step_generate_prompts(self):
        """步骤3：生成提示词"""
        self.all_generation_step = 3
        self.generate_prompts()

    def step_generate_images(self):
        """步骤4：生成图片"""
        self.all_generation_step = 4
        # 获取最新的提示词（因为用户可能在步骤3后修改了）
        prompts_text = self.generated_prompts_edit.toPlainText().strip()
        self.current_prompts = self._parse_prompts(prompts_text)
        
        self.generate_images_only()

    # --- 导出逻辑 (已移至 TopControlBar 信号触发) ---

    def export_markdown(self):
        """导出Markdown文件"""
        if not self.current_titles and not self.current_summaries and not any(self.image_widgets):
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

                    image_count = config_manager.get('ui.default_image_count', 10)
                    for i in range(image_count):
                        f.write(f"## 📺 分镜 {i+1}\n\n")
                        
                        title = self.current_titles[i] if i < len(self.current_titles) and self.current_titles[i] else ""
                        summary = self.current_summaries[i] if i < len(self.current_summaries) and self.current_summaries[i] else ""
                        prompt = self.current_prompts[i] if i < len(self.current_prompts) and self.current_prompts[i] else ""
                        image_url = self.image_widgets[i].image_url if i < len(self.image_widgets) and self.image_widgets[i].image_url else ""
                        
                        if title:
                            f.write(f"**🎭 分镜标题:** {title}\n\n")
                        
                        if summary:
                            f.write(f"**📝 分镜描述:** {summary}\n\n")
                        
                        if prompt:
                            f.write(f"**🎨 AI绘图提示词:** {prompt}\n\n")
                        
                        if image_url:
                            f.write(f"**🖼️ 图片:**\n")
                            f.write(f"![分镜{i+1}]({image_url})\n\n")
                        
                        f.write("---\n\n")

                QMessageBox.information(self, "成功", f"Markdown文件已保存到: {file_path}")
                
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

        # 保存最近使用的导出目录
        self.last_export_dir = output_dir

        timestamp = datetime.now().strftime('%m%d%H%M%S')
        # 获取当前模型的 app_id 作为文件名前缀
        app_id = config_manager.get('bizyair_params.web_app_id', 39808)
        export_count = 0

        for i, widget in enumerate(self.image_widgets):
            if widget.image_url: # 使用 URL 而不是 widget.image
                try:
                    file_name = f"{app_id}_{timestamp}_{i+1}.png"
                    file_path = os.path.join(output_dir, file_name)

                    # 从 URL 下载图片并保存
                    response = requests.get(widget.image_url, timeout=30)
                    if response.status_code == 200:
                        with open(file_path, 'wb') as f:
                            f.write(response.content)
                        export_count += 1
                    else:
                        logger.error(f"下载图片失败: HTTP {response.status_code}")

                except Exception as e:
                    logger.error(f"保存图片失败: {e}")

        if export_count > 0:
            # 直接打开导出文件夹
            QDesktopServices.openUrl(QUrl.fromLocalFile(os.path.abspath(output_dir)))
        else:
            QMessageBox.warning(self, "警告", "没有可导出的图片")

    def open_export_folder(self):
        """打开导出文件夹"""
        # 优先使用最近导出的目录，否则使用默认的output目录
        export_dir = getattr(self, 'last_export_dir', 'output')
        if not os.path.exists(export_dir):
            export_dir = 'output'

        # 如果目录不存在，创建它
        if not os.path.exists(export_dir):
            os.makedirs(export_dir)

        # 使用QDesktopServices打开文件夹
        from PyQt5.QtGui import QDesktopServices
        from PyQt5.QtCore import QUrl
        if os.path.exists(export_dir):
            QDesktopServices.openUrl(QUrl.fromLocalFile(os.path.abspath(export_dir)))
        else:
            QMessageBox.warning(self, "警告", f"目录不存在: {os.path.abspath(export_dir)}")


# 主窗口 (精简)
class MainWindow(FluentWindow):
    def __init__(self):
        super().__init__()
        self.init_window()
        self.init_navigation()
        self.check_api_key()

    def init_window(self):
        """初始化主窗口"""
        self.setWindowTitle("🎬 BOZO-MCN 分镜脚本与图片生成器 v1.0.2")
        self.setMinimumSize(1600, 1000)

        width = config_manager.get('ui.window_width', 1600)
        height = config_manager.get('ui.window_height', 1000)
        self.resize(width, height)

        # 恢复窗口位置，并确保在屏幕可见区域内
        screen = QApplication.primaryScreen()
        if screen:
            screen_geometry = screen.availableGeometry()
            saved_x = config_manager.get('ui.window_x', -1)
            saved_y = config_manager.get('ui.window_y', -1)

            if saved_x >= 0 and saved_y >= 0:
                # 检查保存的位置是否在屏幕范围内
                if (saved_x < screen_geometry.right() and
                    saved_y < screen_geometry.bottom() and
                    saved_x + width > screen_geometry.left() and
                    saved_y + height > screen_geometry.top()):
                    self.move(saved_x, saved_y)
                else:
                    # 位置超出屏幕，居中显示
                    self.move(
                        screen_geometry.center().x() - width // 2,
                        screen_geometry.center().y() - height // 2
                    )
            else:
                # 首次启动，居中显示
                self.move(
                    screen_geometry.center().x() - width // 2,
                    screen_geometry.center().y() - height // 2
                )

    def init_navigation(self):
        """初始化导航栏"""
        # 添加首页
        self.addSubInterface(
            self.create_home_page(),
            FluentIcon.HOME,
            "首页",
            NavigationItemPosition.TOP
        )

        # 添加图片提示词生成器页面
        try:
            from prompt import ImagePromptPage
            self.image_prompt_page = ImagePromptPage(self)
            self.image_prompt_page.setObjectName("image_prompt_page")
            self.addSubInterface(
                self.image_prompt_page,
                FluentIcon.PHOTO,
                "图片提示词",
                NavigationItemPosition.TOP
            )
        except ImportError as e:
            print(f"无法导入图片提示词生成模块: {e}")

        self.storyboard_page = StoryboardPage(self)
        self.storyboard_page.setObjectName("storyboard_page")
        self.addSubInterface(
            self.storyboard_page,
            FluentIcon.VIDEO,
            "分镜生成",
            NavigationItemPosition.TOP
        )

        # 添加视频生成页面
        try:
            from pic2vod import VideoGenerationWidget
            self.video_generation_page = VideoGenerationWidget()
            self.video_generation_page.setObjectName("video_generation_page")
            self.addSubInterface(
                self.video_generation_page,
                FluentIcon.MEDIA,
                "视频生成",
                NavigationItemPosition.TOP
            )
        except ImportError as e:
            print(f"无法导入视频生成模块: {e}")

        # 添加Sora2视频生成页面
        try:
            from sora2 import Sora2VideoGenerationWidget
            self.sora2_video_generation_page = Sora2VideoGenerationWidget()
            self.sora2_video_generation_page.setObjectName("sora2_video_generation_page")
            self.addSubInterface(
                self.sora2_video_generation_page,
                FluentIcon.ROBOT,
                "Sora2生成",
                NavigationItemPosition.TOP
            )
        except ImportError as e:
            print(f"无法导入Sora2视频生成模块: {e}")

        # 添加模板化视频生成页面（基于 vods-json 配置文件）
        try:
            from vods_template_generator import TemplateVideoGenerationWidget
            self.template_video_generation_page = TemplateVideoGenerationWidget()
            self.template_video_generation_page.setObjectName("template_video_generation_page")
            self.addSubInterface(
                self.template_video_generation_page,
                FluentIcon.APPLICATION,
                "模板视频",
                NavigationItemPosition.TOP
            )
        except ImportError as e:
            print(f"无法导入模板化视频生成模块: {e}")

        self.addSubInterface(
            self.create_settings_page(),
            FluentIcon.SETTING,
            "设置",
            NavigationItemPosition.BOTTOM
        )

    def create_home_page(self):
        """创建首页"""
        self.home_page = HomePage(self)
        self.home_page.setObjectName("home_page")
        return self.home_page

    def open_directory(self, dir_path):
        """打开指定的本地目录"""
        if os.path.exists(dir_path):
            QDesktopServices.openUrl(QUrl.fromLocalFile(os.path.abspath(dir_path)))
        else:
            QMessageBox.warning(self, "警告", f"目录不存在: {os.path.abspath(dir_path)}")

    def create_settings_page(self):
        """创建设置页面 (精简版，使用通用 API 设置组件)"""
        page = SmoothScrollArea()
        page.setObjectName("settings_page")
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(20)

        title = SubtitleLabel("⚙️ 设置")
        title.setFont(QFont("font/Light.otf", 18, QFont.Bold))
        layout.addWidget(title)

        # 使用通用的 API 设置组件
        self.api_settings_widget = APISettingsWidget(self)
        layout.addWidget(self.api_settings_widget)

        # 目录设置
        dir_group = QGroupBox("📁 目录设置")
        dir_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        dir_layout = QGridLayout()

        dirs = config_manager.get('directories', {})

        # 输出目录
        dir_layout.addWidget(QLabel("输出目录 (output):"), 0, 0)
        output_btn = PushButton(FluentIcon.FOLDER, "打开")
        output_btn.clicked.connect(lambda: self.open_directory(dirs.get('output', 'output')))
        dir_layout.addWidget(output_btn, 0, 1)

        # 模板目录
        dir_layout.addWidget(QLabel("模板目录 (templates):"), 1, 0)
        templates_btn = PushButton(FluentIcon.FOLDER, "打开")
        templates_btn.clicked.connect(lambda: self.open_directory(dirs.get('templates', 'templates')))
        dir_layout.addWidget(templates_btn, 1, 1)

        dir_group.setLayout(dir_layout)
        layout.addWidget(dir_group)

        # 界面设置
        ui_group = QGroupBox("🎨 界面设置")
        ui_group.setStyleSheet("QGroupBox { border: 1px solid #ccc; margin-top: 1ex; padding: 10px; }")
        ui_layout = QGridLayout()

        ui_layout.addWidget(QLabel("默认图片数量:"), 0, 0)
        self.default_image_count_spin = QSpinBox()
        self.default_image_count_spin.setRange(5, 40)
        self.default_image_count_spin.setSingleStep(5)
        self.default_image_count_spin.setFixedHeight(32)
        self.default_image_count_spin.setValue(config_manager.get('ui.default_image_count', 10))
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
            InfoBar.warning(
                title="API密钥未配置",
                content="请在设置中配置 API密钥以使用完整功能",
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
        # 保存 API 设置（使用通用组件的保存方法）
        if not self.api_settings_widget.save_settings():
            InfoBar.error(
                title="保存失败",
                content="API 设置保存失败，请检查权限",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )
            return

        # 更新默认图片数量，并同步到 StoryboardPage
        new_image_count = self.default_image_count_spin.value()
        config_manager.set('ui.default_image_count', new_image_count)
        self.storyboard_page.init_image_widgets()  # 强制更新主页面的图片数量

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

    # 删除不再需要的 on_bizyair_app_id_changed 方法，已在 APISettingsWidget 中实现

    def closeEvent(self, event):
        """窗口关闭时保存配置"""
        config_manager.set('ui.window_width', self.width())
        config_manager.set('ui.window_height', self.height())
        config_manager.set('ui.window_x', self.x())
        config_manager.set('ui.window_y', self.y())
        config_manager.save_config()

        thread_manager.cancel_all()

        super().closeEvent(event)

def main():
    os.environ["QT_LOGGING_RULES"] = "qt.qpa.fonts.warning=false"
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    QFont.insertSubstitution("Segoe UI", ".AppleSystemUIFont")
    QFont.insertSubstitution("Microsoft YaHei", "PingFang SC")

    app = QApplication(sys.argv)

    default_font = QFont()
    default_font.setPointSize(12)
    app.setFont(default_font)

    app.setApplicationName("BOZO-MCN分镜脚本生成器")
    app.setApplicationVersion("2.0")
    app.setOrganizationName("BOZO-MCN")

    # 设置全局样式优化
    app.setStyleSheet("""
        QGroupBox {
            font-weight: bold;
            /* border: 2px solid #cccccc; */
            border-radius: 8px;
            margin-top: 1ex;
            padding-top: 10px;
        }
        QGroupBox::title {
            subcontrol-origin: margin;
            left: 10px;
            padding: 0 5px 0 5px;
        }
        /* 移除 Tab Widget内部页面的QGroupBox样式 */
        #count_widget, #template_widget, #size_widget {
            border: none;
            padding: 0;
            margin: 0;
        }
        QTabWidget::pane {
             /* 增加 Tab Pane 边距，优化分隔线 */
             /* border: 1px solid #cccccc; */
             border-top: none;
        }
        QTabWidget::tab-bar {
            left: 5px; 
        }
        QTabBar::tab {
             /* 增加 Tab 标题字体大小和填充 */
             font-size: 16px;
             padding: 8px 15px;
             width:100px;
             border: 2px solid transparent;
             border-radius: 8px;
             margin-right: 3px;
             background-color: #cccccc;
             color: #666;
        }
        QTabBar::tab:selected {
             /* 激活状态样式 */
             background-color: #2196f3;
             color: white;
             border-color: #2196f3;
             font-weight: bold;
        }
        QTabBar::tab:hover:!selected {
             /* 悬停但未激活状态 */
             background-color: #e3f2fd;
             color: #1976d2;
             border-color: #bbdefb;
        }
        QToolButton#swap_size_btn {
             /* 调整互换按钮的尺寸和样式 */
             /* border: 1px solid #ccc; */
             border-radius: 4px;
             padding: 4px;
             width: 30px;
        }
        QToolButton#swap_size_btn:hover {
            border-color: #0078d4;
        }
        ComboBox, LineEdit, SpinBox, DoubleSpinBox {
            padding: 5px;
            /* border: 1px solid #cccccc; */
            border-radius: 4px;
            background: white;
        }
        ComboBox:hover, LineEdit:hover, SpinBox:hover, DoubleSpinBox:hover {
            border-color: #888888;
        }
        ComboBox:focus, LineEdit:focus, SpinBox:focus, DoubleSpinBox:focus {
            border-color: #0078d4;
        }
        /* 确保 RadioButton 布局紧凑 */
        QRadioButton {
            margin-right: 10px; 
        }
        /* 统一 QTextEdit/QScrollArea 内部的 QTextEdit 样式 */
        QTextEdit {
            /* border: 1px solid #cccccc; */
            border-radius: 4px;
            padding: 10px;
            min-height: 250px; /* 确保最小高度 */
        }

        /* 图片预览小部件样式 */
        QWidget#ImagePreviewWidget {
            background-color: #2d2d2d;
            border: 1px solid #3d3d3d;
            border-radius: 8px;
        }
    """)

    # 设置主题
    current_theme = config_manager.get('ui.theme', 'dark')
    if current_theme == 'dark':
        setTheme(Theme.DARK)
    else:
        setTheme(Theme.LIGHT)

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
