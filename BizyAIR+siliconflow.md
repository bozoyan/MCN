所有的<token>密钥，都调用系统变量SiliconCloud_API_KEY
export SiliconCloud_API_KEY="your_api_key"


## 文字对话请求-使用siliconflow 的 API 接口。
```shell
curl --request POST \
  --url https://api.siliconflow.cn/v1/chat/completions \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '
{
  "model": "Qwen/Qwen3-Coder-480B-A35B-Instruct",
  "messages": [
    {
      "role": "user",
      "content": "What opportunities and challenges will the Chinese large model industry face in 2025?"
    }
  ],
  "stream": false,
  "max_tokens": 4096,
  "enable_thinking": false,
  "thinking_budget": 4096,
  "min_p": 0.05,
  "stop": null,
  "temperature": 0.7,
  "top_p": 0.7,
  "top_k": 50,
  "frequency_penalty": 0.5,
  "n": 1,
  "response_format": {
    "type": "text"
  },
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "<string>",
        "description": "<string>",
        "parameters": {},
        "strict": false
      }
    }
  ]
}
'
```

```json 响应
{
  "id": "<string>",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "<string>",
        "reasoning_content": "<string>",
        "tool_calls": [
          {
            "id": "<string>",
            "type": "function",
            "function": {
              "name": "<string>",
              "arguments": "<string>"
            }
          }
        ]
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 123,
    "completion_tokens": 123,
    "total_tokens": 123
  },
  "created": 123,
  "model": "<string>",
  "object": "chat.completion"
}
```

## 图片生成 使用 BizyAIR-api 
Z-image 高清2K 批量文生图，一次 5 张。
```python
# Python 示例代码
import requests
import json

url = "https://api.bizyair.cn/w/v1/webapp/task/openapi/create"
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer YOUR_API_KEY"
}
data = {
      "web_app_id": 39808,
      "suppress_preview_output": False,
      "input_values": {
        "42:easy promptList.prompt_1": " 远景俯视跟拍，锈迹斑斑的老式机器人在荒芜金属废土中孤独踱步，蓝眼微光闪烁。沙尘弥漫的末世景象中，镜头缓缓下降跟随其沉重步伐。破败的高楼废墟背景烘托出绝望氛围，机器人踉跄的身影诠释着废弃文明中最后守望者的坚韧与孤寂。",
        "42:easy promptList.prompt_2": "中景侧拍推镜，机身破损的探险机器人在破败城市废墟中艰难前行，能源指示灯忽明忽暗。钢筋裸露的残垣断壁间，机械臂奋力拨开厚重碎石。镜头逐渐推进展现机器人执着神情，飞扬的尘土与扭曲金属构建成充满压迫感的绝望环境。",
        "42:easy promptList.prompt_3": "中景仰角定镜，锈蚀机器人蹲伏在废墟中，小心翼翼地用机械手指轻抚柔嫩荧光幼苗。翠绿新芽在灰暗环境中散发着柔和光芒，与机器人粗糙外表形成强烈对比。轻柔护持动作展现出久违的温柔，科技与生命的初次邂逅唤醒内心深处的守护本能。",
        "42:easy promptList.prompt_4": "二次元赛博朋克少女，蓝粉色挑染短发搭配机械耳饰，眼妆点缀荧光蓝纹路，身着露腰机能风套装，外搭全息投影披风（投射数据流光影），手持能量手枪，站在霓虹闪烁的未来都市街头，背景是悬浮车辆与全息广告牌，画面高对比度，冷调为主，科技感与酷飒感拉满",
        "42:easy promptList.prompt_5": "中景环绕镜头，破损机器人半跪于荧光植物旁，专注凝视着沐浴微光的奇异叶片。头部轻微摆动仔细检查每片叶子的状态，折射出重新激活的情感模块。温暖的荧光与冷峻的金属质感交织，科技理性与自然感性展开初次温柔对话。",
        "35:EmptyLatentImage.width": 1080,
        "35:EmptyLatentImage.height": 1920
      }
    }

response = requests.post(url, headers=headers, json=data)
result = response.json()
print("生成结果:", result)
```
