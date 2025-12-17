import json
import time
import tkinter as tk
import os
from tkinter import ttk, messagebox
import ttkbootstrap as ttk
from ttkbootstrap.constants import *
from PIL import Image, ImageTk
import requests
import urllib3
from io import BytesIO
import pyperclip
from pathlib import Path
from datetime import datetime
import platform
import subprocess

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
# 未验证 HTTPS 请求的警告都会被屏蔽，不再输出到控制台。
python_path = "/Users/hao/miniconda3/envs/modelscope/bin/python"
script_dir = os.path.dirname(os.path.abspath(__file__))

class ModelLauncher:
    def __init__(self, root):
        self.root = root
        self.root.title("BOZO AI启动器 1.1.0")
        self.root.geometry("1040x540")
        self.style = ttk.Style(theme="solar")
        
        # 声音功能默认设置
        self.default_voice_model = "FunAudioLLM/CosyVoice2-0.5B"
        self.voice_frame_width = 1000
        self.text_input_width = 85
        
        # 加载模型数据
        with open('models.json', 'r', encoding='utf-8') as f:
            self.model_data = json.load(f)
        
        # 创建主框架
        self.main_frame = ttk.Frame(root, padding=10)
        self.main_frame.pack(fill=tk.BOTH, expand=True)
        
        # 创建首页按钮和类别按钮栏
        self.create_home_button()
        self.create_category_buttons()
        
        # 创建模型显示区域
        self.create_model_display()
        
        # 默认显示首页
        self.show_home()
        
        self.set_custom_button_style()
    
    def set_custom_button_style(self):
        style = ttk.Style()
        style.configure(
            "My.TButton",
            font=("Helvetica", 16, "bold"),
            foreground="#ffffff",
            background="#3aafa9",
            borderwidth=1,
            focusthickness=3,
            focuscolor="none"
        )
        style.map(
            "My.TButton",
            background=[("active", "#2b8c7a"), ("!active", "#3aafa9")],
            foreground=[("active", "#ffffff"), ("!active", "#ffffff")]
        )
    
    def create_home_button(self):
        """创建首页按钮"""
        self.button_frame = ttk.Frame(self.main_frame)
        self.button_frame.pack(fill=tk.X, pady=(0, 10))
        
        self.home_button = ttk.Button(
            self.button_frame,
            text="首页",
            command=self.show_home,
            bootstyle=SUCCESS
        )
        self.home_button.pack(side=tk.LEFT, padx=5)
        
        self.voice_button = ttk.Button(
            self.button_frame,
            text="声音",
            command=self.show_voice,
            bootstyle=INFO
        )
        self.voice_button.pack(side=tk.LEFT, padx=5)
    
    def create_category_buttons(self):
        """创建类别选择按钮"""
        self.category_buttons = []
        for category in self.model_data.keys():
            btn = ttk.Button(
                self.button_frame, 
                text=category, 
                command=lambda c=category: self.show_category(c),
                bootstyle=PRIMARY
            )
            btn.pack(side=tk.LEFT, padx=5)
            self.category_buttons.append(btn)
    
    def show_home(self):
        """显示首页内容"""
        # 清除当前显示
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()
        
        # 更新按钮状态
        self.home_button.configure(bootstyle=SUCCESS)
        self.voice_button.configure(bootstyle=PRIMARY)
        for btn in self.category_buttons:
            btn.configure(bootstyle=PRIMARY)
        
        # 显示首页内容
        title = ttk.Label(
            self.scrollable_frame,
            text="AIGC操作管理平台",
            font=('Helvetica', 22, 'bold'),
            anchor="center"
        )
        title.pack(fill=tk.X, pady=20)
        
        # 添加图片高清放大功能
        enhancement_frame = ttk.Frame(self.scrollable_frame)
        enhancement_frame.pack(pady=10, fill=tk.X)
        
        ttk.Label(enhancement_frame, text="GPEN人像修复", font=('Helvetica', 14)).pack(side=tk.LEFT, padx=10)
        
        self.file_entry = ttk.Entry(enhancement_frame, width=85)
        self.file_entry.pack(side=tk.LEFT, padx=10)
        
        enhance_btn = ttk.Button(
            enhancement_frame,
            text="修复",
            command=self.enhance_image,
            bootstyle=INFO
        )
        enhance_btn.pack(side=tk.LEFT, padx=10)
        
        # 按钮区域
        button_frame = ttk.Frame(self.scrollable_frame)
        button_frame.pack(pady=20, fill=tk.X)
        
        btn_width = 17
        btn_height = 2
        
        buttons = [
            ("打开MS文件夹", self.open_ms_folder),
            ("MCN多媒体管理器", self.run_mcn),
            ("AI故事绘本生成器", self.run_story),
            ("Modelsope-AI绘画", self.run_ai_pic),
            ("公众号文章与配图", self.run_weixin_mp),
            ("Models模型展示", self.run_models_html),
            ("ROOP换脸", self.run_roop),
            ("XHS小红书", self.run_xhs),
            ("查询SSH密钥", self.show_ssh_key),
            ("查询本地IP", self.show_local_ip),
            ("打开千问3", self.run_qwen3),
            ("MPP短视频剪辑", self.run_mpp_video),
            ("网页截图工具", self.run_screenshot_app),
            ("KindEditor文件管理器", self.run_file_manager),
            ("文件批量改名", self.run_rename_files),
            ("文件批量移动", self.run_move_files),
            ("HTML图片提取", self.run_image_gui),
            ("HTML链接提取器", self.run_html_link_gui),
            ("MD文档内容采集器", self.run_html_to_markdown_gui),
            ("卡卡字幕助手", self.run_VideoCaptioner),
        ]
        
        for idx, (text, cmd) in enumerate(buttons):
            row, col = divmod(idx, 5)
            btn = ttk.Button(
                button_frame,
                text=text,
                command=cmd,
                width=btn_width,
                style="My.TButton"
            )
            btn.grid(row=row, column=col, padx=12, pady=12, sticky="nsew")
    
    def create_model_display(self):
        """创建模型显示区域"""
        self.canvas = tk.Canvas(self.main_frame)
        self.scrollbar = ttk.Scrollbar(
            self.main_frame, 
            orient=tk.VERTICAL, 
            command=self.canvas.yview
        )
        self.scrollable_frame = ttk.Frame(self.canvas)
        
        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(
                scrollregion=self.canvas.bbox("all")
            )
        )
        
        self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        
        # 绑定鼠标滚轮事件
        self.canvas.bind_all("<MouseWheel>", lambda e: self.canvas.yview_scroll(int(-1*(e.delta)), "units"))
        self.canvas.bind_all("<Button-4>", lambda e: self.canvas.yview_scroll(-1, "units"))
        self.canvas.bind_all("<Button-5>", lambda e: self.canvas.yview_scroll(1, "units"))
        
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # 图片缓存字典
        self.image_cache = {}
    
    def show_category(self, category):
        """显示指定类别的模型"""
        # 清除当前显示
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()
        
        # 更新按钮状态
        for btn in self.category_buttons:
            btn.configure(bootstyle=PRIMARY)
        current_btn = self.category_buttons[list(self.model_data.keys()).index(category)]
        current_btn.configure(bootstyle=SUCCESS)
        
        # 显示新类别的模型
        models = self.model_data[category]
        
        # 创建网格布局
        row, col = 0, 0
        max_cols = 6
        
        for model in models:
            frame = ttk.Frame(self.scrollable_frame, padding=5)
            frame.grid(row=row, column=col, padx=5, pady=5)
            
            # 加载图片
            try:
                # 检查缓存
                if model["Purl"] in self.image_cache:
                    photo = self.image_cache[model["Purl"]]
                else:
                    # 异步加载图片
                    def load_image(url):
                        response = requests.get(url, verify=False)
                        img = Image.open(BytesIO(response.content))
                        img = img.resize((140, 185), Image.LANCZOS)
                        photo = ImageTk.PhotoImage(img)
                        self.image_cache[url] = photo
                        return photo
                    
                    # 先显示占位图
                    placeholder = Image.new('RGB', (140, 185), (240, 240, 240))
                    photo = ImageTk.PhotoImage(placeholder)
                    
                    # 启动线程加载图片
                    import threading
                    threading.Thread(target=lambda: load_image(model["Purl"]), daemon=True).start()
                
                label = ttk.Label(frame, image=photo)
                label.image = photo  # 保持引用
                label.pack()
                
                # 绑定点击事件
                label.bind("<Button-1>", lambda e, m=model: self.copy_model_name(m))
                
                # 显示模型信息
                ttk.Label(frame, text=model["Name"], font=('Helvetica', 14, 'bold'), wraplength=140).pack()
                ttk.Label(frame, text=model["Model"], font=('Helvetica', 12), wraplength=140).pack()
                
            except Exception as e:
                print(f"加载图片失败: {e}")
                ttk.Label(frame, text="图片加载失败").pack()
                ttk.Label(frame, text=model["Name"]).pack()
                ttk.Label(frame, text=model["Model"]).pack()
            
            col += 1
            if col >= max_cols:
                col = 0
                row += 1
    
    def enhance_image(self):
        """执行图片增强修复"""
        file_path = self.file_entry.get()
        if not file_path:
            return
            
        # 添加进度条
        self.progress = ttk.Progressbar(
            self.scrollable_frame,
            orient=tk.HORIZONTAL,
            length=300,
            mode='determinate'
        )
        self.progress.pack(pady=10)
        self.progress_label = ttk.Label(self.scrollable_frame, text="准备开始处理...")
        self.progress_label.pack()
        
        try:
            from modelscope.pipelines import pipeline
            from modelscope.utils.constant import Tasks
            from modelscope.outputs import OutputKeys
            import cv2
            
            # 更新进度
            self.progress['value'] = 10
            self.progress_label.config(text="正在加载模型...")
            print(f"[{time.strftime('%H:%M:%S')}] 开始处理图片: {file_path}")
            
            portrait_enhancement = pipeline(
                Tasks.image_portrait_enhancement, 
                model='iic/cv_gpen_image-portrait-enhancement-hires'
            )
            
            self.progress['value'] = 40
            self.progress_label.config(text="正在处理图片...")
            print(f"[{time.strftime('%H:%M:%S')}] 模型加载完成，开始处理图片")
            
            result = portrait_enhancement(file_path)
            
            self.progress['value'] = 80
            self.progress_label.config(text="正在保存结果...")
            print(f"[{time.strftime('%H:%M:%S')}] 图片处理完成，正在保存")
            
            timestamp = time.strftime("%Y%m%d-%H%M%S")
            os.makedirs('repaired', exist_ok=True)
            output_path = os.path.join('repaired', f'{timestamp}.png')
            cv2.imwrite(output_path, result[OutputKeys.OUTPUT_IMG])
            
            self.progress['value'] = 100
            self.progress_label.config(text="处理完成!")
            print(f"[{time.strftime('%H:%M:%S')}] 图片已增强并保存到: {output_path}")
            # messagebox.showinfo("完成", f"图片已增强并保存到: {output_path}")
        except Exception as e:
            self.progress_label.config(text=f"处理失败: {str(e)}")
            print(f"[{time.strftime('%H:%M:%S')}] 增强失败: {str(e)}")
            messagebox.showerror("错误", f"增强失败: {str(e)}")
        finally:
            # 5秒后自动移除进度条
            self.root.after(5000, lambda: [self.progress.pack_forget(), self.progress_label.pack_forget()])
    
    def copy_model_name(self, model):
        """复制模型名称到剪贴板"""
        model_text = model["Model"]
        pyperclip.copy(model_text)
        print(f"已复制: {model_text}")
        
    def show_voice(self):
        """显示声音功能界面"""
        # 清除当前显示
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()
            
        # 更新按钮状态
        self.home_button.configure(bootstyle=PRIMARY)
        self.voice_button.configure(bootstyle=SUCCESS)
        for btn in self.category_buttons:
            btn.configure(bootstyle=PRIMARY)
            
        # 创建选项卡
        self.voice_notebook = ttk.Notebook(self.scrollable_frame)
        self.voice_notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # 先创建"使用用户预置音色"和"使用系统音色"
        self.create_user_voice_tab()
        self.create_system_voice_tab()
        # 再创建其它
        self.create_base64_upload_tab()
        self.create_file_upload_tab()
        self.create_voice_list_tab()
        self.create_delete_voice_tab()
        # 新增：创建声音管理平台选项卡（放最后）
        self.create_voice_manage_tab()
        
    def create_base64_upload_tab(self):
        """创建base64上传音色选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" Base64上传 ")
        
        # 添加组件
        ttk.Label(tab, text="模型名称:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.base64_model_var = tk.StringVar()
        self.base64_model_var.set("FunAudioLLM/CosyVoice2-0.5B")
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.base64_model_combo = ttk.Combobox(tab, textvariable=self.base64_model_var, values=model_options, width=93, state="readonly")
        self.base64_model_combo.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)
        
        ttk.Label(tab, text="音色名称:").grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        self.base64_name_entry = ttk.Entry(tab, width=95)
        self.base64_name_entry.grid(row=1, column=1, padx=5, pady=5)
        
        ttk.Label(tab, text="Base64音频:").grid(row=2, column=0, padx=5, pady=5, sticky=tk.W)
        self.base64_text = tk.Text(tab, height=14, width=95)
        self.base64_text.grid(row=2, column=1, padx=5, pady=5)
        
        ttk.Label(tab, text="参考文本:").grid(row=3, column=0, padx=5, pady=5, sticky=tk.W)
        self.base64_ref_entry = ttk.Entry(tab, width=95)
        self.base64_ref_entry.grid(row=3, column=1, padx=5, pady=5)
        
        upload_btn = ttk.Button(tab, text="上传", command=self.upload_base64_voice)
        upload_btn.grid(row=4, column=1, padx=5, pady=10, sticky=tk.E)
        
    def create_file_upload_tab(self):
        """创建文件上传音色选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" 音频文件上传 ")
        
        ttk.Label(tab, text="模型名称:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.file_model_var = tk.StringVar()
        self.file_model_var.set("FunAudioLLM/CosyVoice2-0.5B")
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.file_model_combo = ttk.Combobox(tab, textvariable=self.file_model_var, values=model_options, width=88, state="readonly")
        self.file_model_combo.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)

        ttk.Label(tab, text="音色名称:").grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        self.file_name_entry = ttk.Entry(tab, width=90)
        self.file_name_entry.grid(row=1, column=1, padx=5, pady=5, sticky=tk.W)

        ttk.Label(tab, text="音频文件:").grid(row=2, column=0, padx=5, pady=5, sticky=tk.W)
        self.file_path_entry = ttk.Entry(tab, width=90)
        self.file_path_entry.grid(row=2, column=1, padx=5, pady=5, sticky=tk.W)
        browse_btn = ttk.Button(tab, text="浏览", command=self.browse_file)
        browse_btn.grid(row=2, column=2, padx=5, pady=5, sticky=tk.W)

        ttk.Label(tab, text="参考文本:").grid(row=3, column=0, padx=5, pady=5, sticky=tk.NW)
        self.file_ref_text = tk.Text(tab, height=14, width=90)
        self.file_ref_text.grid(row=3, column=1, padx=5, pady=5, sticky=tk.W)

        upload_btn = ttk.Button(tab, text="上传", command=self.upload_file_voice)
        upload_btn.grid(row=4, column=1, padx=5, pady=10, sticky=tk.E)
        
    def create_voice_list_tab(self):
        """创建音色列表选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" 云端音色列表 ")
        
        # 添加组件
        self.voice_list = ttk.Treeview(tab, columns=("name", "model", "uri"), show="headings", height=20)
        self.voice_list.heading("name", text="音色名称")
        self.voice_list.heading("model", text="模型")
        self.voice_list.heading("uri", text="URI")
        self.voice_list.column("name", width=125)
        self.voice_list.column("model", width=225)
        self.voice_list.column("uri", width=610)
        self.voice_list.grid(row=0, column=0, padx=5, pady=5, sticky=tk.NSEW)
        
        scrollbar = ttk.Scrollbar(tab, orient=tk.VERTICAL, command=self.voice_list.yview)
        scrollbar.grid(row=0, column=1, sticky=tk.NS)
        self.voice_list.configure(yscrollcommand=scrollbar.set)
        
        refresh_btn = ttk.Button(tab, text="刷新列表", command=self.refresh_voice_list)
        refresh_btn.grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        
        self.voice_list.bind("<ButtonRelease-1>", self.copy_uri_on_click)
        
    def create_delete_voice_tab(self):
        """创建删除音色选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" 删除云端音色 ")
        
        # 添加组件
        ttk.Label(tab, text="音色URI:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.delete_uri_entry = ttk.Entry(tab, width=95)
        self.delete_uri_entry.grid(row=0, column=1, padx=5, pady=5)
        
        delete_btn = ttk.Button(tab, text="删除", command=self.delete_voice)
        delete_btn.grid(row=1, column=1, padx=5, pady=10, sticky=tk.E)
        
    def create_user_voice_tab(self):
        """创建用户预置音色选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" 用户预置音色 ")
        
        ttk.Label(tab, text="模型名称:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.user_model_var = tk.StringVar()
        self.user_model_var.set("FunAudioLLM/CosyVoice2-0.5B")
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.user_model_combo = ttk.Combobox(tab, textvariable=self.user_model_var, values=model_options, width=93, state="readonly")
        self.user_model_combo.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)

        ttk.Label(tab, text="音色URI:").grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        self.user_uri_entry = ttk.Entry(tab, width=95)
        self.user_uri_entry.insert(0, "speech:yanbo20250514:cm1e5qhny00yiyfv6osmivkla:ddjyyseediqvrxmejysh")
        self.user_uri_entry.grid(row=1, column=1, padx=5, pady=5, sticky=tk.W)

        ttk.Label(tab, text="输入文本:").grid(row=2, column=0, padx=5, pady=5, sticky=tk.NW)
        self.user_text_text = tk.Text(tab, height= 16, width=95)
        self.user_text_text.grid(row=2, column=1, padx=5, pady=5, sticky=tk.W)

        # 输出格式和生成按钮在一行
        self.user_format_var = tk.StringVar(value="mp3")
        format_menu = ttk.OptionMenu(tab, self.user_format_var, "mp3", "wav", "opus", "pcm")
        format_menu.grid(row=3, column=1, padx=(0, 120), pady=10, sticky=tk.W)

        generate_btn = ttk.Button(tab, text="生成语音", command=self.generate_user_voice, width=16, bootstyle=SUCCESS)
        generate_btn.grid(row=3, column=1, padx=(180, 0), pady=10, sticky=tk.W)
        
    def create_system_voice_tab(self):
        """创建使用系统音色选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" 使用系统音色 ")
        
        # 添加组件
        ttk.Label(tab, text="模型名称:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.system_model_var = tk.StringVar()
        self.system_model_var.set("FunAudioLLM/CosyVoice2-0.5B")
        model_options = ["FunAudioLLM/CosyVoice2-0.5B", "IndexTeam/IndexTTS-2", "fnlp/MOSS-TTSD-v0.5"]
        self.system_model_combo = ttk.Combobox(tab, textvariable=self.system_model_var, values=model_options, width=78, state="readonly")
        self.system_model_combo.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)

        # 音色下拉菜单紧跟模型名称
        voice_options = [
            ("沉稳男声", "alex"),
            ("低沉男声", "benjamin"),
            ("磁性男声", "charles"),
            ("欢快男声", "david"),
            ("沉稳女声", "anna"),
            ("激情女声", "bella"),
            ("温柔女声", "claire"),
            ("欢快女声", "diana"),
        ]
        self.system_voice_var = tk.StringVar()
        self.system_voice_var.set(voice_options[0][1])
        menu = ttk.OptionMenu(tab, self.system_voice_var, voice_options[0][1], *[v[1] for v in voice_options])
        menu["menu"].delete(0, "end")
        for cn, en in voice_options:
            menu["menu"].add_command(label=f"{cn}（{en}）", command=tk._setit(self.system_voice_var, en))
        menu.grid(row=0, column=2, padx=5, pady=5, sticky=tk.W)

        ttk.Label(tab, text="输入文本:").grid(row=1, column=0, padx=5, pady=5, sticky=tk.NW)
        self.system_text_text = tk.Text(tab, height=17, width=95)
        self.system_text_text.grid(row=1, column=1, padx=5, pady=5, sticky=tk.W, columnspan=2)

        self.system_format_var = tk.StringVar(value="mp3")
        format_menu = ttk.OptionMenu(tab, self.system_format_var, "mp3", "wav", "opus", "pcm")
        format_menu.grid(row=2, column=1, padx=(0, 120), pady=10, sticky=tk.W)

        generate_btn = ttk.Button(tab, text="生成语音", command=self.generate_system_voice, width=16, bootstyle=SUCCESS)
        generate_btn.grid(row=2, column=1, padx=(180, 0), pady=10, sticky=tk.W)
        
    def create_voice_manage_tab(self):
        """创建声音操作管理平台选项卡"""
        tab = ttk.Frame(self.voice_notebook)
        self.voice_notebook.add(tab, text=" 声音管理平台 ")

        # 标题
        title = ttk.Label(
            tab,
            text="声音操作管理平台",
            font=('Helvetica', 22, 'bold'),
            anchor="center"
        )
        title.pack(fill=tk.X, pady=20)

        # 按钮区域
        button_frame = ttk.Frame(tab)
        button_frame.pack(pady=20, fill=tk.X)

        btn_width = 16
        btn_height = 2
        buttons = [
            ("GPT-语音总启动器", self.run_voice_manager),
            ("GPT-语音模型制作", self.run_gpt_sovits_webui),
            ("GPT-启动语音API", self.run_gpt_sovits_api),
            ("CosyVoice启动器", self.run_cosyvoice),
            ("AsrTools语音转文字", self.run_AsrTools),
        ]
        for idx, (text, cmd) in enumerate(buttons):
            row, col = divmod(idx, 5)
            btn = ttk.Button(
                button_frame,
                text=text,
                command=cmd,
                width=btn_width,
                style="My.TButton"
            )
            btn.grid(row=row, column=col, padx=12, pady=12, sticky="nsew")

    def browse_file(self):
        """浏览文件对话框"""
        from tkinter import filedialog
        file_path = filedialog.askopenfilename()
        if file_path:
            self.file_path_entry.delete(0, tk.END)
            self.file_path_entry.insert(0, file_path)
            
    def upload_base64_voice(self):
        """通过base64上传音色"""
        
        print(f"[{time.strftime('%H:%M:%S')}] 开始通过Base64上传音色")
        api_key = os.getenv("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "请设置环境变量SiliconCloud_API_KEY")
            print(f"[{time.strftime('%H:%M:%S')}] 错误: 未设置SiliconCloud_API_KEY环境变量")
            return
            
        url = "https://api.siliconflow.cn/v1/uploads/audio/voice"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        data = {
            "model": self.base64_model_var.get(),
            "customName": self.base64_name_entry.get(),
            "audio": self.base64_text.get("1.0", tk.END).strip(),
            "text": self.base64_ref_entry.get()
        }
        
        try:
            print(f"[{time.strftime('%H:%M:%S')}] 正在上传音色数据到API")
            response = requests.post(url, headers=headers, data=json.dumps(data))
            if response.status_code == 200:
                # messagebox.showinfo("成功", f"上传成功: {response.json()}")
                print(f"[{time.strftime('%H:%M:%S')}] 音色上传成功: {response.json()}")
            else:
                messagebox.showerror("错误", f"上传失败: {response.text}")
                print(f"[{time.strftime('%H:%M:%S')}] 音色上传失败: {response.text}")
        except Exception as e:
            messagebox.showerror("错误", f"上传异常: {str(e)}")
            print(f"[{time.strftime('%H:%M:%S')}] 音色上传异常: {str(e)}")
            
    def upload_file_voice(self):
        """通过文件上传音色"""
        
        api_key = os.getenv("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "请设置环境变量SiliconCloud_API_KEY")
            return
            
        url = "https://api.siliconflow.cn/v1/uploads/audio/voice"
        headers = {"Authorization": f"Bearer {api_key}"}
        
        try:
            with open(self.file_path_entry.get(), "rb") as f:
                files = {"file": f}
                data = {
                    "model": self.file_model_var.get(),
                    "customName": self.file_name_entry.get(),
                    "text": self.file_ref_text.get("1.0", tk.END).strip()
                }
                
                response = requests.post(url, headers=headers, files=files, data=data)
                if response.status_code == 200:
                    # messagebox.showinfo("成功", f"上传成功: {response.json()}")
                    print("上传成功")
                else:
                    messagebox.showerror("错误", f"上传失败: {response.text}")
        except Exception as e:
            messagebox.showerror("错误", f"上传异常: {str(e)}")
            
    def refresh_voice_list(self):
        """刷新音色列表"""
        api_key = os.getenv("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "请设置环境变量SiliconCloud_API_KEY")
            return
            
        url = "https://api.siliconflow.cn/v1/audio/voice/list"
        headers = {"Authorization": f"Bearer {api_key}"}
        
        try:
            # 清空现有列表
            for item in self.voice_list.get_children():
                self.voice_list.delete(item)
                
            response = requests.get(url, headers=headers, verify=False)
            response.raise_for_status()
            data = response.json()
            print("音色列表API返回：", data)

            if "result" not in data:
                messagebox.showerror("错误", f"API返回异常：{data}")
                return

            # 添加音色到列表
            for voice in data["result"]:
                self.voice_list.insert("", "end", values=(
                    voice.get("customName", ""),
                    voice.get("model", ""),
                    voice.get("uri", "")
                ))
                
        except requests.exceptions.RequestException as e:
            messagebox.showerror("错误", f"获取音色列表失败: {str(e)}")
        except json.JSONDecodeError:
            messagebox.showerror("错误", "音色列表数据解析失败")
            
    def delete_voice(self):
        """删除音色"""
        
        api_key = os.getenv("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "请设置环境变量SiliconCloud_API_KEY")
            return
            
        url = "https://api.siliconflow.cn/v1/audio/voice/deletions"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        payload = {"uri": self.delete_uri_entry.get()}
        
        try:
            response = requests.post(url, headers=headers, json=payload)
            if response.status_code == 200:
                # messagebox.showinfo("成功", "删除成功")
                print("删除成功")
            else:
                messagebox.showerror("错误", f"删除失败: {response.text}")
        except Exception as e:
            messagebox.showerror("错误", f"删除异常: {str(e)}")
            
    def generate_user_voice(self):
        """使用用户预置音色生成语音"""
        print(f"[{time.strftime('%H:%M:%S')}] 开始使用用户预置音色生成语音")
        from openai import OpenAI
        
        api_key = os.getenv("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "请设置环境变量SiliconCloud_API_KEY")
            return
            
        # 获取音色名称
        voice_name = self.user_uri_entry.get().split(":")[1] if ":" in self.user_uri_entry.get() else self.user_uri_entry.get()
        timestamp = datetime.now().strftime("%Y%m%d%H%M")
        os.makedirs("speech", exist_ok=True)
        file_ext = self.user_format_var.get()
        speech_file_path = Path(f"speech/{voice_name}-{timestamp}.{file_ext}")
        
        client = OpenAI(
            api_key=api_key,
            base_url="https://api.siliconflow.cn/v1"
        )
        
        try:
            with client.audio.speech.with_streaming_response.create(
                model=self.user_model_var.get(),
                voice=self.user_uri_entry.get(),
                input=self.user_text_text.get("1.0", tk.END).strip(),
                response_format=self.user_format_var.get()
            ) as response:
                response.stream_to_file(speech_file_path)
                # messagebox.showinfo("成功", f"语音生成成功: {speech_file_path}")
                print(f"语音生成成功: {speech_file_path}")
                if platform.system() == "Darwin":
                    os.system("open speech")
                elif platform.system() == "Windows":
                    os.startfile("speech")
                else:
                    os.system("xdg-open speech")
        except Exception as e:
            messagebox.showerror("错误", f"生成语音失败: {str(e)}")
            
    def generate_system_voice(self):
        """使用系统音色生成语音"""
        from pathlib import Path
        from openai import OpenAI
        
        api_key = os.getenv("SiliconCloud_API_KEY")
        if not api_key:
            messagebox.showerror("错误", "请设置环境变量SiliconCloud_API_KEY")
            return
            
        # 获取音色名称
        voice_name = self.system_voice_var.get()
        timestamp = datetime.now().strftime("%Y%m%d%H%M")
        os.makedirs("speech", exist_ok=True)
        file_ext = self.system_format_var.get()
        speech_file_path = Path(f"speech/{voice_name}-{timestamp}.{file_ext}")
        
        client = OpenAI(
            api_key=api_key,
            base_url="https://api.siliconflow.cn/v1"
        )
        
        try:
            with client.audio.speech.with_streaming_response.create(
                model=self.system_model_var.get(),
                voice=f"{self.system_model_var.get()}:{self.system_voice_var.get()}",
                input=self.system_text_text.get("1.0", tk.END).strip(),
                response_format=self.system_format_var.get()
            ) as response:
                response.stream_to_file(speech_file_path)
                # messagebox.showinfo("成功", f"语音生成成功: {speech_file_path}")
                print(f"语音生成成功: {speech_file_path}")
                if platform.system() == "Darwin":
                    os.system("open speech")
                elif platform.system() == "Windows":
                    os.startfile("speech")
                else:
                    os.system("xdg-open speech")
        except Exception as e:
            messagebox.showerror("错误", f"生成语音失败: {str(e)}")

    def copy_uri_on_click(self, event):
        selected_item = self.voice_list.focus()
        if not selected_item:
            return
        values = self.voice_list.item(selected_item, "values")
        if len(values) >= 3:
            uri = values[2]
            pyperclip.copy(uri)
            print(f"已复制URI: {uri}")
            # 可选：弹窗提示
            # messagebox.showinfo("提示", f"已复制URI: {uri}")

    def open_ms_folder(self):
        folder = os.path.dirname(os.path.abspath(__file__))
        if platform.system() == "Darwin":
            os.system(f"open '{folder}'")
        elif platform.system() == "Windows":
            os.startfile(folder)
        else:
            os.system(f"xdg-open '{folder}'")

    def run_ai_pic(self):
        # AI 绘画
        cmd = f"cd '{script_dir}'; '{python_path}' run.py"
        os.system(f'''osascript -e 'tell application "Terminal"
            activate
            do script "{cmd}"
        end tell' ''')

    def run_story(self):
        # AI故事绘本
        cmd = f"cd '{script_dir}'; '{python_path}' story.py"
        os.system(f'''osascript -e 'tell application "Terminal"
            activate
            do script "{cmd}"
        end tell' ''')

    def run_roop(self):
        os.system("open /Volumes/AI/AI/roop/roop-unleashed")

    def run_mcn(self):
        cmd = f"cd '{script_dir}'; conda activate modelscope; '{python_path}' MCN.py"
        os.system(f'''osascript -e 'tell application "Terminal"
            activate
            do script "{cmd}"
        end tell' ''')

    def run_xhs(self):
        os.system("cd /Volumes/AI/SOFT/XHS-Downloader_V2.5_macOS_ARM64 && open ./main")

    def show_ssh_key(self):
        os.system("open -a /Applications/Sublime\ Text.app ~/.ssh/id_rsa.pub")

    def show_local_ip(self):
        os.system("curl -L iplark.com")

    def run_qwen3(self):
        subprocess.run([
            "osascript",
            "-e",
            f'''tell application "Terminal" to do script "cd '{script_dir}'; '{python_path}' Qwen3.py"'''
        ])

    # def run_qwen3(self):
    #     os.system('''osascript -e 'tell application "Terminal"
    #         activate
    #         do script "ollama run qwen3:4b"
    #     end tell' ''')

    def run_weixin_mp(self):
        subprocess.run([
            "osascript",
            "-e",
            f'''tell application "Terminal" to do script "cd '{script_dir}'; '{python_path}' weixin_mp.py"'''
        ])

    def run_mpp_video(self):
        cmd = "cd /Volumes/AI/AI/MoneyPrinterPlus && conda activate mpp && streamlit run gui.py"
        self.open_in_terminal(cmd)

    def run_VideoCaptioner(self):
        # 卡卡字幕助手 VideoCaptioner
        cmd = "/Volumes/AI/AI/VideoCaptioner/启动.command"
        self.open_in_terminal(cmd)

    def run_AsrTools(self):
        # AsrTools字幕导出
        cmd = "/Volumes/AI/AI/AsrTools/启动.command"
        self.open_in_terminal(cmd)

    def run_models_html(self):
        # Models 模型展示
        cmd = "cd /Users/hao/DOC/py/2025/run && php -S localhost:8080 & sleep 3 && open http://localhost:8080/models.html"
        self.open_in_terminal(cmd)

    def run_file_manager(self):
        # KindEditor 文件管理器
        cmd = "cd /Users/hao/Downloads && conda activate modelscope && python /Users/hao/DOC/py/2025/file_manager/run.py"
        self.open_in_terminal(cmd)

    def run_rename_files(self):
        # 批量文件名替换
        cmd = "python /Users/hao/DOC/py/2025/rename_files_with_gradio.py"
        self.open_in_terminal(cmd)

    def run_move_files(self):
        # 批量文件移动
        cmd = "python /Users/hao/DOC/py/2025/move_files_with_gradio.py"
        self.open_in_terminal(cmd)

    def run_screenshot_app(self):
        # 网页截图工具
        cmd = "cd /Users/hao/Downloads && conda activate modelscope && python /Users/hao/DOC/py/2025/screenshot_app.py"
        self.open_in_terminal(cmd)

    def run_image_gui(self):
        # 图片采集
        cmd = "cd /Users/hao/DOC/py/cai && python /Users/hao/DOC/py/cai/image_gui.py"
        self.open_in_terminal(cmd)

    def run_html_link_gui(self):
        # 链接提取
        cmd = "python /Users/hao/DOC/py/cai/html_link_gui.py"
        self.open_in_terminal(cmd)

    def run_html_to_markdown_gui(self):
        # MD文档 URL 内容采集器
        cmd = "python /Users/hao/DOC/py/cai/html_to_markdown_gui.py"
        self.open_in_terminal(cmd)

    def run_voice_manager(self):
        # 语音管理器
        self.open_in_terminal("/Volumes/AI/AI/GPT-SoVITS/总启动.command")

    def run_gpt_sovits_webui(self):
        # GPT-SoVITS语音制作
        self.open_in_terminal("/Volumes/AI/AI/GPT-SoVITS/go-webui.command")

    def run_gpt_sovits_api(self):
        # 启动语音API
        self.open_in_terminal("/Volumes/AI/AI/GPT-SoVITS/启动API.command")

    def run_cosyvoice(self):
        # CosyVoice启动
        self.open_in_terminal("/Volumes/AI/AI/CosyVoice/启动.command")

    def open_in_terminal(self, cmd):
        system = platform.system()
        if system == "Darwin":
            # macOS: 用 AppleScript 打开新终端窗口
            if cmd.endswith('.command'):
                # 直接打开.command文件
                subprocess.Popen(["open", cmd])
            else:
                subprocess.Popen([
                    "osascript",
                    "-e",
                    f'''tell application \"Terminal\" to do script \"{cmd}\"'''
                ])
        elif system == "Windows":
            # Windows: 用 start cmd 新开窗口
            subprocess.Popen(["cmd", "/c", "start", "cmd", "/k", cmd])
        else:
            # Linux: 用 gnome-terminal 或 x-terminal-emulator
            try:
                subprocess.Popen(["gnome-terminal", "--", "bash", "-c", cmd])
            except FileNotFoundError:
                subprocess.Popen(["x-terminal-emulator", "-e", cmd])

if __name__ == "__main__":
    root = ttk.Window()
    app = ModelLauncher(root)
    root.mainloop()
