import os
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import ttkbootstrap as tb
from ttkbootstrap.constants import *
from datetime import datetime
import subprocess
import requests
import json
from PIL import Image
import chardet
import re
import shutil

# 添加环境编码设置：
os.environ["LANG"] = "zh_CN.UTF-8"  # 或其他合适的编码

# 设置字体
TITLE_FONT = ("PingFang SC Medium", 26)
LABEL_FONT = ("PingFang SC", 18)
ENTRY_FONT = ("PingFang SC", 16)

# dark风格
STYLE_THEME = "darkly"

class MultimediaEditor(tb.Window):
    def __init__(self):
        super().__init__(themename=STYLE_THEME)
        self.title("BOZO-MCN 多媒体编辑器 1.1.3")
        self.geometry("1040x540")
        # self.resizable(False, False)
        self.create_widgets()

    def create_widgets(self):
        # 主标题
        title = tb.Label(self, text=" 📽️  MCN多媒体编辑器 - BOZO专用 ", font=TITLE_FONT, bootstyle=INVERSE)
        title.pack(pady=40)

        # 选项卡
        notebook = tb.Notebook(self, bootstyle=SECONDARY)
        notebook.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)

        # 0. 视频转换
        tab0 = tb.Frame(notebook)
        self.create_tab0_video_convert(tab0)
        notebook.add(tab0, text=" 转换视频与音频 ")

        # 1. 图片转视频片段
        tab1 = tb.Frame(notebook)
        self.create_tab1(tab1)
        notebook.add(tab1, text=" 图片转视频片段 ")

        # 2. 合并视频片段与音频
        tab2 = tb.Frame(notebook)
        self.create_tab2(tab2)
        notebook.add(tab2, text=" 合并视频与音频 ")

        # 3. 生成字幕文件
        tab3 = tb.Frame(notebook)
        self.create_tab3(tab3)
        notebook.add(tab3, text=" 生成字幕文件 ")

        # 3.5 字幕转文本
        tab3_5 = tb.Frame(notebook)
        self.create_tab3_5(tab3_5)
        notebook.add(tab3_5, text=" 字幕转文本 ")

        # 4. 调整字幕文件
        tab4 = tb.Frame(notebook)
        self.create_tab4(tab4)
        notebook.add(tab4, text=" 调整字幕文件 ")

        # 5. 整合视频字幕
        tab5 = tb.Frame(notebook)
        self.create_tab5(tab5)
        notebook.add(tab5, text=" 整合视频字幕 ")

    def create_tab0_video_convert(self, frame):
        # 第一行：视频文件选择
        video_label = tb.Label(frame, text="填视频文件：", font=LABEL_FONT)
        video_label.grid(row=0, column=0, sticky=tk.W, pady=8, padx=8)
        self.vc_video_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.vc_video_entry.grid(row=0, column=1, pady=8, padx=8)
        video_btn = tb.Button(frame, text="选择视频文件", command=self.select_vc_video)
        video_btn.grid(row=0, column=2, padx=8)

        # 第二行：批量文件夹选择
        batch_label = tb.Label(frame, text="批量文件夹：", font=LABEL_FONT)
        batch_label.grid(row=1, column=0, sticky=tk.W, pady=8, padx=8)
        self.vc_batch_entry = tb.Entry(frame, font=ENTRY_FONT, width=65, state="disabled")
        self.vc_batch_entry.grid(row=1, column=1, pady=8, padx=8)
        self.vc_batch_btn = tb.Button(frame, text="选择文件夹", command=self.select_vc_batch_folder, state="disabled")
        self.vc_batch_btn.grid(row=1, column=2, padx=8)
        self.vc_batch_var = tk.BooleanVar()
        self.vc_batch_switch = tb.Checkbutton(frame, text="批量模式", variable=self.vc_batch_var, command=self.toggle_vc_batch)
        self.vc_batch_switch.grid(row=1, column=3, sticky=tk.W, pady=8, padx=(8,0))

        # 第三行：无声视频
        mute_label = tb.Label(frame, text="设定无声名：", font=LABEL_FONT)
        mute_label.grid(row=2, column=0, sticky=tk.W, pady=8, padx=8)
        self.mute_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.mute_entry.grid(row=2, column=1, pady=8, padx=8)
        mute_btn = tb.Button(frame, text="转换无声视频", command=self.convert_to_mute_video)
        mute_btn.grid(row=2, column=2, padx=8)

        # 第四行：音频文件
        audio_label = tb.Label(frame, text="设定音频名：", font=LABEL_FONT)
        audio_label.grid(row=3, column=0, sticky=tk.W, pady=8, padx=8)
        self.audio_out_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.audio_out_entry.grid(row=3, column=1, pady=8, padx=8)
        audio_btn = tb.Button(frame, text="转换音频文件", command=self.convert_to_audio_file)
        audio_btn.grid(row=3, column=2, padx=8)

        # 第五行：横线
        sep = tb.Separator(frame, orient='horizontal')
        sep.grid(row=4, column=0, columnspan=4, sticky='ew', pady=16)

        # 第六行：分割视频片段名、数量（无标题）
        seg_label = tb.Label(frame, text="视频片段名：", font=LABEL_FONT)
        seg_label.grid(row=5, column=0, sticky=tk.W, pady=8, padx=8)
        self.seg_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.seg_entry.grid(row=5, column=1, sticky=tk.W, pady=8, padx=8)
        self.count_entry = tb.Entry(frame, font=ENTRY_FONT, width=10)
        self.count_entry.insert(0, "3")
        self.count_entry.grid(row=5, column=2, sticky=tk.E, pady=8, padx=8)

        # 第七行：分割按钮和批量模式勾选同一行
        self.vc_batch_switch.grid_forget()  # 先移除原位置
        seg_btn = tb.Button(frame, text="按分割数量 生成视频片段", bootstyle=SUCCESS, width=30, command=self.split_video_by_count)
        self.vc_batch_switch.grid(row=6, column=0, sticky=tk.W, pady=16, padx=(8,0))
        seg_btn.grid(row=6, column=1, pady=16, sticky=tk.W)

    def toggle_vc_batch(self):
        if self.vc_batch_var.get():
            self.vc_batch_entry.config(state="normal")
            self.vc_batch_btn.config(state="normal")
        else:
            self.vc_batch_entry.config(state="disabled")
            self.vc_batch_btn.config(state="disabled")

    def select_vc_batch_folder(self):
        path = filedialog.askdirectory()
        if path:
            self.vc_batch_entry.delete(0, tk.END)
            self.vc_batch_entry.insert(0, path)

    def create_tab1(self, frame):
        # 常规短视频尺寸下拉菜单
        size_options = [
            "1:1 (1240x1240)", "3:4 (1080x1440)", "4:3 (1440x1080)",
            "9:16 (900x1600)", "16:9 (1600x900)",
            "1:2 (870x1740)", "2:1 (1740x870)", "1:3 (720x2160)",
            "3:1 (2160x720)", "2:3 (960x1440)", "3:2 (1440x960)",
            "2:5 (720x1800)", "5:2 (1800x720)", "3:5 (960x1600)",
            "5:3 (1600x960)", "4:5 (1080x1350)", "5:4 (1350x1080)"
        ]
        self.size_var = tk.StringVar()
        self.size_var.set(size_options[0])
        size_menu = tb.Combobox(frame, textvariable=self.size_var, values=size_options, width=15, font=ENTRY_FONT, state="readonly")
        # 图片路径
        img_label = tb.Label(frame, text="图片路径：", font=LABEL_FONT)
        self.img_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        img_btn = tb.Button(frame, text="浏览单张图片", command=self.select_image)
        # 图片停留秒数和视频尺寸同一行
        dur_label = tb.Label(frame, text="停留秒数：", font=LABEL_FONT)
        self.dur_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        self.dur_entry.insert(0, "6")
        size_label = tb.Label(frame, text="视频宽高：", font=LABEL_FONT)
        self.size_entry = tb.Entry(frame, font=ENTRY_FONT, width=17)
        self.size_entry.insert(0, "1080x1920")
        # 批量图片文件夹
        batch_label = tb.Label(frame, text="批量文件夹：", font=LABEL_FONT)
        self.batch_entry = tb.Entry(frame, font=ENTRY_FONT, width=50, state="disabled")
        self.batch_btn = tb.Button(frame, text="选择文件夹", command=self.select_folder, state="disabled")
        self.batch_var = tk.BooleanVar()
        self.batch_switch = tb.Checkbutton(frame, text="批量模式", variable=self.batch_var, command=self.toggle_batch)
        # 生成按钮
        gen_btn = tb.Button(frame, text="生成视频片段", bootstyle=SUCCESS, width=20, command=self.generate_video_from_image)

        # 布局
        img_label.grid(row=0, column=1, sticky=tk.W, pady=8, padx=8)
        self.img_entry.grid(row=0, column=2, pady=8, padx=8)
        img_btn.grid(row=0, column=3, padx=8)
        dur_label.grid(row=1, column=1, sticky=tk.W, pady=8, padx=(8,0))
        self.dur_entry.grid(row=1, column=2, sticky=tk.W, pady=8, padx=(2,2))
        size_label.grid(row=1, column=3, sticky=tk.W, pady=8, padx=(8,0))
        self.size_entry.grid(row=1, column=4, sticky=tk.W, pady=8, padx=(2,2))
        # 批量文件夹和尺寸下拉菜单同一行
        batch_label.grid(row=2, column=1, sticky=tk.W, pady=8, padx=8)
        self.batch_entry.grid(row=2, column=2, pady=8, padx=8)
        self.batch_btn.grid(row=2, column=3, padx=8)
        size_menu.grid(row=2, column=4, sticky=tk.W, pady=8, padx=(8,0))
        # 批量模式和生成按钮同一行
        self.batch_switch.grid(row=3, column=1, sticky=tk.W, pady=20, padx=(8,0))
        gen_btn.grid(row=3, column=2, pady=20, padx=(8,0))

        size_menu.bind("<<ComboboxSelected>>", self.on_size_select)

    def on_size_select(self, event):
        # 选中下拉菜单后自动填充尺寸输入框
        text = self.size_var.get()
        match = re.search(r'\((\d+x\d+)\)', text)
        if match:
            self.size_entry.delete(0, tk.END)
            self.size_entry.insert(0, match.group(1))

    def toggle_batch(self):
        if self.batch_var.get():
            self.batch_entry.config(state="normal")
            self.batch_btn.config(state="normal")
        else:
            self.batch_entry.config(state="disabled")
            self.batch_btn.config(state="disabled")

    def select_image(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("PNG图片", "*.png"),
                ("JPG图片", "*.jpg"),
                ("JPEG图片", "*.jpeg"),
                ("BMP图片", "*.bmp"),
                ("所有图片", "*.*")
            ]
        )
        if path:
            self.img_entry.delete(0, tk.END)
            self.img_entry.insert(0, path)

    def select_folder(self):
        path = filedialog.askdirectory()
        if path:
            self.batch_entry.delete(0, tk.END)
            self.batch_entry.insert(0, path)

    def create_tab2(self, frame):
        # 视频封面文件
        cover_label = tb.Label(frame, text="封面文件：", font=LABEL_FONT)
        cover_label.grid(row=0, column=0, sticky=tk.W, pady=8, padx=8)
        self.cover_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.cover_entry.grid(row=0, column=1, pady=8, padx=8)
        cover_btn = tb.Button(frame, text="选择封面文件", command=self.select_cover)
        cover_btn.grid(row=0, column=2, padx=8)

        # 视频片段文件夹
        v_label = tb.Label(frame, text="片段文件夹：", font=LABEL_FONT)
        v_label.grid(row=1, column=0, sticky=tk.W, pady=8, padx=8)
        self.v_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.v_entry.grid(row=1, column=1, pady=8, padx=8)
        v_btn = tb.Button(frame, text="选择 文件夹", command=self.select_video_folder)
        v_btn.grid(row=1, column=2, padx=8)

        # 音频文件
        a_label = tb.Label(frame, text="音频文件路径：", font=LABEL_FONT)
        a_label.grid(row=2, column=0, sticky=tk.W, pady=8, padx=8)
        self.a_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.a_entry.grid(row=2, column=1, pady=8, padx=8)
        a_btn = tb.Button(frame, text="选择音频文件", command=self.select_audio)
        a_btn.grid(row=2, column=2, padx=8)

        # 新视频名称和合并按钮同一行
        name_label = tb.Label(frame, text="设定视频名：", font=LABEL_FONT)
        name_label.grid(row=3, column=0, sticky=tk.W, pady=8, padx=8)
        self.name_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.name_entry.grid(row=3, column=1, sticky=tk.W, pady=8, padx=8)
        merge_btn = tb.Button(frame, text="合并新视频", bootstyle=SUCCESS, width=9, command=self.merge_videos_with_audio)
        merge_btn.grid(row=3, column=2, pady=8, padx=8)

        # 插入横线
        sep = tb.Separator(frame, orient='horizontal')
        sep.grid(row=4, column=0, columnspan=3, sticky='ew', pady=16)

        # 滤镜功能
        # 第五行：缩放动画
        zoom_to_label = tb.Label(frame, text="缩放结束值：", font=LABEL_FONT)
        zoom_to_label.grid(row=5, column=0, sticky=tk.W, pady=8, padx=(8,2))
        self.zoom_to_entry = tb.Entry(frame, font=ENTRY_FONT, width=65, state="disabled")
        self.zoom_to_entry.insert(0, "1.2")
        self.zoom_to_entry.grid(row=5, column=1, sticky=tk.W, pady=8, padx=(8,2))
        self.zoom_var = tk.BooleanVar()
        zoom_check = tb.Checkbutton(frame, text="缩放动画", variable=self.zoom_var, command=self.toggle_zoom_controls)
        zoom_check.grid(row=5, column=2, sticky=tk.E, pady=8, padx=8)

        # 第六行：滤镜类型选择
        filter_label = tb.Label(frame, text="缩放滤镜类型：", font=LABEL_FONT)
        filter_label.grid(row=6, column=0, sticky=tk.W, pady=8, padx=8)
        self.filter_var = tk.StringVar()
        self.filter_var.set("无")
        filter_options = ["scale+zoom", "scale+zoompan", "无"]
        self.filter_menu = tb.Combobox(frame, textvariable=self.filter_var, values=filter_options, width=63, font=ENTRY_FONT, state="disabled")
        self.filter_menu.grid(row=6, column=1, pady=8, padx=8)

        # 合并缩放滤镜视频按钮放在滤镜类型右边
        self.merge_all_btn = tb.Button(frame, text="合并缩放视频", bootstyle=SUCCESS, width=9, command=self.merge_all_videos_with_filters, state="disabled")
        self.merge_all_btn.grid(row=6, column=2, pady=8, padx=8)

    def toggle_zoom_controls(self):
        # 勾选缩放动画时，启用缩放结束值、滤镜类型、合并按钮，否则禁用
        state = "normal" if self.zoom_var.get() else "disabled"
        self.zoom_to_entry.config(state=state)
        self.filter_menu.config(state=state)
        self.merge_all_btn.config(state=state)

    def select_cover(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("PNG图片", "*.png"),
                ("JPG图片", "*.jpg"),
                ("JPEG图片", "*.jpeg"),
                ("BMP图片", "*.bmp"),
                ("所有图片", "*.*")
            ]
        )
        if path:
            self.cover_entry.delete(0, tk.END)
            self.cover_entry.insert(0, path)

    def select_video_folder(self):
        path = filedialog.askdirectory()
        if path:
            self.v_entry.delete(0, tk.END)
            self.v_entry.insert(0, path)

    def select_audio(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("MP3音频", "*.mp3"),
                ("WAV音频", "*.wav"),
                ("AAC音频", "*.aac"),
                ("FLAC音频", "*.flac"),
                ("所有音频", "*.*")
            ]
        )
        if path:
            self.a_entry.delete(0, tk.END)
            self.a_entry.insert(0, path)

    def create_tab3(self, frame):
        # 音频文件
        audio_label = tb.Label(frame, text="音频文件路径：", font=LABEL_FONT)
        audio_label.grid(row=0, column=0, sticky=tk.W, pady=8, padx=8)
        self.audio_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.audio_entry.grid(row=0, column=1, pady=8, padx=8)
        audio_btn = tb.Button(frame, text="选择Mp3音频文件", command=self.select_audio3)
        audio_btn.grid(row=0, column=2, padx=8)

        # 新音频文本名和生成按钮同一行
        srt_label = tb.Label(frame, text="设定TXT名称：", font=LABEL_FONT)
        srt_label.grid(row=1, column=0, sticky=tk.W, pady=8, padx=8)
        self.srt_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.srt_entry.grid(row=1, column=1, sticky=tk.W, pady=8, padx=8)
        gen_btn = tb.Button(frame, text="生成文本", bootstyle=SUCCESS, width=12, command=self.generate_txt_from_audio)
        gen_btn.grid(row=1, column=2, pady=8, padx=8)

        # --- 新增whisper.cpp本地SRT生成 ---
        # 分割线
        sep = tb.Separator(frame, orient='horizontal')
        sep.grid(row=2, column=0, columnspan=3, sticky='ew', pady=16)

        # 本地whisper.cpp字幕文件名输入
        local_srt_label = tb.Label(frame, text="字幕文件名：", font=LABEL_FONT)
        local_srt_label.grid(row=3, column=0, sticky=tk.W, pady=8, padx=8)
        self.local_srt_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.local_srt_entry.grid(row=3, column=1, sticky=tk.W, pady=8, padx=8)
        # ml参数输入框（无标题，宽20，默认30）
        self.ml_entry = tb.Entry(frame, font=ENTRY_FONT, width=12)
        self.ml_entry.insert(0, "30")
        self.ml_entry.grid(row=3, column=2, sticky=tk.W, pady=8, padx=8)

        # 本地生成按钮
        local_gen_btn = tb.Button(frame, text="按字符长度 生成字幕", bootstyle=SUCCESS, width=30, command=self.generate_srt_with_whisper)
        local_gen_btn.grid(row=4, column=1, pady=16)

    def select_audio3(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("MP3音频", "*.mp3"),
                ("WAV音频", "*.wav"),
                ("AAC音频", "*.aac"),
                ("FLAC音频", "*.flac"),
                ("所有音频", "*.*")
            ]
        )
        if path:
            self.audio_entry.delete(0, tk.END)
            self.audio_entry.insert(0, path)

    def create_tab3_5(self, frame):
        # 第一行：选择SRT字幕文件
        srt_label = tb.Label(frame, text="SRT字幕路径：", font=LABEL_FONT)
        srt_label.grid(row=0, column=0, sticky=tk.W, pady=8, padx=8)
        self.srt2txt_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.srt2txt_entry.grid(row=0, column=1, pady=8, padx=8)
        srt_btn = tb.Button(frame, text="选择SRT文件", command=self.select_srt2txt)
        srt_btn.grid(row=0, column=2, padx=8)

        # 第二行：TXT文件名和生成按钮
        txt_label = tb.Label(frame, text="设定TXT名称：", font=LABEL_FONT)
        txt_label.grid(row=1, column=0, sticky=tk.W, pady=8, padx=8)
        self.txtname_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.txtname_entry.grid(row=1, column=1, pady=8, padx=8)
        gen_btn = tb.Button(frame, text="保存文本", bootstyle=SUCCESS, width=10, command=self.srt_to_txt)
        gen_btn.grid(row=1, column=2, padx=8)

        # 新增：横线
        sep = tb.Separator(frame, orient='horizontal')
        sep.grid(row=2, column=0, columnspan=3, sticky='ew', pady=16)

        # 新增：翻译SRT功能
        trans_label = tb.Label(frame, text="翻译SRT名称：", font=LABEL_FONT)
        trans_label.grid(row=3, column=0, sticky=tk.W, pady=8, padx=8)
        self.trans_srt_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.trans_srt_entry.grid(row=3, column=1, pady=8, padx=8, sticky=tk.W)
        self.trans_lang_var = tk.StringVar()
        self.trans_lang_var.set("英文")
        lang_options = [
            "中文", "英文", "繁体中文", "韩语", "日语", "俄语", "德语", "法语", "阿拉伯语", "越南语", "印地语", "西班牙语", "葡萄牙语"
        ]
        trans_lang_menu = tb.Combobox(frame, textvariable=self.trans_lang_var, values=lang_options, width=8, font=ENTRY_FONT, state="readonly")
        trans_lang_menu.grid(row=3, column=2, pady=8, padx=8, sticky=tk.W)

        # 新增：翻译按钮
        trans_btn = tb.Button(frame, text="按语言翻译SRT文件", bootstyle=SUCCESS, width=30, command=self.translate_srt_file)
        trans_btn.grid(row=4, column=0, columnspan=3, pady=18)
        trans_btn.grid_configure(sticky='n')

    def select_srt2txt(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("SRT字幕", "*.srt"),
                ("所有文件", "*.*")
            ]
        )
        if path:
            self.srt2txt_entry.delete(0, tk.END)
            self.srt2txt_entry.insert(0, path)

    def srt_to_txt(self):
        srt_path = self.srt2txt_entry.get()
        txt_name = self.txtname_entry.get().strip() or "subtitle.txt"
        txt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(txt_dir, exist_ok=True)
        if not os.path.isfile(srt_path):
            messagebox.showerror("错误", "请选择SRT字幕文件")
            print("[错误] SRT字幕文件无效")
            return
        txt_path = os.path.join(txt_dir, txt_name if txt_name.endswith('.txt') else txt_name + '.txt')
        # 检测编码
        with open(srt_path, 'rb') as f:
            raw = f.read()
            detect_result = chardet.detect(raw)
            enc = detect_result['encoding'] or 'utf-8'
            print(f"[字幕转文本] 检测到SRT编码: {enc}")
        lines = []
        for line in raw.decode(enc, errors='replace').splitlines():
            line = line.strip()
            if line.isdigit():
                continue
            if re.match(r"\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}", line):
                continue
            if not line:
                continue
            lines.append(line)
        merged_text = ''.join(lines)
        with open(txt_path, 'w', encoding='utf-8') as f:
            f.write(merged_text)
        print(f"[字幕转文本] TXT文本已保存到: {txt_path}")

    def translate_srt_file(self):
        srt_path = self.srt2txt_entry.get()
        out_name = self.trans_srt_entry.get().strip() or "translated"
        lang = self.trans_lang_var.get()
        txt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(txt_dir, exist_ok=True)
        if not os.path.isfile(srt_path):
            messagebox.showerror("错误", "请选择SRT字幕文件")
            print("[错误] SRT字幕文件无效")
            return
        # 检测编码
        with open(srt_path, 'rb') as f:
            raw = f.read()
            detect_result = chardet.detect(raw)
            enc = detect_result['encoding'] or 'utf-8'
        srt_content = raw.decode(enc, errors='replace')
        # 目标语言映射
        lang_map = {
            "中文": "Chinese",
            "英文": "English",
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
        target_lang = lang_map.get(lang, "English")
        # 构造API请求
        api_key = os.environ.get("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "未检测到API KEY")
            print("[错误] 未检测到API KEY")
            return
        url = "https://api.siliconflow.cn/v1/chat/completions"
        prompt = f"帮我将输入的srt字幕文本内容翻译转换为{target_lang}。保持srt文本结构，序号，时间都不变，只需要翻译内容，并输出srt格式的翻译内容就可以，不需要其他额外注释和说明。\n\n" + srt_content
        payload = {
            "model": "Qwen/Qwen2.5-Coder-32B-Instruct",
            "messages": [
                {"role": "user", "content": prompt}
            ],
            "stream": False,
            "max_tokens": 4096,
            "response_format": {"type": "text"}
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        try:
            print("[翻译SRT] 请求API...")
            resp = requests.post(url, json=payload, headers=headers, timeout=120)
            if resp.status_code == 200:
                result = resp.json()
                # 兼容API返回格式
                content = result.get("choices", [{}])[0].get("message", {}).get("content", "").strip()
                if not content:
                    messagebox.showerror("错误", "API未返回有效翻译内容")
                    print("[错误] API未返回有效翻译内容")
                    return
                out_path = os.path.join(txt_dir, f"{out_name}-{target_lang}.srt")
                with open(out_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"[翻译SRT] 翻译SRT已保存到: {out_path}")
                # messagebox.showinfo("完成", f"翻译SRT已保存到: {out_path}")
            else:
                messagebox.showerror("错误", f"API请求失败: {resp.text}")
                print(f"[错误] API请求失败: {resp.text}")
        except Exception as e:
            messagebox.showerror("错误", str(e))
            print(f"[错误] {e}")

    def create_tab4(self, frame):
        # SRT文件
        srt_label = tb.Label(frame, text="SRT字幕路径：", font=LABEL_FONT)
        srt_label.grid(row=0, column=0, sticky=tk.W, pady=8, padx=8)
        self.srtfile_entry = tb.Entry(frame, font=ENTRY_FONT, width=65)
        self.srtfile_entry.grid(row=0, column=1, pady=8, padx=8)
        srt_btn = tb.Button(frame, text="选择SRT文件", command=self.select_srt)
        srt_btn.grid(row=0, column=2, padx=8)

        # 新字幕内容宽度80
        text_label = tb.Label(frame, text="设定字幕内容：", font=LABEL_FONT)
        text_label.grid(row=1, column=0, sticky=tk.NW, pady=8, padx=8)
        self.text_box = tk.Text(frame, font=ENTRY_FONT, width=65, height=10)
        self.text_box.grid(row=1, column=1, pady=8, padx=8)

        # 调整按钮
        adjust_btn = tb.Button(frame, text="一行一字幕 调整SRT字幕文件", bootstyle=SUCCESS, width=20, command=self.adjust_srt_file)
        adjust_btn.grid(row=2, column=1, pady=20)

    def select_srt(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("SRT字幕", "*.srt"),
                ("所有文件", "*.*")
            ]
        )
        if path:
            self.srtfile_entry.delete(0, tk.END)
            self.srtfile_entry.insert(0, path)

    def create_tab5(self, frame):
        # 视频文件
        video_label = tb.Label(frame, text="视频文件路径：", font=LABEL_FONT)
        video_label.grid(row=0, column=0, sticky=tk.W, pady=8, padx=8)
        self.video_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        self.video_entry.grid(row=0, column=1, pady=8, padx=8)
        video_btn = tb.Button(frame, text="🗂️ 选择视频文件", command=self.select_video)
        video_btn.grid(row=0, column=2, padx=8)

        # 字幕文件
        srt_label = tb.Label(frame, text="SRT字幕路径：", font=LABEL_FONT)
        srt_label.grid(row=1, column=0, sticky=tk.W, pady=8, padx=(8,0))
        self.srt2_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        self.srt2_entry.grid(row=1, column=1,  pady=8, padx=(2,2))
        srt2_btn = tb.Button(frame, text="🎼 选择SRT文件", command=self.select_srt2)
        srt2_btn.grid(row=1, column=2, padx=8)

        # 字幕字体和字幕字体大小同一行
        font_label = tb.Label(frame, text="设定字幕字体：", font=LABEL_FONT)
        font_label.grid(row=2, column=0, sticky=tk.W, pady=8, padx=(8,0))
        self.font_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        self.font_entry.insert(0, "font/Light.otf")
        self.font_entry.grid(row=2, column=1, sticky=tk.W, pady=8, padx=(2,2))
        size_label = tb.Label(frame, text="字幕字体大小：", font=LABEL_FONT)
        size_label.grid(row=2, column=2, sticky=tk.W, pady=8, padx=(8,0))
        self.size2_entry = tb.Entry(frame, font=ENTRY_FONT, width=10)
        self.size2_entry.insert(0, "18")
        self.size2_entry.grid(row=2, column=3, sticky=tk.W, pady=8, padx=(2,2))

        # 字幕背景色和字幕位置同一行，输入框width=20
        color_label = tb.Label(frame, text="字幕背景色值：", font=LABEL_FONT)
        color_label.grid(row=3, column=0, sticky=tk.W, pady=8, padx=(8,0))
        self.color_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        self.color_entry.insert(0, "#333333")
        self.color_entry.grid(row=3, column=1, sticky=tk.W, pady=8, padx=(2,2))
        pos_label = tb.Label(frame, text="设定字幕位置：", font=LABEL_FONT)
        pos_label.grid(row=3, column=2, sticky=tk.W, pady=8, padx=(8,0))
        self.pos_entry = tb.Entry(frame, font=ENTRY_FONT, width=10)
        self.pos_entry.insert(0, "bottom")
        self.pos_entry.grid(row=3, column=3, sticky=tk.W, pady=8, padx=(2,2))

        # 新视频名称和整合字幕按钮同一行
        name2_label = tb.Label(frame, text="设定视频名称：", font=LABEL_FONT)
        name2_label.grid(row=4, column=0, sticky=tk.W, pady=8, padx=(8,0))
        self.name2_entry = tb.Entry(frame, font=ENTRY_FONT, width=50)
        self.name2_entry.grid(row=4, column=1, sticky=tk.W, pady=8, padx=(2,2))
        merge2_btn = tb.Button(frame, text="📽️ 整合总视频", bootstyle=SUCCESS, width=12, command=self.merge_video_with_srt)
        merge2_btn.grid(row=4, column=2, pady=8, padx=(8,0))

        # 新增：最下方横线
        sep = tb.Separator(frame, orient='horizontal')
        sep.grid(row=5, column=0, columnspan=4, sticky='ew', pady=16)

        # 新增：四个文件夹按钮（独立一行，四列横向对齐）
        btn_font = tb.Button(frame, text="字体文件夹", width=10, command=self.open_font_folder)
        btn_temp = tb.Button(frame, text="打开整合视频 temp缓存文件夹", width=18, command=self.open_temp_folder)
        btn_srt = tb.Button(frame, text="字幕文件夹", width=10, command=self.open_srt_folder)
        btn_speech = tb.Button(frame, text="音频文件夹", width=10, command=self.open_speech_folder)
        btn_font.grid(row=7, column=0, pady=8, padx=8, sticky='ew')
        btn_temp.grid(row=7, column=1, pady=8, padx=8, sticky='ew')
        btn_srt.grid(row=7, column=2, pady=8, padx=8, sticky='ew')
        btn_speech.grid(row=7, column=3, pady=8, padx=8, sticky='ew')

    def open_font_folder(self):
        import subprocess, os
        folder = os.path.join(os.getcwd(), 'font')
        if not os.path.exists(folder):
            os.makedirs(folder, exist_ok=True)
        subprocess.Popen(['open', folder])

    def open_temp_folder(self):
        import subprocess, os
        folder = os.path.join(os.getcwd(), 'temp')
        if not os.path.exists(folder):
            os.makedirs(folder, exist_ok=True)
        subprocess.Popen(['open', folder])

    def open_srt_folder(self):
        import subprocess, os
        folder = os.path.join(os.getcwd(), 'SRT')
        if not os.path.exists(folder):
            os.makedirs(folder, exist_ok=True)
        subprocess.Popen(['open', folder])

    def open_speech_folder(self):
        import subprocess, os
        folder = os.path.join(os.getcwd(), 'speech')
        if not os.path.exists(folder):
            os.makedirs(folder, exist_ok=True)
        subprocess.Popen(['open', folder])

    def select_video(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("MP4视频", "*.mp4"),
                ("MOV视频", "*.mov"),
                ("AVI视频", "*.avi"),
                ("所有视频", "*.*")
            ]
        )
        if path:
            self.video_entry.delete(0, tk.END)
            self.video_entry.insert(0, path)

    def select_srt2(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("SRT字幕", "*.srt"),
                ("所有文件", "*.*")
            ]
        )
        if path:
            self.srt2_entry.delete(0, tk.END)
            self.srt2_entry.insert(0, path)

    def generate_video_from_image(self):
        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)
        size = self.size_entry.get().strip()
        width, height = size.split('x')
        duration = int(self.dur_entry.get().strip())
        fps = 30
        batch_mode = self.batch_var.get()
        images = []
        if batch_mode and self.batch_entry.get():
            folder = self.batch_entry.get()
            for f in os.listdir(folder):
                if f.lower().endswith((".png", ".jpg", ".jpeg", ".bmp")):
                    images.append(os.path.join(folder, f))
        elif self.img_entry.get():
            images = [self.img_entry.get()]
        else:
            messagebox.showerror("错误", "请提供图片路径")
            print("[错误] 未提供图片路径")
            return
        for img_path in images:
            img_name = os.path.splitext(os.path.basename(img_path))[0]
            out_path = os.path.join(temp_dir, f"{img_name}.mp4")
            print(f"[图片转视频] 处理图片: {img_path}")
            # 生成2x2模糊背景
            bg_img = os.path.join(temp_dir, f"{img_name}-bg.jpg")
            cmd_bg = [
                "ffmpeg", "-y", "-loop", "1", "-framerate", str(fps), "-t", str(duration),
                "-i", img_path,
                "-vf", f"scale=2*{width}:2*{height},boxblur=20:1,crop={width}:{height}",
                "-q:v", "3", bg_img
            ]
            print(f"[图片转视频] 生成模糊背景: {' '.join(cmd_bg)}")
            subprocess.run(cmd_bg)
            # 合成前景+背景
            filter_complex = (
                f"[0:v]scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=rgba[fg];"
                f"[1:v]scale={width}:{height}[bg];"
                f"[bg][fg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=1,fade=t=out:st={duration-1}:d=1"
            )
            cmd = [
                "ffmpeg", "-y",
                "-loop", "1", "-framerate", str(fps), "-t", str(duration), "-i", img_path,
                "-i", bg_img,
                "-filter_complex", filter_complex,
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-r", str(fps),
                out_path
            ]
            print(f"[图片转视频] 合成视频命令: {' '.join(cmd)}")
            subprocess.run(cmd)
            print(f"[图片转视频] 生成视频片段: {out_path}")
        # messagebox.showinfo("完成", "图片转视频片段已生成")
        print("[图片转视频] 所有图片处理完成！")

    def merge_videos_with_audio(self):
        temp_dir = os.path.join(os.getcwd(), 'temp')
        video_dir = self.v_entry.get()
        audio_file = self.a_entry.get()
        cover_file = self.cover_entry.get()
        out_name = self.name_entry.get().strip() or "output"
        ts = datetime.now().strftime("%Y%m%d%H%M")
        out_path = os.path.join(temp_dir, f"{out_name}-{ts}.mp4")
        print(f"[合并视频] 视频片段文件夹: {video_dir}")
        print(f"[合并视频] 音频文件: {audio_file}")
        print(f"[合并视频] 封面文件: {cover_file}")
        if not os.path.isdir(video_dir) or not os.path.isfile(audio_file):
            messagebox.showerror("错误", "请正确选择视频片段文件夹和音频文件")
            print("[错误] 视频片段文件夹或音频文件无效")
            return
        # 合并视频片段（直接转码，保证参数统一）
        filelist = os.path.join(temp_dir, "filelist.txt")
        videos = [f for f in os.listdir(video_dir) if f.lower().endswith('.mp4')]
        videos.sort()
        with open(filelist, 'w') as f:
            for v in videos:
                f.write(f"file '{os.path.join(video_dir, v)}'\n")
        concat_path = os.path.join(temp_dir, f"concat_{ts}.mp4")
        cmd_concat = [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", filelist,
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k",
            concat_path
        ]
        print(f"[合并视频] 合并视频命令: {' '.join(cmd_concat)}")
        result_concat = subprocess.run(cmd_concat, capture_output=True, text=True)
        print(result_concat.stdout)
        print(result_concat.stderr)
        # 合成音视频（推荐转码，保证同步）
        cmd_merge = [
            "ffmpeg", "-y", "-i", concat_path, "-i", audio_file,
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k",
            "-map", "0:v:0", "-map", "1:a:0",
            "-shortest", out_path
        ]
        print(f"[合并视频] 合成音视频命令: {' '.join(cmd_merge)}")
        result_merge = subprocess.run(cmd_merge, capture_output=True, text=True)
        print(result_merge.stdout)
        print(result_merge.stderr)
        # 检查输出文件大小
        if not os.path.isfile(out_path) or os.path.getsize(out_path) < 1024:
            messagebox.showerror("错误", "合成失败，输出文件为空，请检查日志")
            print("[错误] 合成失败，输出文件为空")
            return
        # 添加封面（如果有）
        if cover_file and os.path.isfile(cover_file):
            # 若为png，先转为jpg
            cover_ext = os.path.splitext(cover_file)[1].lower()
            if cover_ext == ".png":
                cover_jpg = os.path.join(temp_dir, f"cover_{ts}.jpg")
                self.convert_png_to_jpg(cover_file, cover_jpg)
                cover_file_to_use = cover_jpg
            else:
                cover_file_to_use = cover_file
            out_with_cover = os.path.join(temp_dir, f"{out_name}-{ts}-cover.mp4")
            cmd_cover = [
                "ffmpeg", "-y", "-i", out_path, "-i", cover_file_to_use,
                "-map", "0", "-map", "1", "-c", "copy", "-disposition:v:1", "attached_pic", out_with_cover
            ]
            print(f"[合并视频] 添加封面命令: {' '.join(cmd_cover)}")
            result_cover = subprocess.run(cmd_cover, capture_output=True, text=True)
            print(result_cover.stdout)
            print(result_cover.stderr)
            if not os.path.isfile(out_with_cover) or os.path.getsize(out_with_cover) < 1024:
                messagebox.showerror("错误", "添加封面失败，输出文件为空，请检查日志")
                print("[错误] 添加封面失败，输出文件为空")
                return
            os.replace(out_with_cover, out_path)
        # messagebox.showinfo("完成", f"合成视频已保存到: {out_path}")
        print(f"[合并视频] 合成视频已保存到: {out_path}")
        # 自动填充到"整合视频字幕"tab的输入框
        self.video_entry.delete(0, tk.END)
        self.video_entry.insert(0, out_path)

    def convert_png_to_jpg(self, png_path, jpg_path):
        img = Image.open(png_path)
        rgb_img = img.convert('RGB')
        rgb_img.save(jpg_path, quality=95)

    def generate_txt_from_audio(self):
        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)
        audio_file = self.audio_entry.get()
        out_name = self.srt_entry.get().strip() or "audio_text"
        ts = datetime.now().strftime("%Y%m%d%H%M")
        out_path = os.path.join(srt_dir, f"{out_name}-{ts}.txt")
        api_key = os.environ.get("SiliconCloud_API_KEY")
        print(f"[语音转文本] 音频文件: {audio_file}")
        print(f"[语音转文本] 输出路径: {out_path}")
        if not api_key:
            messagebox.showerror("错误", "未检测到API KEY")
            print("[错误] 未检测到API KEY")
            return
        if not os.path.isfile(audio_file):
            messagebox.showerror("错误", "请选择音频文件")
            print("[错误] 音频文件无效")
            return
        url = "https://api.siliconflow.cn/v1/audio/transcriptions"
        headers = {"Authorization": f"Bearer {api_key}"}
        files = {"file": open(audio_file, "rb")}
        data = {"model": "FunAudioLLM/SenseVoiceSmall"}
        try:
            print(f"[语音转文本] 请求API: {url}")
            resp = requests.post(url, headers=headers, files=files, data=data)
            if resp.status_code == 200:
                try:
                    result = resp.json()
                    text = result.get("text", "").strip()
                except Exception as e:
                    messagebox.showerror("错误", f"API返回解析失败: {e}")
                    print(f"[错误] API返回解析失败: {e}")
                    return
                if not text:
                    messagebox.showerror("错误", "API未返回有效文本")
                    print("[错误] API未返回有效文本")
                    return
                with open(out_path, 'w', encoding='utf-8') as f:
                    f.write(text)
                # messagebox.showinfo("完成", f"文本文件已保存到: {out_path}")
                print(f"[语音转文本] 文本文件已保存到: {out_path}")
            else:
                messagebox.showerror("错误", f"API请求失败: {resp.text}")
                print(f"[错误] API请求失败: {resp.text}")
        except Exception as e:
            messagebox.showerror("错误", str(e))
            print(f"[错误] {e}")

    def adjust_srt_file(self):
        srt_dir = os.path.join(os.getcwd(), 'SRT')
        srt_file = self.srtfile_entry.get()
        lines = self.text_box.get("1.0", tk.END).strip().splitlines()
        print(f"[调整字幕] 原SRT文件: {srt_file}")
        if not os.path.isfile(srt_file):
            messagebox.showerror("错误", "请选择SRT字幕文件")
            print("[错误] SRT字幕文件无效")
            return
        if len(lines) == 0:
            messagebox.showerror("错误", "请输入字幕内容")
            print("[错误] 未输入字幕内容")
            return
        base = os.path.splitext(os.path.basename(srt_file))[0]
        out_path = os.path.join(srt_dir, f"{base}-1.srt")
        with open(srt_file, 'r', encoding='utf-8') as f:
            srt_content = f.read()
        times = re.findall(r'(\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3})', srt_content)
        n = min(len(lines), len(times))
        with open(out_path, 'w', encoding='utf-8') as f:
            for i in range(n):
                f.write(f"{i+1}\n{times[i]}\n{lines[i]}\n\n")
        # messagebox.showinfo("完成", f"新字幕文件已保存到: {out_path}")
        print(f"[调整字幕] 新字幕文件已保存到: {out_path}")

    def merge_video_with_srt(self):
        temp_dir = os.path.join(os.getcwd(), 'temp')
        video_file = self.video_entry.get()
        srt_file = self.srt2_entry.get()
        font_file = self.font_entry.get()
        font_size = self.size2_entry.get()
        bg_color = self.color_entry.get()
        pos = self.pos_entry.get()
        out_name = self.name2_entry.get().strip() or "output"
        ts = datetime.now().strftime("%Y%m%d%H%M")
        out_path = os.path.join(temp_dir, f"{out_name}-{ts}.mp4")
        print(f"[整合字幕] 视频文件: {video_file}")
        print(f"[整合字幕] 字幕文件: {srt_file}")
        print(f"[整合字幕] 字体: {font_file}, 字号: {font_size}, 背景色: {bg_color}, 位置: {pos}")
        if not (os.path.isfile(video_file) and os.path.isfile(srt_file) and os.path.isfile(font_file)):
            messagebox.showerror("错误", "请正确选择视频、字幕和字体文件")
            print("[错误] 视频、字幕或字体文件无效")
            return

        # 位置映射
        pos_map = {"bottom": "2", "top": "8"}
        alignment = pos_map.get(pos, "2")  # 默认底部居中

        # 颜色格式转换（ASS格式：&HBBGGRR&，如&H000080&，注意顺序）
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
        fontname = os.path.splitext(os.path.basename(font_file))[0]

        # 构造force_style
        force_style = f"FontName={fontname},FontSize={font_size},OutlineColour={ass_color},Alignment={alignment}"

        cmd = [
            "ffmpeg", "-y", "-i", video_file, "-vf",
            f"subtitles='{srt_file}':force_style='{force_style}'",
            "-c:a", "copy", out_path
        ]
        print(f"[整合字幕] 合成命令: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        print(result.stdout)
        print(result.stderr)
        if not os.path.isfile(out_path) or os.path.getsize(out_path) < 1024:
            messagebox.showerror("错误", "整合字幕失败，输出文件为空，请检查日志")
            print("[错误] 整合字幕失败，输出文件为空")
            return
        # messagebox.showinfo("完成", f"带字幕视频已保存到: {out_path}")
        print(f"[整合字幕] 带字幕视频已保存到: {out_path}")

    def generate_srt_with_whisper(self):
        srt_dir = os.path.join(os.getcwd(), 'SRT')
        os.makedirs(srt_dir, exist_ok=True)
        audio_file = self.audio_entry.get()
        out_name = self.local_srt_entry.get().strip() or "subtitle"
        ml_value = self.ml_entry.get().strip() or "30"
        ts = datetime.now().strftime("%Y%m%d%H%M")
        srt_path = os.path.join(srt_dir, f"{out_name}-{ts}.srt")
        # 检查音频格式，若不是wav，转为wav
        if not os.path.isfile(audio_file):
            messagebox.showerror("错误", "请选择音频文件")
            print("[错误] 音频文件无效")
            return
        ext = os.path.splitext(audio_file)[1].lower()
        wav_path = audio_file
        if ext != ".wav":
            wav_path = os.path.join(srt_dir, f"{out_name}-{ts}.wav")
            cmd_ffmpeg = [
                "ffmpeg", "-y", "-i", audio_file, wav_path
            ]
            print(f"[whisper.cpp] 转码命令: {' '.join(cmd_ffmpeg)}")
            result = subprocess.run(cmd_ffmpeg, capture_output=True, text=True)
            print(result.stdout)
            print(result.stderr)
            if not os.path.isfile(wav_path):
                messagebox.showerror("错误", "音频转码为wav失败")
                print("[错误] 音频转码为wav失败")
                return
        # whisper.cpp命令
        whisper_bin = "/Users/yons/AI/whisper.cpp/build/bin/whisper-cli"
        whisper_model = "/Users/yons/AI/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin"
        of_path = os.path.splitext(srt_path)[0]  # 不带扩展名
        # 设置线程数（根据 CPU 核心数调整）
        threads = os.cpu_count() or 4  # 使用系统 CPU 核心数，或默认 4

        cmd_whisper = [
            whisper_bin,
            "-m", whisper_model,
            "-f", wav_path,
            "-l", "zh",  # 明确指定中文
            "-ml", str(ml_value),
            "-osrt",
            "-of", of_path,
            "-t", str(threads),          # 设置线程数（根据 CPU 核心数调整）
            # "--no-translate",  # 额外保险参数（部分版本适用）
        ]
        print(f"[whisper.cpp] 命令: {' '.join(cmd_whisper)}")
        # 在conda环境下执行
        conda_prefix = os.environ.get("CONDA_PREFIX", "")
        activate_cmd = f"conda activate modelscope && {' '.join(cmd_whisper)}"
        shell_cmd = f"source ~/.zshrc && {activate_cmd}" if shutil.which("zsh") else f"source ~/.bashrc && {activate_cmd}"
        try:
            result = subprocess.run(shell_cmd, shell=True, capture_output=True, text=True, executable="/bin/zsh")
            # 检测输出的编码
            stdout = result.stdout.decode(encoding)
            stderr = result.stderr.decode(encoding)

            print(result.stdout)
            print(result.stderr)
            if os.path.isfile(srt_path):
                # messagebox.showerror("错误", "字幕文件生成失败，请检查日志")
                print(f"[生成字幕] 字幕文件已保存到: {srt_path}")
            else:
                # messagebox.showerror("错误", "生成字幕失败，请检查日志")
                print("[错误] 生成字幕失败，输出文件未找到")
        except Exception as e:
            messagebox.showerror("错误", str(e))
            print(f"[错误] {e}")

    def select_vc_video(self):
        path = filedialog.askopenfilename(
            filetypes=[
                ("MP4视频", "*.mp4"),
                ("MOV视频", "*.mov"),
                ("AVI视频", "*.avi"),
                ("所有视频", "*.*")
            ]
        )
        if path:
            self.vc_video_entry.delete(0, tk.END)
            self.vc_video_entry.insert(0, path)

    def convert_to_mute_video(self):
        import glob
        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d%H%M")
        if self.vc_batch_var.get() and self.vc_batch_entry.get():
            folder = self.vc_batch_entry.get()
            for f in os.listdir(folder):
                if f.lower().endswith(('.mp4', '.mov', '.avi')):
                    video_file = os.path.join(folder, f)
                    base = os.path.splitext(os.path.basename(f))[0]
                    out_path = os.path.join(temp_dir, f"{base}-mute-{ts}.mp4")
                    cmd = [
                        "ffmpeg", "-y", "-i", video_file, "-an", out_path
                    ]
                    print(f"[批量无声视频] {f}: {' '.join(cmd)}")
                    result = subprocess.run(cmd, capture_output=True, text=True)
                    print(result.stdout)
                    print(result.stderr)
            print(f"[批量无声视频] 批量处理完成，输出目录: {temp_dir}")
        else:
            video_file = self.vc_video_entry.get()
            mute_name = self.mute_entry.get().strip() or "mute_video"
            out_path = os.path.join(temp_dir, f"{mute_name}-{ts}.mp4")
            if not os.path.isfile(video_file):
                messagebox.showerror("错误", "请选择视频文件")
                print("[错误] 视频文件无效")
                return
            cmd = [
                "ffmpeg", "-y", "-i", video_file, "-an", out_path
            ]
            print(f"[视频转换] 无声视频命令: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            print(result.stdout)
            print(result.stderr)
            print(f"[视频转换] 无声视频已保存到: {out_path}")

    def convert_to_audio_file(self):
        import glob
        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d%H%M")
        if self.vc_batch_var.get() and self.vc_batch_entry.get():
            folder = self.vc_batch_entry.get()
            for f in os.listdir(folder):
                if f.lower().endswith(('.mp4', '.mov', '.avi')):
                    video_file = os.path.join(folder, f)
                    base = os.path.splitext(os.path.basename(f))[0]
                    out_path = os.path.join(temp_dir, f"{base}-audio-{ts}.wav")
                    cmd = [
                        "ffmpeg", "-y", "-i", video_file, "-vn", "-acodec", "pcm_s16le", out_path
                    ]
                    print(f"[批量音频提取] {f}: {' '.join(cmd)}")
                    result = subprocess.run(cmd, capture_output=True, text=True)
                    print(result.stdout)
                    print(result.stderr)
            print(f"[批量音频提取] 批量处理完成，输出目录: {temp_dir}")
        else:
            video_file = self.vc_video_entry.get()
            audio_name = self.audio_out_entry.get().strip() or "audio"
            out_path = os.path.join(temp_dir, f"{audio_name}-{ts}.wav")
            if not os.path.isfile(video_file):
                messagebox.showerror("错误", "请选择视频文件")
                print("[错误] 视频文件无效")
                return
            cmd = [
                "ffmpeg", "-y", "-i", video_file, "-vn", "-acodec", "pcm_s16le", out_path
            ]
            print(f"[视频转换] 音频提取命令: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            print(result.stdout)
            print(result.stderr)
            print(f"[视频转换] 音频文件已保存到: {out_path}")
            # 自动填充到生成字幕文件tab的音频输入框
            try:
                self.audio_entry.delete(0, tk.END)
                self.audio_entry.insert(0, out_path)
            except Exception as e:
                print(f"[警告] 自动填充音频输入框失败: {e}")

    def split_video_by_count(self):
        video_file = self.vc_video_entry.get()
        seg_name = self.seg_entry.get().strip() or "segment"
        count = self.count_entry.get().strip()
        temp_dir = os.path.join(os.getcwd(), 'temp')
        ts = datetime.now().strftime("%Y%m%d%H%M")
        seg_dir = os.path.join(temp_dir, f"{seg_name}-{ts}")
        os.makedirs(seg_dir, exist_ok=True)
        if not os.path.isfile(video_file):
            messagebox.showerror("错误", "请选择视频文件")
            print("[错误] 视频文件无效")
            return
        try:
            count = int(count)
            if count < 1:
                raise ValueError
        except Exception:
            messagebox.showerror("错误", "分割数量需为正整数")
            print("[错误] 分割数量无效")
            return
        # 获取视频总时长
        cmd_probe = [
            "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", video_file
        ]
        result = subprocess.run(cmd_probe, capture_output=True, text=True)
        try:
            duration = float(result.stdout.strip())
        except Exception:
            messagebox.showerror("错误", "无法获取视频时长")
            print("[错误] 无法获取视频时长")
            return
        seg_len = duration / count
        for i in range(count):
            start = i * seg_len
            out_path = os.path.join(seg_dir, f"{seg_name}_{i+1}.mp4")
            cmd = [
                "ffmpeg", "-y", "-i", video_file, "-ss", str(start), "-t", str(seg_len),
                "-c:v", "libx264", "-c:a", "copy", out_path
            ]
            print(f"[视频分割] 片段{i+1}命令: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            print(result.stdout)
            print(result.stderr)
        print(f"[视频分割] 所有片段已保存到: {seg_dir}")

    def get_video_duration(self, path):
        import subprocess
        cmd = [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", path
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        try:
            return float(result.stdout.strip())
        except Exception:
            return None

    def merge_all_videos_with_filters(self):
        import glob
        import shutil
        video_dir = self.v_entry.get()
        audio_file = self.a_entry.get()
        out_name = self.name_entry.get().strip() or "output"
        ts = datetime.now().strftime("%Y%m%d%H%M")
        temp_dir = os.path.join(os.getcwd(), 'temp')
        os.makedirs(temp_dir, exist_ok=True)
        filtered_list = []
        zoom_enabled = self.zoom_var.get()
        try:
            zoom_end = float(self.zoom_to_entry.get().strip() or "1.2")
        except Exception:
            messagebox.showerror("错误", "缩放结束值必须为数字！")
            return
        filter_type = self.filter_var.get()
        videos = [f for f in os.listdir(video_dir) if f.lower().endswith('.mp4')]
        videos.sort()
        if not videos:
            messagebox.showerror("错误", "片段文件夹内没有mp4视频文件！")
            print("[错误] 片段文件夹内没有mp4视频文件！")
            return
        for idx, v in enumerate(videos):
            in_path = os.path.join(video_dir, v)
            filtered_path = os.path.join(temp_dir, f"filtered_{idx+1}.mp4")
            if zoom_enabled and filter_type in ["scale+zoom", "scale+zoompan"]:
                # 先获取视频时长
                duration = self.get_video_duration(in_path)
                if not duration or duration <= 0:
                    messagebox.showerror("错误", f"无法获取视频时长: {in_path}")
                    return
                zoom_ratio = zoom_end - 1
                # 构造ffmpeg表达式，避免duration变量未定义
                vf_str = f"scale=iw*(1+{zoom_ratio}*t/{duration}):ih*(1+{zoom_ratio}*t/{duration}),crop=iw:ih"
                cmd = [
                    "ffmpeg", "-y", "-i", in_path, "-vf", vf_str,
                    "-c:v", "libx264", "-c:a", "aac", filtered_path
                ]
                print(f"[滤镜处理-ffmpeg动画] {v}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, text=True)
                print(result.stdout)
                print(result.stderr)
                if not os.path.isfile(filtered_path):
                    messagebox.showerror("错误", f"滤镜处理失败: {filtered_path} 未生成，请检查ffmpeg输出！")
                    print(f"[错误] {filtered_path} 未生成，命令输出：\n{result.stderr}")
                    return
            else:
                vf_str = "scale=iw:ih"
                cmd = [
                    "ffmpeg", "-y", "-i", in_path, "-vf", vf_str,
                    "-c:v", "libx264", "-c:a", "copy", filtered_path
                ]
                print(f"[滤镜处理] {v}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, text=True)
                print(result.stdout)
                print(result.stderr)
                if not os.path.isfile(filtered_path):
                    messagebox.showerror("错误", f"滤镜处理失败: {filtered_path} 未生成，请检查ffmpeg输出！")
                    print(f"[错误] {filtered_path} 未生成，命令输出：\n{result.stderr}")
                    return
            filtered_list.append(filtered_path)
        if not filtered_list:
            messagebox.showerror("错误", "没有生成任何滤镜视频片段，请检查片段文件夹和ffmpeg命令！")
            print("[错误] 没有生成任何滤镜视频片段")
            return
        # 生成filelist.txt
        filelist_path = os.path.join(temp_dir, "filelist.txt")
        with open(filelist_path, "w") as f:
            for fp in filtered_list:
                f.write(f"file '{fp}'\n")
        merged_path = os.path.join(temp_dir, f"{out_name}-{ts}-merged.mp4")
        cmd_concat = [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", filelist_path,
            "-c", "copy", merged_path
        ]
        print(f"[合并片段] {' '.join(cmd_concat)}")
        result_concat = subprocess.run(cmd_concat, capture_output=True, text=True)
        print(result_concat.stdout)
        print(result_concat.stderr)
        if not os.path.isfile(merged_path):
            messagebox.showerror("错误", f"合并片段失败: {merged_path} 未生成，请检查ffmpeg输出！")
            print(f"[错误] {merged_path} 未生成，命令输出：\n{result_concat.stderr}")
            return
        # 合成音视频
        final_path = os.path.join(temp_dir, f"{out_name}-{ts}-final.mp4")
        cmd_merge = [
            "ffmpeg", "-y", "-i", merged_path, "-i", audio_file,
            "-c:v", "copy", "-c:a", "aac", "-shortest", final_path
        ]
        print(f"[合成音视频] {' '.join(cmd_merge)}")
        result_merge = subprocess.run(cmd_merge, capture_output=True, text=True)
        print(result_merge.stdout)
        print(result_merge.stderr)
        if not os.path.isfile(final_path):
            messagebox.showerror("错误", f"合成音视频失败: {final_path} 未生成，请检查ffmpeg输出！")
            print(f"[错误] {final_path} 未生成，命令输出：\n{result_merge.stderr}")
            return
        print(f"[完成] 合成视频已保存到: {final_path}")
        # 可自动填充到下游tab

if __name__ == "__main__":
    app = MultimediaEditor()
    app.mainloop() 
