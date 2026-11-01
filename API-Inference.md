# 魔搭社区 API-Inference

## API示例代码
```python
import requests
import time
import json
from PIL import Image
from io import BytesIO

base_url = 'https://api-inference.modelscope.cn/'
api_key = '$MODELSCOPE_API_KEY' # ModelScope Token ，或者环境变量中调用

common_headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json",
}

response = requests.post(
    f"{base_url}v1/images/generations",
    headers={**common_headers, "X-ModelScope-Async-Mode": "true"},
    data=json.dumps({
        "model": 'Qwen/Qwen-Image-2.1-Turbo', # 底座大模型 ModelScope Model-Id, required
        "prompt": "给图中的狗戴上一个生日帽", # 大部分模型建议使用英文提示词效果较好,长度小于2000
        "loras": "bozoyan/Q-FEIFEI", # loRA模型 optional lora(s) <lora-repo-id>
        """
        LoRA(s) Configuration:
        - for Single LoRA: 
        "loras": "<lora-repo-id>"
        - for Multiple LoRAs: 
        "loras": {"<lora-repo-id1>": 0.6, "<lora-repo-id2>": 0.4}
        - Upto 6 LoRAs, all weight-coeffients must sum to 1.0，多LoRA权重总和须为1.0，最多6个
        """
        "size":"2048x2048", # 生成图像分辨率大小 [512x512, 2048x2048]
        "seed":-1, # 随机种子
        "guidance":1.0, # 提示词引导系数
        "steps": 8, # 注意 Qwen/Qwen-Image-2.1-Turbo 的步数设置为 8，Qwen/Qwen-Image-2.1 的步数是 50
        "image_url": [
            "https://modelscope.oss-cn-beijing.aliyuncs.com/Dog.png"
        ]
        # 待编辑图片的url地址（或者编码过的base64数据），该参数只适用于支持图片编辑的模型,确保公网可访问（或者编码过的base64数据）
        # Multiple-image edit example (uncomment to use):
        # "prompt": "写实风格，生成一张图片，图一中的狗，去追图二中的飞盘",
        # "image_url": [
        #     "https://modelscope.oss-cn-beijing.aliyuncs.com/Dog.png",
        #     "https://modelscope.oss-cn-beijing.aliyuncs.com/Frisbee.png"
        # ]
    }, ensure_ascii=False).encode('utf-8')
)

response.raise_for_status()
task_id = response.json()["task_id"]

while True:
    result = requests.get(
        f"{base_url}v1/tasks/{task_id}",
        headers={**common_headers, "X-ModelScope-Task-Type": "image_generation"},
    )
    result.raise_for_status()
    data = result.json()

    if data["task_status"] == "SUCCEED":
        image = Image.open(BytesIO(requests.get(data["output_images"][0]).content))
        image.save("result_image.png")
        break
    elif data["task_status"] == "FAILED":
        print("Image Generation Failed.")
        break

    time.sleep(5)
```

## Base64 图片输入支持

- Base64 本地图片编码工具函数#
对于具备视觉理解能力的图像编辑模型，如果需要使用本地图片而非线上URL，可以通过以下工具函数将本地图片转为Base64编码：
``` python
import os
import mimetypes
import base64

def image_to_data_url(image_path):
    if not os.path.isfile(image_path):
        raise FileNotFoundError(f"Image file not found: {image_path}")

    with open(image_path, "rb") as f:
        image_data = f.read()

    mime_type, _ = mimetypes.guess_type(image_path)

    if mime_type is None or not mime_type.startswith('image/'):
        mime_type = 'image/png'

    base64_encoded = base64.b64encode(image_data).decode('utf-8')
    return f"data:{mime_type};base64,{base64_encoded}"
```
对于图像编辑模型，输入的图片建议使用线上托管的图像URL地址。如果需要使用本地文件，可以使用上方的image_to_data_url函数对本地图片进行Base64编码，并将编码后的数据作为image_url传递给模型。一个典型的调用方式是：
``` python
        # input as base64
        "image_url": [
           image_to_data_url("path/to/local/image.jpg")
        ]
```
