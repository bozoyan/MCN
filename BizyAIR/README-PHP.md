# BizyAIR Studio - 技术文档

## 📋 项目概述

BizyAIR Studio 是一个基于 **PHP** 和 **原生 JavaScript** 的单页应用（SPA），专门为 BizyAir API 设计的多媒体内容创作工具。它将完整的后端 API 和前端界面集成在一个 PHP 文件中，提供简洁高效的开发和部署体验。

### 核心特性

- 🎨 **画布模式** - 手绘涂鸦、图片编辑、视频生成
- 🔗 **节点模式** - 可视化工作流编辑器
- 🖼️ **画廊管理** - 历史记录和作品管理
- ⚙️ **配置管理** - JSON 配置文件可视化管理
- 🌐 **API 集成** - 完整的 BizyAir API 支持
- 🚀 **零依赖部署** - 单文件架构，无需额外配置

---

## 🏗️ 架构设计

### 文件结构

```
index.php (1846 行)
├── PHP 后端 (1-120 行)
│   ├── 路由处理
│   ├── API 端点
│   └── 静态文件服务
│
├── HTML 结构 (121-760 行)
│   ├── 头部元数据
│   ├── CSS 样式系统
│   └── 页面布局
│
└── JavaScript (761-1846 行)
    ├── 全局状态管理
    ├── 画布操作
    ├── 节点编辑器
    ├── API 集成
    └── UI 交互
```

### 技术栈

| 层级 | 技术 | 版本/说明 |
|------|------|-----------|
| **后端** | PHP | 7.4+ (内置服务器) |
| **前端** | 原生 JavaScript | ES6+ |
| **编辑器** | CodeMirror | 5.65.2 |
| **API** | BizyAir API | REST |
| **样式** | 原生 CSS | 自定义主题 |
| **图标** | SVG | 内联 |

---

## 🔧 PHP 后端详解

### 1. 路由系统 (1-26 行)

```php
if (php_sapi_name() === 'cli-server') {
    // 静态文件处理
    // CSS, JS, 图片等资源直接提供服务
}
```

**功能：**
- 检测 PHP 内置服务器环境
- 自动处理静态文件请求
- 将其他请求路由到主应用

### 2. API 端点 (29-119 行)

#### 获取配置文件列表
```http
GET /api/configs
```

**响应示例：**
```json
[
  "Wan2.2_Remix_NSFW.json",
  "Wan2.6图生视频.json",
  "去水印.json"
]
```

#### 读取配置文件
```http
GET /api/config/{filename}
```

**特性：**
- 支持 URL 编码的中文文件名
- 自动添加 `.json` 扩展名
- UTF-8 编码转换

#### 保存配置文件
```http
POST /api/config/{filename}
Content-Type: application/json

{
  "web_app_id": 39419,
  "input_values": {...}
}
```

#### 删除配置文件
```http
DELETE /api/config/{filename}
```

### 3. CORS 配置

```php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
```

---

## 🎨 前端架构

### 全局状态 (689-738 行)

```javascript
// 核心状态变量
let currentMode = 'canvas';           // 当前视图模式
let apiKey = localStorage.getItem('id_works_api_key');
let canvasScale = 1.0;                // 画布缩放
let nodes = [];                        // 节点数据
let currentWebAppId = 39419;          // BizyAir App ID

// 超时配置
const API_TIMEOUT = 1200 * 1000;      // 20分钟
```

### 核心功能模块

#### 1. 画布模式 (Canvas Mode)

**主要功能：**
- 手绘涂鸦（画笔、橡皮擦）
- 图片粘贴和编辑
- 缩放和拖拽
- 图片对象管理

**关键函数：**
- `initCanvas()` - 初始化画布
- `updateCanvasRatio()` - 更新画布比例
- `redrawCanvas()` - 重绘画布内容
- `undoCanvas()` - 撤销操作
- `handlePaste()` - 粘贴图片

**使用场景：**
- 手绘草图生成视频
- 图片标注和修改
- 多图合成编辑

#### 2. 节点模式 (Node Mode)

**主要功能：**
- 可视化节点编辑器
- 节点拖拽和连接
- 动态配置管理
- 工作流执行

**关键函数：**
- `createDefaultNodes()` - 创建默认节点
- `parseAndBuildNodes()` - 解析 JSON 构建节点
- `renderNodes()` - 渲染节点界面
- `drawDynamicConnections()` - 绘制连接线
- `generateJSONFromNodes()` - 导出节点配置

**节点类型：**
- LoadImage - 图片加载节点
- BizyAir API - API 调用节点
- Output - 结果输出节点

#### 3. 历史画廊 (History Gallery)

**主要功能：**
- 生成历史记录
- 图片预览和查看
- 本地存储管理
- 批量删除

**关键函数：**
- `saveToHistory()` - 保存到历史
- `loadHistory()` - 加载历史记录
- `deleteHistoryItem()` - 删除历史项
- `showLightbox()` - 大图查看

**存储机制：**
```javascript
// 使用 localStorage 持久化
localStorage.setItem('id_works_history', JSON.stringify(h));
```

#### 4. 配置管理器 (Config Manager)

**主要功能：**
- JSON 配置文件编辑
- 文件列表管理
- 导入到节点模式
- CodeMirror 编辑器集成

**关键函数：**
- `loadConfigFileList()` - 加载文件列表
- `loadConfigFile()` - 加载文件内容
- `saveCurrentConfig()` - 保存配置
- `importConfigToNodes()` - 导入到节点

---

## 🎯 UI 设计系统

### CSS 变量系统 (103-114 行)

```css
:root {
    --bg-color: #1e1e1e;           /* 背景色 */
    --panel-bg: #2d2d2d;           /* 面板背景 */
    --text-main: #ffffff;          /* 主文本 */
    --text-sub: #a0a0a0;           /* 次级文本 */
    --accent: #4dabf7;             /* 强调色 */
    --border: #404040;             /* 边框色 */
    --grid-color: #333333;         /* 网格色 */
    --font-mono: 'SF Mono', ...;   /* 等宽字体 */
}
```

### 主要布局组件

#### 侧边栏 (Sidebar)
```html
<div class="sidebar">
    <div class="icon-btn active">画布</div>
    <div class="icon-btn">工作流</div>
    <div class="icon-btn">历史</div>
    <div class="icon-btn">配置</div>
</div>
```

#### 工作区 (Workspace)
```html
<div class="workspace active">
    <div class="canvas-wrapper">...</div>
    <div class="floating-panel">...</div>
</div>
```

#### 右侧画廊 (Right Sidebar)
```html
<div class="right-sidebar open">
    <div class="gallery-scroll-area">...</div>
    <button class="gallery-toggle-btn">HIDE PANEL</button>
</div>
```

### CodeMirror 自定义样式 (316-452 行)

```css
.CodeMirror {
    font-family: var(--font-mono);
    font-size: 20px;
    line-height: 2.0;
}

/* JSON 语法高亮 */
.cm-property { color: #66d9ef; }
.cm-string { color: #e6db74; }
.cm-number { color: #ae81ff; }
```

---

## 🌐 API 集成

### BizyAir API 调用

#### 1. 创建任务 (1183-1190 行)

```javascript
const res = await fetchWithTimeout(
    'https://api.bizyair.cn/w/v1/webapp/task/openapi/create',
    {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`
        },
        body: JSON.stringify(payload)
    }
);
```

**请求负载示例：**
```json
{
  "web_app_id": 39419,
  "suppress_preview_output": false,
  "input_values": {
    "2:LoadImage.image": "data:image/png;base64,...",
    "3:BizyAirSiliconCloudLLMAPI.user_prompt": "提示词",
    "1:BizyAir_NanoBananaPro.operation": "edit",
    "1:BizyAir_NanoBananaPro.aspect_ratio": "1:1",
    "1:BizyAir_NanoBananaPro.resolution": "1K"
  }
}
```

#### 2. 检查任务状态 (1765-1769 行)

```javascript
const res = await fetchWithTimeout(
    `https://api.bizyair.cn/w/v1/webapp/task/${requestId}/status`,
    {
        headers: {
            'Authorization': `Bearer ${apiKey}`
        }
    }
);
```

### 超时控制 (716-734 行)

```javascript
async function fetchWithTimeout(url, options = {}, timeout = API_TIMEOUT) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
        const response = await fetch(url, {
            ...options,
            signal: controller.signal
        });
        clearTimeout(timeoutId);
        return response;
    } catch (error) {
        clearTimeout(timeoutId);
        if (error.name === 'AbortError') {
            throw new Error(`请求超时（${timeout / 1000}秒）`);
        }
        throw error;
    }
}
```

**超时设置：**
- 默认：20 分钟（1200 秒）
- 适用于所有 BizyAir API 调用
- 提供友好的超时提示

---

## 🔌 本地 API 接口

### 配置管理 API

#### 获取文件列表
```javascript
const response = await fetch('/api/configs');
const files = await response.json();
```

#### 读取配置
```javascript
const response = await fetch(`/api/config/${encodeURIComponent(filename)}`);
const config = await response.json();
```

#### 保存配置
```javascript
const response = await fetch(`/api/config/${encodeURIComponent(filename)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(configData)
});
```

#### 删除配置
```javascript
const response = await fetch(`/api/config/${encodeURIComponent(filename)}`, {
    method: 'DELETE'
});
```

---

## 🚀 部署和配置

### 环境要求

- **PHP**: 7.4 或更高版本
- **扩展**: 无需特殊扩展
- **浏览器**: Chrome 90+, Firefox 88+, Safari 14+

### 快速启动

#### 方法 1：使用启动脚本
```bash
chmod +x start.sh
./start.sh
```

#### 方法 2：手动启动
```bash
php -S 127.0.0.1:8004 index.php
```

### 生产环境部署

#### 使用 Apache
```apache
<VirtualHost *:80>
    ServerName bizyair.example.com
    DocumentRoot /path/to/MCN

    <Directory /path/to/MCN>
        DirectoryIndex index.php
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>
```

#### 使用 Nginx
```nginx
server {
    listen 80;
    server_name bizyair.example.com;
    root /path/to/MCN;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

---

## 📁 数据存储

### localStorage 结构

```javascript
// API 密钥
localStorage.setItem('id_works_api_key', apiKey);

// 历史记录（最多 50 条）
localStorage.setItem('id_works_history', JSON.stringify([
  {
    url: "https://...",
    time: "10:30:45",
    id: 1734567890
  }
]));
```

### 文件系统结构

```
MCN/
├── index.php              # 主应用文件
├── json/                  # 配置文件目录
│   ├── Wan2.2_Remix_NSFW.json
│   ├── Wan2.6图生视频.json
│   └── 去水印.json
├── start.sh               # 启动脚本
└── README-PHP.md          # 本文档
```

---

## 🛠️ 开发指南

### 添加新的视图模式

1. **HTML 结构**
```html
<div id="view-newmode" class="workspace">
    <!-- 内容 -->
</div>
```

2. **CSS 样式**
```css
#view-newmode {
    /* 样式定义 */
}
```

3. **JavaScript 初始化**
```javascript
function switchMode(mode) {
    // 添加新模式到路由
    if (mode === 'newmode') {
        initNewMode();
    }
}
```

### 添加新的 API 端点

在 `index.php` 的 API 部分添加：

```php
elseif ($path[1] === 'newendpoint' && $_SERVER['REQUEST_METHOD'] === 'GET') {
    // 处理逻辑
    echo json_encode(['data' => 'response']);
    exit;
}
```

### 自定义 CodeMirror 主题

编辑样式块（316-452 行）：

```css
.CodeMirror {
    background: #your-color !important;
    color: #your-text-color !important;
}
```

---

## 🐛 调试和故障排除

### 常见问题

#### 1. 服务器启动失败
**问题**: `Address already in use`
**解决**:
```bash
# 查找占用端口的进程
lsof -i :8004

# 杀死进程
kill -9 <PID>

# 或使用不同端口
php -S 127.0.0.1:8005 index.php
```

#### 2. API 调用超时
**问题**: 请求超过 20 分钟
**解决**:
```javascript
// 修改超时时间（第 707 行）
const API_TIMEOUT = 30 * 60 * 1000; // 30分钟
```

#### 3. 中文文件名乱码
**问题**: JSON 文件名显示为乱码
**解决**:
```php
// 确保使用 UTF-8 编码保存文件
// PHP 已处理编码转换（第 61、71 行）
```

#### 4. CORS 错误
**问题**: API 跨域请求被阻止
**解决**:
```php
// 已配置 CORS（第 38-40 行）
header('Access-Control-Allow-Origin: *');
```

### 调试技巧

#### 1. 启用 PHP 错误显示
```bash
php -S 127.0.0.1:8004 -d display_errors=1 index.php
```

#### 2. 查看浏览器控制台
- 打开开发者工具 (F12)
- 查看 Console 标签的错误信息
- 查看 Network 标签的 API 请求

#### 3. 添加调试日志
```javascript
console.log('Debug:', variable);
console.error('Error:', error);
```

---

## 🔒 安全注意事项

### 1. API 密钥保护
```javascript
// 密钥存储在 localStorage（仅客户端）
// 生产环境应考虑：
// - 使用服务端会话
// - 实施 HTTPS
// - 添加密钥过期机制
```

### 2. 文件上传验证
```php
// 当前实现信任 JSON 数据
// 建议添加：
// - JSON schema 验证
// - 文件大小限制
// - 内容类型检查
```

### 3. CORS 配置
```php
// 当前允许所有来源 (*)
// 生产环境应限制：
header('Access-Control-Allow-Origin: https://yourdomain.com');
```

---

## 📊 性能优化

### 当前实现

- ✅ 单文件架构减少 HTTP 请求
- ✅ localStorage 缓存减少重复请求
- ✅ CodeMirror 按需加载
- ✅ 事件委托减少监听器数量

### 优化建议

1. **图片处理**
   - 添加图片压缩
   - 实现懒加载
   - 使用 WebP 格式

2. **历史记录**
   - 实现分页加载
   - 添加图片缩略图
   - 定期清理旧记录

3. **节点渲染**
   - 使用虚拟滚动
   - 优化连接线绘制
   - 添加防抖处理

---

## 📚 代码规范

### 命名约定

- **变量**: camelCase (`currentMode`, `apiKey`)
- **常量**: UPPER_SNAKE_CASE (`API_TIMEOUT`)
- **函数**: camelCase (`loadConfigFile()`)
- **CSS 类**: kebab-case (`workspace`, `icon-btn`)
- **ID**: kebab-case (`view-canvas`, `node-layer`)

### 注释规范

```javascript
/**
 * 多行注释
 * 描述函数功能、参数、返回值
 * @param {string} url - The URL to fetch
 * @returns {Promise<Response>}
 */
async function fetchWithTimeout(url, options) {}

// 单行注释：解释代码意图
let timerInterval = null; // Timer handle
```

---

## 🔄 版本历史

### v1.0.0 (2025-12-26)
- ✨ 初始版本发布
- 🎨 画布模式实现
- 🔗 节点编辑器实现
- 🖼️ 历史画廊实现
- ⚙️ 配置管理器实现
- 🌐 BizyAir API 集成
- 🚀 路由系统集成
- ⏱️ 20 分钟超时配置

---

## 📞 支持和反馈

### 文档相关文件

- `启动说明.txt` - 快速启动指南
- `API超时配置说明.txt` - API 超时配置详解
- `README-PHP.md` - 本文档（技术详解）

### 获取帮助

1. 查看 **启动说明.txt** 快速上手
2. 阅读本文档了解技术细节
3. 检查浏览器控制台获取错误信息
4. 查看 **故障排除** 章节解决常见问题

---

## 📄 许可证

本项目仅供学习和个人使用。

---

## 🙏 致谢

- **BizyAir** - 提供 AI 视频生成 API
- **CodeMirror** - 优秀的代码编辑器
- **PHP** - 强大的后端语言
- **开源社区** - 各种工具和库

---

**文档更新日期**: 2025-12-26
**维护者**: BizyAIR Studio Team
**版本**: 1.0.0
