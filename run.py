#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 分镜脚本与图片生成器启动脚本
"""
import os
import sys
import subprocess
import platform
import time
import threading

def check_environment():
    """检查环境配置"""
    print("🔍 检查环境配置...")
    
    # 检查Python环境
    python_version = sys.version
    print(f"✅ Python版本: {python_version}")
    
    # 检查必要的包
    required_packages = [
        'PyQt5', 'qfluentwidgets', 'requests', 'PIL', 'openai'
    ]
    
    missing_packages = []
    for package in required_packages:
        try:
            __import__(package)
            print(f"✅ {package} 已安装")
        except ImportError:
            missing_packages.append(package)
            print(f"❌ {package} 未安装")
    
    if missing_packages:
        print(f"\n⚠️  缺少以下包: {', '.join(missing_packages)}")
        print("请运行以下命令安装:")
        print(f"pip install {' '.join(missing_packages)}")
        return False
    
    # 检查API密钥
    api_key = os.getenv('SiliconCloud_API_KEY')
    if api_key:
        print(f"✅ API密钥已配置 (长度: {len(api_key)})")
    else:
        print("⚠️  API密钥未配置")
        print("请设置环境变量 SiliconCloud_API_KEY")
        print("或在应用设置中配置API密钥")
    
    return True

def create_directories():
    """创建必要的目录"""
    directories = [
        'output',
        'temp',
        'templates',
        'json'
    ]

    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        print(f"📁 确保目录存在: {directory}")

def start_php_server():
    """启动PHP开发服务器"""
    print("\n🌐 启动PHP开发服务器...")

    # 检查 BizyAIR 目录是否存在
    bizyair_dir = os.path.join(os.getcwd(), 'BizyAIR')
    if not os.path.exists(bizyair_dir):
        print(f"❌ BizyAIR 目录不存在: {bizyair_dir}")
        print("请确保 BizyAIR 文件夹在当前目录下")
        return None

    print(f"📁 BizyAIR 目录: {bizyair_dir}")

    # 检查 BizyAIR 目录中是否有 index.php
    index_php = os.path.join(bizyair_dir, 'index.php')
    if not os.path.exists(index_php):
        print(f"❌ BizyAIR 目录中未找到 index.php")
        print(f"期望位置: {index_php}")
        return None

    print(f"✅ 找到 index.php")

    # 检查是否安装了PHP
    try:
        subprocess.run(['php', '--version'], capture_output=True, check=True)
        print("✅ PHP已安装")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 未找到PHP，请先安装PHP")
        return None

    # 启动PHP服务器
    try:
        # 在后台启动PHP服务器，工作目录设置为 BizyAIR 文件夹
        if platform.system() == "Windows":
            # Windows系统
            php_cmd = ['start', '/B', 'php', '-S', '127.0.0.1:8004', 'index.php']
        else:
            # macOS/Linux系统
            php_cmd = ['php', '-S', '127.0.0.1:8004', 'index.php']

        # 启动服务器进程，工作目录为 BizyAIR 文件夹
        php_process = subprocess.Popen(
            php_cmd,
            cwd=bizyair_dir,  # 关键：设置工作目录为 BizyAIR 文件夹
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        print("✅ PHP服务器正在启动在 http://127.0.0.1:8004")
        print(f"📂 工作目录: {bizyair_dir}")
        print("⏳ 等待服务器启动...")

        # 等待2秒让服务器完全启动
        time.sleep(2)

        # 在新线程中打开浏览器
        def open_browser():
            time.sleep(1)  # 再等待1秒
            try:
                if platform.system() == "Darwin":  # macOS
                    subprocess.run(['open', 'http://127.0.0.1:8004'])
                elif platform.system() == "Windows":  # Windows
                    subprocess.run(['start', 'http://127.0.0.1:8004'], shell=True)
                else:  # Linux
                    subprocess.run(['xdg-open', 'http://127.0.0.1:8004'])
                print("✅ 已在浏览器中打开 http://127.0.0.1:8004")
            except Exception as e:
                print(f"⚠️  无法自动打开浏览器: {e}")

        browser_thread = threading.Thread(target=open_browser)
        browser_thread.daemon = True
        browser_thread.start()

        return php_process

    except Exception as e:
        print(f"❌ 启动PHP服务器失败: {e}")
        return None

def main():
    """主函数"""
    print("=" * 60)
    print("🎬 BOZO-MCN 分镜脚本与图片生成器 v1.0")
    print("=" * 60)

    # 检查环境
    if not check_environment():
        input("按回车键退出...")
        return

    # 创建目录
    create_directories()

    # 询问要启动的服务
    print("\n" + "=" * 60)
    print("请选择要启动的服务:")
    print("1. 仅启动分镜生成器")
    print("2. 启动分镜生成器 + PHP网页服务器")
    print("3. 启动MCN多媒体编辑器")
    print("=" * 60)

    choice = input("请输入选择 (1/2/3, 默认2): ").strip() or "2"

    php_process = None
    if choice == "2":
        php_process = start_php_server()
    elif choice == "3":
        print("\n🚀 启动MCN多媒体编辑器...")
        try:
            # 导入并运行MCN主程序
            import MCN
            MCN.main()
        except ImportError:
            print("❌ 未找到MCN.py文件")
            input("按回车键退出...")
        except Exception as e:
            print(f"❌ 启动MCN失败: {e}")
            input("按回车键退出...")
        return
    else:
        print("\n⚠️  跳过PHP服务器启动")
        print("如需使用配置管理功能，请手动启动PHP服务器:")
        print("php -S 127.0.0.1:8004")

    print("\n🚀 启动应用...")

    # 启动主应用
    try:
        from storyboard_generator import main as app_main
        app_main()
    except Exception as e:
        print(f"❌ 启动失败: {e}")
        input("按回车键退出...")
    finally:
        # 清理：关闭PHP服务器
        if php_process:
            print("\n🛑 正在关闭PHP服务器...")
            try:
                php_process.terminate()
                php_process.wait(timeout=5)
                print("✅ PHP服务器已关闭")
            except subprocess.TimeoutExpired:
                php_process.kill()
                print("⚠️  强制关闭PHP服务器")
            except Exception as e:
                print(f"⚠️  关闭PHP服务器时出错: {e}")

if __name__ == "__main__":
    main()
