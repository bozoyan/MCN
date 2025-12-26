# BizyAIR Studio - 启动说明（新版）

## 目录结构说明

```
MCN/                          # 根目录（其他服务）
├── run.py                    # 主启动脚本
├── MCN.py                    # 多媒体编辑器
├── storyboard_generator.py   # 分镜生成器
│
└── BizyAIR/                  # BizyAIR Studio（PHP 网页应用）
    ├── index.php             # 主应用文件（90 KB）
    ├── start.sh              # 快速启动脚本
    ├── json/                 # 配置文件目录
    │   ├── Wan2.2_Remix_NSFW.json
    │   ├── Wan2.6图生视频.json
    │   └── 去水印.json
    └── *.md                  # 完整文档
```

---

## 🚀 快速启动方式

### 方式 1：使用 run.py 启动（推荐）

```bash
# 在根目录执行
cd /Users/yons/AI/MCN
python3 run.py
```

**启动选项：**
1. 仅启动分镜生成器
2. **启动分镜生成器 + PHP 网页服务器**（推荐）
3. 启动 MCN 多媒体编辑器

**工作目录说明：**
- PHP 服务器会在 `BizyAIR/` 目录下启动
- 其他服务在根目录运行
- 浏览器自动打开 http://127.0.0.1:8004

### 方式 2：使用 BizyAIR 目录下的 start.sh

```bash
# 进入 BizyAIR 目录
cd /Users/yons/AI/MCN/BizyAIR

# 启动 PHP 服务器
./start.sh
```

### 方式 3：手动启动

```bash
# 进入 BizyAIR 目录
cd /Users/yons/AI/MCN/BizyAIR

# 启动 PHP 服务器
php -S 127.0.0.1:8004 index.php
```

然后在浏览器打开：http://127.0.0.1:8004

---

## ✅ run.py 改进说明

### 新增功能

1. **自动检测 BizyAIR 目录**
   ```python
   bizyair_dir = os.path.join(os.getcwd(), 'BizyAIR')
   ```

2. **验证 index.php 存在**
   ```python
   index_php = os.path.join(bizyair_dir, 'index.php')
   ```

3. **在 BizyAIR 目录中启动 PHP 服务器**
   ```python
   php_process = subprocess.Popen(
       php_cmd,
       cwd=bizyair_dir,  # 关键改动
       ...
   )
   ```

### 启动流程

```
run.py 执行
    ↓
检查环境
    ↓
询问用户选择
    ↓
选择 "2" (启动 PHP 服务器)
    ↓
检查 BizyAIR/ 目录是否存在
    ↓
检查 BizyAIR/index.php 是否存在
    ↓
在 BizyAIR/ 目录中启动 PHP 服务器
    ↓
自动打开浏览器 http://127.0.0.1:8004
    ↓
同时启动其他服务（分镜生成器）
```

---

## 📋 详细的启动输出示例

```bash
$ python3 run.py

============================================================
🎬 BOZO-MCN 分镜脚本与图片生成器 v1.0
============================================================
🔍 检查环境配置...
✅ Python版本: 3.9.x
✅ PyQt5 已安装
✅ qfluentwidgets 已安装
✅ requests 已安装
✅ PIL 已安装
✅ openai 已安装
⚠️  API密钥未配置
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
📂 工作目录: /Users/yons/AI/MCN/BizyAIR
⏳ 等待服务器启动...
✅ 已在浏览器中打开 http://127.0.0.1:8004

🚀 启动应用...
```

---

## 🎯 使用建议

### 开发场景
**推荐方式**: 使用 `run.py` 选项 2
- 同时启动 PHP 服务器和分镜生成器
- 方便开发和测试

### 仅使用 BizyAIR Studio
**推荐方式**: 直接使用 `BizyAIR/start.sh`
```bash
cd BizyAIR
./start.sh
```

### 调试 PHP 服务器
**推荐方式**: 手动启动，查看详细日志
```bash
cd BizyAIR
php -S 127.0.0.1:8004 index.php
```

---

## 🐛 故障排除

### 问题 1：BizyAIR 目录未找到

**错误信息**:
```
❌ BizyAIR 目录不存在: /Users/yons/AI/MCN/BizyAIR
```

**解决方案**:
```bash
# 确认目录结构
ls -la /Users/yons/AI/MCN/ | grep BizyAIR

# 如果不存在，创建目录
mkdir -p /Users/yons/AI/MCN/BizyAIR

# 复制 index.php 到 BizyAIR 目录
cp index.php BizyAIR/
```

### 问题 2：index.php 未找到

**错误信息**:
```
❌ BizyAIR 目录中未找到 index.php
期望位置: /Users/yons/AI/MCN/BizyAIR/index.php
```

**解决方案**:
```bash
# 检查 index.php 是否存在
ls -la BizyAIR/index.php

# 如果不存在，从其他位置复制
# 或者重新生成 BizyAIR Studio
```

### 问题 3：PHP 服务器启动失败

**错误信息**:
```
❌ 启动PHP服务器失败: ...
```

**解决方案**:
```bash
# 1. 检查 PHP 是否安装
php --version

# 2. 手动测试启动
cd BizyAIR
php -S 127.0.0.1:8004 index.php

# 3. 检查端口是否被占用
lsof -i :8004
```

### 问题 4：浏览器无法打开

**错误信息**:
```
⚠️  无法自动打开浏览器: ...
```

**解决方案**:
手动在浏览器中打开：http://127.0.0.1:8004

---

## 📊 目录权限检查

```bash
# 确保 BizyAIR 目录可访问
ls -ld BizyAIR/

# 确保 index.php 可读
ls -l BizyAIR/index.php

# 确保 json 目录可写
ls -ld BizyAIR/json/
```

**预期权限**:
```
drwxr-xr-x  BizyAIR/
-rw-r--r--  BizyAIR/index.php
drwxr-xr-x  BizyAIR/json/
```

---

## 🔗 相关文档

### BizyAIR Studio 文档

1. **[DOCS-INDEX.md](BizyAIR/DOCS-INDEX.md)** - 文档导航中心
2. **[README-MAIN.md](BizyAIR/README-MAIN.md)** - 项目总览
3. **[README-PHP.md](BizyAIR/README-PHP.md)** - 技术详解
4. **[ARCHITECTURE.md](BizyAIR/ARCHITECTURE.md)** - 架构设计
5. **[QUICK-REFERENCE.md](BizyAIR/QUICK-REFERENCE.md)** - 快速参考

### 启动相关

1. **[启动说明.txt](BizyAIR/启动说明.txt)** - BizyAIR 启动指南
2. **[start.sh](BizyAIR/start.sh)** - 快速启动脚本

---

## ⚙️ 配置说明

### 环境变量

```bash
# BizyAir API 密钥（可选，也可在应用中设置）
export SiliconCloud_API_KEY="your_api_key_here"

# ModelScope API 密钥（可选）
export MODELSCOPE_SDK_TOKEN="your_token_here"
```

### PHP 服务器配置

```bash
# 默认配置
主机: 127.0.0.1
端口: 8004
路由文件: index.php

# 自定义端口（需要修改 run.py）
php -S 127.0.0.1:自定义端口 index.php
```

---

## 🎨 功能说明

### BizyAIR Studio 主要功能

1. **画布模式** - 手绘涂鸦、图片编辑
2. **节点模式** - 可视化工作流编辑
3. **历史画廊** - 生成历史管理
4. **配置管理** - JSON 配置文件编辑

### 分镜生成器功能

1. AI 生成分镜脚本
2. 批量图片生成
3. 模板管理
4. Markdown 导出

---

## 📝 更新日志

### v1.1 (2025-12-26)

- ✨ 修改 run.py，在 BizyAIR 子目录中启动 PHP 服务器
- ✨ 添加 BizyAIR 目录和 index.php 存在性检查
- ✨ 改进错误提示信息
- 📝 更新启动说明文档

### v1.0 (2025-12-26)

- 🎉 初始版本发布
- 🚀 支持 PHP 服务器自动启动
- 🌐 自动打开浏览器

---

## 💡 使用技巧

1. **首次使用**
   - 建议先手动启动一次 PHP 服务器，确保配置正确
   - 浏览器访问 http://127.0.0.1:8004
   - 设置 API 密钥

2. **日常开发**
   - 使用 `python3 run.py` 选项 2
   - 同时启动多个服务
   - 提高开发效率

3. **生产环境**
   - 直接使用 `BizyAIR/start.sh`
   - 或使用 Apache/Nginx 部署

---

**文档版本**: 1.1
**最后更新**: 2025-12-26
**维护者**: BizyAIR Studio Team
