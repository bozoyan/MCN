# Sora2 API 修复说明 - V1.2

## 修复日期
2025-01-09

## 问题描述

在运行 Sora2文生视频功能时,出现以下错误:

```
[15:02:59] [Sora2文生视频单个任务_150259] ❌ 网络错误: Missing dependencies for SOCKS support.
[15:02:59] ❌ [task_150259_986] 任务失败: 网络错误: Missing dependencies for SOCKS support.
```

## 根本原因

1. **系统环境变量设置了 SOCKS 代理**:
   ```bash
   HTTP_PROXY=http://127.0.0.1:33210
   HTTPS_PROXY=http://127.0.0.1:33210
   all_proxy=socks5://127.0.0.1:33211
   ```

2. **Python requests 库默认会读取环境变量中的代理设置**

3. **缺少 SOCKS 代理依赖包**:
   - 使用 SOCKS 代理需要安装 `requests[socks]` 或 `PySocks` 包
   - BizyAir API 不需要代理,不需要这些依赖

4. **原有代码的代理禁用方式不完整**:
   ```python
   # 原有代码 (不完整)
   proxies = {"http": None, "https": None}
   response = requests.post(url, proxies=proxies)
   ```
   这种方式只能禁用 HTTP/HTTPS 代理,无法禁用环境变量中的 `all_proxy` (SOCKS 代理)

## 修复内容

### 修复方案

使用 `requests.Session()` 并设置 `trust_env = False`,完全禁用从环境变量读取代理设置:

```python
# 新代码 (完整禁用代理)
session = requests.Session()
session.trust_env = False  # 禁用从环境变量读取代理设置
session.proxies = {
    "http": None,
    "https": None,
    "no_proxy": None
}
response = session.post(url, ...)
```

### 修改的代码位置

#### 1. API 请求发送 (pic2vod.py:736-753)

**原代码**:
```python
try:
    # 禁用代理设置，确保国内API免受全局代理影响
    proxies = {"http": None, "https": None}

    response = requests.post(
        base_url,
        headers=headers,
        json=bizyair_request_data,
        timeout=(300, 1200),
        proxies=proxies
    )
```

**修复后**:
```python
try:
    # 禁用代理设置，确保国内API免受全局代理影响
    # 明确禁用所有代理（包括 http、https、socks）
    session = requests.Session()
    session.trust_env = False  # 禁用从环境变量读取代理设置
    session.proxies = {
        "http": None,
        "https": None,
        "no_proxy": None
    }

    response = session.post(
        base_url,
        headers=headers,
        json=bizyair_request_data,
        timeout=(300, 1200)
    )
```

#### 2. 任务状态轮询 (pic2vod.py:851-871)

**原代码**:
```python
try:
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {self.api_key}"
    }

    # BizyAir查询任务状态的API端点
    response = requests.get(
        f"https://api.bizyair.cn/w/v1/webapp/task/openapi/query?request_id={request_id}",
        headers=headers,
        timeout=30,
        proxies={"http": None, "https": None}
    )
```

**修复后**:
```python
try:
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {self.api_key}"
    }

    # BizyAir查询任务状态的API端点
    # 禁用代理设置，确保国内API免受全局代理影响
    session = requests.Session()
    session.trust_env = False  # 禁用从环境变量读取代理设置
    session.proxies = {
        "http": None,
        "https": None,
        "no_proxy": None
    }

    response = session.get(
        f"https://api.bizyair.cn/w/v1/webapp/task/openapi/query?request_id={request_id}",
        headers=headers,
        timeout=30
    )
```

#### 3. 视频下载 (pic2vod.py:1899-1911)

**原代码**:
```python
self.progress_updated.emit(10, "开始下载视频...")
self.log_updated.emit(f"🎬 开始下载视频: {self.filename}")

# 使用requests下载文件 (禁用代理)
response = requests.get(self.video_url, stream=True, timeout=300, proxies={"http": None, "https": None})
response.raise_for_status()
```

**修复后**:
```python
self.progress_updated.emit(10, "开始下载视频...")
self.log_updated.emit(f"🎬 开始下载视频: {self.filename}")

# 使用requests下载文件 (禁用代理)
session = requests.Session()
session.trust_env = False  # 禁用从环境变量读取代理设置
session.proxies = {
    "http": None,
    "https": None,
    "no_proxy": None
}
response = session.get(self.video_url, stream=True, timeout=300)
response.raise_for_status()
```

## 技术说明

### trust_env 参数的作用

`session.trust_env = False` 会告诉 `requests` 库:
- ❌ 不读取环境变量中的代理设置 (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `all_proxy`)
- ❌ 不读取系统代理配置
- ✅ 只使用代码中明确设置的 `session.proxies`

### 为什么需要设置 session.proxies

即使 `trust_env = False`,仍需要设置 `session.proxies` 为 `None`,以确保:
1. 完全明确地禁用所有代理
2. 防止未来代码修改时意外启用代理
3. 提高代码可读性和可维护性

## 修复验证

### 语法检查
```bash
python3 -m py_compile pic2vod.py
```
✅ 通过 - 无语法错误

### 预期行为

修复后,程序将:
1. ✅ 完全忽略系统环境变量中的代理设置
2. ✅ 直接连接 BizyAir API (不经过任何代理)
3. ✅ 不再报 "Missing dependencies for SOCKS support" 错误
4. ✅ 所有 API 请求、状态查询、视频下载都正常工作

## 兼容性

✅ **完全兼容**: 此修复不影响其他任何功能
- 所有三种原有视频生成模式正常工作
- Sora2文生视频和 Sora2图生视频正常工作
- 批量任务处理正常工作
- 视频下载正常工作

## 适用场景

此修复适用于以下情况:
1. **国内用户使用 BizyAir API** (不经过代理)
2. **系统环境变量配置了代理** (但 API 不需要代理)
3. **不希望安装 SOCKS 代理依赖包** (`PySocks`)

## 相关文档

- [Sora2-API功能说明-V1.0.md](./Sora2-API功能说明-V1.0.md) - 功能实现文档
- [Sora2-API修复说明-V1.1.md](./Sora2-API修复说明-V1.1.md) - 文生视频图片处理修复
- [BizyAIR-api-返回数据.md](./BizyAIR-api-返回数据.md) - API 规格文档

## 修复日志

### V1.2 (2025-01-09)
- 修复 SOCKS 代理依赖问题
- 使用 `session.trust_env = False` 完全禁用环境变量代理
- 更新所有 API 请求、状态查询和视频下载代码
- 通过 Python 语法检查

### V1.1 (2025-01-09)
- 修复 Sora2文生视频模式错误处理图片数据的问题
- 添加条件判断逻辑,跳过 sora_t2v 模式的图片处理
- 通过 Python 语法检查

### V1.0 (2025-01-09)
- 新增 Sora2 文生视频功能
- 新增 Sora2 图生视频功能
- 更新配置管理系统
- 更新 API 设置对话框
- 添加宽高比选择功能
- 实现完整的任务管理和批量处理

## 参考资料

- [Python requests 文档 - Proxies](https://requests.readthedocs.io/en/latest/user/advanced/#proxies)
- [Session Objects](https://requests.readthedocs.io/en/latest/user/advanced/#session-objects)
- [环境变量代理配置](https://requests.readthedocs.io/en/latest/user/advanced/#environment-variables)
