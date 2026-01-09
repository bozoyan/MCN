## Sora2文生视频 接口API 提交
```javascript
const response = await fetch('https://api.bizyair.cn/w/v1/webapp/task/openapi/create', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_API_KEY'
  },
  body: JSON.stringify({
      "web_app_id": 42921,
      "suppress_preview_output": true,
      "input_values": {
        "57:BizyAir_Sora_V2_T2V_API.prompt": "@yanbo1984 这个男人去爬山，男人正视相机镜头",
        "57:BizyAir_Sora_V2_T2V_API.aspect_ratio": "9:16"
      }
    })
});

const result = await response.json();
console.log('生成结果:', result);
```

## Sora2图生视频 接口API提交
```javascript
// JavaScript 示例代码
const response = await fetch('https://api.bizyair.cn/w/v1/webapp/task/openapi/create', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_API_KEY'
  },
  body: JSON.stringify({
      "web_app_id": 42936,
      "suppress_preview_output": true,
      "input_values": {
        "18:LoadImage.image": "https://bizyair-prod.oss-cn-shanghai.aliyuncs.com/inputs/20251028/O41IXAyOpJpWDJlTXhUbicKXjMkxcOdz.png",
        "6:CR Prompt Text.prompt": "图片中的一个女子，粉色连衣裙，高清HD，4k，TikTok热门自拍风格，专业博主自拍视频。全程微笑，亲切，动作流畅，拍摄角度专业，出色的广告大片和电影灯光。",
        "54:BizyAir_Sora_V2_I2V_API.aspect_ratio": "9:16"
      }
    })
});

const result = await response.json();
console.log('生成结果:', result);
```

## 视频数据返回数据
```json
{
  "type": "API",
  "status": "Success",
  "created_at": "2025-12-17 21:27:43",
  "updated_at": "2025-12-17 21:29:10",
  "executed_at": "2025-12-17 21:27:43",
  "running_at": "2025-12-17 21:27:45",
  "ended_at": "2025-12-17 21:29:10",
  "expired_at": "2026-01-01 00:00:00",
  "request_id": "e55ddf64-b3a0-4835-854d-d89fsf246f41",
  "outputs": [
    {
      "object_url": "https://storage.bizyair.cn/outputs/3101c8f0-8020-4382-9f41-1707632d7627_e56ec5327ad0b4ed0e790a0ce91de4c5_ComfyUI_d2e83b2e_00001_.mp4",
      "output_ext": ".mp4",
      "cost_time": 84119,
      "audit_status": 2,
      "error_type": "NOT_ERROR"
    }
  ],
  "cost_times": {
    "inference_cost_time": 84576,
    "running_cost_time": 86480,
    "total_cost_time": 86505,
    "real_cpu_cost_time": 1470,
    "real_gpu_cost_time": 82206,
    "real_total_cost_time": 83676
  }
}
```