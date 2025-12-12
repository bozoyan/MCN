#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 多媒体编辑器 2.0 (改进版)
主运行脚本
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
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                            QHBoxLayout, QGridLayout, QLabel, QLineEdit,
                            QPushButton, QFileDialog, QTextEdit, QCheckBox,
                            QComboBox, QSpinBox, QProgressBar, QMessageBox,
                            QSplitter, QFrame, QScrollArea, QGroupBox, QDoubleSpinBox,
                            QDialog, QDialogButtonBox, QFormLayout)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QUrl, QSettings
from PyQt5.QtGui import QFont, QIcon, QDesktopServices
from qfluentwidgets import (FluentIcon, NavigationInterface, NavigationItemPosition,
                          FluentWindow, SubtitleLabel, BodyLabel, PrimaryPushButton,
                          PushButton, LineEdit, ComboBox, CheckBox, SpinBox,
                          ProgressBar, InfoBar, InfoBarPosition, ToolTipFilter,
                          setTheme, Theme, FluentIcon as FIcon, SmoothScrollArea, RadioButton)

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 配置管理器
class ConfigManager:
    """配置文件管理器"""

    def __init__(self, config_file="config.json"):
        self.config_file = config_file
        self.config = self.load_config()

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
            "paths": {
                "whisper_binary": "whisper.cpp/build/bin/whisper-cli",
                "whisper_model": "whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin",
                "ffmpeg_binary": "ffmpeg"
            },
            "api": {
                "siliconcloud_key": "",
                "base_url": "https://api.siliconflow.cn/v1/chat/completions",
                "model": "Qwen/Qwen2.5-Coder-32B-Instruct"
            },
            "processing": {
                "max_concurrent_workers": 4,
                "batch_size": 10,
                "timeout_seconds": 120
            },
            "ui": {
                "theme": "dark",
                "window_width": 1400,
                "window_height": 900
            },
            "directories": {
                "temp": "temp",
                "srt": "SRT",
                "speech": "speech",
                "font": "font"
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

# 全局配置管理器
config_manager = ConfigManager()

# 环境检查器
class EnvironmentChecker:
    """环境依赖检查器"""

    @staticmethod
    def check_dependencies():
        """检查必要的依赖"""
        dependencies = {
            'ffmpeg': 'ffmpeg -version',
        }

        results = {}
        for name, command in dependencies.items():
            try:
                result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=10)
                results[name] = result.returncode == 0
            except (subprocess.TimeoutExpired, Exception):
                results[name] = False

        # 检查whisper二进制文件
        whisper_path = config_manager.get('paths.whisper_binary', 'whisper')
        results['whisper'] = os.path.exists(whisper_path)

        return results

    @staticmethod
    def check_directories():
        """检查并创建必要的目录"""
        directories = ['temp', 'SRT', 'speech', 'font']
        created_dirs = []

        for dir_name in directories:
            dir_path = os.path.join(os.getcwd(), dir_name)
            if not os.path.exists(dir_path):
                os.makedirs(dir_path, exist_ok=True)
                created_dirs.append(dir_name)

        return created_dirs

# API密钥设置对话框
class ApiKeyDialog(QDialog):
    """API密钥设置对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("API密钥设置")
        self.setMinimumWidth(400)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # 表单布局
        form_layout = QFormLayout()

        self.api_key_edit = LineEdit()
        self.api_key_edit.setPlaceholderText("请输入SiliconCloud API密钥...")
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        form_layout.addRow("SiliconCloud API密钥:", self.api_key_edit)

        self.base_url_edit = LineEdit()
        self.base_url_edit.setText("https://api.siliconflow.cn/v1/chat/completions")
        form_layout.addRow("API基础URL:", self.base_url_edit)

        self.model_edit = LineEdit()
        self.model_edit.setText("Qwen/Qwen2.5-Coder-32B-Instruct")
        form_layout.addRow("模型名称:", self.model_edit)

        layout.addLayout(form_layout)

        # 按钮
        button_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

    def get_settings(self):
        return {
            'api_key': self.api_key_edit.text().strip(),
            'base_url': self.base_url_edit.text().strip(),
            'model': self.model_edit.text().strip()
        }

# 配置常量
TITLE_FONT = QFont("Microsoft YaHei", 16)
LABEL_FONT = QFont("Microsoft YaHei", 12)
ENTRY_FONT = QFont("Microsoft YaHei", 10)

# 工作线程基类
class WorkerThread(QThread):
    """工作线程基类"""
    progress_updated = pyqtSignal(int)
    log_updated = pyqtSignal(str)
    finished = pyqtSignal(bool, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.is_cancelled = False
        self.process = None

    def cancel(self):
        """取消当前任务"""
        self.is_cancelled = True
        if self.process:
            self.process.terminate()
            self.process.wait(timeout=5)

    def run_command(self, cmd, shell=False):
        """执行命令并处理结果"""
        try:
            if shell:
                self.process = subprocess.Popen(cmd, shell=True, capture_output=True, text=True)
                stdout, stderr = self.process.communicate()
                return self.process.returncode, stdout, stderr
            else:
                self.process = subprocess.Popen(cmd, capture_output=True, text=True)
                stdout, stderr = self.process.communicate()
                return self.process.returncode, stdout, stderr
        except Exception as e:
            return -1, "", str(e)

# 简化版本的页面类（为了演示主要功能）
class BasePage(QWidget):
    """页面基类"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.main_window = parent
        self.worker_threads = []
        self.active_workers = 0
        self.max_workers = config_manager.get('processing.max_concurrent_workers', 4)

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

    def get_file_path(self, title, filter_str):
        """获取文件路径"""
        file_path, _ = QFileDialog.getOpenFileName(self, title, "", filter_str)
        return file_path

    def get_folder_path(self, title):
        """获取文件夹路径"""
        folder_path = QFileDialog.getExistingDirectory(self, title)
        return folder_path

    def add_worker(self, worker):
        """添加工作线程"""
        self.worker_threads.append(worker)
        self.active_workers += 1

        worker.finished.connect(self.on_worker_finished)
        worker.start()

    def on_worker_finished(self):
        """工作线程完成回调"""
        self.active_workers -= 1

    def cleanup_workers(self):
        """清理工作线程"""
        for worker in self.worker_threads:
            if worker.isRunning():
                worker.quit()
                worker.wait(3000)
        self.worker_threads.clear()
        self.active_workers = 0

class SimpleVideoConvertPage(BasePage):
    """简化的视频转换页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎬 视频转换工具")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 说明信息
        info_label = QLabel("此版本为演示版本，展示了主要的改进功能：\n"
                          "• 配置文件管理\n"
                          "• 线程资源管理\n"
                          "• 环境依赖检查\n"
                          "• API密钥管理\n"
                          "• 改进的错误处理")
        info_label.setWordWrap(True)
        layout.addWidget(info_label)

        # 功能按钮
        test_btn = PrimaryPushButton(FluentIcon.PLAY, "测试环境检查")
        test_btn.clicked.connect(self.test_environment)
        test_btn.setFixedHeight(45)
        layout.addWidget(test_btn)

        config_btn = PrimaryPushButton(FluentIcon.SETTING, "测试API配置")
        config_btn.clicked.connect(self.test_api_config)
        config_btn.setFixedHeight(45)
        layout.addWidget(config_btn)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def test_environment(self):
        """测试环境检查功能"""
        self.show_info("环境检查", "正在检查环境依赖...")

        deps_results = EnvironmentChecker.check_dependencies()
        created_dirs = EnvironmentChecker.check_directories()

        message = "环境检查完成:\n\n"
        for dep_name, available in deps_results.items():
            status = "✅" if available else "❌"
            message += f"{dep_name}: {status}\n"

        if created_dirs:
            message += f"\n已创建目录: {', '.join(created_dirs)}"

        if all(deps_results.values()):
            self.show_success("环境检查", "所有依赖都已满足")
        else:
            missing = [name for name, available in deps_results.items() if not available]
            self.show_warning("环境检查", f"缺少依赖: {', '.join(missing)}")

        self.progress_bar.setValue(100)
        QTimer.singleShot(2000, lambda: self.progress_bar.setValue(0))

    def test_api_config(self):
        """测试API配置功能"""
        api_key = config_manager.get('api.siliconcloud_key')
        if api_key:
            self.show_success("API配置", "API密钥已配置")
        else:
            dialog = ApiKeyDialog(self)
            if dialog.exec_() == QDialog.Accepted:
                settings = dialog.get_settings()
                config_manager.set('api.siliconcloud_key', settings['api_key'])
                config_manager.save_config()
                self.show_success("API配置", "API密钥已保存")

# 主窗口类
class MainWindow(FluentWindow):
    def __init__(self):
        super().__init__()
        self.init_window()
        self.init_navigation()
        self.run_initial_environment_check()

    def init_window(self):
        """初始化主窗口"""
        self.setWindowTitle("BOZO-MCN 多媒体编辑器 2.0 (改进版演示)")
        self.setMinimumSize(1200, 800)

        # 从配置文件读取窗口大小
        width = config_manager.get('ui.window_width', 1400)
        height = config_manager.get('ui.window_height', 900)
        self.resize(width, height)

    def init_navigation(self):
        """初始化导航栏"""
        # 添加主要的演示页面
        self.addSubInterface(
            self.create_demo_page(),
            FluentIcon.VIDEO,
            "功能演示",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_settings_page(),
            FluentIcon.SETTING,
            "设置",
            FluentWindow.NavigationItemPosition.BOTTOM
        )

    def create_demo_page(self):
        """创建演示页面"""
        self.demo_page = SimpleVideoConvertPage(self)
        return self.demo_page

    def create_settings_page(self):
        """创建设置页面"""
        page = SmoothScrollArea()
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(20)

        title = SubtitleLabel("⚙️ 设置")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 主题切换
        theme_group = QGroupBox("界面主题")
        theme_layout = QVBoxLayout()

        self.light_radio = RadioButton("浅色主题")
        self.dark_radio = RadioButton("深色主题")

        current_theme = config_manager.get('ui.theme', 'dark')
        if current_theme == 'dark':
            self.dark_radio.setChecked(True)
        else:
            self.light_radio.setChecked(True)

        self.light_radio.clicked.connect(lambda: self.change_theme('light'))
        self.dark_radio.clicked.connect(lambda: self.change_theme('dark'))

        theme_layout.addWidget(self.light_radio)
        theme_layout.addWidget(self.dark_radio)
        theme_group.setLayout(theme_layout)
        layout.addWidget(theme_group)

        # API设置
        api_group = QGroupBox("API设置")
        api_layout = QGridLayout()

        api_status_label = QLabel("API密钥状态:")
        api_layout.addWidget(api_status_label, 0, 0)

        self.api_status_value = QLabel()
        self.update_api_status()
        api_layout.addWidget(self.api_status_value, 0, 1)

        api_config_btn = PushButton(FluentIcon.SETTING, "配置API密钥")
        api_config_btn.clicked.connect(self.show_api_config_dialog)
        api_layout.addWidget(api_config_btn, 0, 2)

        api_group.setLayout(api_layout)
        layout.addWidget(api_group)

        # 路径配置
        path_group = QGroupBox("路径配置")
        path_layout = QGridLayout()

        path_layout.addWidget(QLabel("FFmpeg路径:"), 0, 0)
        self.ffmpeg_path_label = QLabel(config_manager.get('paths.ffmpeg_binary', 'ffmpeg'))
        path_layout.addWidget(self.ffmpeg_path_label, 0, 1)

        path_layout.addWidget(QLabel("Whisper路径:"), 1, 0)
        self.whisper_path_label = QLabel(config_manager.get('paths.whisper_binary', 'whisper'))
        path_layout.addWidget(self.whisper_path_label, 1, 1)

        path_group.setLayout(path_layout)
        layout.addWidget(path_group)

        # 环境检查
        env_group = QGroupBox("环境检查")
        env_layout = QVBoxLayout()

        env_check_btn = PushButton(FluentIcon.SEARCH, "运行环境检查")
        env_check_btn.clicked.connect(self.run_environment_check)
        env_layout.addWidget(env_check_btn)

        env_group.setLayout(env_layout)
        layout.addWidget(env_group)

        # 打开文件夹按钮
        folders_group = QGroupBox("常用文件夹")
        folders_layout = QGridLayout()

        temp_btn = PushButton(FluentIcon.FOLDER, "临时文件")
        temp_btn.clicked.connect(lambda: self.open_folder("temp"))
        folders_layout.addWidget(temp_btn, 0, 0)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "字幕文件夹")
        srt_btn.clicked.connect(lambda: self.open_folder("SRT"))
        folders_layout.addWidget(srt_btn, 0, 1)

        folders_group.setLayout(folders_layout)
        layout.addWidget(folders_group)

        # 保存配置按钮
        save_config_btn = PushButton(FluentIcon.SAVE, "保存配置")
        save_config_btn.clicked.connect(self.save_current_config)
        layout.addWidget(save_config_btn)

        layout.addStretch()

        page.setWidget(widget)
        page.setWidgetResizable(True)
        return page

    def change_theme(self, theme):
        """切换主题"""
        config_manager.set('ui.theme', theme)
        if theme == 'dark':
            setTheme(Theme.DARK)
        else:
            setTheme(Theme.LIGHT)

        InfoBar.success(title="主题切换", content=f"已切换到{theme}主题",
                      orient=Qt.Horizontal, isClosable=True,
                      position=InfoBarPosition.TOP, duration=2000, parent=self)

    def update_api_status(self):
        """更新API状态显示"""
        api_key = config_manager.get('api.siliconcloud_key')
        if api_key:
            self.api_status_value.setText("已配置 ✅")
            self.api_status_value.setStyleSheet("color: green;")
        else:
            self.api_status_value.setText("未配置 ❌")
            self.api_status_value.setStyleSheet("color: red;")

    def show_api_config_dialog(self):
        """显示API配置对话框"""
        dialog = ApiKeyDialog(self)

        # 预填充现有配置
        dialog.api_key_edit.setText(config_manager.get('api.siliconcloud_key', ''))
        dialog.base_url_edit.setText(config_manager.get('api.base_url', 'https://api.siliconflow.cn/v1/chat/completions'))
        dialog.model_edit.setText(config_manager.get('api.model', 'Qwen/Qwen2.5-Coder-32B-Instruct'))

        if dialog.exec_() == QDialog.Accepted:
            settings = dialog.get_settings()

            config_manager.set('api.siliconcloud_key', settings['api_key'])
            config_manager.set('api.base_url', settings['base_url'])
            config_manager.set('api.model', settings['model'])

            if config_manager.save_config():
                self.update_api_status()
                InfoBar.success(title="配置保存", content="API配置已保存",
                              orient=Qt.Horizontal, isClosable=True,
                              position=InfoBarPosition.TOP, duration=2000, parent=self)
            else:
                InfoBar.error(title="保存失败", content="配置文件保存失败",
                            orient=Qt.Horizontal, isClosable=True,
                            position=InfoBarPosition.TOP, duration=3000, parent=self)

    def run_environment_check(self):
        """运行环境检查"""
        deps_results = EnvironmentChecker.check_dependencies()
        created_dirs = EnvironmentChecker.check_directories()

        message = "环境检查结果:\n\n"
        all_good = True

        for dep_name, available in deps_results.items():
            status = "✅" if available else "❌"
            message += f"{dep_name}: {status}\n"
            if not available:
                all_good = False

        if created_dirs:
            message += f"\n已创建目录: {', '.join(created_dirs)}"

        if all_good:
            InfoBar.success(title="环境检查", content="所有依赖都已满足",
                          orient=Qt.Horizontal, isClosable=True,
                          position=InfoBarPosition.TOP, duration=3000, parent=self)
        else:
            InfoBar.warning(title="环境检查", content="部分依赖缺失",
                          orient=Qt.Horizontal, isClosable=True,
                          position=InfoBarPosition.TOP, duration=3000, parent=self)

    def run_initial_environment_check(self):
        """运行初始环境检查"""
        QTimer.singleShot(1000, self.run_environment_check)

    def open_folder(self, folder_name):
        """打开指定文件夹"""
        folder_path = os.path.join(os.getcwd(), folder_name)
        os.makedirs(folder_path, exist_ok=True)

        try:
            if sys.platform == "darwin":  # macOS
                subprocess.run(["open", folder_path])
            elif sys.platform == "win32":  # Windows
                subprocess.run(["explorer", folder_path])
            else:  # Linux
                subprocess.run(["xdg-open", folder_path])
        except Exception as e:
            InfoBar.error(title="打开失败", content=f"无法打开文件夹: {str(e)}",
                        orient=Qt.Horizontal, isClosable=True,
                        position=InfoBarPosition.TOP, duration=3000, parent=self)

    def save_current_config(self):
        """保存当前配置"""
        config_manager.set('ui.window_width', self.width())
        config_manager.set('ui.window_height', self.height())

        if config_manager.save_config():
            InfoBar.success(title="保存成功", content="配置已保存到文件",
                          orient=Qt.Horizontal, isClosable=True,
                          position=InfoBarPosition.TOP, duration=2000, parent=self)
        else:
            InfoBar.error(title="保存失败", content="配置文件保存失败",
                        orient=Qt.Horizontal, isClosable=True,
                        position=InfoBarPosition.TOP, duration=3000, parent=self)

    def closeEvent(self, event):
        """窗口关闭时保存配置"""
        config_manager.set('ui.window_width', self.width())
        config_manager.set('ui.window_height', self.height())
        config_manager.save_config()

        if hasattr(self, 'demo_page'):
            self.demo_page.cleanup_workers()

        super().closeEvent(event)

def main():
    # 设置高DPI支持
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    app = QApplication(sys.argv)

    # 设置应用信息
    app.setApplicationName("BOZO-MCN多媒体编辑器")
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