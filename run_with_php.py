#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 快速启动脚本（包含PHP服务器）
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

    # 检查是否安装了PHP
    try:
        subprocess.run(['php', '--version'], capture_output=True, check=True)
        print("✅ PHP已安装")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 未找到PHP，请先安装PHP")
        print("macOS: brew install php")
        print("Ubuntu: sudo apt-get install php-cli")
        print("Windows: 请从 https://www.php.net/downloads.php 下载安装")
        return None

    # 启动PHP服务器
    try:
        # 在后台启动PHP服务器
        if platform.system() == "Windows":
            # Windows系统
            php_cmd = ['start', '/B', 'php', '-S', '127.0.0.1:8004']
        else:
            # macOS/Linux系统
            php_cmd = ['php', '-S', '127.0.0.1:8004']

        print(f"执行命令: {' '.join(php_cmd)}")

        # 启动服务器进程
        php_process = subprocess.Popen(
            php_cmd,
            cwd=os.getcwd(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        print("✅ PHP服务器正在启动在 http://127.0.0.1:8004")
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
    print("🎬 BOZO-MCN 分镜脚本与图片生成器 (含PHP服务器)")
    print("=" * 60)

    # 检查环境
    if not check_environment():
        input("按回车键退出...")
        return

    # 创建目录
    create_directories()

    # 启动PHP服务器
    php_process = start_php_server()
    if not php_process:
        print("\n❌ 无法启动PHP服务器，退出程序")
        input("按回车键退出...")
        return

    print("\n🚀 启动分镜生成器应用...")
    print("提示: PHP服务器将在后台运行，关闭此窗口时会自动关闭")

    # 启动主应用
    try:
        from storyboard_generator import main as app_main
        app_main()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断")
    except Exception as e:
        print(f"\n❌ 启动失败: {e}")
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

        print("\n👋 程序已退出")
        time.sleep(1)

if __name__ == "__main__":
    main()