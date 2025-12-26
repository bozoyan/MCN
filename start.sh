#!/bin/bash
# BizyAIR Studio 快速启动脚本

echo "🚀 启动 BizyAIR Studio 服务器..."

# 停止旧的服务器（如果存在）
pkill -f "php -S 127.0.0.1:8004" 2>/dev/null
sleep 1

# 启动新的服务器（使用 index.php 作为路由器）
php -S 127.0.0.1:8004 index.php &
sleep 2

# 检查是否成功启动
if ps aux | grep -v grep | grep "php -S 127.0.0.1:8004" > /dev/null; then
    echo "✅ 服务器启动成功！"
    echo ""
    echo "🌐 在浏览器中打开: http://127.0.0.1:8004"
    echo ""
    echo "💡 提示: 按 Ctrl+C 停止服务器，或运行: pkill -f 'php -S 127.0.0.1:8004'"
else
    echo "❌ 服务器启动失败！请检查 PHP 是否已安装。"
fi
