## BizyAIR 异步查询使用教程

## 适用场景[¶]

- **它是什么**: 异步查询模式允许你提交任务后立即获得一个 `requestId`或者`request_id` 并断开连接，随后通过主动轮询接口来查询任务的实时进度和最终结果。
- **它能解决的问题**: 避免客户端与服务端长时间保持 HTTP 连接；适用于客户端网络不稳定、无法维持长连接，或者无法提供公网回调地址（无法使用 WebHook）的场景。

快速判断是否适合使用

- 你的网络环境无法维持 60s+ 的长连接
- 你无法提供公网可达的回调 URL（即无法使用 WebHook）
- 你希望能非阻塞地提交任务，并按需查询进度

本教程将带你完成一次完整的异步查询流程：

1.  获取 API 指令
2.  启用异步模式并发起任务，拿到 `requestId`或者`request_id`
3.  任务完成后，使用 `requestId` 或者`request_id`获取最终的生成内容

---
异步工作流程
1. 用户在"API密钥设置"中开启异步API开关并保存
2. 任务提交时自动在 HTTP Header 中添加 X-Bizyair-Task-Async: enable
3. 收到 202 Accepted + requestId → 在"任务状态"选项卡显示任务ID
4. 静默等待5分钟 → 每10分钟轮询 detail 接口查状态
5. 状态变为 Success → 调用 outputs 接口获取视频URL → 显示在"响应结果"选项卡
6. 计时器正常运行，任务间隔保持15秒不变

兼容多种响应格式 (requestId / request_id / data.requestId /
  data.request_id)

## 异步任务交互流程

  1. 异步任务提交 → 响应结果选项卡出现紫色等待卡片（显示任务ID + 轮询按钮）
  2. 用户点击轮询 → 立即查询API状态 → 成功则卡片变绿色完成态并自动下载
  3. 后台5分钟等待的自动轮询完成后也会更新同一张卡片（不重复创建）
  4. 已获取到结果的卡片不再显示轮询按钮

## 前置准备[¶]

- 已获取 BizyAir API Key（ ）

---

## 步骤一：获取 API 指令[¶]

首先，你需要从 BizyAir 官网获取用于发起任务的 API 命令：

1.  登录 BizyAir 官网，进入 **AI 应用 (AI Apps)** 界面。
2.  选择并点击进入你想使用的 AI 应用。
3.  调整参数后，点击界面左上角的 **紫色 API 按钮**。
4.  在弹出的窗口中，选择 **Shell (curl)** 或其他语言，复制对应的 API 请求命令。

---

## 步骤二：发起异步任务[¶]

将步骤一中获取的 API 命令稍作修改，在 HTTP Header 中加入 `X-Bizyair-Task-Async: enable` 即可启用异步模式。

| 修改后的异步请求示例 |
| -------------------- |

```markdown
# Shell 示例代码 (注意加入了 X-Bizyair-Task-Async)

# 请确保已设置 BIZYAIR_API_KEY 环境变量，或者直接替换为您的 API Key

curl -s -X POST "https://api.bizyair.cn/w/v1/webapp/task/openapi/create" \
 -H "Content-Type: application/json" \
 -H "Authorization: Bearer ${BIZYAIR_API_KEY}" \
 -H "X-Bizyair-Task-Async: enable" \
 -d '{
"web_app_id": 38214,
"suppress_preview_output": false,
"input_values": {
"84:CLIPTextEncode.text": "A hyper-realistic environmental portrait of a forest ranger standing deep within an ...",
"88:KSampler.seed": 354884000907176,
"81:EmptySD3LatentImage.width": 1280,
"81:EmptySD3LatentImage.height": 1280
}
}'
```

成功后服务会立即返回 `202 Accepted` 与 `requestId`或者`request_id`，而不是等待任务完成：

| 响应示例 |
| -------- |

```json
{
  "requestId": "29f53793-12d3-4dd3-b2a8-4d9848e0c7da"
}
```


保存 requestId

请务必保存返回的 `requestId`或者`request_id`，它是你后续查询任务状态和结果的唯一凭证。

---

## 步骤三：获取异步任务生成内容

当步骤三中的状态变为 `Success` 时，调用“查询任务结果”接口来获取最终的图片或其他输出。

获取任务结果

```bash
curl -X GET "https://api.bizyair.cn/w/v1/webapp/task/openapi/outputs?requestId={requestId}" \
  -H "Authorization: Bearer ${BIZYAIR_API_KEY}"
```

### 结果解析

响应中的 `data.outputs` 数组包含了所有的生成结果：

| 任务成功完成 |
| ------------ |
```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "request_id": "YOUR_REQUEST_ID",
    "status": "Success",
    "outputs": [
      {
        "object_url": "https://storage.bizyair.cn/outputs/b4608cef-d19f-4ccb-9973-271c99887693_bc3ce67c427705dc2a79976801ea7691_ComfyUI_262556f6_00001_.png",
        "output_ext": ".png",
        "cost_time": 10775,
        "audit_status": 2,
        "error_type": "NOT_ERROR"
      }
    ]
  }
}
```

| 任务正在执行 |
| ------------ |

```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "request_id": "YOUR_REQUEST_ID",
    "status": "Running",
    "outputs": []
  }
}
```

| 任务执行失败 |
| ------------ |

```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "request_id": "YOUR_REQUEST_ID",
    "status": "Failed",
    "outputs": [
      {
        "error_type": "EXECUTION_ERROR",
        "error_message": "执行过程中发生错误"
      }
    ]
  }
}
```

- **`object_url`**: 生成文件的下载链接。请尽快下载并保存，该链接通常有时效性。
- **`audit_status`**: 审核状态（1:未审核, 2:通过, 3:不通过, 4:报错）。

---

## 附加：轮询任务状态

拿到 `requestId`或者`request_id` 后，你可以定期调用“查询任务状态”接口来检查任务是否完成。

查询任务状态

```bash
curl -X GET "https://api.bizyair.cn/w/v1/webapp/task/openapi/detail?requestId={requestId}" \
  -H "Authorization: Bearer ${BIZYAIR_API_KEY}"
```

### 响应解析

响应中的 `data.status` 字段代表了当前任务的状态：

排队状态响应示例

```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "type": "API",
    "status": "Queuing",
    "created_at": "2026-01-13 17:33:15",
    "updated_at": "2026-01-13 17:33:15",
    "expired_at": "2026-01-28 00:00:00",
    "queue_info": {
      "queue_count": -1
    },
    "cost_times": {},
    "group_id": 94
  }
}
```

运行状态响应示例

```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "type": "API",
    "status": "Running",
    "created_at": "2026-01-13 16:56:07",
    "updated_at": "2026-01-13 16:56:08",
    "executed_at": "2026-01-13 16:56:07",
    "expired_at": "2026-01-28 00:00:00",
    "cost_times": {},
    "group_id": 94
  }
}
```

成功状态响应示例

```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "type": "API",
    "status": "Success",
    "created_at": "2026-01-13 16:54:44",
    "updated_at": "2026-01-13 16:54:57",
    "executed_at": "2026-01-13 16:54:44",
    "ended_at": "2026-01-13 16:54:57",
    "expired_at": "2026-01-28 00:00:00",
    "cost_times": {
      "inference_cost_time": 10858,
      "running_cost_time": 13502,
      "total_cost_time": 13724,
      "real_cpu_cost_time": 408,
      "real_gpu_cost_time": 6587,
      "real_total_cost_time": 6995
    },
    "group_id": 94
  }
}
```

失败状态响应示例

```json
{
  "code": 20000,
  "message": "Ok",
  "status": true,
  "data": {
    "type": "API",
    "status": "Failed",
    "created_at": "2026-01-13 16:54:44",
    "updated_at": "2026-01-13 16:54:57",
    "executed_at": "2026-01-13 16:54:44",
    "ended_at": "2026-01-13 16:54:57",
    "expired_at": "2026-01-28 00:00:00",
    "error_message": "任务执行失败",
    "cost_times": {},
    "group_id": 94
  }
}
```

你需要根据 `status` 的值决定下一步操作：

| 状态值      | 含义                               | 建议操作                             |
| ----------- | ---------------------------------- | ------------------------------------ |
| `Queuing`   | **排队中**。任务正在等待资源调度。 | **继续轮询**。建议间隔 1-3 秒。      |
| `Preparing` | **准备中**。正在加载模型或环境。   | **继续轮询**。                       |
| `Running`   | **运行中**。任务正在生成中。       | **继续轮询**。                       |
| `Success`   | **成功**。任务已完成。             | **停止轮询**。跳转到步骤四获取结果。 |
| `Failed`    | **失败**。任务执行出错。           | **停止轮询**。查看响应中的错误信息。 |
| `Canceled`  | **已取消**。                       | **停止轮询**。                       |

轮询策略建议

建议设置一个合理的轮询间隔（例如 1-3 秒），避免过于频繁地请求。如果在 `Queuing` 状态，可以关注 `data.queueInfo` 了解排队情况。

---

## 附加：完整代码示例 (Python)

下面是一个使用 Python 串联整个异步查询流程的简单脚本：

async_task.py

```python
import time
import requests

API_KEY = "BIZYAIR_API_KEY" #从BizyAir官网获取的api-key
BASE_URL = "https://api.bizyair.cn/w/v1/webapp/task/openapi"

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

def create_task():
    url = f"{BASE_URL}/create"
    # 启用异步模式
    headers["X-Bizyair-Task-Async"] = "enable"

    payload = {
        "web_app_id": 38214,
        "input_values": {
            "84:CLIPTextEncode.text": "A hyper-realistic environmental portrait of a forest ranger standing deep within an ancient old-growth forest at early morning. The subject is framed from the waist up, surrounded by towering moss-covered trees with thick trunks and intricate bark textures rendered in extreme detail. Soft mist drifts between the trees, catching beams of golden sunrise light that filter through the dense canopy above. The ranger’s face shows natural skin texture, light freckles, and subtle lines shaped by years spent outdoors, with calm, observant eyes that reflect a deep connection to the wilderness. They wear a practical field jacket with visible fabric weave, weather stains, reinforced seams, and a slightly faded color from prolonged sun exposure. A leather strap from binoculars crosses their chest, showing creases, scratches, and age. Ferns, fallen leaves, and damp soil fill the foreground with rich micro-details, including dew droplets and tiny insects. Shot on an 85mm lens with shallow depth of field, sharp focus on facial features, natural color grading emphasizing greens and earth tones. The mood is serene, grounded, and respectful, portraying quiet guardianship and harmony between human presence and untouched nature.\n",
            "88:KSampler.seed": 354884000907176,
            "81:EmptySD3LatentImage.width": 1280,
            "81:EmptySD3LatentImage.height": 1280
        }
    }

    resp = requests.post(url, json=payload, headers=headers)

    response_data = resp.json()

    if isinstance(response_data, dict):
        # 成功情况
        request_id = response_data.get("requestId") or response_data.get("request_id")
        if not request_id:
             print(f"Error: No requestId in response: {response_data}")
        return request_id
    else:
        # 失败情况
        print(f"API Error: {response_data}")
        return None

def poll_status(request_id):
    url = f"{BASE_URL}/detail"
    # 查询状态不需要 Async Header
    if "X-Bizyair-Task-Async" in headers:
        del headers["X-Bizyair-Task-Async"]

    while True:
        resp = requests.get(url, params={"requestId": request_id}, headers=headers)
        print(resp.json())
        data = resp.json().get("data", {})
        status = data.get("status")

        print(f"当前状态: {status}")

        if status == "Success":
            return True
        elif status in ["Failed", "Canceled"]:
            print("任务失败或取消")
            return False

        time.sleep(2)  # 等待2秒后再次查询

def get_results(request_id):
    url = f"{BASE_URL}/outputs"
    resp = requests.get(url, params={"requestId": request_id}, headers=headers)
    outputs = resp.json().get("data", {}).get("outputs", [])

    for idx, out in enumerate(outputs):
        print(f"结果 {idx+1}: {out.get('object_url')}")

# 主流程
if __name__ == "__main__":
    req_id = create_task()
    if req_id:
        print(f"任务已提交，ID: {req_id}")
        if poll_status(req_id):
            get_results(req_id)
```

### 执行脚本

```text
python async_task.py
```

### 脚本输出示例

脚本输出示例

```bash
### 任务已提交，ID: 8fc91a86-9edc-44df-ac25-9dc08af06692
{'code': 20000, 'message': 'Ok', 'status': True, 'data': {'type': 'API', 'status': 'Queuing', 'created_at': '2026-01-14 10:53:35', 'updated_at': '2026-01-14 10:53:35', 'expired_at': '2026-01-29 00:00:00', 'queue_info': {'queue_count': -1}, 'cost_times': {}, 'group_id': 94}}

### 当前状态: Queuing
{'code': 20000, 'message': 'Ok', 'status': True, 'data': {'type': 'API', 'status': 'Preparing', 'created_at': '2026-01-14 10:53:35', 'updated_at': '2026-01-14 10:53:36', 'executed_at': '2026-01-14 10:53:36', 'expired_at': '2026-01-29 00:00:00', 'cost_times': {}, 'group_id': 94}}

### 当前状态: Preparing
{'code': 20000, 'message': 'Ok', 'status': True, 'data': {'type': 'API', 'status': 'Running', 'created_at': '2026-01-14 10:53:35', 'updated_at': '2026-01-14 10:53:38', 'executed_at': '2026-01-14 10:53:36', 'expired_at': '2026-01-29 00:00:00', 'cost_times': {}, 'group_id': 94}}

### 当前状态: Running
{'code': 20000, 'message': 'Ok', 'status': True, 'data': {'type': 'API', 'status': 'Running', 'created_at': '2026-01-14 10:53:35', 'updated_at': '2026-01-14 10:53:38', 'executed_at': '2026-01-14 10:53:36', 'expired_at': '2026-01-29 00:00:00', 'cost_times': {}, 'group_id': 94}}

### 当前状态: Running
{'code': 20000, 'message': 'Ok', 'status': True, 'data': {'type': 'API', 'status': 'Running', 'created_at': '2026-01-14 10:53:35', 'updated_at': '2026-01-14 10:53:38', 'executed_at': '2026-01-14 10:53:36', 'expired_at': '2026-01-29 00:00:00', 'cost_times': {}, 'group_id': 94}}

### 当前状态: Running
{'code': 20000, 'message': 'Ok', 'status': True, 'data': {'type': 'API', 'status': 'Success', 'created_at': '2026-01-14 10:53:35', 'updated_at': '2026-01-14 10:53:46', 'executed_at': '2026-01-14 10:53:36', 'ended_at': '2026-01-14 10:53:46', 'expired_at': '2026-01-29 00:00:00', 'cost_times': {'inference_cost_time': 9057, 'running_cost_time': 10104, 'total_cost_time': 10305, 'real_cpu_cost_time': 1410, 'real_gpu_cost_time': 6609, 'real_total_cost_time': 8019}, 'group_id': 94}}

### 当前状态: Success
结果 1: https://storage.bizyair.cn/outputs/f73ce5b9-e226-42db-a1d6-e085ef878d7a_9fb1dd56f1a1f8d29b35096d87f37f36_ComfyUI_a6f720ed_00001_.png
```

