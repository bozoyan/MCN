# 主窗口和环境检查功能
import sys
import os
from PyQt5.QtWidgets import QApplication, QVBoxLayout, QHBoxLayout, QLabel, QGroupBox, QGridLayout
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont
from qfluentwidgets import (FluentIcon, FluentWindow, SubtitleLabel, PushButton,
                          ScrollArea, SmoothScrollArea, setTheme, Theme,
                          RadioButton, InfoBar, InfoBarPosition)

# 导入页面类
from MCN_improved import config_manager, EnvironmentChecker, ApiKeyDialog
from MCN_improved_pages import (
    VideoConvertPage, ImageToVideoPage, MergeVideoAudioPage,
    SubtitleGenerationPage, SubtitleTextPage, AdjustSubtitlePage, MergeSubtitlePage
)

# 配置常量
TITLE_FONT = QFont("Microsoft YaHei", 16)
LABEL_FONT = QFont("Microsoft YaHei", 12)
ENTRY_FONT = QFont("Microsoft YaHei", 10)

# 环境检查对话框
class EnvironmentCheckDialog(QDialog):
    """环境检查结果对话框"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("环境检查")
        self.setMinimumWidth(500)
        self.setModal(True)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🔍 环境依赖检查")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 依赖检查结果
        self.results_group = QGroupBox("依赖检查结果")
        self.results_layout = QGridLayout()
        self.results_group.setLayout(self.results_layout)
        layout.addWidget(self.results_group)

        # 目录创建结果
        self.dir_group = QGroupBox("目录状态")
        self.dir_layout = QVBoxLayout()
        self.dir_group.setLayout(self.dir_layout)
        layout.addWidget(self.dir_group)

        # 修复建议
        self.suggestions_group = QGroupBox("修复建议")
        self.suggestions_layout = QVBoxLayout()
        self.suggestions_group.setLayout(self.suggestions_layout)
        layout.addWidget(self.suggestions_group)

    def show_results(self, deps_results, created_dirs):
        """显示检查结果"""
        # 清除原有内容
        for i in reversed(range(self.results_layout.count())):
            self.results_layout.itemAt(i).widget().setParent(None)

        for i in reversed(range(self.dir_layout.count())):
            self.dir_layout.itemAt(i).widget().setParent(None)

        for i in reversed(range(self.suggestions_layout.count())):
            self.suggestions_layout.itemAt(i).widget().setParent(None)

        # 显示依赖检查结果
        row = 0
        for dep_name, available in deps_results.items():
            status = "✅ 已安装" if available else "❌ 未安装"
            color = "green" if available else "red"

            status_label = QLabel(f"{dep_name}: {status}")
            status_label.setStyleSheet(f"color: {color}; font-weight: bold;")
            self.results_layout.addWidget(status_label, row, 0)
            row += 1

        # 显示目录创建结果
        if created_dirs:
            dir_info = QLabel(f"✅ 已创建目录: {', '.join(created_dirs)}")
            dir_info.setStyleSheet("color: green;")
            self.dir_layout.addWidget(dir_info)
        else:
            dir_info = QLabel("✅ 所有必要目录已存在")
            dir_info.setStyleSheet("color: green;")
            self.dir_layout.addWidget(dir_info)

        # 显示修复建议
        suggestions = []
        if not deps_results.get('ffmpeg', False):
            suggestions.append("请安装 FFmpeg: brew install ffmpeg")

        if not deps_results.get('whisper', False):
            suggestions.append("请编译安装 whisper.cpp 或检查路径配置")

        if suggestions:
            for suggestion in suggestions:
                suggestion_label = QLabel(f"• {suggestion}")
                suggestion_label.setWordWrap(True)
                self.suggestions_layout.addWidget(suggestion_label)
        else:
            success_label = QLabel("✅ 环境检查通过，所有依赖都已满足")
            success_label.setStyleSheet("color: green; font-weight: bold;")
            self.suggestions_layout.addWidget(success_label)

class MainWindow(FluentWindow):
    def __init__(self):
        super().__init__()
        self.init_window()
        self.init_navigation()
        self.run_environment_check()

    def init_window(self):
        """初始化主窗口"""
        self.setWindowTitle("BOZO-MCN 多媒体编辑器 2.0 (改进版)")
        self.setMinimumSize(1200, 800)

        # 从配置文件读取窗口大小
        width = config_manager.get('ui.window_width', 1400)
        height = config_manager.get('ui.window_height', 900)
        self.resize(width, height)

        # 设置应用图标
        # self.setWindowIcon(QIcon("icon.png"))

    def init_navigation(self):
        """初始化导航栏"""
        # 添加导航项
        self.addSubInterface(
            self.create_video_convert_page(),
            FluentIcon.VIDEO,
            "视频转换",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_image_to_video_page(),
            FluentIcon.IMAGE,
            "图片转视频",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_merge_page(),
            FluentIcon.MERGE,
            "合并视频音频",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_subtitle_page(),
            FluentIcon.DOCUMENT,
            "生成字幕",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_subtitle_text_page(),
            FluentIcon.FONT,
            "字幕转文本",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_adjust_subtitle_page(),
            FluentIcon.EDIT,
            "调整字幕",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_merge_subtitle_page(),
            FluentIcon.MEDIA,
            "整合字幕",
            FluentWindow.NavigationItemPosition.TOP
        )

        self.addSubInterface(
            self.create_settings_page(),
            FluentIcon.SETTING,
            "设置",
            FluentWindow.NavigationItemPosition.BOTTOM
        )

    def create_video_convert_page(self):
        """创建视频转换页面"""
        self.video_convert_page = VideoConvertPage(self)
        return self.video_convert_page

    def create_image_to_video_page(self):
        """创建图片转视频页面"""
        self.image_to_video_page = ImageToVideoPage(self)
        return self.image_to_video_page

    def create_merge_page(self):
        """创建合并页面"""
        self.merge_page = MergeVideoAudioPage(self)
        return self.merge_page

    def create_subtitle_page(self):
        """创建字幕生成页面"""
        self.subtitle_page = SubtitleGenerationPage(self)
        return self.subtitle_page

    def create_subtitle_text_page(self):
        """创建字幕转文本页面"""
        page = SubtitleTextPage(self)
        return page

    def create_adjust_subtitle_page(self):
        """创建调整字幕页面"""
        page = AdjustSubtitlePage(self)
        return page

    def create_merge_subtitle_page(self):
        """创建整合字幕页面"""
        page = MergeSubtitlePage(self)
        return page

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

        # 从配置读取主题设置
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

        # FFmpeg路径
        path_layout.addWidget(QLabel("FFmpeg路径:"), 0, 0)
        self.ffmpeg_path_label = QLabel(config_manager.get('paths.ffmpeg_binary', 'ffmpeg'))
        path_layout.addWidget(self.ffmpeg_path_label, 0, 1)

        # Whisper路径
        path_layout.addWidget(QLabel("Whisper路径:"), 1, 0)
        self.whisper_path_label = QLabel(config_manager.get('paths.whisper_binary', 'whisper'))
        path_layout.addWidget(self.whisper_path_label, 1, 1)

        # Whisper模型路径
        path_layout.addWidget(QLabel("Whisper模型:"), 2, 0)
        self.whisper_model_label = QLabel(config_manager.get('paths.whisper_model', '默认模型'))
        self.whisper_model_label.setWordWrap(True)
        path_layout.addWidget(self.whisper_model_label, 2, 1)

        path_group.setLayout(path_layout)
        layout.addWidget(path_group)

        # 性能设置
        performance_group = QGroupBox("性能设置")
        performance_layout = QGridLayout()

        performance_layout.addWidget(QLabel("最大并发任务数:"), 0, 0)
        self.max_workers_label = QLabel(str(config_manager.get('processing.max_concurrent_workers', 4)))
        performance_layout.addWidget(self.max_workers_label, 0, 1)

        performance_layout.addWidget(QLabel("批量处理限制:"), 1, 0)
        self.batch_size_label = QLabel(str(config_manager.get('processing.batch_size', 10)))
        performance_layout.addWidget(self.batch_size_label, 1, 1)

        performance_layout.addWidget(QLabel("任务超时时间(秒):"), 2, 0)
        self.timeout_label = QLabel(str(config_manager.get('processing.timeout_seconds', 120)))
        performance_layout.addWidget(self.timeout_label, 2, 1)

        performance_group.setLayout(performance_layout)
        layout.addWidget(performance_group)

        # 环境检查
        env_group = QGroupBox("环境检查")
        env_layout = QVBoxLayout()

        env_check_btn = PushButton(FluentIcon.SEARCH, "运行环境检查")
        env_check_btn.clicked.connect(self.run_environment_check)
        env_layout.addWidget(env_check_btn)

        env_info_label = QLabel("检查FFmpeg、Whisper等依赖是否已安装，以及必要的目录是否已创建")
        env_info_label.setWordWrap(True)
        env_info_label.setStyleSheet("color: gray; font-size: 12px;")
        env_layout.addWidget(env_info_label)

        env_group.setLayout(env_layout)
        layout.addWidget(env_group)

        # 打开文件夹按钮
        folders_group = QGroupBox("常用文件夹")
        folders_layout = QGridLayout()

        font_btn = PushButton(FluentIcon.FONT, "字体文件夹")
        font_btn.clicked.connect(lambda: self.open_folder("font"))
        folders_layout.addWidget(font_btn, 0, 0)

        temp_btn = PushButton(FluentIcon.FOLDER, "临时文件")
        temp_btn.clicked.connect(lambda: self.open_folder("temp"))
        folders_layout.addWidget(temp_btn, 0, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "字幕文件夹")
        srt_btn.clicked.connect(lambda: self.open_folder("SRT"))
        folders_layout.addWidget(srt_btn, 1, 0)

        speech_btn = PushButton(FluentIcon.MICROPHONE, "语音文件夹")
        speech_btn.clicked.connect(lambda: self.open_folder("speech"))
        folders_layout.addWidget(speech_btn, 1, 1)

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

            # 保存到配置管理器
            config_manager.set('api.siliconcloud_key', settings['api_key'])
            config_manager.set('api.base_url', settings['base_url'])
            config_manager.set('api.model', settings['model'])

            # 保存配置文件
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
        # 检查依赖
        deps_results = EnvironmentChecker.check_dependencies()

        # 检查并创建目录
        created_dirs = EnvironmentChecker.check_directories()

        # 显示结果
        dialog = EnvironmentCheckDialog(self)
        dialog.show_results(deps_results, created_dirs)
        dialog.exec_()

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
        if config_manager.save_config():
            InfoBar.success(title="保存成功", content="配置已保存到文件",
                          orient=Qt.Horizontal, isClosable=True,
                          position=InfoBarPosition.TOP, duration=2000, parent=self)
        else:
            InfoBar.error(title="保存失败", content="配置文件保存失败",
                        orient=Qt.Horizontal, isClosable=True,
                        position=InfoBarPosition.TOP, duration=3000, parent=self)

    def closeEvent(self, event):
        """窗口关闭时保存配置并清理资源"""
        # 保存窗口大小
        config_manager.set('ui.window_width', self.width())
        config_manager.set('ui.window_height', self.height())

        # 保存配置
        config_manager.save_config()

        # 清理所有页面的工作线程
        for page in [self.video_convert_page, self.image_to_video_page,
                     self.merge_page, self.subtitle_page]:
            if hasattr(page, 'cleanup_workers'):
                page.cleanup_workers()

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