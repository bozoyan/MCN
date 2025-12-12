#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 多媒体编辑器依赖安装脚本
"""

import subprocess
import sys
import os
import platform

def run_command(command, description, check=True):
    """运行命令并处理结果"""
    print(f"\n🔄 {description}...")
    print(f"执行命令: {command}")

    try:
        result = subprocess.run(command, shell=True, check=check, capture_output=True, text=True)
        if result.stdout:
            print(f"✅ 成功: {result.stdout.strip()}")
        if result.stderr:
            print(f"⚠️  警告: {result.stderr.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ 失败: {e.stderr.strip()}")
        return False
    except Exception as e:
        print(f"❌ 异常: {str(e)}")
        return False

def check_python_version():
    """检查Python版本"""
    print("🐍 检查Python版本...")
    version = sys.version_info
    print(f"当前Python版本: {version.major}.{version.minor}.{version.micro}")

    if version.major < 3 or (version.major == 3 and version.minor < 7):
        print("❌ Python版本过低，需要Python 3.7或更高版本")
        return False

    print("✅ Python版本满足要求")
    return True

def check_conda():
    """检查conda是否已安装"""
    print("\n🔍 检查conda环境...")
    try:
        result = subprocess.run(["conda", "--version"], capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✅ conda已安装: {result.stdout.strip()}")
            return True
        else:
            print("❌ conda未安装或不可用")
            return False
    except FileNotFoundError:
        print("❌ conda未找到，请先安装Anaconda或Miniconda")
        return False

def create_conda_env():
    """创建或激活conda环境"""
    print("\n📦 准备conda环境...")

    # 检查是否已存在modelscope环境
    result = subprocess.run("conda env list", shell=True, capture_output=True, text=True)
    if "modelscope" in result.stdout:
        print("✅ modelscope环境已存在")
        return True

    print("🆕 创建新的conda环境...")

    create_cmd = """conda create -n modelscope python=3.9 -y"""
    if not run_command(create_cmd, "创建conda环境"):
        print("❌ 创建conda环境失败")
        return False

    print("✅ conda环境创建成功")
    return True

def install_python_packages():
    """安装Python依赖包"""
    print("\n📚 安装Python依赖包...")

    packages = [
        "pyqt5",
        "qfluentwidgets",
        "pillow",
        "requests",
        "chardet",
        "opencv-python"  # 可选，用于图像处理
    ]

    success_count = 0
    for package in packages:
        print(f"\n📦 安装 {package}...")
        # 使用conda activate环境并安装
        install_cmd = f"conda activate modelscope && pip install {package}"
        if run_command(install_cmd, f"安装 {package}", check=False):
            success_count += 1
        else:
            # 尝试不激活环境直接安装
            alt_cmd = f"pip install {package}"
            if run_command(alt_cmd, f"备用方式安装 {package}", check=False):
                success_count += 1

    print(f"\n📊 安装结果: {success_count}/{len(packages)} 个包安装成功")
    return success_count >= len(packages) - 1  # 允许一个包失败

def check_system_dependencies():
    """检查系统依赖"""
    print("\n🔧 检查系统依赖...")

    system = platform.system().lower()

    if system == "darwin":  # macOS
        return check_macos_dependencies()
    elif system == "linux":
        return check_linux_dependencies()
    elif system == "windows":
        return check_windows_dependencies()
    else:
        print(f"⚠️  未知系统: {system}")
        return True

def check_macos_dependencies():
    """检查macOS依赖"""
    print("🍎 检查macOS依赖...")

    # 检查Homebrew
    try:
        subprocess.run(["brew", "--version"], capture_output=True, check=True)
        print("✅ Homebrew已安装")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ Homebrew未安装")
        print("请先安装Homebrew:")
        print('/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"')
        return False

    # 安装FFmpeg
    if not run_command("brew install ffmpeg", "安装FFmpeg"):
        print("❌ FFmpeg安装失败")
        return False

    print("✅ macOS依赖检查完成")
    return True

def check_linux_dependencies():
    """检查Linux依赖"""
    print("🐧 检查Linux依赖...")

    # 尝试不同的包管理器
    package_managers = [
        ("apt-get", "sudo apt-get update && sudo apt-get install -y ffmpeg"),
        ("yum", "sudo yum install -y ffmpeg"),
        ("dnf", "sudo dnf install -y ffmpeg"),
    ]

    for pm, cmd in package_managers:
        try:
            subprocess.run([pm, "--version"], capture_output=True, check=True)
            print(f"✅ 找到包管理器: {pm}")
            if run_command(cmd, f"使用{pm}安装FFmpeg"):
                print("✅ FFmpeg安装成功")
                return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue

    print("❌ 未找到支持的包管理器或FFmpeg安装失败")
    print("请手动安装FFmpeg")
    return False

def check_windows_dependencies():
    """检查Windows依赖"""
    print("🪟 检查Windows依赖...")

    # 检查是否已安装FFmpeg
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        print("✅ FFmpeg已安装")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ FFmpeg未安装")
        print("请下载并安装FFmpeg:")
        print("1. 访问 https://ffmpeg.org/download.html")
        print("2. 下载Windows版本的FFmpeg")
        print("3. 将FFmpeg的bin目录添加到系统PATH")
        return False

def setup_whisper():
    """设置whisper.cpp"""
    print("\n🤫 设置whisper.cpp...")

    # 检查whisper二进制文件
    whisper_paths = [
        "whisper.cpp/build/bin/whisper-cli",
        "whisper-cli",
        "whisper"
    ]

    for path in whisper_paths:
        if os.path.exists(path) or run_command(f"which {path.split('/')[-1]}", f"检查{path}", check=False):
            print(f"✅ 找到whisper: {path}")
            return True

    print("❌ 未找到whisper.cpp")
    print("请按照以下步骤安装whisper.cpp:")
    print("1. git clone https://github.com/ggerganov/whisper.cpp.git")
    print("2. cd whisper.cpp")
    print("3. make")
    print("4. 下载模型文件到models目录")
    return False

def create_directories():
    """创建必要的目录"""
    print("\n📁 创建工作目录...")

    directories = ["temp", "SRT", "speech", "font"]

    for directory in directories:
        if not os.path.exists(directory):
            os.makedirs(directory)
            print(f"✅ 创建目录: {directory}")
        else:
            print(f"✅ 目录已存在: {directory}")

    return True

def create_config():
    """创建配置文件"""
    print("\n⚙️ 创建配置文件...")

    config_file = "config.json"
    if os.path.exists(config_file):
        print("✅ 配置文件已存在")
        return True

    default_config = """{
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
}"""

    try:
        with open(config_file, 'w', encoding='utf-8') as f:
            f.write(default_config)
        print("✅ 配置文件创建成功")
        return True
    except Exception as e:
        print(f"❌ 配置文件创建失败: {str(e)}")
        return False

def main():
    """主安装流程"""
    print("🚀 BOZO-MCN 多媒体编辑器依赖安装程序")
    print("=" * 50)

    # 检查Python版本
    if not check_python_version():
        sys.exit(1)

    # 检查系统依赖
    if not check_system_dependencies():
        print("⚠️  系统依赖检查失败，但继续安装...")

    # 检查conda
    conda_available = check_conda()

    # 创建conda环境（如果可用）
    if conda_available:
        if not create_conda_env():
            print("⚠️  conda环境创建失败，尝试使用系统Python...")

    # 安装Python包
    if not install_python_packages():
        print("❌ Python包安装失败")
        sys.exit(1)

    # 设置whisper
    whisper_ok = setup_whisper()

    # 创建目录
    create_directories()

    # 创建配置文件
    create_config()

    # 安装完成
    print("\n" + "=" * 50)
    print("🎉 安装完成!")
    print("\n📋 后续步骤:")
    print("1. 如果使用conda环境，运行: conda activate modelscope")
    print("2. 如果whisper未安装，请手动安装whisper.cpp")
    print("3. 运行程序: python run_improved.py")

    if not whisper_ok:
        print("\n⚠️  注意: whisper.cpp未安装，字幕生成功能将不可用")

    print("\n💡 提示:")
    print("- 如果遇到问题，请检查各个依赖是否正确安装")
    print("- API密钥需要在程序设置页面中配置")
    print("- 确保FFmpeg在系统PATH中可用")

if __name__ == "__main__":
    main()