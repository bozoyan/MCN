# 继续完善其他页面类

class ImageToVideoPage(BasePage):
    """图片转视频页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.batch_completed = 0
        self.batch_total = 0
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🖼️ 图片转视频")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 图片选择组
        image_group = QGroupBox("图片设置")
        image_layout = QGridLayout()

        image_layout.addWidget(QLabel("图片文件:"), 0, 0)
        self.image_path_edit = LineEdit()
        self.image_path_edit.setPlaceholderText("选择单个图片文件...")
        self.image_path_edit.setFixedHeight(35)
        image_layout.addWidget(self.image_path_edit, 0, 1)

        image_btn = PushButton(FluentIcon.IMAGE, "浏览")
        image_btn.setFixedWidth(80)
        image_btn.clicked.connect(self.browse_image)
        image_layout.addWidget(image_btn, 0, 2)

        # 批量模式
        self.batch_checkbox = CheckBox("批量处理")
        self.batch_checkbox.stateChanged.connect(self.toggle_batch_mode)
        image_layout.addWidget(self.batch_checkbox, 1, 0)

        image_layout.addWidget(QLabel("批量文件夹:"), 2, 0)
        self.batch_folder_edit = LineEdit()
        self.batch_folder_edit.setPlaceholderText("选择包含图片的文件夹...")
        self.batch_folder_edit.setFixedHeight(35)
        self.batch_folder_edit.setEnabled(False)
        image_layout.addWidget(self.batch_folder_edit, 2, 1)

        batch_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        batch_folder_btn.setFixedWidth(80)
        batch_folder_btn.clicked.connect(self.browse_batch_folder)
        batch_folder_btn.setEnabled(False)
        self.batch_folder_btn = batch_folder_btn
        image_layout.addWidget(batch_folder_btn, 2, 2)

        image_group.setLayout(image_layout)
        layout.addWidget(image_group)

        # 视频设置组
        video_group = QGroupBox("视频设置")
        video_layout = QGridLayout()

        # 视频尺寸预设
        video_layout.addWidget(QLabel("视频尺寸:"), 0, 0)
        self.size_combo = ComboBox()
        size_options = [
            "1:1 (1240x1240)", "3:4 (1080x1440)", "4:3 (1440x1080)",
            "9:16 (900x1600)", "16:9 (1600x900)", "1:2 (870x1740)",
            "2:1 (1740x870)", "自定义"
        ]
        self.size_combo.addItems(size_options)
        self.size_combo.setCurrentIndex(3)  # 默认9:16
        self.size_combo.currentTextChanged.connect(self.on_size_changed)
        self.size_combo.setFixedHeight(35)
        video_layout.addWidget(self.size_combo, 0, 1)

        video_layout.addWidget(QLabel("自定义尺寸:"), 1, 0)
        self.size_edit = LineEdit()
        self.size_edit.setText("900x1600")
        self.size_edit.setPlaceholderText("宽x高 (如 1920x1080)")
        self.size_edit.setFixedHeight(35)
        video_layout.addWidget(self.size_edit, 1, 1)

        video_layout.addWidget(QLabel("停留时长(秒):"), 2, 0)
        self.duration_spin = SpinBox()
        self.duration_spin.setRange(1, 60)
        self.duration_spin.setValue(6)
        self.duration_spin.setFixedHeight(35)
        video_layout.addWidget(self.duration_spin, 2, 1)

        video_group.setLayout(video_layout)
        layout.addWidget(video_group)

        # 生成按钮
        generate_btn = PrimaryPushButton(FluentIcon.PLAY, "生成视频片段")
        generate_btn.setFixedHeight(45)
        generate_btn.clicked.connect(self.generate_video)
        layout.addWidget(generate_btn)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_image(self):
        file_path = self.get_file_path("选择图片文件",
            "图片文件 (*.png *.jpg *.jpeg *.bmp);;所有文件 (*)")
        if file_path:
            self.image_path_edit.setText(file_path)

    def browse_batch_folder(self):
        folder_path = self.get_folder_path("选择图片文件夹")
        if folder_path:
            self.batch_folder_edit.setText(folder_path)

    def toggle_batch_mode(self, state):
        is_checked = state == Qt.Checked
        self.image_path_edit.setEnabled(not is_checked)
        self.batch_folder_edit.setEnabled(is_checked)
        self.batch_folder_btn.setEnabled(is_checked)

    def on_size_changed(self, text):
        if text == "自定义":
            self.size_edit.setEnabled(True)
        else:
            match = re.search(r'\((\d+x\d+)\)', text)
            if match:
                self.size_edit.setText(match.group(1))
            self.size_edit.setEnabled(False)

    def generate_video(self):
        if self.batch_checkbox.isChecked():
            self.batch_generate_video()
        else:
            image_path = self.image_path_edit.text().strip()
            if not image_path or not os.path.exists(image_path):
                self.show_error("错误", "请选择有效的图片文件")
                return

            self.generate_single_video(image_path)

    def generate_single_video(self, image_path):
        size = self.size_edit.text().strip()
        duration = self.duration_spin.value()

        if not re.match(r'\d+x\d+', size):
            self.show_error("错误", "请输入正确的尺寸格式 (如 1920x1080)")
            return

        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        img_name = os.path.splitext(os.path.basename(image_path))[0]
        output_path = os.path.join(temp_dir, f"{img_name}.mp4")

        worker = ImageToVideoThread(image_path, output_path, size, duration, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_generation_finished)
        self.add_worker(worker)
        self.show_info("开始生成", f"正在生成视频: {os.path.basename(image_path)}")

    def batch_generate_video(self):
        folder_path = self.batch_folder_edit.text().strip()
        if not folder_path or not os.path.exists(folder_path):
            self.show_error("错误", "请选择有效的图片文件夹")
            return

        image_files = [f for f in os.listdir(folder_path)
                      if f.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp'))]

        if not image_files:
            self.show_error("错误", "文件夹中没有找到图片文件")
            return

        # 限制批量处理数量
        batch_size = config_manager.get('processing.batch_size', 10)
        if len(image_files) > batch_size:
            image_files = image_files[:batch_size]
            self.show_warning("批量处理限制", f"单次最多处理{batch_size}个文件，已选择前{batch_size}个")

        self.show_info("批量处理", f"找到 {len(image_files)} 个图片文件，开始处理...")

        self.batch_total = len(image_files)
        self.batch_completed = 0
        self.progress_bar.setValue(0)

        for i, image_file in enumerate(image_files):
            image_path = os.path.join(folder_path, image_file)

            worker = ImageToVideoThread(image_path,
                                       os.path.join(os.getcwd(), 'temp', f"{os.path.splitext(image_file)[0]}.mp4"),
                                       self.size_edit.text().strip(),
                                       self.duration_spin.value(),
                                       self)
            worker.progress_updated.connect(lambda v, idx=i: self.update_batch_progress(v, idx))
            worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
            worker.finished.connect(lambda success, msg, idx=i: self.on_batch_generation_finished(success, msg, idx))
            self.add_worker(worker)

    def update_batch_progress(self, value, worker_idx):
        """更新批量进度"""
        if self.batch_total > 0:
            task_progress = value / 100
            overall_progress = ((self.batch_completed + task_progress) / self.batch_total) * 100
            self.progress_bar.setValue(int(overall_progress))

    def on_generation_finished(self, success, message):
        if success:
            self.show_success("完成", f"视频生成完成: {message}")
        else:
            self.show_error("错误", f"视频生成失败: {message}")
        self.progress_bar.setValue(0)

    def on_batch_generation_finished(self, success, message, worker_idx):
        """批量生成完成回调"""
        self.batch_completed += 1

        if success:
            self.show_info("进度", f"文件 {self.batch_completed}/{self.batch_total} 完成")
        else:
            self.show_error("错误", f"文件 {self.batch_completed} 失败: {message}")

        if self.batch_completed >= self.batch_total:
            self.progress_bar.setValue(100)
            self.show_success("批量完成", f"批量生成完成，共处理 {self.batch_total} 个文件")
            QTimer.singleShot(2000, lambda: self.progress_bar.setValue(0))

class MergeVideoAudioPage(BasePage):
    """合并视频与音频页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎵 合并视频与音频")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 文件选择组
        file_group = QGroupBox("文件选择")
        file_layout = QGridLayout()

        file_layout.addWidget(QLabel("封面文件:"), 0, 0)
        self.cover_path_edit = LineEdit()
        self.cover_path_edit.setPlaceholderText("选择封面图片文件 (可选)...")
        self.cover_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.cover_path_edit, 0, 1)

        cover_btn = PushButton(FluentIcon.IMAGE, "浏览")
        cover_btn.setFixedWidth(80)
        cover_btn.clicked.connect(lambda: self.browse_file("cover"))
        file_layout.addWidget(cover_btn, 0, 2)

        file_layout.addWidget(QLabel("视频片段文件夹:"), 1, 0)
        self.video_folder_edit = LineEdit()
        self.video_folder_edit.setPlaceholderText("选择包含视频片段的文件夹...")
        self.video_folder_edit.setFixedHeight(35)
        file_layout.addWidget(self.video_folder_edit, 1, 1)

        video_folder_btn = PushButton(FluentIcon.FOLDER, "选择")
        video_folder_btn.setFixedWidth(80)
        video_folder_btn.clicked.connect(lambda: self.browse_file("video_folder"))
        file_layout.addWidget(video_folder_btn, 1, 2)

        file_layout.addWidget(QLabel("音频文件:"), 2, 0)
        self.audio_path_edit = LineEdit()
        self.audio_path_edit.setPlaceholderText("选择音频文件...")
        self.audio_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.audio_path_edit, 2, 1)

        audio_btn = PushButton(FluentIcon.MUSIC, "浏览")
        audio_btn.setFixedWidth(80)
        audio_btn.clicked.connect(lambda: self.browse_file("audio"))
        file_layout.addWidget(audio_btn, 2, 2)

        file_group.setLayout(file_layout)
        layout.addWidget(file_group)

        # 合并设置组
        merge_group = QGroupBox("合并设置")
        merge_layout = QGridLayout()

        merge_layout.addWidget(QLabel("输出视频名:"), 0, 0)
        self.output_name_edit = LineEdit()
        self.output_name_edit.setPlaceholderText("输入输出视频名称...")
        self.output_name_edit.setFixedHeight(35)
        merge_layout.addWidget(self.output_name_edit, 0, 1)

        # 缩放动画设置
        self.zoom_checkbox = CheckBox("启用缩放动画")
        self.zoom_checkbox.stateChanged.connect(self.toggle_zoom_controls)
        merge_layout.addWidget(self.zoom_checkbox, 1, 0)

        merge_layout.addWidget(QLabel("缩放结束值:"), 2, 0)
        self.zoom_end_spin = QDoubleSpinBox()
        self.zoom_end_spin.setRange(1.0, 5.0)
        self.zoom_end_spin.setValue(1.2)
        self.zoom_end_spin.setSingleStep(0.1)
        self.zoom_end_spin.setEnabled(False)
        merge_layout.addWidget(self.zoom_end_spin, 2, 1)

        merge_layout.addWidget(QLabel("滤镜类型:"), 3, 0)
        self.filter_combo = ComboBox()
        self.filter_combo.addItems(["scale+zoom", "scale+zoompan"])
        self.filter_combo.setEnabled(False)
        merge_layout.addWidget(self.filter_combo, 3, 1)

        merge_group.setLayout(merge_layout)
        layout.addWidget(merge_group)

        # 操作按钮
        btn_layout = QHBoxLayout()

        merge_btn = PrimaryPushButton(FluentIcon.MERGE, "基础合并")
        merge_btn.setFixedHeight(45)
        merge_btn.clicked.connect(self.merge_videos)
        btn_layout.addWidget(merge_btn)

        zoom_merge_btn = PrimaryPushButton(FluentIcon.FULL_SCREEN, "缩放合并")
        zoom_merge_btn.setFixedHeight(45)
        zoom_merge_btn.clicked.connect(self.merge_with_zoom)
        zoom_merge_btn.setEnabled(False)
        self.zoom_merge_btn = zoom_merge_btn
        btn_layout.addWidget(zoom_merge_btn)

        layout.addLayout(btn_layout)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_file(self, file_type):
        if file_type == "cover":
            file_path = self.get_file_path("选择封面文件",
                "图片文件 (*.png *.jpg *.jpeg *.bmp);;所有文件 (*)")
            if file_path:
                self.cover_path_edit.setText(file_path)
        elif file_type == "video_folder":
            folder_path = self.get_folder_path("选择视频片段文件夹")
            if folder_path:
                self.video_folder_edit.setText(folder_path)
        elif file_type == "audio":
            file_path = self.get_file_path("选择音频文件",
                "音频文件 (*.mp3 *.wav *.aac *.flac);;所有文件 (*)")
            if file_path:
                self.audio_path_edit.setText(file_path)

    def toggle_zoom_controls(self, state):
        is_checked = state == Qt.Checked
        self.zoom_end_spin.setEnabled(is_checked)
        self.filter_combo.setEnabled(is_checked)
        self.zoom_merge_btn.setEnabled(is_checked)

    def merge_videos(self):
        video_folder = self.video_folder_edit.text().strip()
        audio_path = self.audio_path_edit.text().strip()
        cover_path = self.cover_path_edit.text().strip() or None
        output_name = self.output_name_edit.text().strip() or "output"

        if not video_folder or not audio_path:
            self.show_error("错误", "请选择视频文件夹和音频文件")
            return

        if not os.path.exists(video_folder):
            self.show_error("错误", "视频文件夹不存在")
            return

        if not os.path.exists(audio_path):
            self.show_error("错误", "音频文件不存在")
            return

        if cover_path and not os.path.exists(cover_path):
            self.show_warning("封面文件", "封面文件不存在，将跳过封面")
            cover_path = None

        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d%H%M")
        output_path = os.path.join(temp_dir, f"{output_name}-{ts}.mp4")

        worker = MergeVideoAudioThread(video_folder, audio_path, output_path, cover_path, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_merge_finished)
        self.add_worker(worker)
        self.show_info("开始合并", "正在合并视频和音频...")

    def merge_with_zoom(self):
        video_folder = self.video_folder_edit.text().strip()
        audio_path = self.audio_path_edit.text().strip()
        output_name = self.output_name_edit.text().strip() or "output"
        zoom_end = self.zoom_end_spin.value()
        filter_type = self.filter_combo.currentText()

        if not video_folder or not audio_path:
            self.show_error("错误", "请选择视频文件夹和音频文件")
            return

        if not os.path.exists(video_folder):
            self.show_error("错误", "视频文件夹不存在")
            return

        if not os.path.exists(audio_path):
            self.show_error("错误", "音频文件不存在")
            return

        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d%H%M")
        output_path = os.path.join(temp_dir, f"{output_name}-zoom-{ts}.mp4")

        worker = MergeVideoWithZoomThread(video_folder, audio_path, output_path, zoom_end, filter_type, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_merge_finished)
        self.add_worker(worker)
        self.show_info("开始缩放合并", "正在应用缩放效果并合并...")

    def on_merge_finished(self, success, message):
        if success:
            self.show_success("完成", f"视频合并完成: {message}")
        else:
            self.show_error("错误", f"视频合并失败: {message}")
        self.progress_bar.setValue(0)

class SubtitleGenerationPage(BasePage):
    """字幕生成页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("📝 生成字幕文件")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 音频文件选择
        audio_group = QGroupBox("音频文件")
        audio_layout = QGridLayout()

        audio_layout.addWidget(QLabel("音频文件:"), 0, 0)
        self.audio_path_edit = LineEdit()
        self.audio_path_edit.setPlaceholderText("选择音频文件...")
        self.audio_path_edit.setFixedHeight(35)
        audio_layout.addWidget(self.audio_path_edit, 0, 1)

        audio_btn = PushButton(FluentIcon.MUSIC, "浏览")
        audio_btn.setFixedWidth(80)
        audio_btn.clicked.connect(self.browse_audio)
        audio_layout.addWidget(audio_btn, 0, 2)

        audio_group.setLayout(audio_layout)
        layout.addWidget(audio_group)

        # 字幕生成设置
        srt_group = QGroupBox("字幕设置")
        srt_layout = QGridLayout()

        srt_layout.addWidget(QLabel("字幕文件名:"), 0, 0)
        self.srt_name_edit = LineEdit()
        self.srt_name_edit.setPlaceholderText("输入字幕文件名...")
        self.srt_name_edit.setFixedHeight(35)
        srt_layout.addWidget(self.srt_name_edit, 0, 1)

        srt_layout.addWidget(QLabel("每行字符数:"), 1, 0)
        self.char_count_spin = SpinBox()
        self.char_count_spin.setRange(10, 100)
        self.char_count_spin.setValue(30)
        self.char_count_spin.setFixedHeight(35)
        srt_layout.addWidget(self.char_count_spin, 1, 1)

        srt_group.setLayout(srt_layout)
        layout.addWidget(srt_group)

        # 生成按钮
        generate_btn = PrimaryPushButton(FluentIcon.DOCUMENT, "生成字幕文件")
        generate_btn.setFixedHeight(45)
        generate_btn.clicked.connect(self.generate_subtitle)
        layout.addWidget(generate_btn)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_audio(self):
        file_path = self.get_file_path("选择音频文件",
            "音频文件 (*.mp3 *.wav *.aac *.flac);;所有文件 (*)")
        if file_path:
            self.audio_path_edit.setText(file_path)

    def generate_subtitle(self):
        audio_path = self.audio_path_edit.text().strip()
        srt_name = self.srt_name_edit.text().strip() or "subtitle"
        char_count = self.char_count_spin.value()

        if not audio_path or not os.path.exists(audio_path):
            self.show_error("错误", "请选择有效的音频文件")
            return

        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d%H%M")
        output_path = os.path.join(srt_dir, f"{srt_name}-{ts}.srt")

        worker = SRTGenerationThread(audio_path, output_path, char_count, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_subtitle_finished)
        self.add_worker(worker)
        self.show_info("开始生成", f"正在生成字幕: {os.path.basename(audio_path)}")

    def on_subtitle_finished(self, success, message):
        if success:
            self.show_success("完成", f"字幕生成完成: {message}")
        else:
            self.show_error("错误", f"字幕生成失败: {message}")
        self.progress_bar.setValue(0)

class SubtitleTextPage(BasePage):
    """字幕转文本页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("📄 字幕转文本")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # SRT文件选择组
        srt_group = QGroupBox("SRT字幕文件")
        srt_layout = QGridLayout()

        srt_layout.addWidget(QLabel("SRT文件路径:"), 0, 0)
        self.srt_path_edit = LineEdit()
        self.srt_path_edit.setPlaceholderText("选择SRT字幕文件...")
        self.srt_path_edit.setFixedHeight(35)
        srt_layout.addWidget(self.srt_path_edit, 0, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "浏览")
        srt_btn.setFixedWidth(80)
        srt_btn.clicked.connect(self.browse_srt)
        srt_layout.addWidget(srt_btn, 0, 2)

        srt_group.setLayout(srt_layout)
        layout.addWidget(srt_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("TXT文件名:"), 0, 0)
        self.txt_name_edit = LineEdit()
        self.txt_name_edit.setPlaceholderText("输入输出文本文件名...")
        self.txt_name_edit.setFixedHeight(35)
        output_layout.addWidget(self.txt_name_edit, 0, 1)

        convert_btn = PrimaryPushButton(FluentIcon.DOWNLOAD, "保存为文本")
        convert_btn.setFixedWidth(150)
        convert_btn.clicked.connect(self.convert_srt_to_text)
        output_layout.addWidget(convert_btn, 0, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        # 翻译功能组
        translate_group = QGroupBox("翻译功能")
        translate_layout = QGridLayout()

        translate_layout.addWidget(QLabel("翻译SRT名称:"), 0, 0)
        self.translate_name_edit = LineEdit()
        self.translate_name_edit.setPlaceholderText("输入翻译后SRT文件名...")
        self.translate_name_edit.setFixedHeight(35)
        translate_layout.addWidget(self.translate_name_edit, 0, 1)

        translate_layout.addWidget(QLabel("目标语言:"), 1, 0)
        self.language_combo = ComboBox()
        language_options = [
            "英文", "中文", "繁体中文", "韩语", "日语", "俄语",
            "德语", "法语", "阿拉伯语", "越南语", "印地语",
            "西班牙语", "葡萄牙语"
        ]
        self.language_combo.addItems(language_options)
        self.language_combo.setCurrentIndex(0)  # 默认英文
        self.language_combo.setFixedHeight(35)
        translate_layout.addWidget(self.language_combo, 1, 1)

        translate_btn = PrimaryPushButton(FluentIcon.LANGUAGE, "翻译SRT文件")
        translate_btn.setFixedHeight(45)
        translate_btn.clicked.connect(self.translate_srt_file)
        translate_layout.addWidget(translate_btn, 1, 2)

        translate_group.setLayout(translate_layout)
        layout.addWidget(translate_group)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_srt(self):
        file_path = self.get_file_path("选择SRT字幕文件",
            "SRT字幕文件 (*.srt);;所有文件 (*)")
        if file_path:
            self.srt_path_edit.setText(file_path)

    def convert_srt_to_text(self):
        srt_path = self.srt_path_edit.text().strip()
        txt_name = self.txt_name_edit.text().strip() or "subtitle"

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)

        output_path = os.path.join(srt_dir, f"{txt_name}.txt")

        worker = SRTToTextThread(srt_path, output_path, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_srt_to_text_finished)
        self.add_worker(worker)
        self.show_info("开始转换", f"正在转换SRT到文本: {os.path.basename(srt_path)}")

    def translate_srt_file(self):
        srt_path = self.srt_path_edit.text().strip()
        output_name = self.translate_name_edit.text().strip() or "translated"
        target_language = self.language_combo.currentText()

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        # 检查API配置
        api_key = config_manager.get('api.siliconcloud_key')
        if not api_key:
            self.show_error("配置错误", "请先在设置中配置API密钥")
            return

        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)

        # 语言映射
        lang_map = {
            "英文": "English",
            "中文": "Chinese",
            "繁体中文": "Traditional Chinese",
            "韩语": "Korean",
            "日语": "Japanese",
            "俄语": "Russian",
            "德语": "German",
            "法语": "French",
            "阿拉伯语": "Arabic",
            "越南语": "Vietnamese",
            "印地语": "Hindi",
            "西班牙语": "Spanish",
            "葡萄牙语": "Portuguese"
        }

        target_lang = lang_map.get(target_language, "English")
        output_path = os.path.join(srt_dir, f"{output_name}-{target_lang}.srt")

        worker = SRTTranslateThread(srt_path, output_path, target_lang, self)
        worker.progress_updated.connect(self.progress_bar.setValue)
        worker.log_updated.connect(lambda msg: self.show_info("处理中", msg))
        worker.finished.connect(self.on_translate_finished)
        self.add_worker(worker)
        self.show_info("开始翻译", f"正在翻译SRT文件到{target_language}")

    def on_srt_to_text_finished(self, success, message):
        if success:
            self.show_success("完成", f"SRT转文本完成: {message}")
        else:
            self.show_error("错误", f"SRT转文本失败: {message}")
        self.progress_bar.setValue(0)

    def on_translate_finished(self, success, message):
        if success:
            self.show_success("完成", f"SRT翻译完成: {message}")
        else:
            self.show_error("错误", f"SRT翻译失败: {message}")
        self.progress_bar.setValue(0)

class AdjustSubtitlePage(BasePage):
    """调整字幕页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("✏️ 调整字幕文件")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # SRT文件选择组
        srt_group = QGroupBox("SRT字幕文件")
        srt_layout = QGridLayout()

        srt_layout.addWidget(QLabel("SRT文件路径:"), 0, 0)
        self.srt_path_edit = LineEdit()
        self.srt_path_edit.setPlaceholderText("选择SRT字幕文件...")
        self.srt_path_edit.setFixedHeight(35)
        srt_layout.addWidget(self.srt_path_edit, 0, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "浏览")
        srt_btn.setFixedWidth(80)
        srt_btn.clicked.connect(self.browse_srt)
        srt_layout.addWidget(srt_btn, 0, 2)

        load_btn = PrimaryPushButton(FluentIcon.DOWNLOAD, "加载字幕")
        load_btn.setFixedWidth(100)
        load_btn.clicked.connect(self.load_subtitle)
        srt_layout.addWidget(load_btn, 0, 3)

        srt_group.setLayout(srt_layout)
        layout.addWidget(srt_group)

        # 字幕内容编辑组
        content_group = QGroupBox("字幕内容编辑")
        content_layout = QVBoxLayout()

        content_label = QLabel("设置新的字幕内容 (一行一个字幕):")
        content_layout.addWidget(content_label)

        self.content_edit = QTextEdit()
        self.content_edit.setPlaceholderText("请输入字幕内容，每行一个字幕...")
        self.content_edit.setMinimumHeight(200)
        content_layout.addWidget(self.content_edit)

        content_group.setLayout(content_layout)
        layout.addWidget(content_group)

        # 操作按钮
        adjust_btn = PrimaryPushButton(FluentIcon.EDIT, "调整字幕文件")
        adjust_btn.setFixedHeight(45)
        adjust_btn.clicked.connect(self.adjust_subtitle)
        layout.addWidget(adjust_btn)

        layout.addStretch()

    def browse_srt(self):
        file_path = self.get_file_path("选择SRT字幕文件",
            "SRT字幕文件 (*.srt);;所有文件 (*)")
        if file_path:
            self.srt_path_edit.setText(file_path)

    def load_subtitle(self):
        srt_path = self.srt_path_edit.text().strip()

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        try:
            # 检测编码
            with open(srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'

            # 读取并解析SRT内容
            content = raw.decode(enc, errors='replace')

            # 提取字幕文本
            lines = []
            for line in content.splitlines():
                line = line.strip()
                if line.isdigit():
                    continue
                if re.match(r"\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}", line):
                    continue
                if not line:
                    continue
                lines.append(line)

            self.content_edit.setPlainText('\n'.join(lines))
            self.show_success("加载完成", f"已加载 {len(lines)} 条字幕")

        except Exception as e:
            self.show_error("加载失败", f"加载字幕文件失败: {str(e)}")

    def adjust_subtitle(self):
        srt_path = self.srt_path_edit.text().strip()
        content = self.content_edit.toPlainText().strip()

        if not srt_path or not os.path.exists(srt_path):
            self.show_error("错误", "请选择有效的SRT字幕文件")
            return

        if not content:
            self.show_error("错误", "请输入字幕内容")
            return

        try:
            srt_dir = os.path.join(os.getcwd(), 'SRT')
            os.makedirs(srt_dir, exist_ok=True)

            base_name = os.path.splitext(os.path.basename(srt_path))[0]
            output_path = os.path.join(srt_dir, f"{base_name}-adjusted.srt")

            # 读取原SRT文件获取时间轴
            with open(srt_path, 'rb') as f:
                raw = f.read()
                detect_result = chardet.detect(raw)
                enc = detect_result['encoding'] or 'utf-8'

            srt_content = raw.decode(enc, errors='replace')

            # 提取时间轴
            times = re.findall(r'(\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3})', srt_content)

            # 获取新内容行
            new_lines = content.split('\n')
            new_lines = [line.strip() for line in new_lines if line.strip()]

            if not new_lines:
                self.show_error("错误", "字幕内容为空")
                return

            # 生成新SRT文件
            with open(output_path, 'w', encoding='utf-8') as f:
                for i in range(min(len(new_lines), len(times))):
                    f.write(f"{i+1}\n")
                    f.write(f"{times[i]}\n")
                    f.write(f"{new_lines[i]}\n\n")

            self.show_success("完成", f"调整后的字幕文件已保存: {output_path}")

        except Exception as e:
            self.show_error("错误", f"调整字幕失败: {str(e)}")

class MergeSubtitlePage(BasePage):
    """整合视频字幕页面"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(20)

        # 标题
        title = SubtitleLabel("🎬 整合视频字幕")
        title.setFont(TITLE_FONT)
        layout.addWidget(title)

        # 文件选择组
        file_group = QGroupBox("文件选择")
        file_layout = QGridLayout()

        file_layout.addWidget(QLabel("视频文件:"), 0, 0)
        self.video_path_edit = LineEdit()
        self.video_path_edit.setPlaceholderText("选择视频文件...")
        self.video_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.video_path_edit, 0, 1)

        video_btn = PushButton(FluentIcon.VIDEO, "浏览")
        video_btn.setFixedWidth(80)
        video_btn.clicked.connect(lambda: self.browse_file("video"))
        file_layout.addWidget(video_btn, 0, 2)

        file_layout.addWidget(QLabel("SRT字幕文件:"), 1, 0)
        self.srt_path_edit = LineEdit()
        self.srt_path_edit.setPlaceholderText("选择SRT字幕文件...")
        self.srt_path_edit.setFixedHeight(35)
        file_layout.addWidget(self.srt_path_edit, 1, 1)

        srt_btn = PushButton(FluentIcon.DOCUMENT, "浏览")
        srt_btn.setFixedWidth(80)
        srt_btn.clicked.connect(lambda: self.browse_file("srt"))
        file_layout.addWidget(srt_btn, 1, 2)

        file_group.setLayout(file_layout)
        layout.addWidget(file_group)

        # 字幕样式设置组
        style_group = QGroupBox("字幕样式")
        style_layout = QGridLayout()

        style_layout.addWidget(QLabel("字体文件:"), 0, 0)
        self.font_path_edit = LineEdit()
        self.font_path_edit.setText("font/Light.otf")
        self.font_path_edit.setPlaceholderText("选择字体文件...")
        self.font_path_edit.setFixedHeight(35)
        style_layout.addWidget(self.font_path_edit, 0, 1)

        font_btn = PushButton(FluentIcon.FONT, "浏览")
        font_btn.setFixedWidth(80)
        font_btn.clicked.connect(lambda: self.browse_file("font"))
        style_layout.addWidget(font_btn, 0, 2)

        style_layout.addWidget(QLabel("字体大小:"), 1, 0)
        self.font_size_spin = QSpinBox()
        self.font_size_spin.setRange(10, 72)
        self.font_size_spin.setValue(18)
        self.font_size_spin.setFixedHeight(35)
        style_layout.addWidget(self.font_size_spin, 1, 1)

        style_layout.addWidget(QLabel("背景色值:"), 2, 0)
        self.bg_color_edit = LineEdit()
        self.bg_color_edit.setText("#333333")
        self.bg_color_edit.setPlaceholderText("如 #333333")
        self.bg_color_edit.setFixedHeight(35)
        style_layout.addWidget(self.bg_color_edit, 2, 1)

        style_layout.addWidget(QLabel("字幕位置:"), 3, 0)
        self.position_combo = ComboBox()
        position_options = ["bottom", "top"]
        self.position_combo.addItems(position_options)
        self.position_combo.setCurrentIndex(0)
        self.position_combo.setFixedHeight(35)
        style_layout.addWidget(self.position_combo, 3, 1)

        style_group.setLayout(style_layout)
        layout.addWidget(style_group)

        # 输出设置组
        output_group = QGroupBox("输出设置")
        output_layout = QGridLayout()

        output_layout.addWidget(QLabel("输出视频名称:"), 0, 0)
        self.output_name_edit = LineEdit()
        self.output_name_edit.setPlaceholderText("输入输出视频名称...")
        self.output_name_edit.setFixedHeight(35)
        output_layout.addWidget(self.output_name_edit, 0, 1)

        merge_btn = PrimaryPushButton(FluentIcon.MEDIA, "整合总视频")
        merge_btn.setFixedHeight(45)
        merge_btn.clicked.connect(self.merge_video_subtitle)
        output_layout.addWidget(merge_btn, 0, 2)

        output_group.setLayout(output_layout)
        layout.addWidget(output_group)

        # 进度条
        self.progress_bar = ProgressBar()
        self.progress_bar.setFixedHeight(20)
        layout.addWidget(self.progress_bar)

        layout.addStretch()

    def browse_file(self, file_type):
        if file_type == "video":
            file_path = self.get_file_path("选择视频文件",
                "视频文件 (*.mp4 *.mov *.avi);;所有文件 (*)")
            if file_path:
                self.video_path_edit.setText(file_path)
        elif file_type == "srt":
            file_path = self.get_file_path("选择SRT字幕文件",
                "SRT字幕文件 (*.srt);;所有文件 (*)")
            if file_path:
                self.srt_path_edit.setText(file_path)
        elif file_type == "font":
            file_path = self.get_file_path("选择字体文件",
                "字体文件 (*.otf *.ttf);;所有文件 (*)")
            if file_path:
                self.font_path_edit.setText(file_path)

    def merge_video_subtitle(self):
        video_path = self.video_path_edit.text().strip()
        srt_path = self.srt_path_edit.text().strip()
        font_path = self.font_path_edit.text().strip()
        font_size = self.font_size_spin.value()
        bg_color = self.bg_color_edit.text().strip()
        position = self.position_combo.currentText()
        output_name = self.output_name_edit.text().strip() or "output"

        # 验证输入
        if not all([video_path, srt_path, font_path]):
            self.show_error("错误", "请选择视频、字幕和字体文件")
            return

        if not all([os.path.exists(video_path), os.path.exists(srt_path), os.path.exists(font_path)]):
            self.show_error("错误", "请确保所有文件路径都有效")
            return

        try:
            temp_dir = os.path.join(os.getcwd(), 'temp')
            os.makedirs(temp_dir, exist_ok=True)

            ts = datetime.now().strftime("%Y%m%d%H%M")
            output_path = os.path.join(temp_dir, f"{output_name}-{ts}.mp4")

            # 位置映射
            pos_map = {"bottom": "2", "top": "8"}
            alignment = pos_map.get(position, "2")

            # 颜色格式转换（ASS格式：&HBBGGRR&）
            def hex_to_ass_color(hex_color):
                hex_color = hex_color.lstrip('#')
                if len(hex_color) == 6:
                    b, g, r = hex_color[4:6], hex_color[2:4], hex_color[0:2]
                    return f"&H00{b}{g}{r}&"
                elif len(hex_color) == 8:  # 带透明度
                    a, b, g, r = hex_color[0:2], hex_color[6:8], hex_color[4:6], hex_color[2:4]
                    return f"&H{a}{b}{g}{r}&"
                else:
                    return "&H000000&"

            ass_color = hex_to_ass_color(bg_color)

            # 字体名只要文件名不带扩展
            fontname = os.path.splitext(os.path.basename(font_path))[0]

            # 构造force_style
            force_style = f"FontName={fontname},FontSize={font_size},OutlineColour={ass_color},Alignment={alignment}"

            ffmpeg_path = config_manager.get('paths.ffmpeg_binary', 'ffmpeg')

            # FFmpeg命令
            cmd = [
                ffmpeg_path, "-y", "-i", video_path, "-vf",
                f"subtitles='{srt_path}':force_style='{force_style}'",
                "-c:a", "copy", output_path
            ]

            self.show_info("开始整合", "正在整合视频和字幕...")

            # 执行FFmpeg命令
            result = subprocess.run(cmd, capture_output=True, text=True)

            if os.path.exists(output_path) and os.path.getsize(output_path) > 1024:
                self.show_success("完成", f"带字幕视频已保存: {output_path}")
            else:
                self.show_error("错误", f"整合失败: {result.stderr}")

        except Exception as e:
            self.show_error("错误", f"整合异常: {str(e)}")