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
import threading
import time
from io import BytesIO
from PIL import Image
from openai import OpenAI

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QSpinBox,
                            QProgressBar, QMessageBox, QSplitter, QGroupBox,
                            QDialog, QToolButton, QSizePolicy)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl, QSettings, QSize, pyqtSlot
from PyQt5.QtGui import QFont, QIcon, QDesktopServices, QPixmap
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

# 预设尺寸和比例数据
PRESET_RESOLUTIONS = {
    "1920x1080 (1080P)": (1920, 1080), 
    "1707x960 (960P)": (1707, 960),
    "1280x720 (720P)": (1280, 720),
}

ASPECT_RATIOS = {
    "16:9": 16/9,
    "4:3": 4/3,
    "21:9": 21/9,
    "1:1": 1/1,
    "2:3": 2/3,
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
                "text_model": "Qwen/Qwen3-Coder-480B-A35B-Instruct",
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
                "window_width": 1678,
                "window_height": 1049,
                "default_image_count": 10
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
        self.model_id = model_id or config_manager.get('api.text_model', 'Qwen/Qwen3-Coder-480B-A35B-Instruct')
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
            char_count = 0
            
            # 处理流式响应
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
                        self.content_updated.emit(content_text)

                        # 每500字符更新一次进度
                        if char_count % 500 == 0:
                            elapsed = time.time() - self.start_time
                            speed = char_count / elapsed if elapsed > 0 else 0
                            self.progress_updated.emit(f"生成中... 已生成 {len(content_text)} 字符 (速度: {speed:.1f} 字符/秒)")

                except Exception as e:
                    logger.error(f"处理API响应时出错: {e}")
                    continue

            # 确保最终结果被发送
            if not self.is_cancelled:
                self.finished.emit(True, content_text)
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

    def run(self):
        try:
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
                
                # 提交任务
                progress = int(batch_index / num_batches * 10) # 提交阶段占前 10%
                self.progress_updated.emit(progress, f"正在提交 BizyAIR 第 {batch_index+1}/{num_batches} 批任务...")
                
                response = requests.post(
                    base_url,
                    headers=common_headers,
                    json={
                        "web_app_id": self.web_app_id,
                        "suppress_preview_output": False,
                        "input_values": input_values
                    },
                    timeout=300 # 增加超时时间以应对生成较慢的情况
                )

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
                        
                            # 更新进度 (10% + 已完成百分比 * 90%)
                            progress = 10 + int(len(final_urls) / self.image_count * 90)
                            self.progress_updated.emit(progress, f"已生成 {len(final_urls)}/{self.image_count} 张图片 URL")
                else:
                    logger.error(f"第 {batch_index+1} 批图片生成失败: {result}")
                    # 即使失败，也继续下一批次
                    for _ in range(batch_size):
                        if start_index + _ < self.image_count:
                             final_urls.append('') # 添加空URL占位

            # 最终返回
            if not self.is_cancelled:
                self.progress_updated.emit(100, "图片生成完成!")
                # 只返回实际需要的 URL 数量
                self.finished.emit(True, [], final_urls[:self.image_count])
            else:
                 self.finished.emit(False, [], final_urls[:self.image_count])
                 
        except Exception as e:
            logger.error(f"图片生成失败: {e}")
            self.finished.emit(False, [], [])


# 模板管理对话框 (保留不变)
class TemplateManagerDialog(QDialog):
    """提示词模板管理对话框"""
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
        self.template_combo.setFixedHeight(32)
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
        self.template_name_edit.setFixedHeight(32)
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

        new_btn = PushButton(FluentIcon.ADD, "新建模板")
        new_btn.clicked.connect(self.new_template)
        button_layout.addWidget(new_btn)

        load_btn = PushButton(FluentIcon.DOWNLOAD, "加载模板")
        load_btn.clicked.connect(self.load_template_content)
        button_layout.addWidget(load_btn)

        save_btn = PushButton(FluentIcon.SAVE, "保存模板")
        save_btn.clicked.connect(self.save_template_content)
        button_layout.addWidget(save_btn)

        delete_btn = PushButton(FluentIcon.DELETE, "删除模板")
        delete_btn.clicked.connect(self.delete_template)
        button_layout.addWidget(delete_btn)

        # 导入导出功能
        import_btn = PushButton(FluentIcon.FOLDER, "导入模板")
        import_btn.clicked.connect(self.import_template)
        button_layout.addWidget(import_btn)

        export_btn = PushButton(FluentIcon.DOWNLOAD, "导出模板")
        export_btn.clicked.connect(self.export_template)
        button_layout.addWidget(export_btn)

        button_layout.addStretch()

        ok_btn = PrimaryPushButton("确定")
        ok_btn.clicked.connect(self.accept)
        button_layout.addWidget(ok_btn)

        cancel_btn = PushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)

        layout.addLayout(button_layout)

    def new_template(self):
        """新建模板"""
        self.template_name_edit.clear()
        self.template_content_edit.clear()
        self.template_name_edit.setFocus()

    def load_templates(self):
        """加载模板列表"""
        self.template_combo.clear()
        templates = config_manager.get('prompt_templates', {})
        for key, template in templates.items():
            self.template_combo.addItem(template.get('name', key), key)
        self.template_combo.setCurrentIndex(-1) # 默认不选中

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

    def import_template(self):
        """导入模板"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "导入模板文件", "", "JSON Files (*.json)"
        )
        if file_path:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    template_data = json.load(f)

                if not isinstance(template_data, dict) or 'name' not in template_data or 'template' not in template_data:
                    QMessageBox.warning(self, "警告", "无效的模板文件格式")
                    return

                template_name = template_data.get('name', '导入的模板')
                template_key = template_name.replace(' ', '_').lower()

                if config_manager.save_template(template_key, template_data):
                    QMessageBox.information(self, "成功", f"模板 '{template_name}' 导入成功")
                    self.load_templates()
                    for i in range(self.template_combo.count()):
                        if self.template_combo.itemData(i) == template_key:
                            self.template_combo.setCurrentIndex(i)
                            break
                else:
                    QMessageBox.critical(self, "错误", "模板导入失败")

            except Exception as e:
                QMessageBox.critical(self, "错误", f"导入模板时出错：{str(e)}")

    def export_template(self):
        """导出模板"""
        current_data = self.template_combo.currentData()
        if not current_data:
            QMessageBox.warning(self, "警告", "请先选择要导出的模板")
            return

        template = config_manager.get_template(current_data)
        if not template:
            QMessageBox.warning(self, "警告", "模板数据不存在")
            return

        file_path, _ = QFileDialog.getSaveFileName(
            self, "导出模板文件",
            f"{template.get('name', current_data)}.json",
            "JSON Files (*.json)"
        )

        if file_path:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(template, f, indent=2, ensure_ascii=False)
                QMessageBox.information(self, "成功", f"模板 '{template.get('name')}' 导出成功")
            except Exception as e:
                QMessageBox.critical(self, "错误", f"导出模板时出错：{str(e)}")


# 图片预览小部件 (保留不变，但精简了不用的导入)
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
    """用于放置一键生成和导出按钮的顶部控制栏"""
    
    # 信号用于触发主页面的功能
    generate_all_requested = pyqtSignal()
    export_md_requested = pyqtSignal()
    export_images_requested = pyqtSignal()

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

        # 1. 一键生成按钮
        self.generate_all_btn = PrimaryPushButton(FluentIcon.PLAY, "一键生成全部")
        self.generate_all_btn.setFixedHeight(36)
        self.generate_all_btn.clicked.connect(self.generate_all_requested.emit)
        layout.addWidget(self.generate_all_btn)

        # 2. 导出 Markdown
        self.export_md_btn = PushButton(FluentIcon.SAVE, "导出Markdown")
        self.export_md_btn.setFixedHeight(36)
        self.export_md_btn.clicked.connect(self.export_md_requested.emit)
        layout.addWidget(self.export_md_btn)

        # 3. 导出全部图片
        self.export_images_btn = PushButton(FluentIcon.FOLDER, "导出全部图片")
        self.export_images_btn.setFixedHeight(36)
        self.export_images_btn.clicked.connect(self.export_images_requested.emit)
        layout.addWidget(self.export_images_btn)
    
    def set_generate_enabled(self, enabled):
        """控制一键生成按钮的启用状态"""
        self.generate_all_btn.setEnabled(enabled)
        # 导出按钮的状态可以独立控制，但为了安全，在生成时也禁用
        if not enabled:
            self.export_md_btn.setEnabled(False)
            self.export_images_btn.setEnabled(False)
        else:
            # 导出按钮的状态应由图片/内容是否生成决定，这里先保持启用，等待主页面更新
             self.export_md_btn.setEnabled(True)
             self.export_images_btn.setEnabled(True)

# 主功能页面 (主要修改区域)
class StoryboardPage(SmoothScrollArea):
    """分镜脚本与图片生成主页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.current_titles = []
        self.current_summaries = []
        self.current_prompts = []
        self.image_widgets = []
        self.image_urls = [] # 添加 URL 列表
        self.all_generation_step = 0 # 0: idle, 1: title, 2: summary, 3: prompt, 4: image
        
        # 创建顶部控制栏
        self.top_control_bar = TopControlBar()
        self.top_control_bar.generate_all_requested.connect(self.generate_all)
        self.top_control_bar.export_md_requested.connect(self.export_markdown)
        self.top_control_bar.export_images_requested.connect(self.export_all_images)
        
        self.init_ui()
        self.init_image_widgets() # 确保初始化图片小部件，以便后续更新

    def init_ui(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(20)

        # 1. 顶部控制栏
        layout.addWidget(self.top_control_bar)


        # 2. 主要内容区域 - 左右分栏
        main_splitter = QSplitter(Qt.Horizontal)
        layout.addWidget(main_splitter)

        # 左侧面板 - 文字内容区
        left_panel = self.create_left_panel()
        main_splitter.addWidget(left_panel)

        # 右侧面板 - 图片生成区
        right_panel = self.create_right_panel()
        main_splitter.addWidget(right_panel)

        # 设置分割比例 (左50% : 右50%)
        main_splitter.setSizes([800, 800])

        self.setWidget(widget)
        self.setWidgetResizable(True)

    def create_left_panel(self):
        """创建左侧面板 - 文字内容区"""
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setSpacing(15)

        # 故事内容输入区
        content_card = ElevatedCardWidget()
        content_layout = QVBoxLayout(content_card)
        content_layout.setContentsMargins(20, 20, 20, 20)

        content_title = SubtitleLabel("📝 故事内容")
        content_title.setFont(QFont("", 14, QFont.Bold))
        content_layout.addWidget(content_title)

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
        left_layout.addWidget(content_card)

        # 分镜标题生成区
        title_card = CardWidget()
        title_layout = QVBoxLayout(title_card)
        title_layout.setContentsMargins(20, 20, 20, 20)

        title_header_layout = QHBoxLayout()
        title_header = SubtitleLabel("🎭 分镜标题生成")
        title_header.setFont(QFont("", 14, QFont.Bold))
        title_header_layout.addWidget(title_header)
        title_header_layout.addStretch()
        title_layout.addLayout(title_header_layout)

        title_btn_layout = QHBoxLayout()
        self.generate_title_btn = PrimaryPushButton(FluentIcon.ADD, "生成分镜标题")
        self.generate_title_btn.clicked.connect(self.generate_titles)
        title_btn_layout.addWidget(self.generate_title_btn)

        self.title_progress = ProgressBar()
        self.title_progress.setFixedHeight(8)
        title_btn_layout.addWidget(self.title_progress)
        title_layout.addLayout(title_btn_layout)

        self.title_output_edit = QTextEdit()
        self.title_output_edit.setPlaceholderText("生成的分镜标题将显示在这里...")
        self.title_output_edit.setMinimumHeight(120)
        title_layout.addWidget(self.title_output_edit)

        left_layout.addWidget(title_card)

        # 分镜描述生成区
        summary_card = CardWidget()
        summary_layout = QVBoxLayout(summary_card)
        summary_layout.setContentsMargins(20, 20, 20, 20)

        summary_header_layout = QHBoxLayout()
        summary_header = SubtitleLabel("📝 分镜描述生成")
        summary_header.setFont(QFont("", 14, QFont.Bold))
        summary_header_layout.addWidget(summary_header)
        summary_header_layout.addStretch()
        summary_layout.addLayout(summary_header_layout)

        summary_btn_layout = QHBoxLayout()
        self.generate_summary_btn = PrimaryPushButton(FluentIcon.EDIT, "生成分镜描述")
        self.generate_summary_btn.clicked.connect(self.generate_summaries)
        summary_btn_layout.addWidget(self.generate_summary_btn)

        self.summary_progress = ProgressBar()
        self.summary_progress.setFixedHeight(8)
        summary_btn_layout.addWidget(self.summary_progress)
        summary_layout.addLayout(summary_btn_layout)

        self.summary_output_edit = QTextEdit()
        self.summary_output_edit.setPlaceholderText("生成的分镜描述将显示在这里...")
        self.summary_output_edit.setMinimumHeight(120)
        summary_layout.addWidget(self.summary_output_edit)

        left_layout.addWidget(summary_card)

        # 生成控制区 (调整为三列布局)
        control_card = CardWidget()
        control_layout = QVBoxLayout(control_card)
        control_layout.setContentsMargins(10, 10, 10, 10) # 减小边距以适应紧凑布局

        # 标题 (单独一行，确保不被挤压)
        control_title_layout = QHBoxLayout()
        control_header = SubtitleLabel("⚙️ 生成控制")
        control_header.setFont(QFont("", 14, QFont.Bold))
        control_title_layout.addWidget(control_header)
        control_title_layout.addStretch()
        control_layout.addLayout(control_title_layout)

        # 功能模块布局
        control_modules_layout = QHBoxLayout()
        control_modules_layout.setSpacing(10) # 模块间距
        control_modules_layout.setContentsMargins(0, 0, 0, 0) # 移除模块布局的边距

        # --- 1. 图片尺寸 (左) ---
        size_widget = QWidget()
        size_widget.setObjectName("size_widget") # 用于样式隔离
        size_layout = QVBoxLayout(size_widget)
        size_layout.setContentsMargins(0, 0, 0, 0) # 移除边框，内容紧凑
        
        # 尺寸输入 (W/H 同一行)
        size_input_layout = QHBoxLayout()
        size_input_layout.setContentsMargins(0, 0, 0, 0)
        
        size_input_layout.addWidget(QLabel("W:"))
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 4096)
        self.width_spin.setValue(config_manager.get('bizyair_params.default_width', 1080))
        self.width_spin.setSingleStep(64)
        self.width_spin.setFixedWidth(55)
        size_input_layout.addWidget(self.width_spin)

        # 互换按钮
        self.swap_size_btn = QToolButton()
        self.swap_size_btn.setIcon(FluentIcon.ROTATE.icon()) 
        self.swap_size_btn.setToolTip("互换宽度和高度")
        self.swap_size_btn.clicked.connect(self.swap_image_size)
        size_input_layout.addWidget(self.swap_size_btn)

        # 高度
        size_input_layout.addWidget(QLabel("H:"))
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 4096)
        self.height_spin.setValue(config_manager.get('bizyair_params.default_height', 1920))
        self.height_spin.setSingleStep(64)
        self.height_spin.setFixedWidth(55)
        size_input_layout.addWidget(self.height_spin)
        size_layout.addLayout(size_input_layout)
        
        # 尺寸预设下拉菜单 (同一行)
        preset_layout = QHBoxLayout()
        preset_layout.setContentsMargins(0, 0, 0, 0)
        
        self.resolution_combo = ComboBox()
        self.resolution_combo.addItem("分辨率预设", None)
        for name, size in PRESET_RESOLUTIONS.items():
            self.resolution_combo.addItem(name, size) 
        self.resolution_combo.activated.connect(self.set_preset_resolution) # 修正信号连接
        preset_layout.addWidget(self.resolution_combo)

        self.aspect_ratio_combo = ComboBox()
        self.aspect_ratio_combo.addItem("比例预设", None)
        for name, ratio in ASPECT_RATIOS.items():
            self.aspect_ratio_combo.addItem(name, ratio)
        self.aspect_ratio_combo.activated.connect(self.set_aspect_ratio) # 修正信号连接
        preset_layout.addWidget(self.aspect_ratio_combo)
        size_layout.addLayout(preset_layout)
        
        control_modules_layout.addWidget(size_widget)
        control_modules_layout.setStretchFactor(size_widget, 2)


        # --- 2. 图片数量 (中) ---
        count_widget = QWidget()
        count_widget.setObjectName("count_widget")
        count_layout = QVBoxLayout(count_widget)
        count_layout.setContentsMargins(0, 0, 0, 0) # 移除边框，内容紧凑
        
        count_input_layout = QHBoxLayout()
        count_input_layout.setContentsMargins(0, 0, 0, 0)
        self.image_count_spin = QSpinBox()
        self.image_count_spin.setRange(5, 20)
        self.image_count_spin.setSingleStep(5)
        self.image_count_spin.setValue(config_manager.get('ui.default_image_count', 10))
        self.image_count_spin.setFixedWidth(50)
        self.image_count_spin.valueChanged.connect(self.image_count_changed)
        count_input_layout.addWidget(self.image_count_spin)

        count_info = QLabel("张 (5的倍数)")
        count_info.setStyleSheet("color: #666; font-size: 12px;")
        count_input_layout.addWidget(count_info)
        count_input_layout.addStretch()
        count_layout.addLayout(count_input_layout)
        
        count_layout.addWidget(QLabel("图片总数")) # 占位符或其他说明
        
        control_modules_layout.addWidget(count_widget)
        control_modules_layout.setStretchFactor(count_widget, 1)

        # --- 3. 模板管理 (右) ---
        template_widget = QWidget()
        template_widget.setObjectName("template_widget")
        template_layout = QVBoxLayout(template_widget)
        template_layout.setContentsMargins(0, 0, 0, 0) # 移除边框，内容紧凑

        template_btn = PushButton(FluentIcon.EDIT, "管理提示词模板")
        template_btn.clicked.connect(self.show_template_manager)
        template_layout.addWidget(template_btn)
        
        template_layout.addWidget(QLabel("模板编辑")) # 占位符或其他说明
        
        control_modules_layout.addWidget(template_widget)
        control_modules_layout.setStretchFactor(template_widget, 1)


        # 添加到主布局
        control_layout.addLayout(control_modules_layout)

        left_layout.addWidget(control_card)
        left_layout.addStretch()

        return left_widget

    # --- 尺寸预设逻辑 (修复 ComboBox Bug) ---
    @pyqtSlot(int) # 修正：接收 index
    def set_preset_resolution(self, index):
        """根据选择的分辨率预设设置尺寸"""
        if index == 0:
            return
            
        data = self.resolution_combo.itemData(index)
        
        if data and isinstance(data, tuple):
            width, height = data
            self.width_spin.setValue(width)
            self.height_spin.setValue(height)
            
        # 必须在操作结束后重置为 index 0，防止 ComboBox 内部尝试将数据渲染为图标
        QTimer.singleShot(250, lambda: self.resolution_combo.setCurrentIndex(0)) 
        
    @pyqtSlot(int) # 修正：接收 index
    def set_aspect_ratio(self, index):
        """根据选择的比例预设设置尺寸"""
        if index == 0:
            return
            
        ratio = self.aspect_ratio_combo.itemData(index)
        
        if ratio and isinstance(ratio, (float, int)):
            current_width = self.width_spin.value()
            current_height = self.height_spin.value()
            
            # 选择一个较大的值作为基准 (避免极小值导致计算不准确)
            base_size = max(current_width, current_height, 1080)
            
            # 假设基准是宽度，计算高度
            if ratio >= 1: # 横向或方形 (如 16:9, 4:3, 1:1, 21:9)
                new_width = base_size
                new_height = int(new_width / ratio)
            else: # 纵向 (如 2:3)
                new_height = base_size
                new_width = int(new_height * ratio)

            self.width_spin.setValue(new_width)
            self.height_spin.setValue(new_height)

        # 必须在操作结束后重置为 index 0，防止 ComboBox 内部尝试将数据渲染为图标
        QTimer.singleShot(250, lambda: self.aspect_ratio_combo.setCurrentIndex(0)) 
    # --- 尺寸预设逻辑结束 ---
    
    def create_right_panel(self):
        """创建右侧面板 - 图片生成区"""
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setSpacing(15)

        # 图片生成设置区 (保留)
        generate_card = ElevatedCardWidget()
        generate_layout = QVBoxLayout(generate_card)
        generate_layout.setContentsMargins(20, 20, 20, 20)

        generate_title = SubtitleLabel("🎨 图片生成设置")
        generate_title.setFont(QFont("", 14, QFont.Bold))
        generate_layout.addWidget(generate_title)

        # 生成绘图提示词
        prompt_btn_layout = QHBoxLayout()
        self.generate_prompt_btn = PrimaryPushButton(FluentIcon.LINK, "生成绘图提示词")
        self.generate_prompt_btn.clicked.connect(self.generate_prompts)
        prompt_btn_layout.addWidget(self.generate_prompt_btn)

        self.prompt_progress = ProgressBar()
        self.prompt_progress.setFixedHeight(8)
        prompt_btn_layout.addWidget(self.prompt_progress)
        generate_layout.addLayout(prompt_btn_layout)
        
        # 生成的绘图提示词显示区
        prompts_label = QLabel("绘图提示词 (可编辑):")
        prompts_label.setFont(QFont("", 12, QFont.Bold))
        generate_layout.addWidget(prompts_label)

        self.generated_prompts_edit = QTextEdit()
        self.generated_prompts_edit.setPlaceholderText("点击\"生成绘图提示词\"后，这里将显示生成的提示词，您可以编辑修改...")
        self.generated_prompts_edit.setMinimumHeight(120)
        self.generated_prompts_edit.setMaximumHeight(200)
        generate_layout.addWidget(self.generated_prompts_edit)

        # 仅生成图片按钮
        self.generate_images_btn = PrimaryPushButton(FluentIcon.PHOTO, "仅生成图片")
        self.generate_images_btn.clicked.connect(self.generate_images_only)
        generate_layout.addWidget(self.generate_images_btn)

        right_layout.addWidget(generate_card)

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

        right_layout.addWidget(progress_card)

        # 图片预览区域 (占据剩余空间)
        preview_card = ElevatedCardWidget()
        preview_layout = QVBoxLayout(preview_card)
        preview_layout.setContentsMargins(20, 20, 20, 20)

        preview_title = SubtitleLabel("🖼️ 图片预览")
        preview_title.setFont(QFont("", 14, QFont.Bold))
        preview_layout.addWidget(preview_title)

        # 创建可滚动的图片网格
        self.image_scroll_area = SmoothScrollArea()
        self.image_scroll_widget = QWidget()
        self.image_grid_layout = QGridLayout(self.image_scroll_widget)
        self.image_grid_layout.setSpacing(15)

        self.image_scroll_area.setWidget(self.image_scroll_widget)
        self.image_scroll_area.setWidgetResizable(True)
        preview_layout.addWidget(self.image_scroll_area)

        right_layout.addWidget(preview_card)
        
        # 导出操作区 (移除，功能已移至顶部)
        # right_layout.addStretch()

        return right_widget
    
    # ... (其他方法保持不变)

    def image_count_changed(self, value):
        """图片数量改变时，重新初始化图片预览小部件"""
        config_manager.set('ui.default_image_count', value)
        config_manager.save_config()
        self.init_image_widgets()

    def init_image_widgets(self):
        """初始化图片预览小部件"""
        # 清空现有小部件
        for i in reversed(range(self.image_grid_layout.count())):
            child = self.image_grid_layout.itemAt(i).widget()
            if child is not None:
                child.setParent(None)

        self.image_widgets.clear()
        self.image_urls.clear() # 清空URL列表
        image_count = self.image_count_spin.value()
        
        # 创建新的小部件网格
        cols = 3
        for i in range(image_count):
            widget = ImagePreviewWidget(i)
            self.image_widgets.append(widget)
            self.image_urls.append('')
            row = i // cols
            col = i % cols
            self.image_grid_layout.addWidget(widget, row, col)
            
        # 添加一个空白占位符，确保网格布局正确拉伸
        if self.image_grid_layout.count() > 0:
            spacer = QWidget()
            spacer.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
            # 确保添加到下一行
            self.image_grid_layout.addWidget(spacer, (self.image_count_spin.value() + cols - 1) // cols, 0)


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
        dialog.exec_()

    def set_image_size(self, width, height):
        """设置图片尺寸"""
        self.width_spin.setValue(width)
        self.height_spin.setValue(height)
        config_manager.set('bizyair_params.default_width', width)
        config_manager.set('bizyair_params.default_height', height)
        config_manager.save_config()
        
    def swap_image_size(self):
        """互换宽度和高度"""
        current_width = self.width_spin.value()
        current_height = self.height_spin.value()
        
        self.width_spin.setValue(current_height)
        self.height_spin.setValue(current_width)
        
        config_manager.set('bizyair_params.default_width', current_height)
        config_manager.set('bizyair_params.default_height', current_width)
        config_manager.save_config()


    # --- 文本生成核心逻辑 (保留，仅清理了部分不用的打印和变量) ---

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
            target_count = self.image_count_spin.value()
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
            target_count = self.image_count_spin.value()
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

    # --- 修复：单次 API 调用生成所有绘图提示词 ---
    def generate_prompts(self):
        """生成绘图提示词 (单次 API 调用)"""
        summary_text = self.summary_output_edit.toPlainText().strip()
        if not summary_text:
            QMessageBox.warning(self, "警告", "请先生成分镜描述")
            return

        template = config_manager.get_template('image_prompt')
        system_prompt = template.get('template', '')
        
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
            # 移除所有空行、可能出现的序号和解释
            raw_prompts = [line.strip() for line in result.split('\n') if line.strip()]
            
            # 重新格式化并解析为 self.current_prompts 列表
            final_display_text = ""
            self.current_prompts.clear()
            
            target_count = self.image_count_spin.value()
            
            # 过滤掉标题、序号和非英文内容，只保留实际的英文提示词
            clean_prompts = []
            for line in raw_prompts:
                 # 简单的过滤规则：排除包含中文、等号或分镜字样的行，且长度不为零
                 if not re.search(r'[\u4e00-\u9fa5]|=|\*', line) and len(line) > 5:
                     clean_prompts.append(line)
            
            for i, prompt in enumerate(clean_prompts):
                if i < target_count:
                    self.current_prompts.append(prompt)
                    final_display_text += f"=== 分镜 {i+1} ===\n{prompt}\n\n"
            
            # 如果数量不足，用空字符串填充
            while len(self.current_prompts) < target_count:
                self.current_prompts.append('')

            self.generated_prompts_edit.setPlainText(final_display_text.strip())
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

    # --- 图片生成核心逻辑 (修改：适配 BizyAIR 批量，移除旧的单图逻辑) ---

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

        # 确保提示词数量与 UI 设置的数量一致
        target_count = self.image_count_spin.value()
        if len(self.current_prompts) > target_count:
            self.current_prompts = self.current_prompts[:target_count]
        elif len(self.current_prompts) < target_count:
            # 填充提示词
            last_prompt = self.current_prompts[-1] if self.current_prompts else ""
            self.current_prompts.extend([last_prompt] * (target_count - len(self.current_prompts)))

        # 获取当前尺寸设置
        width = self.width_spin.value()
        height = self.height_spin.value()

        # 更新 BizyAIR 默认配置
        config_manager.set('bizyair_params.default_width', width)
        config_manager.set('bizyair_params.default_height', height)
        config_manager.save_config()

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
        
        # 启动图片生成 (批量一次性发送)
        self.generate_images_btn.setEnabled(False)
        self.top_control_bar.set_generate_enabled(False) # 禁用一键生成按钮和导出按钮
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备生成图片...")
        
        # 获取图片数量（以 UI 设置为准）
        image_count = self.image_count_spin.value()

        # 创建图片生成worker
        self.image_worker = ImageGenerationWorker(
            self.current_prompts,
            width,
            height,
            image_count
        )
        
        # 连接信号
        self.image_worker.progress_updated.connect(self.on_batch_image_progress)
        self.image_worker.image_generated.connect(self.on_batch_image_url_received)
        self.image_worker.finished.connect(self.on_all_images_finished)

        # 启动worker
        self.image_worker.start()
        self.image_worker.finished.connect(lambda: self.image_worker.deleteLater())

    def on_batch_image_progress(self, progress, msg):
        """批量图片生成进度"""
        self.image_progress.setValue(progress)
        self.image_status_label.setText(msg)

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
            self.image_status_label.setText("图片生成完成！")
            success_count = sum(1 for url in urls if url)
            QMessageBox.information(self, "成功", f"成功生成 {success_count}/{self.image_count_spin.value()} 张图片！")
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
        # self.clear_content() # 清空所有旧内容
        self.title_output_edit.clear()
        self.summary_output_edit.clear()
        self.generated_prompts_edit.clear()
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备就绪")
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

                    image_count = self.image_count_spin.value()
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

        timestamp = datetime.now().strftime('%m%d%H%M%S')
        export_count = 0

        for i, widget in enumerate(self.image_widgets):
            if widget.image_url: # 使用 URL 而不是 widget.image
                try:
                    file_name = f"storyboard_{timestamp}_{i+1}.png"
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
            QMessageBox.information(self, "成功", f"已导出 {export_count} 张图片到:\n{output_dir}")
        else:
            QMessageBox.warning(self, "警告", "没有可导出的图片")


# 主窗口 (精简)
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

        width = config_manager.get('ui.window_width', 1600)
        height = config_manager.get('ui.window_height', 1000)
        self.resize(width, height)

    def init_navigation(self):
        """初始化导航栏"""
        self.storyboard_page = StoryboardPage(self)
        self.storyboard_page.setObjectName("storyboard_page")
        self.addSubInterface(
            self.storyboard_page,
            FluentIcon.VIDEO,
            "分镜生成",
            NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_settings_page(),
            FluentIcon.SETTING,
            "设置",
            NavigationItemPosition.BOTTOM
        )

    def open_directory(self, dir_path):
        """打开指定的本地目录"""
        if os.path.exists(dir_path):
            QDesktopServices.openUrl(QUrl.fromLocalFile(os.path.abspath(dir_path)))
        else:
            QMessageBox.warning(self, "警告", f"目录不存在: {os.path.abspath(dir_path)}")

    def create_settings_page(self):
        """创建设置页面 (精简图片设置)"""
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
        self.api_key_edit.setPlaceholderText("请输入 API密钥...")
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        self.api_key_edit.setFixedHeight(32)
        self.api_key_edit.setText(config_manager.get('api.api_key', ''))
        api_layout.addWidget(self.api_key_edit, 0, 1)

        api_layout.addWidget(QLabel("文本 API URL:"), 1, 0)
        self.api_url_edit = LineEdit()
        self.api_url_edit.setFixedHeight(32)
        self.api_url_edit.setText(config_manager.get('api.base_url', 'https://api.siliconflow.cn/v1/'))
        api_layout.addWidget(self.api_url_edit, 1, 1)

        api_layout.addWidget(QLabel("文本模型:"), 2, 0)
        self.text_model_edit = LineEdit()
        self.text_model_edit.setFixedHeight(32)
        self.text_model_edit.setText(config_manager.get('api.text_model', 'Qwen/Qwen3-Coder-480B-A35B-Instruct'))
        api_layout.addWidget(self.text_model_edit, 2, 1)
        
        # BizyAIR App ID
        api_layout.addWidget(QLabel("BizyAIR App ID:"), 3, 0)
        self.bizyair_app_id_spin = QSpinBox()
        self.bizyair_app_id_spin.setRange(1, 99999)
        self.bizyair_app_id_spin.setValue(config_manager.get('bizyair_params.web_app_id', 39808))
        self.bizyair_app_id_spin.setFixedHeight(32)
        api_layout.addWidget(self.bizyair_app_id_spin, 3, 1)


        api_group.setLayout(api_layout)
        layout.addWidget(api_group)
        
        # 目录设置
        dir_group = QGroupBox("📁 目录设置")
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
        ui_layout = QGridLayout()

        ui_layout.addWidget(QLabel("默认图片数量:"), 0, 0)
        self.default_image_count_spin = QSpinBox()
        self.default_image_count_spin.setRange(5, 20)
        self.default_image_count_spin.setSingleStep(5)
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
        config_manager.set('api.api_key', self.api_key_edit.text().strip())
        config_manager.set('api.base_url', self.api_url_edit.text().strip())
        config_manager.set('api.text_model', self.text_model_edit.text().strip())
        config_manager.set('bizyair_params.web_app_id', self.bizyair_app_id_spin.value())
        
        # 更新默认图片数量，并同步到 StoryboardPage
        new_image_count = self.default_image_count_spin.value()
        config_manager.set('ui.default_image_count', new_image_count)
        self.storyboard_page.image_count_spin.setValue(new_image_count)

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
            border: 2px solid #cccccc;
            border-radius: 8px;
            margin-top: 1ex;
            padding-top: 10px;
        }
        QGroupBox::title {
            subcontrol-origin: margin;
            left: 10px;
            padding: 0 5px 0 5px;
        }
        /* 移除生成控制区内部模块的QGroupBox样式 */
        #count_widget, #template_widget, #size_widget {
            border: none;
            padding: 0;
            margin: 0;
        }
        ComboBox, LineEdit, SpinBox, DoubleSpinBox {
            padding: 5px;
            border: 1px solid #cccccc;
            border-radius: 4px;
            background: white;
        }
        ComboBox:hover, LineEdit:hover, SpinBox:hover, DoubleSpinBox:hover {
            border-color: #888888;
        }
        ComboBox:focus, LineEdit:focus, SpinBox:focus, DoubleSpinBox:focus {
            border-color: #0078d4;
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
    window.show()

    sys.exit(app.exec_())

if __name__ == "__main__":
    main()