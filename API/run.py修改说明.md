# run.py 修改说明

## 📝 修改内容

### 主要改动
修改了 `start_php_server()` 函数，使其在 `BizyAIR/` 子目录中启动 PHP 服务器，而不是在根目录。

### 修改前后对比

**修改前**:
```python
php_process = subprocess.Popen(
    php_cmd,
    cwd=os.getcwd(),  # 在根目录启动
    ...
)
```

**修改后**:
```python
bizyair_dir = os.path.join(os.getcwd(), 'BizyAIR')
php_process = subprocess.Popen(
    php_cmd,
    cwd=bizyair_dir,  # 在 BizyAIR 目录启动
    ...
)
```

---

## ✨ 新增功能

1. **目录检查**
   - 自动检测 `BizyAIR/` 目录是否存在
   - 验证 `BizyAIR/index.php` 文件是否存在

2. **详细提示**
   - 显示 BizyAIR 目录路径
   - 显示 index.php 查找结果
   - 显示 PHP 服务器工作目录

3. **命令行改进**
   - 添加 `index.php` 参数到 PHP 命令
   - 确保正确的路由文件被使用

---

## 🎯 使用方法

### 启动步骤

1. **在根目录执行**:
   ```bash
   cd /Users/yons/AI/MCN
   python3 run.py
   ```

2. **选择选项 2**:
   ```
   请选择要启动的服务:
   1. 仅启动分镜生成器
   2. 启动分镜生成器 + PHP网页服务器  ← 选择这个
   3. 启动MCN多媒体编辑器

   请输入选择 (1/2/3, 默认2): 2
   ```

3. **自动启动**:
   - ✅ PHP 服务器在 BizyAIR/ 目录中启动
   - ✅ 浏览器自动打开 http://127.0.0.1:8004
   - ✅ 分镜生成器同时启动

---

## 📂 目录结构

```
/Users/yons/AI/MCN/
├── run.py                    # 主启动脚本（已修改）
├── MCN.py                    # 多媒体编辑器
├── storyboard_generator.py   # 分镜生成器
│
└── BizyAIR/                  # BizyAIR Studio（PHP 服务器在这里启动）
    ├── index.php             # 90 KB
    ├── start.sh
    ├── json/
    │   ├── Wan2.2_Remix_NSFW.json
    │   ├── Wan2.6图生视频.json
    │   └── 去水印.json
    └── *.md                  # 文档
```

---

## 🔍 验证方法

### 检查目录结构

```bash
# 检查 BizyAIR 目录
ls -la BizyAIR/

# 检查 index.php
ls -lh BizyAIR/index.php

# 检查 json 目录
ls -la BizyAIR/json/
```

### 测试启动

```bash
# 方式 1：使用 run.py
python3 run.py
# 选择选项 2

# 方式 2：手动启动（用于测试）
cd BizyAIR
php -S 127.0.0.1:8004 index.php
```

---

## 🐛 可能遇到的问题

### 问题 1: BizyAIR 目录不存在

**症状**:
```
❌ BizyAIR 目录不存在: /Users/yons/AI/MCN/BizyAIR
```

**解决**:
```bash
# 创建 BizyAIR 目录
mkdir BizyAIR

# 复制 index.php（如果需要）
cp index.php BizyAIR/
```

### 问题 2: index.php 不存在

**症状**:
```
❌ BizyAIR 目录中未找到 index.php
期望位置: /Users/yons/AI/MCN/BizyAIR/index.php
```

**解决**:
```bash
# 确认文件位置
find . -name "index.php"

# 如果在其他位置，复制到 BizyAIR/
cp /path/to/index.php BizyAIR/
```

### 问题 3: PHP 服务器无法启动

**症状**:
```
❌ 启动PHP服务器失败: ...
```

**解决**:
```bash
# 手动测试
cd BizyAIR
php -S 127.0.0.1:8004 index.php

# 检查端口占用
lsof -i :8004
```

---

## 📊 启动输出示例

```
============================================================
🎬 BOZO-MCN 分镜脚本与图片生成器 v1.0
============================================================
🔍 检查环境配置...
✅ Python版本: 3.9.x
✅ PyQt5 已安装
...
📁 确保目录存在: output
📁 确保目录存在: temp
📁 确保目录存在: templates
📁 确保目录存在: json

============================================================
请选择要启动的服务:
1. 仅启动分镜生成器
2. 启动分镜生成器 + PHP网页服务器
3. 启动MCN多媒体编辑器
============================================================
请输入选择 (1/2/3, 默认2): 2

🌐 启动PHP开发服务器...
📁 BizyAIR 目录: /Users/yons/AI/MCN/BizyAIR
✅ 找到 index.php
✅ PHP已安装
✅ PHP服务器正在启动在 http://127.0.0.1:8004
📂 工作目录: /Users/yons/AI/MCN/BizyAIR  ← 关键：工作目录是 BizyAIR/
⏳ 等待服务器启动...
✅ 已在浏览器中打开 http://127.0.0.1:8004

🚀 启动应用...
```

---

## 🎉 改进优势

### 1. 目录结构更清晰
- PHP 应用独立在 BizyAIR/ 目录
- 不与根目录的其他服务混在一起

### 2. 更好的组织性
- 每个应用有独立的目录
- 便于管理和维护

### 3. 更安全的隔离
- PHP 服务器的工作目录限制在 BizyAIR/
- 避免访问根目录的文件

### 4. 更灵活的部署
- 可以独立部署 BizyAIR/ 目录
- 不影响根目录的其他服务

---

## 📚 相关文档

- **[启动说明-新版.txt](启动说明-新版.txt)** - 详细的启动指南
- **[BizyAIR/启动说明.txt](BizyAIR/启动说明.txt)** - BizyAIR 启动指南
- **[BizyAIR/DOCS-INDEX.md](BizyAIR/DOCS-INDEX.md)** - 文档导航

---

## 🔄 版本历史

### v1.1 (2025-12-26)
- ✨ 修改 PHP 服务器启动目录为 BizyAIR/
- ✨ 添加目录和文件存在性检查
- ✨ 改进错误提示信息
- 📝 更新文档

### v1.0 (原版本)
- 🎉 初始版本
- 🚀 支持启动 PHP 服务器（在根目录）

---

**修改日期**: 2025-12-26
**修改人**: Claude AI
**版本**: 1.1
