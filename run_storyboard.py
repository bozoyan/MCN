#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOZO-MCN 分镜脚本与图片生成器启动脚本
"""
import os
import sys
import subprocess

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
    api_key = os.getenv('MODELSCOPE_SDK_TOKEN')
    if api_key:
        print(f"✅ ModelScope API密钥已配置 (长度: {len(api_key)})")
    else:
        print("⚠️  ModelScope API密钥未配置")
        print("请设置环境变量 MODELSCOPE_SDK_TOKEN")
        print("或在应用设置中配置API密钥")
    
    return True

def create_directories():
    """创建必要的目录"""
    directories = [
        'output',
        'temp', 
        'templates'
    ]
    
    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        print(f"📁 确保目录存在: {directory}")

def main():
    """主函数"""
    print("=" * 60)
    print("🎬 BOZO-MCN 分镜脚本与图片生成器 v2.0")
    print("=" * 60)
    
    # 检查环境
    if not check_environment():
        input("按回车键退出...")
        return
    
    # 创建目录
    create_directories()
    
    print("\n🚀 启动应用...")
    
    # 启动主应用
    try:
        from storyboard_generator import main as app_main
        app_main()
    except Exception as e:
        print(f"❌ 启动失败: {e}")
        input("按回车键退出...")

if __name__ == "__main__":
    main()
