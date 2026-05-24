## API Key 
API Key 调用 API 密钥管理器 或者 BIZYAIR_API_KEY 变量的数据，包括 txt 文本内的批量keys 数据

## 轮询获取url数据
优先从 data 内部取 status 和 outputs，能正确匹配到 "Success" 和视频 URL。

## LTX2.3-文生视频
### 请求参数代码 
界面上只需要保留展示方式display（宽屏与竖屏的radio 按钮选项）、提示词prompt 多行文本框 两个参数输入项
```
import requests

url = "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/text-to-video"
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer ${BIZYAIR_API_KEY}"
}
payload = {
  "seed": -1,
  "display": "horizontal",
  "resolution": "1080P",
  "duration": 5,
  "prompt": "Slow gentle camera movement, seawater flowing softly with slight ripples, schools of small tropical fish swimming freely, swinging tails naturally, corals swaying slightly with current, smooth dynamic motion, realistic underwater quiet atmosphere, no rigid static effect, low saturation, authentic muted natural color grading."
}

response = requests.post(url, json=payload, headers=headers)
response.raise_for_status()
print(response.json())
```
#### 请求参数说明
种子seed	number	取值范围：1 ~ 2147483647	（默认：-1，固定住不用填写）
展示方式display	string	枚举值：horizontal、vertical	（宽屏与竖屏的radio 按钮选项）
视频分辨率resolution	string	枚举值：	1080P（默认：1080P，固定住不用填写）
视频时长 duration		number	取值范围：5 （默认：5，固定住不用填写）
提示词prompt	string	必填		文本长度限制：1 - 2500

使用方法：在请求头中携带 X-BizyAir-Log-Mask-Fields，指定需要脱敏的字段，多个字段用英文逗号分隔。
```
Content-Type: application/json
Authorization: Bearer ${BIZYAIR_API_KEY}
X-BizyAir-Log-Mask-Fields: prompt, image_urls
```

### 响应字段
```
{
  "request_id": "4569bb94-1d30-417a-a987-9715de1e2633"
}
```
在成功提交请求后，您会收到类似的信息反馈。
这是一个异步任务提交的成功回执，作用是告诉你：“请求已接收，任务正在排队执行中”。
request_id	string	请求ID，用于后续查询任务状态。

### 查询结果
分别将下方的 ${BIZYAIR_API_KEY}、${REQUEST_ID}，
更换成 API Key 以及任务单号（request_id），

```
import requests

url = f"https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/${REQUEST_ID}"
headers = {
    "Authorization": "Bearer ${BIZYAIR_API_KEY}"
}

response = requests.get(url, headers=headers)
response.raise_for_status()
print(response.json())
```

### 响应示例
通过调用 BizyAir 查询接口，在任务生成完成、成功生成内容之后，服务器最终返回的结果回执。
```
{
  "request_id": "4569bb94-1d30-417a-a987-9715de1e2633",
  "status": "Success",
  "message": null,
  "executed_at": "2026-04-15 13:32:32",
  "ended_at": "2026-04-15 13:42:32",
  "outputs": {
    "videos": [
      "https://storage.bizyair.cn/outputs/38u3vfcpy9wxs_9ae34515b02c29afc353dc09490c78b6_video_LTX_2.3_i2v_574b52ee_00001_.mp4"
    ]
  }
}
```



## LTX2.3-图生视频
### 请求参数代码 
界面上只需要保留展示方式display（宽屏与竖屏的radio 按钮选项）、提示词prompt 多行文本框 、上传图像
image 三个参数输入项，其中上传图像必须是远程的 URL 图像，本地图像需要上传到 bizyair 的 OSS 上获取到 url，可以多图，至少上传1张图片，还可以是其他url 图片。
```
import requests

url = "https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/ltx-2-3/image-to-video"
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer ${BIZYAIR_API_KEY}"
}
payload = {
  "prompt": "Slow gentle camera movement, seawater flowing softly with slight ripples, schools of small tropical fish swimming freely, swinging tails naturally, corals swaying slightly with current, smooth dynamic motion, realistic underwater quiet atmosphere, no rigid static effect.",
  "image": [
    "https://bizyair-prod.oss-cn-shanghai.aliyuncs.com/inputs/20260514/vgXeuJN4pWlqFoi5ccmrm9bl9bN1iEap.png?uploads="
  ],
  "duration": 5,
  "resolution": "1080P",
  "display": "horizontal",
  "seed": -1
}

response = requests.post(url, json=payload, headers=headers)
response.raise_for_status()
print(response.json())
```
#### 请求参数说明
- 种子 seed	
number	取值范围：1 ~ 2147483647	（默认：-1，固定住不用填写）
- 展示方式 display	
string	枚举值：horizontal、vertical	（宽屏与竖屏的radio 按钮选项）
- 视频分辨率 resolution	
string	枚举值：	1080P（默认：1080P，固定住不用填写）
- 视频时长 duration		
number	取值范围：5 （默认：5，固定住不用填写）
- 提示词 prompt	
string	必填		文本长度限制：1 - 2500
- 上传图像 image
array 图片数组，需要时 url 地址。本地上传的图片，或者其他url 图片。必填


使用方法：在请求头中携带 X-BizyAir-Log-Mask-Fields，指定需要脱敏的字段，多个字段用英文逗号分隔。
```
Content-Type: application/json
Authorization: Bearer ${BIZYAIR_API_KEY}
X-BizyAir-Log-Mask-Fields: prompt, image_urls
```

### 响应字段
```
{
  "request_id": "4569bb94-1d30-417a-a987-9715de1e2633"
}
```
在成功提交请求后，您会收到类似的信息反馈。
这是一个异步任务提交的成功回执，作用是告诉你：“请求已接收，任务正在排队执行中”。
request_id	string	请求ID，用于后续查询任务状态。

### 查询结果
分别将下方的 ${BIZYAIR_API_KEY}、${REQUEST_ID}，
更换成 API Key 以及任务单号（request_id），

```
import requests

url = f"https://api.bizyair.cn/x/v1/modelzoo/tasks/openapi/${REQUEST_ID}"
headers = {
    "Authorization": "Bearer ${BIZYAIR_API_KEY}"
}

response = requests.get(url, headers=headers)
response.raise_for_status()
print(response.json())
```

### 响应示例
通过调用 BizyAir 查询接口，在任务生成完成、成功生成内容之后，服务器最终返回的结果回执。
```
{
  "request_id": "4569bb94-1d30-417a-a987-9715de1e2633",
  "status": "Success",
  "message": null,
  "executed_at": "2026-04-15 13:32:32",
  "ended_at": "2026-04-15 13:42:32",
  "outputs": {
    "videos": [
      "https://storage.bizyair.cn/outputs/38u3vfcpy9wxs_9ae34515b02c29afc353dc09490c78b6_video_LTX_2.3_i2v_574b52ee_00001_.mp4"
    ]
  }
}
```

### 文件上传
这项操作用于资源上传，支持上传图片、音频、视频等资源至 BizyAir 服务器。
上传后的文件将可以作为输入资源使用到您运行的任务当中。

1. 获取上传凭证与参数
调用获取上传凭证接口，服务端会返回本次上传所需的 OSS 信息与临时 STS 凭证。
```
import requests

url = "https://api.bizyair.cn/x/v1/upload/token"
params = {
    "file_name": "example.webp",
    "file_type": "inputs"
}
headers = {
    "Authorization": "Bearer ${BIZYAIR_API_KEY}"
}

response = requests.get(url, params=params, headers=headers)
response.raise_for_status()
print(response.json())
```
2. 使用 阿里云 OSS 简单上传
使用上一步返回的 endpoint、bucket、region、object_key 与 STS 凭证将本地文件上传到 OSS。更详细信息参考：阿里云 OSS 简单上传、BizyAir 上传教程。
```
import os
import alibabacloud_oss_v2 as oss

def upload_to_oss(region, endpoint, bucket, object_key, file_path, access_key_id, access_key_secret, security_token):
    os.environ["ALIBABA_CLOUD_ACCESS_KEY_ID"] = access_key_id
    os.environ["ALIBABA_CLOUD_ACCESS_KEY_SECRET"] = access_key_secret
    os.environ["ALIBABA_CLOUD_SECURITY_TOKEN"] = security_token

    cfg = oss.config.load_default()
    cfg.credentials_provider = oss.credentials.EnvironmentVariableCredentialsProvider()
    cfg.region = region[4:] if region.startswith("oss-") else region
    cfg.endpoint = endpoint

    client = oss.Client(cfg)
    return client.put_object_from_file(
        oss.PutObjectRequest(bucket=bucket, key=object_key),
        file_path,
    )
```
注意：

有些 SDK 需要去掉 region 的 oss- 前缀，如 oss-cn-shanghai → cn-shanghai。
建议同时设置 region 与 endpoint，以返回的 endpoint 为准。
3. 提交输入资源
当 OSS 上传成功后，提交本次输入资源，便于后续任务直接引用。
```
import requests

url = "https://api.bizyair.cn/x/v1/input_resource/commit"
payload = {
    "name": "example.webp",
    "object_key": "inputs/20250911/abc123.webp"
}
headers = {
    "Authorization": "Bearer ${BIZYAIR_API_KEY}",
    "Content-Type": "application/json"
}

response = requests.post(url, json=payload, headers=headers)
response.raise_for_status()
print(response.json())
```
4. 查询 inputs 列表（可选）
这项操作可以查询您的查询 inputs 列表，

您可以这样校验上传的内容。
```
import requests

url = "https://api.bizyair.cn/x/v1/input_resource"
params = {
    "current": 1,
    "page_size": 20
}
headers = {
    "Authorization": "Bearer ${BIZYAIR_API_KEY}"
}

response = requests.get(url, params=params, headers=headers)
response.raise_for_status()
print(response.json())
```
