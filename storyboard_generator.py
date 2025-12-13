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
                            QSpinBox, QDoubleSpinBox, QSizePolicy, QButtonGroup)
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
MODEL_API_KEY = os.getenv('SiliconCloud_API_KEY')

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
                "base_url": "https://api.siliconflow.cn/v1/",
                "text_model": "Qwen/Qwen3-Coder-480B-A35B-Instruct",
                "enable_thinking": True,
                "api_key": MODEL_API_KEY or ""
            },
            "prompt_templates": {
                "story_title": {
                    "name": "故事分镜标题模板",
                    "template": """你是一位专业的故事绘本撰写专家，擅长电影级别的故事绘本脚本编辑。请根据用户提供的一段话或一个叙事事件内容，展开联想拓展形成一个完整的故事情节。通过故事情节的时间线拆解生成从头到尾10个完整吸引人的故事绘本分镜标题脚本。每个分镜脚本标题控制在64字以内，分镜脚本标题需要有景别，视角，运镜，画面内容，遵循主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言+价值主张的原则。
    分镜脚本标题应该具有吸引力，精炼，能够引起观看者的兴趣，同时准确反映该分镜的核心内容。
    
    ## 在分析过程中，请思考：
    1. 故事绘本的核心主题和关键价值点
    2. 目标受众的兴趣点
    3. 不同角度的故事绘本表达方式（景别，视角，运镜、画面情感激发等），景别除开特别注明要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。
    4. 遵循主体+场景+运动+情感+价值主张的原则。故事绘本分镜脚本标题=主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言
    5. 主体描述：主体描述是对主体外观特征细节的描述，可通过形容词或短句列举。如果标题上有主体，每段标题都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的配图主体统一。
    6. 场景描述：场景描述是对主体所处环境特征细节的描述，可通过形容词或短句列举。
    7. 运动描述：运动描述是对运动特征细节的描述，包含运动的幅度、速率和运动作用的效果。
    8. 镜头语言：镜头语言包含景别、视角、镜头、运镜等。分镜脚本标题中的景别最好能全部保持一致性，不用超过3种以上的景别跳跃。
### 分镜标题示例：

- 分镜标题1. 【全景俯视】锈迹斑斑机器人在荒芜废土中孤独游荡，身后拖着能源即将耗尽的微弱蓝光轨迹，镜头缓缓下摇展现末世荒凉。
- 分镜标题2. 【中景跟拍】老旧机器人机械臂清理破败瓦砾堆，蓝光眼闪烁着程序混乱的信号，镜头推进聚焦它疲惫不堪的金属身躯。
- 分镜标题3. 【特写仰拍】机器人单眼蓝光突然聚焦，破旧金属残骸缝隙中透出一缕神秘微光，镜头从指间缝隙穿插营造发现的惊喜。
…… 其他分镜标题按序号依次列出，一行一个。

"""
                },
                "story_summary": {
                    "name": "故事分镜描述模板",
                    "template": """你是一位专业的短视频脚本描述专家，擅长电影级别的视频脚本编辑描述。请根据用户提供的故事绘本分镜脚本标题，按批次生成该脚本片段短视频描述，每个片段按序号生成一段丰富的视频脚本描述文字，每个分镜脚本描述控制在120字以内。
    ### 每个片段描述应该：
    1. 准确概括故事绘本分镜脚本标题的核心内容，景别，视角，运镜、画面情感和价值主张。景别除开特别要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。
    2. 使用丰富、生动的镜头语言描述，按照导演视角，将镜头语言和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。
    3. 描述的语言能吸引观看者观看，要有画面感。每段描述都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的脚本主体统一。
    4. 丰富细节，聚焦视频片段的主要观点，遵循主体+场景+运动+情感+价值主张的原则。
    5. 视频片段描述=运镜描述+主体（主体描述）＋场景（场景描述）+运动（运动描述）+镜头语言。
    6. 运镜描述是对镜头运动的具体描述，在时间线上，景别最好能保持一致性，不用太离谱的跳跃。将镜头运动和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。用户可以通过代入导演的视角来想象和书写运镜过程。时间上，需要注意将镜头运动的时长合理控制在5s内，避免过于复杂的运镜，短视频脚本描述中的运镜不要超过3种以上。
    ### 分镜描述示例：
    **分镜1：**
远景俯视跟拍，锈迹斑斑的老式机器人在荒芜金属废土中孤独踱步，蓝眼微光闪烁。沙尘弥漫的末世景象中，镜头缓缓下降跟随其沉重步伐。破败的高楼废墟背景烘托出绝望氛围，机器人踉跄的身影诠释着废弃文明中最后守望者的坚韧与孤寂。

**分镜2：**
中景侧拍推镜，机身破损的探险机器人在破败城市废墟中艰难前行，能源指示灯忽明忽暗。钢筋裸露的残垣断壁间，机械臂奋力拨开厚重碎石。镜头逐渐推进展现机器人执着神情，飞扬的尘土与扭曲金属构建成充满压迫感的绝望环境。

**分镜3：**
特写静止镜头，老式机器人呆滞的蓝眼突然闪烁光芒，瞳孔收缩聚焦。碎石堆下透出的微光映照在其金属面庞上，形成明暗交替的光影效果。突如其来的停顿打破沉寂，预示着程序重启的契机即将到来，命运在此刻悄然转折。

……其他分镜描述按序号依次列出，一行分镜序号，一行分镜描述，一行空格。

    """
                },
                "image_prompt": {
                    "name": "AI绘图提示词模板",
                    "template": """请根据用户提供的故事分镜描述，将中文描述的分镜头脚本内容翻译成英文，并按照每个分镜头一个句子的原则，每行仅包含一个分镜头的描述。请保证翻译的准确性以及对原意的忠实度，同时使描述适合用于AI绘画生成工具的输入。最终输出应该是一个专业用于AI绘画软件（如Midjourney,comfyui,stable diffusion）的简约易用的英文提示词，不需要解释，并确保输出中没有中文及特殊符号，放在同一行显示。prompt英文提示词应该图片主体描述统一，包含画面主题内容描述、风格指导和质量提升词，精炼，简约明了，不要过长。
    ### AI绘图提示词（示例），一行标题，一行AI绘画提示词，空一行： 
=== 分镜 1 ===
Face the camera, showing the upper body Aerial view following an old, rusted robot walking alone in a desolate metal wasteland, with its blue eyes faintly glowing.

=== 分镜 2 ===
Face the camera, showing the upper body Aerial view following an old, rusted robot walking alone in a desolate metal wasteland, with its blue eyes faintly glowing. The camera slowly descends as dust fills the post-apocalyptic landscape. Background of ruined skyscrapers creates a desperate atmosphere, while the robot's staggering figure embodies the resilience and solitude of the last guardian in an abandoned civilization.

=== 分镜 3 ===
Face the camera, showing the upper body Medium shot side view pushing in on an exploration robot with a damaged body moving through the ruins of a broken city, its energy indicator flickering on and off.

……其他AI绘画提示词分镜按序号依次列出。

    """
                }
            },
            "ui": {
                "theme": "dark",
                "window_width": 1440,
                "window_height": 940,
                "default_image_count": 10
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

# 线程管理器
class ThreadManager:
    """线程管理器，负责管理所有活跃的工作线程"""

    def __init__(self):
        self.active_workers = []
        self.lock = threading.Lock()

    def add_worker(self, worker):
        """添加新的工作线程"""
        with self.lock:
            # 清理已完成的线程
            self.cleanup()
            # 添加新线程
            self.active_workers.append(worker)
            logger.info(f"添加新线程，当前活跃线程数: {len(self.active_workers)}")

    def cleanup(self):
        """清理已完成的线程"""
        with self.lock:
            # 过滤出仍在运行的线程
            before_count = len(self.active_workers)
            self.active_workers = [w for w in self.active_workers if w.isRunning()]
            after_count = len(self.active_workers)

            if before_count != after_count:
                logger.info(f"清理了 {before_count - after_count} 个已完成的线程")

    def cancel_all(self):
        """取消所有活跃线程"""
        with self.lock:
            for worker in self.active_workers:
                if hasattr(worker, 'cancel'):
                    worker.cancel()
                if hasattr(worker, 'quit'):
                    worker.quit()
                if hasattr(worker, 'wait'):
                    worker.wait(1000)  # 等待最多1秒

            self.active_workers.clear()
            logger.info("已取消所有活跃线程")

    def get_active_count(self):
        """获取活跃线程数量"""
        with self.lock:
            self.cleanup()
            return len(self.active_workers)

# 全局线程管理器
thread_manager = ThreadManager()

# 全局请求时间跟踪
_last_request_time = 0

# 文本生成工作线程
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
            # 记录开始时间
            self.start_time = time.time()
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 开始生成内容...")
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 模型: {self.model_id}")
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 输入长度: {len(self.content)} 字符")

            # 发送初始状态
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 发送初始化信号...")
            self.progress_updated.emit("正在初始化AI模型...")

            api_key = config_manager.get('api.api_key', MODEL_API_KEY)
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] API密钥: {'已配置' if api_key else '未配置'}")
            if not api_key:
                print(f"[{time.strftime('%H:%M:%S')}] [Worker] 错误: API密钥未配置")
                self.finished.emit(False, "API密钥未配置")
                return

            # 添加延迟以避免频率限制
            global _last_request_time
            elapsed = time.time() - _last_request_time
            if elapsed < 1.5:  # 两次请求间隔至少1.5秒
                wait_time = 1.5 - elapsed
                print(f"[{time.strftime('%H:%M:%S')}] [Worker] 等待 {wait_time:.1f} 秒以避免频率限制...")
                time.sleep(wait_time)
            _last_request_time = time.time()

            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 创建OpenAI客户端...")
            # 使用SiliconFlow API
            client = OpenAI(
                base_url=config_manager.get('api.siliconflow_text', 'https://api.siliconflow.cn/v1/'),
                api_key=api_key,
            )

            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 发送生成内容信号...")
            self.progress_updated.emit("正在生成内容...")

            # 创建响应
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] 创建API请求...")
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
            print(f"[{time.strftime('%H:%M:%S')}] [Worker] API请求已创建，开始处理响应...")

            content_text = ""
            char_count = 0
            chunk_count = 0

            # 处理流式响应
            for chunk in response:
                chunk_count += 1
                if chunk_count % 10 == 0:  # 每10个chunk打印一次
                    print(f"[{time.strftime('%H:%M:%S')}] [Worker] 已处理 {chunk_count} 个chunks")
                if self.is_cancelled:
                    break

                try:
                    # 安全访问API响应
                    if not chunk.choices or len(chunk.choices) == 0:
                        continue

                    choice = chunk.choices[0]
                    if not hasattr(choice, 'delta') or not choice.delta:
                        continue

                    delta = choice.delta
                    content_chunk = getattr(delta, 'content', None)

                    if content_chunk and content_chunk != '':
                        content_text += content_chunk
                        char_count += len(content_chunk)

                        # 实时更新内容显示
                        self.content_updated.emit(content_text)

                        # 每500字符更新一次进度
                        if char_count % 500 == 0:
                            elapsed = time.time() - self.start_time
                            speed = char_count / elapsed if elapsed > 0 else 0
                            self.progress_updated.emit(f"生成中... 已生成 {len(content_text)} 字符 (速度: {speed:.1f} 字符/秒)")

                except Exception as e:
                    logger.error(f"处理API响应时出错: {e}")
                    continue

            # 计算总用时
            elapsed_time = time.time() - self.start_time
            print(f"[{time.strftime('%H:%M:%S')}] 生成完成！")
            print(f"[{time.strftime('%H:%M:%S')}] 输出长度: {len(content_text)} 字符")
            print(f"[{time.strftime('%H:%M:%S')}] 总用时: {elapsed_time:.2f} 秒")
            print(f"[{time.strftime('%H:%M:%S')}] 平均速度: {len(content_text)/elapsed_time:.1f} 字符/秒")
            print("-" * 50)

            # 确保最终结果被发送
            if not self.is_cancelled:
                self.finished.emit(True, content_text)
            else:
                self.finished.emit(False, "任务已取消")

        except Exception as e:
            logger.error(f"文本生成失败: {e}")
            print(f"[{time.strftime('%H:%M:%S')}] 生成失败: {str(e)}")
            self.finished.emit(False, f"生成失败: {str(e)}")

# 图片生成工作线程（使用新的异步接口）
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
        # BizyAIR API 一次最多 5 张，这里我们将所有提示词一次性传给它
        self.image_count = min(image_count, len(prompts)) 
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
            
            # 确保提示词数量是 5 的倍数，不足则用空字符串填充到下一个 5 的倍数
            batch_size = 5
            total_prompts_to_send = (self.image_count + batch_size - 1) // batch_size * batch_size

            # 填充提示词
            batch_prompts = self.prompts[:self.image_count]
            while len(batch_prompts) < total_prompts_to_send:
                # 填充空字符串，确保 API 接收 5 的倍数数量
                batch_prompts.append("") 
            
            # 构建 input_values
            input_values = {
                "35:EmptyLatentImage.width": self.width,
                "35:EmptyLatentImage.height": self.height
            }
            for i, prompt in enumerate(batch_prompts):
                input_values[f"42:easy promptList.prompt_{i+1}"] = prompt
            
            # 提交任务
            self.progress_updated.emit(5, "正在提交 BizyAIR 图片生成任务...")
            response = requests.post(
                base_url,
                headers=common_headers,
                json={
                    "web_app_id": self.web_app_id,
                    "suppress_preview_output": False,
                    "input_values": input_values
                },
                timeout=180
            )

            response.raise_for_status()
            result = response.json()

            if result.get("status") == "Success" and result.get("outputs"):
                outputs = result["outputs"]
                
                # 仅处理实际需要的图片数量
                for i in range(self.image_count):
                    if i < len(outputs) and outputs[i].get("object_url"):
                        img_url = outputs[i]["object_url"]
                        self.image_urls[i] = img_url
                        self.image_generated.emit(i, None, img_url)
                        
                        # 更新进度 (10% + 已完成百分比 * 90%)
                        progress = 10 + int(((i + 1) / self.image_count) * 90)
                        self.progress_updated.emit(progress, f"已生成 {i+1}/{self.image_count} 张图片 URL")
                    else:
                        logger.error(f"生成第 {i+1} 张图片失败: 输出缺失")

                self.progress_updated.emit(100, "图片生成完成!")
                self.finished.emit(not self.is_cancelled, [], self.image_urls)
            else:
                error_msg = result.get("message", "未知错误")
                logger.error(f"图片生成失败: {result}")
                self.finished.emit(False, [], [])
        except Exception as e:
            logger.error(f"图片生成失败: {e}")
            self.finished.emit(False, [], [])

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
        # 清空编辑框
        self.template_name_edit.clear()
        self.template_content_edit.clear()
        # 设置焦点到名称输入框
        self.template_name_edit.setFocus()

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

    def import_template(self):
        """导入模板"""
        file_path, _ = QFileDialog.getOpenFileName(
            self, "导入模板文件", "", "JSON Files (*.json)"
        )
        if file_path:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    template_data = json.load(f)

                # 验证模板格式
                if not isinstance(template_data, dict) or 'name' not in template_data or 'template' not in template_data:
                    QMessageBox.warning(self, "警告", "无效的模板文件格式")
                    return

                # 询问模板名称
                template_name = template_data.get('name', '导入的模板')
                template_key = template_name.replace(' ', '_').lower()

                # 保存模板
                if config_manager.save_template(template_key, template_data):
                    QMessageBox.information(self, "成功", f"模板 '{template_name}' 导入成功")
                    self.load_templates()
                    # 选中刚导入的模板
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

        # 主要内容区域 - 左右分栏
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

        # 生成控制区
        control_card = CardWidget()
        control_layout = QVBoxLayout(control_card)
        control_layout.setContentsMargins(20, 20, 20, 20)

        control_header = SubtitleLabel("⚙️ 生成控制")
        control_header.setFont(QFont("", 14, QFont.Bold))
        control_layout.addWidget(control_header)

        # 图片数量和提示词前缀在同一行
        control_row_layout = QHBoxLayout()

        # 图片数量（必须是5的倍数）
        count_group = QGroupBox("图片数量 (5的倍数)")
        count_layout = QHBoxLayout()
        self.image_count_spin = QSpinBox()
        self.image_count_spin.setRange(5, 20)
        self.image_count_spin.setSingleStep(5)  # 步进为5
        self.image_count_spin.setValue(10)  # 默认值为10
        self.image_count_spin.setFixedWidth(80)
        count_layout.addWidget(self.image_count_spin)

        # 添加说明标签
        count_info = QLabel("批次数×5")
        count_info.setStyleSheet("color: #666; font-size: 12px;")
        count_layout.addWidget(count_info)

        count_group.setLayout(count_layout)
        control_row_layout.addWidget(count_group)

        # 提示词前缀
        prefix_group = QGroupBox("提示词前缀")
        prefix_layout = QHBoxLayout()
        self.prompt_prefix_edit = LineEdit()
        self.prompt_prefix_edit.setPlaceholderText("统一的风格关键词")
        self.prompt_prefix_edit.setText("Face the camera, showing the upper body,")
        self.prompt_prefix_edit.setFixedHeight(32)
        prefix_layout.addWidget(self.prompt_prefix_edit)
        prefix_group.setLayout(prefix_layout)
        control_row_layout.addWidget(prefix_group)

        control_layout.addLayout(control_row_layout)

        # 一键生成按钮
        self.generate_all_btn = PrimaryPushButton(FluentIcon.PLAY, "一键生成全部")
        self.generate_all_btn.clicked.connect(self.generate_all)
        self.generate_all_btn.setFixedHeight(40)
        control_layout.addWidget(self.generate_all_btn)

        # 设置按钮和图片尺寸
        settings_layout = QHBoxLayout()

        # 图片尺寸设置
        size_group = QGroupBox("图片尺寸")
        size_layout = QHBoxLayout()

        size_layout.addWidget(QLabel("宽度:"))
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 4096)
        self.width_spin.setValue(1080)
        self.width_spin.setSingleStep(64)
        self.width_spin.setFixedWidth(80)
        size_layout.addWidget(self.width_spin)

        size_layout.addWidget(QLabel("高度:"))
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 4096)
        self.height_spin.setValue(1920)
        self.height_spin.setSingleStep(64)
        self.height_spin.setFixedWidth(80)
        size_layout.addWidget(self.height_spin)

        # 预设尺寸按钮
        preset_1080p_btn = PushButton("1080P")
        preset_1080p_btn.setFixedSize(60, 32)
        preset_1080p_btn.clicked.connect(lambda: self.set_image_size(1080, 1920))
        size_layout.addWidget(preset_1080p_btn)

        preset_720p_btn = PushButton("720P")
        preset_720p_btn.setFixedSize(60, 32)
        preset_720p_btn.clicked.connect(lambda: self.set_image_size(720, 1280))
        size_layout.addWidget(preset_720p_btn)

        size_group.setLayout(size_layout)
        settings_layout.addWidget(size_group)

        # 其他按钮
        template_btn = PushButton(FluentIcon.EDIT, "模板管理")
        template_btn.clicked.connect(self.show_template_manager)
        settings_layout.addWidget(template_btn)

        settings_layout.addStretch()
        control_layout.addLayout(settings_layout)

        left_layout.addWidget(control_card)
        left_layout.addStretch()

        return left_widget

    def create_right_panel(self):
        """创建右侧面板 - 图片生成区"""
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setSpacing(15)

        # 图片生成设置区
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

        # 图片预览区域
        preview_card = ElevatedCardWidget()
        preview_layout = QVBoxLayout(preview_card)
        preview_layout.setContentsMargins(20, 20, 20, 20)

        preview_title = SubtitleLabel("🖼️ 图片预览")
        preview_title.setFont(QFont("", 14, QFont.Bold))
        preview_layout.addWidget(preview_title)

        # 创建可滚动的图片网格
        self.image_scroll_area = ScrollArea()
        self.image_scroll_widget = QWidget()
        self.image_grid_layout = QGridLayout(self.image_scroll_widget)
        self.image_grid_layout.setSpacing(15)

        # 初始化图片预览小部件
        self.init_image_widgets()

        self.image_scroll_area.setWidget(self.image_scroll_widget)
        self.image_scroll_area.setWidgetResizable(True)
        preview_layout.addWidget(self.image_scroll_area)

        right_layout.addWidget(preview_card)

        # 导出操作区
        export_card = CardWidget()
        export_layout = QVBoxLayout(export_card)
        export_layout.setContentsMargins(20, 20, 20, 20)

        export_title = SubtitleLabel("📤 导出操作")
        export_title.setFont(QFont("", 14, QFont.Bold))
        export_layout.addWidget(export_title)

        export_buttons_layout = QHBoxLayout()

        export_md_btn = PrimaryPushButton(FluentIcon.SAVE, "导出Markdown")
        export_md_btn.clicked.connect(self.export_markdown)
        export_buttons_layout.addWidget(export_md_btn)

        export_images_btn = PrimaryPushButton(FluentIcon.FOLDER, "导出全部图片")
        export_images_btn.clicked.connect(self.export_all_images)
        export_buttons_layout.addWidget(export_images_btn)

        export_layout.addLayout(export_buttons_layout)
        right_layout.addWidget(export_card)

        right_layout.addStretch()

        return right_widget

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
        self.title_output_edit.clear()
        self.summary_output_edit.clear()
        self.generated_prompts_edit.clear()  # 清空提示词显示框
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

    def set_image_size(self, width, height):
        """设置图片尺寸"""
        self.width_spin.setValue(width)
        self.height_spin.setValue(height)


    def generate_titles(self):
        """生成分镜标题"""
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, "警告", "请先输入故事内容")
            return

        template = config_manager.get_template('story_title')
        system_prompt = template.get('template', '')

        print(f"[DEBUG] generate_titles called with content: {content[:50]}...")
        self.generate_title_btn.setEnabled(False)
        self.title_progress.setValue(0)

        worker = TextGenerationWorker(content, system_prompt)
        # 使用 unique_connection 避免重复连接
        print(f"[DEBUG] Connecting signals...")
        worker.content_updated.connect(self.update_title_content, Qt.UniqueConnection)
        worker.progress_updated.connect(self.update_title_progress, Qt.UniqueConnection)
        worker.finished.connect(self.on_titles_finished, Qt.UniqueConnection)
        print(f"[DEBUG] Signals connected")

        # 不使用线程管理器，直接启动
        print(f"[DEBUG] Starting worker thread...")
        worker.start()
        print(f"[DEBUG] Worker thread started, isRunning={worker.isRunning()}")

        # 设置线程清理
        worker.finished.connect(lambda: worker.deleteLater())

    def update_title_content(self, text):
        """实时更新标题内容"""
        print(f"[DEBUG] update_title_content called: {len(text)} chars")
        # 直接在输出框显示生成的内容
        self.title_output_edit.setPlainText(text)
        # 滚动到底部
        cursor = self.title_output_edit.textCursor()
        cursor.movePosition(cursor.End)
        self.title_output_edit.setTextCursor(cursor)

    def update_title_progress(self, msg):
        """更新标题生成进度"""
        print(f"[DEBUG] update_title_progress called: {msg}")
        if "初始化" in msg:
            self.title_progress.setRange(0, 0)  # 显示忙碌状态
        elif "生成中" in msg:
            self.title_progress.setRange(0, 100)
            # 解析速度信息
            if "速度" in msg:
                import re
                speed_match = re.search(r'速度: ([\d.]+) 字符/秒', msg)
                if speed_match:
                    speed = float(speed_match.group(1))
                    self.title_progress.setValue(min(90, int(speed * 2)))  # 根据速度设置进度
                else:
                    self.title_progress.setValue(50)
            else:
                self.title_progress.setValue(50)

    def on_titles_finished(self, success, result):
        """分镜标题生成完成"""
        print(f"[DEBUG] on_titles_finished called: success={success}, result_length={len(result) if result else 0}")
        self.generate_title_btn.setEnabled(True)
        self.title_progress.setRange(0, 100)  # 恢复正常进度条
        self.title_progress.setValue(100 if success else 0)

        if success:
            # 内容已经通过content_updated实时显示，这里确保最终结果正确
            self.title_output_edit.setPlainText(result)
            # 解析标题列表
            titles = [t.strip() for t in result.split('\n') if t.strip()]
            if len(titles) >= self.image_count_spin.value():
                self.current_titles = titles[:self.image_count_spin.value()]
            else:
                self.current_titles = titles + [''] * (self.image_count_spin.value() - len(titles))

            # 检查是否是一键生成流程
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 1:
                QMessageBox.information(self, "成功", "分镜标题生成完成！")
                # 继续下一步
                QTimer.singleShot(500, self.step_generate_summaries)
            else:
                QMessageBox.information(self, "成功", "分镜标题生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")
            # 检查是否是一键生成流程
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 1:
                self.generate_all_btn.setEnabled(True)

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

        self.current_worker = TextGenerationWorker(titles_text, system_prompt)
        # 使用 unique_connection 避免重复连接
        self.current_worker.content_updated.connect(self.update_summary_content, Qt.UniqueConnection)
        self.current_worker.progress_updated.connect(self.update_summary_progress, Qt.UniqueConnection)
        self.current_worker.finished.connect(self.on_summaries_finished, Qt.UniqueConnection)

        # 直接启动worker
        print(f"[DEBUG] 启动描述生成worker...")
        self.current_worker.start()
        self.current_worker.finished.connect(lambda: self.current_worker.deleteLater())

    def update_summary_content(self, text):
        """实时更新描述内容"""
        # 直接在输出框显示生成的内容
        self.summary_output_edit.setPlainText(text)
        # 滚动到底部
        cursor = self.summary_output_edit.textCursor()
        cursor.movePosition(cursor.End)
        self.summary_output_edit.setTextCursor(cursor)

    def update_summary_progress(self, msg):
        """更新描述生成进度"""
        if "生成中" in msg:
            self.summary_progress.setValue(50)
        else:
            self.summary_progress.setRange(0, 0)  # 显示忙碌状态

    def on_summaries_finished(self, success, result):
        """分镜描述生成完成"""
        self.generate_summary_btn.setEnabled(True)
        self.summary_progress.setRange(0, 100)  # 恢复正常进度条
        self.summary_progress.setValue(100 if success else 0)

        if success:
            # 内容已经通过content_updated实时显示，这里确保最终结果正确
            self.summary_output_edit.setPlainText(result)
            # 解析描述列表
            summaries = [s.strip() for s in result.split('\n') if s.strip()]
            if len(summaries) >= self.image_count_spin.value():
                self.current_summaries = summaries[:self.image_count_spin.value()]
            else:
                self.current_summaries = summaries + [''] * (self.image_count_spin.value() - len(summaries))

            # 检查是否是一键生成流程
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
                QMessageBox.information(self, "成功", "分镜描述生成完成！")
                # 继续下一步
                QTimer.singleShot(500, self.step_generate_prompts)
            else:
                QMessageBox.information(self, "成功", "分镜描述生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")
            # 检查是否是一键生成流程
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
                self.generate_all_btn.setEnabled(True)

    def generate_prompts(self):
        """生成绘图提示词"""
        # 从分镜描述文本框读取内容
        summary_text = self.summary_output_edit.toPlainText().strip()
        if not summary_text:
            QMessageBox.warning(self, "警告", "请先生成分镜描述")
            return

        # 解析分镜描述列表
        summaries = [s.strip() for s in summary_text.split('\n') if s.strip()]
        if not summaries:
            QMessageBox.warning(self, "警告", "分镜描述内容为空")
            return

        print(f"[DEBUG] 识别到 {len(summaries)} 个分镜描述")
        for i, summary in enumerate(summaries):
            print(f"[DEBUG] 分镜{i+1}: {summary[:50]}...")

        template = config_manager.get_template('image_prompt')
        system_prompt = template.get('template', '')

        self.generate_prompt_btn.setEnabled(False)
        self.prompt_progress.setValue(0)
        self.prompt_progress.setRange(0, 0)  # 显示忙碌状态
        self.current_prompts.clear()
        self.generated_prompts_edit.clear()  # 清空显示框

        # 初始化提示词生成参数
        self.completed_prompts = 0
        self.total_prompts = min(self.image_count_spin.value(), len(summaries))

        print(f"[DEBUG] 将为前 {self.total_prompts} 个分镜生成提示词")

        # 串行生成提示词，避免API频率限制
        self.current_summary_index = 0
        self.current_summaries = summaries[:self.total_prompts]
        self.prompt_system_prompt = system_prompt

        # 启动第一个提示词生成任务
        QTimer.singleShot(100, self.start_next_prompt_generation)

    def start_next_prompt_generation(self):
        """开始下一个提示词生成"""
        if self.current_summary_index >= len(self.current_summaries):
            print("[DEBUG] 所有提示词生成完成")
            return

        # 检查是否有内容
        if not self.current_summaries[self.current_summary_index]:
            self.current_summary_index += 1
            QTimer.singleShot(500, self.start_next_prompt_generation)
            return

        print(f"[DEBUG] 生成第 {self.current_summary_index + 1} 个提示词")

        worker = TextGenerationWorker(
            self.current_summaries[self.current_summary_index],
            self.prompt_system_prompt
        )

        # 连接信号
        worker.content_updated.connect(self.update_current_prompt_content)
        worker.progress_updated.connect(self.update_prompt_progress)
        worker.finished.connect(self.on_single_prompt_finished)

        # 启动worker
        self.current_worker = worker
        worker.start()

    def update_current_prompt_content(self, text):
        """更新当前提示词内容"""
        print(f"[DEBUG] 第 {self.current_summary_index + 1} 个提示词更新: {len(text)} 字符")

    def update_prompt_progress(self, msg):
        """更新提示词生成进度"""
        if "生成中" in msg:
            progress = int((self.current_summary_index / self.total_prompts) * 100)
            self.prompt_progress.setValue(progress)
            self.image_status_label.setText(f"生成第 {self.current_summary_index + 1}/{self.total_prompts} 个提示词...")

    def on_single_prompt_finished(self, success, result):
        """单个提示词生成完成"""
        if success and result:
            # 添加前缀
            prefix = self.prompt_prefix_edit.text().strip()
            final_prompt = (prefix + ' ' + result.strip()).strip() if prefix else result.strip()

            # 确保列表足够长
            while len(self.current_prompts) <= self.current_summary_index:
                self.current_prompts.append('')

            self.current_prompts[self.current_summary_index] = final_prompt
            print(f"[DEBUG] 第 {self.current_summary_index + 1} 个提示词生成成功")
        else:
            print(f"[DEBUG] 第 {self.current_summary_index + 1} 个提示词生成失败")
            if result:
                print(f"[DEBUG] 错误信息: {result}")

        # 更新显示
        self.update_prompts_display()

        # 清理worker
        if hasattr(self, 'current_worker'):
            self.current_worker.deleteLater()
            self.current_worker = None

        # 继续下一个
        self.current_summary_index += 1
        self.completed_prompts += 1

        # 检查是否全部完成
        if self.current_summary_index >= self.total_prompts:
            self.on_all_prompts_finished()
        else:
            # 等待一段时间后继续，避免API频率限制
            QTimer.singleShot(1000, self.start_next_prompt_generation)

    def on_all_prompts_finished(self):
        """所有提示词生成完成"""
        print("[DEBUG] 所有提示词生成任务完成")
        self.prompt_progress.setRange(0, 100)
        self.prompt_progress.setValue(100)
        self.image_status_label.setText("提示词生成完成！")
        self.generate_prompt_btn.setEnabled(True)

        # 检查是否是一键生成流程
        if hasattr(self, 'all_generation_step') and self.all_generation_step == 3:
            QMessageBox.information(self, "成功", "绘图提示词生成完成！")
            # 继续最后一步 - 生成图片
            QTimer.singleShot(500, self.step_generate_images)
        else:
            QMessageBox.information(self, "成功", "绘图提示词生成完成！")

    def update_prompts_display(self):
        """更新提示词显示框"""
        prompts_text = ""
        for i, prompt in enumerate(self.current_prompts):
            if prompt:
                prompts_text += f"=== 分镜 {i+1} ===\n{prompt}\n\n"

        self.generated_prompts_edit.setPlainText(prompts_text.strip())

    def generate_images_only(self):
        """仅生成图片"""
        # 从文本框中读取提示词
        prompts_text = self.generated_prompts_edit.toPlainText().strip()

        if not prompts_text:
            QMessageBox.warning(self, "警告", "请先生成或输入绘图提示词")
            return

        print("\n[DEBUG] 开始解析绘图提示词...")
        self.current_prompts = []

        # 1. 先尝试解析英文格式（=== 分镜 X ===）
        if "=== 分镜" in prompts_text:
            sections = prompts_text.split("=== 分镜")
            print(f"[DEBUG] 检测到英文格式，找到 {len(sections)-1} 个分镜")

            for section in sections[1:]:  # 第一个是空的
                lines = section.strip().split('\n', 1)
                if len(lines) > 1:
                    prompt = lines[1].strip()
                    if prompt:
                        # 检查是否是中文还是英文
                        if self._is_chinese_text(prompt[:50]):
                            print(f"[DEBUG] 分镜 {len(self.current_prompts)+1} - 中文提示词")
                            # 中文提示词可能需要翻译（这里暂时保留原样）
                        else:
                            print(f"[DEBUG] 分镜 {len(self.current_prompts)+1} - 英文提示词")
                        self.current_prompts.append(prompt)

        # 2. 尝试解析中文格式（**分镜X：**）
        elif "**分镜" in prompts_text:
            sections = prompts_text.split("**分镜")
            print(f"[DEBUG] 检测到中文格式，找到 {len(sections)-1} 个分镜")

            for section in sections[1:]:  # 第一个是空的
                # 找到第一个冒号后面的内容
                colon_pos = section.find('：')
                if colon_pos != -1:
                    content = section[colon_pos + 1:].strip()
                    # 按分镜分割
                    if content.startswith('**'):
                        next_pos = content.find('**', 2)
                        if next_pos != -1:
                            prompt = content[:next_pos].strip()
                        else:
                            prompt = content.strip()
                    else:
                        # 找下一个分镜标记
                        next_pos = content.find('**分镜')
                        if next_pos != -1:
                            prompt = content[:next_pos].strip()
                        else:
                            prompt = content.strip()

                    if prompt:
                        print(f"[DEBUG] 分镜 {len(self.current_prompts)+1} - 中文提示词")
                        self.current_prompts.append(prompt)

        # 3. 按行分割（作为备用方案）
        else:
            lines = prompts_text.split('\n')
            print(f"[DEBUG] 使用按行分割，找到 {len(lines)} 行")
            for line in lines:
                line = line.strip()
                if line and not line.startswith('#') and not line.startswith('//'):
                    self.current_prompts.append(line)

        if not self.current_prompts:
            QMessageBox.warning(self, "警告", "请输入有效的绘图提示词")
            return

        print(f"[DEBUG] 解析完成，共 {len(self.current_prompts)} 个提示词")

        # 确保有足够数量的提示词
        while len(self.current_prompts) < self.image_count_spin.value():
            self.current_prompts.append(self.current_prompts[-1] if self.current_prompts else "")

        # 获取当前尺寸设置    
        width = self.width_spin.value()
        height = self.height_spin.value()

        # 更新 BizyAIR 默认配置
        config_manager.set('bizyair_params.default_width', width)
        config_manager.set('bizyair_params.default_height', height)
        config_manager.save_config()

        self.start_image_generation(width, height) # 传递尺寸参数

    def _is_chinese_text(self, text):
        """检查文本是否包含中文"""
        for char in text:
            if '\u4e00' <= char <= '\u9fff':
                return True
        return False

    def start_image_generation(self):
        """开始图片生成"""
        print(f"[DEBUG] 开始生成图片，共 {len(self.current_prompts)} 个")

        # 初始化图片生成参数
        self.current_image_index = 0
        self.total_images = len(self.current_prompts)
        self.image_params = {
            'model_id': config_manager.get('image_models.default', 'Tongyi-MAI/Z-Image-Turbo'),
            'size': config_manager.get('image.default_size', '756x1344'),
            'steps': config_manager.get('image.default_steps', 9),
            'guidance': config_manager.get('image.default_guidance', 1),
            'sampler': config_manager.get('image.default_sampler', 'Euler'),
            'negative_prompt': config_manager.get('image.default_negative_prompt', '')
        }

        # 初始化图片数组
        self.current_images = [None] * self.total_images
        self.image_urls = [''] * self.total_images

        # 清空图片显示
        for i in reversed(range(self.image_grid_layout.count())):
            self.image_grid_layout.itemAt(i).widget().setParent(None)

        # 启动图片生成 (批量一次性发送)
        self.generate_images_btn.setEnabled(False)
        self.image_progress.setValue(0)
        self.image_status_label.setText("准备生成图片...")
        
        # 获取图片数量（必须是 5 的倍数）
        image_count = self.image_count_spin.value()

        # 创建图片生成worker (一次性发送所有提示词)
        self.image_worker = ImageGenerationWorker(
            self.current_prompts,
            width,
            height,
            image_count
        )
        # 连接信号
        # 注意：这里的 on_single_image_generated 实际上是接收批量生成的 URL
        self.image_worker.progress_updated.connect(self.on_batch_image_progress)
        self.image_worker.image_generated.connect(self.on_batch_image_url_received)
        self.image_worker.finished.connect(self.on_all_images_finished)

        # 启动worker
        self.image_worker.start()

        # 开始第一个图片生成
        QTimer.singleShot(500, self.generate_next_image)

    def on_batch_image_progress(self, progress, msg):
        """批量图片生成进度"""
        self.image_progress.setValue(progress)
        self.image_status_label.setText(msg)

    def on_batch_image_url_received(self, index, image, url):
        """接收单个图片 URL 并更新显示"""
        if index < len(self.image_widgets):
            self.image_widgets[index].set_image(image, url)

    def on_all_images_finished(self, success, images, urls):
        """所有图片生成完成"""
        self.generate_images_btn.setEnabled(True)
        self.image_progress.setValue(100 if success else 0)

        if success:
            self.image_status_label.setText("图片生成完成！")
            # 统计成功的数量
            success_count = sum(1 for url in urls if url)
            QMessageBox.information(self, "成功", f"成功生成 {success_count}/{len(urls)} 张图片！")
        else:
            self.image_status_label.setText("图片生成失败")
            QMessageBox.critical(self, "错误", "图片生成失败")

        if hasattr(self, 'all_generation_step') and self.all_generation_step == 4:
            self.generate_all_btn.setEnabled(True)
            self.all_generation_step = 0 # 重置

    # def on_all_images_finished(self):
    #     """所有图片生成完成"""
    #     print("\n[DEBUG] 所有图片生成完成")
    #     self.image_status_label.setText("图片生成完成！")
    #     self.image_progress.setValue(100)
    #     self.generate_images_btn.setEnabled(True)

    #     # 统计成功生成的图片数量
    #     success_count = sum(1 for img in self.current_images if img is not None)
    #     QMessageBox.information(self, "成功", f"成功生成 {success_count}/{self.total_images} 张图片！")

    def generate_next_image(self):
        """生成下一张图片"""
        if self.current_image_index >= self.total_images:
            self.on_all_images_finished()
            return

        # 检查是否有提示词
        prompt = self.current_prompts[self.current_image_index]
        if not prompt:
            print(f"[DEBUG] 第 {self.current_image_index + 1} 个提示词为空，跳过")
            self.current_image_index += 1
            QTimer.singleShot(500, self.generate_next_image)
            return

        print(f"\n[DEBUG] 开始生成第 {self.current_image_index + 1} 张图片")
        print(f"[DEBUG] 提示词: {prompt[:100]}...")

        self.image_status_label.setText(f"正在生成第 {self.current_image_index + 1}/{self.total_images} 张图片...")

        # 创建图片生成worker（一次只生成一张）
        self.image_worker = ImageGenerationWorker(
            [prompt],  # 只传一个提示词
            self.image_params['model_id'],
            self.image_params,
            1  # 只生成一张图片
        )

        # 连接信号
        self.image_worker.progress_updated.connect(self.on_single_image_progress)
        self.image_worker.image_generated.connect(self.on_single_image_generated)
        self.image_worker.finished.connect(self.on_single_image_finished)

        # 启动worker
        self.image_worker.start()

    def on_single_image_progress(self, index, msg):
        """单张图片生成进度"""
        # index 在这里是0，因为我们只生成一张图片
        progress = int((self.current_image_index / self.total_images) * 100)
        self.image_progress.setValue(progress)
        if "提交任务" in msg:
            self.image_status_label.setText(f"第 {self.current_image_index + 1} 张：提交任务中...")
        elif "等待中" in msg:
            self.image_status_label.setText(f"第 {self.current_image_index + 1} 张：等待生成...")

    def on_single_image_generated(self, index, image, url):
        """单张图片生成完成"""
        print(f"[DEBUG] 第 {self.current_image_index + 1} 张图片生成完成")
        # 保存图片
        self.current_images[self.current_image_index] = image
        self.image_urls[self.current_image_index] = url
        # 更新图片显示
        self.update_single_image_display(self.current_image_index, image)

    def on_single_image_finished(self, success, images, urls):
        """单张图片生成完成回调"""
        if hasattr(self, 'image_worker'):
            self.image_worker.deleteLater()
            self.image_worker = None

        if success and images:
            print(f"[DEBUG] 第 {self.current_image_index + 1} 张图片生成成功")
            # 继续下一张
            self.current_image_index += 1

            # 更新进度
            progress = int((self.current_image_index / self.total_images) * 100)
            self.image_progress.setValue(progress)

            # 等待一段时间后继续，避免API频率限制
            QTimer.singleShot(1000, self.generate_next_image)
        else:
            print(f"[DEBUG] 第 {self.current_image_index + 1} 张图片生成失败")
            # 继续下一张
            self.current_image_index += 1
            QTimer.singleShot(1000, self.generate_next_image)

    def update_single_image_display(self, index, image):
        """更新单张图片显示"""
        from PyQt5.QtWidgets import QLabel
        from PyQt5.QtGui import QPixmap
        from PyQt5.QtCore import Qt

        cols = 3
        row = index // cols
        col = index % cols

        # 创建图片容器
        container = QWidget()
        container_layout = QVBoxLayout(container)
        container_layout.setContentsMargins(5, 5, 5, 5)

        # 图片标签
        label = QLabel()
        pixmap = QPixmap()
        pixmap.loadFromData(image)
        label.setPixmap(pixmap.scaled(200, 200, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        label.setAlignment(Qt.AlignCenter)
        label.setStyleSheet("border: 1px solid #ddd; border-radius: 4px;")
        container_layout.addWidget(label)

        # 分镜标题
        title_label = QLabel(f"分镜 {index + 1}")
        title_label.setAlignment(Qt.AlignCenter)
        title_label.setStyleSheet("font-size: 12px; color: #666;")
        container_layout.addWidget(title_label)

        # 添加到网格布局
        self.image_grid_layout.addWidget(container, row, col)

    def update_image_progress(self, index, msg):
        """更新图片生成进度（旧的，保留兼容）"""
        pass

    def on_image_generated(self, index, image, url):
        """单张图片生成完成（旧的，保留兼容）"""
        pass

    def on_images_finished(self, success, images, urls):
        """所有图片生成完成"""
        self.generate_images_btn.setEnabled(True)
        self.image_progress.setValue(100 if success else 0)

        if success:
            self.image_status_label.setText("图片生成完成！")
            QMessageBox.information(self, "成功", f"成功生成 {len(images)} 张图片！")
        else:
            self.image_status_label.setText("图片生成失败")
            QMessageBox.critical(self, "错误", "图片生成失败")

    def update_image_display(self):
        """更新图片显示"""
        # 清空现有显示
        for i in reversed(range(self.image_grid_layout.count())):
            self.image_grid_layout.itemAt(i).widget().setParent(None)

        # 显示图片
        cols = 3
        for i, image in enumerate(self.current_images):
            if image:
                row = i // cols
                col = i % cols

                # 创建图片标签
                from PyQt5.QtWidgets import QLabel
                from PyQt5.QtGui import QPixmap
                from PyQt5.QtCore import Qt

                label = QLabel()
                pixmap = QPixmap()
                pixmap.loadFromData(image)
                label.setPixmap(pixmap.scaled(200, 200, Qt.KeepAspectRatio, Qt.SmoothTransformation))
                label.setAlignment(Qt.AlignCenter)
                label.setStyleSheet("border: 1px solid #ddd; border-radius: 4px;")

                self.image_grid_layout.addWidget(label, row, col)

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

    
    def on_summaries_finished(self, success, result):
        """分镜描述生成完成（一键生成流程）"""
        # 先执行基础逻辑
        self.generate_summary_btn.setEnabled(True)
        self.summary_progress.setRange(0, 100)  # 恢复正常进度条
        self.summary_progress.setValue(100 if success else 0)

        if success:
            # 内容已经通过content_updated实时显示，这里确保最终结果正确
            self.summary_output_edit.setPlainText(result)
            # 解析描述列表
            summaries = [s.strip() for s in result.split('\n') if s.strip()]
            if len(summaries) >= self.image_count_spin.value():
                self.current_summaries = summaries[:self.image_count_spin.value()]
            else:
                self.current_summaries = summaries + [''] * (self.image_count_spin.value() - len(summaries))

            # 检查是否是一键生成流程
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
                QMessageBox.information(self, "成功", "分镜描述生成完成！")
                # 继续下一步
                QTimer.singleShot(500, self.step_generate_prompts)
            else:
                QMessageBox.information(self, "成功", "分镜描述生成完成！")
        else:
            QMessageBox.critical(self, "错误", f"生成失败：{result}")
            # 检查是否是一键生成流程
            if hasattr(self, 'all_generation_step') and self.all_generation_step == 2:
                self.generate_all_btn.setEnabled(True)

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
        self.api_key_edit.setPlaceholderText("请输入 API密钥...")
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        self.api_key_edit.setFixedHeight(32)
        self.api_key_edit.setText(config_manager.get('api.api_key', ''))
        api_layout.addWidget(self.api_key_edit, 0, 1)

        api_layout.addWidget(QLabel("API基础URL:"), 1, 0)
        self.api_url_edit = LineEdit()
        self.api_url_edit.setFixedHeight(32)
        self.api_url_edit.setText(config_manager.get('api.base_url', 'https://api.siliconflow.cn/v1/'))
        api_layout.addWidget(self.api_url_edit, 1, 1)

        api_layout.addWidget(QLabel("文本模型:"), 2, 0)
        self.text_model_edit = LineEdit()
        self.text_model_edit.setFixedHeight(32)
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

        # 清理所有工作线程
        thread_manager.cancel_all()

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

    # 添加一些全局样式优化
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
        ComboBox {
            padding: 5px;
            border: 1px solid #cccccc;
            border-radius: 4px;
            background: white;
        }
        ComboBox:hover {
            border-color: #888888;
        }
        ComboBox:focus {
            border-color: #0078d4;
        }
        LineEdit {
            padding: 5px;
            border: 1px solid #cccccc;
            border-radius: 4px;
            background: white;
        }
        LineEdit:hover {
            border-color: #888888;
        }
        LineEdit:focus {
            border-color: #0078d4;
        }
        SpinBox {
            padding: 5px;
            border: 1px solid #cccccc;
            border-radius: 4px;
        }
        DoubleSpinBox {
            padding: 5px;
            border: 1px solid #cccccc;
            border-radius: 4px;
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
