# BizyAIR Studio

> 基于 PHP 和原生 JavaScript 的单页应用，专为 BizyAir API 设计的多媒体内容创作工具

## 🚀 快速开始

### 1. 启动服务器

```bash
# 使用启动脚本
./start.sh

# 或手动启动
php -S 127.0.0.1:8004 index.php
```

### 2. 访问应用

在浏览器中打开：http://127.0.0.1:8004

### 3. 设置 API 密钥

点击右上角设置按钮，输入您的 BizyAir API 密钥

---

## ✨ 核心特性

- 🎨 **画布模式** - 手绘涂鸦、图片编辑、视频生成
- 🔗 **节点模式** - 可视化工作流编辑器
- 🖼️ **画廊管理** - 历史记录和作品管理
- ⚙️ **配置管理** - JSON 配置文件可视化管理
- 🌐 **API 集成** - 完整的 BizyAir API 支持（20分钟超时）
- 🚀 **零依赖部署** - 单文件架构，无需额外配置

---

## 📚 文档导航

### 🌟 推荐文档

| 文档 | 说明 | 适合人群 |
|------|------|----------|
| **[DOCS-INDEX.md](DOCS-INDEX.md)** | 📖 文档导航中心 | **所有用户** |
| **[启动说明.txt](启动说明.txt)** | 🚀 5分钟快速上手 | 新手用户 |
| **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** | ⚡ 开发者速查手册 | 开发者 |
| **[README-PHP.md](README-PHP.md)** | 📖 完整技术文档 | 深入学习 |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | 🏗️ 架构设计详解 | 架构师 |

### 📋 文档清单

```
MCN/
├── README-MAIN.md          # 本文件（项目总览）
├── DOCS-INDEX.md          # 📖 文档导航中心（从这里开始）
├── README-PHP.md          # 📖 完整技术文档（732行）
├── ARCHITECTURE.md        # 🏗️ 架构设计详解（397行）
├── QUICK-REFERENCE.md     # ⚡ 快速参考手册（394行）
├── 启动说明.txt           # 🚀 快速启动指南
├── API超时配置说明.txt     # ⏱️  API超时配置详解
└── index.php              # 主应用文件（1846行）
```

---

## 🎯 使用场景

### 场景 1：手绘生成视频
1. 打开画布模式
2. 手绘草图或粘贴图片
3. 输入提示词
4. 点击 GENERATE
5. 等待结果（最多20分钟）

### 场景 2：配置工作流
1. 打开配置管理器
2. 选择或创建配置
3. 编辑参数
4. 导入到节点模式
5. 运行工作流

### 场景 3：批量处理
1. 准备多个配置文件
2. 保存到 `json/` 目录
3. 在配置管理器中切换
4. 依次导入和执行

---

## 🏗️ 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **后端** | PHP 7.4+ | 内置服务器，REST API |
| **前端** | 原生 JavaScript ES6+ | 无框架依赖 |
| **编辑器** | CodeMirror 5.65.2 | 代码编辑 |
| **样式** | 原生 CSS3 | 自定义深色主题 |
| **API** | BizyAir API | 视频生成服务 |

---

## 📁 项目结构

```
index.php (1846行)
├── PHP 后端 (1-120行)
│   ├── 路由处理
│   └── API 端点
│
├── HTML + CSS (121-760行)
│   ├── 样式系统
│   └── 页面布局
│
└── JavaScript (761-1846行)
    ├── 全局状态
    ├── 画布操作
    ├── 节点编辑器
    └── API 集成
```

**详细架构**: 查看 [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 🔌 API 端点

### 本地 API (PHP)

```bash
GET  /api/configs           # 获取配置列表
GET  /api/config/{name}     # 读取配置
POST /api/config/{name}     # 保存配置
DELETE /api/config/{name}   # 删除配置
```

### BizyAir API

```javascript
// 创建任务（20分钟超时）
POST https://api.bizyair.cn/w/v1/webapp/task/openapi/create

// 检查状态（20分钟超时）
GET https://api.bizyair.cn/w/v1/webapp/task/{id}/status
```

**完整 API 文档**: 查看 [README-PHP.md](README-PHP.md)

---

## 🛠️ 开发指南

### 添加新功能

1. **添加视图模式**
   - HTML 结构：`<div id="view-newmode">`
   - CSS 样式：`#view-newmode { }`
   - JavaScript：`function switchMode()`

2. **添加 API 端点**
   ```php
   elseif ($path[1] === 'newendpoint') {
       // 处理逻辑
   }
   ```

**开发指南**: 查看 [README-PHP.md](README-PHP.md) → 开发指南

---

## 🐛 故障排除

### 常见问题

**Q: 服务器启动失败**
```bash
# 查找占用端口的进程
lsof -i :8004
# 杀死进程
kill -9 <PID>
```

**Q: API 调用超时**
- 已配置 20 分钟超时
- 查看 [API超时配置说明.txt](API超时配置说明.txt)

**Q: 中文文件名乱码**
- PHP 已处理编码转换
- 确保使用 UTF-8 编码

**完整故障排除**: 查看 [README-PHP.md](README-PHP.md) → 故障排除

---

## ⚙️ 配置

### 全局配置

```javascript
// API 超时（第 707 行）
const API_TIMEOUT = 1200 * 1000; // 20分钟

// Web App ID
let currentWebAppId = 39419;
```

### CSS 变量

```css
--bg-color: #1e1e1e;
--accent: #4dabf7;
--font-mono: 'SF Mono', monospace;
```

**完整配置说明**: 查看 [QUICK-REFERENCE.md](QUICK-REFERENCE.md)

---

## 📊 性能指标

| 指标 | 目标 | 实际 |
|------|------|------|
| 首次加载 | < 2秒 | ~1.5秒 |
| API 响应 | < 20分钟 | 5-15分钟 |
| 历史加载 | < 1秒 | ~0.5秒 |
| 节点渲染 | < 500ms | ~300ms |

---

## 🔒 安全注意事项

- ✅ API 密钥存储在 localStorage（仅客户端）
- ✅ 20 分钟超时防止长时间挂起
- ✅ JSON 验证防止注入攻击
- ⚠️ 生产环境应实施 HTTPS
- ⚠️ 配置 CORS 限制允许的域名

**安全最佳实践**: 查看 [README-PHP.md](README-PHP.md) → 安全注意事项

---

## 📈 版本历史

### v1.0.0 (2025-12-26)
- ✨ 初始版本发布
- 🎨 四种工作模式
- 🌐 BizyAir API 集成
- ⏱️ 20 分钟超时配置
- 🚀 路由系统集成
- 📚 完整文档体系

---

## 📞 获取帮助

### 查看文档

1. **首次使用？** → [DOCS-INDEX.md](DOCS-INDEX.md)
2. **快速上手？** → [启动说明.txt](启动说明.txt)
3. **开发参考？** → [QUICK-REFERENCE.md](QUICK-REFERENCE.md)
4. **深入学习？** → [README-PHP.md](README-PHP.md)
5. **理解架构？** → [ARCHITECTURE.md](ARCHITECTURE.md)

### 调试技巧

```javascript
// 查看控制台日志
console.log('Debug:', variable);

// 查看网络请求
// 开发者工具 → Network 标签

// 查看服务器日志
tail -f /tmp/php-server.log
```

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

<div align="center">

**[⬆ 返回顶部](#bizyair-studio)**

**[📖 查看文档中心](DOCS-INDEX.md)**

**[🚀 快速开始](#-快速开始)**

</div>

---

**项目版本**: 1.0.0
**最后更新**: 2025-12-26
**维护团队**: BizyAIR Studio Team
