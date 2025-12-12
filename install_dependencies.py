#!/usr/bin/env python3
"""
安装 BOZO-MCN PyQt5版本所需的依赖包
"""

import subprocess
import sys
import os

def install_package(package):
    """安装单个包"""
    try:
        print(f"正在安装 {package}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
        print(f"✓ {package} 安装成功")
        return True
    except subprocess.CalledProcessError:
        print(f"✗ {package} 安装失败")
        return False

def main():
    """主函数"""
    print("BOZO-MCN PyQt5版本 依赖安装器")
    print("=" * 40)

    # 需要安装的包列表
    packages = [
        "PyQt5",
        "qfluentwidgets",
        "Pillow",
        "chardet",
        "requests"
    ]

    # 检查pip是否可用
    try:
        import pip
        print("✓ pip 可用")
    except ImportError:
        print("✗ pip 不可用，请先安装pip")
        return

    # 安装每个包
    success_count = 0
    for package in packages:
        if install_package(package):
            success_count += 1
        print()

    print("=" * 40)
    print(f"安装完成：{success_count}/{len(packages)} 个包安装成功")

    if success_count == len(packages):
        print("✅ 所有依赖安装成功！可以运行 MCN_pyqt.py")
    else:
        print("⚠️  部分依赖安装失败，请手动安装失败的包")

    # 提示用户
    print("\n使用说明：")
    print("1. 安装完成后运行: python MCN_pyqt.py")
    print("2. 确保系统已安装 FFmpeg")
    print("3. 如需翻译功能请设置环境变量: SiliconCloud_API_KEY")

if __name__ == "__main__":
    main()