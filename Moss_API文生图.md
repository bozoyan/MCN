# MOSS 文生图

根据文本描述生成图像，支持长文本和文字渲染，适合海报设计、插画创作和视觉内容生成。可直接使用原始提示词生图，也可开启提示词增强，在同一次请求内先增强再生图。

Endpoint

POST `https://api.mosi.cn/v1/images/generations`

模型名称

`moss-image-sft-1.0`

1. ## 创建 API Key
   进入 [API Key 管理平台](https://platform.mosi.cn/app/api-keys/) ，创建 API Key，并保存为环境变量。不要把 API Key 写进客户端代码或提交到仓库。
   环境变量
   ```bash
   export MOSS_API_KEY='YOUR_API_KEY'
   ```
2. ## 准备请求输入
   填入文本描述、图片尺寸和模型 ID。目前仅支持一次生成一张图片，不支持流式输出。
   字段 类型 要求 说明
   - model: string 必填 模型 ID 默认：`"moss-image-sft-1.0"`
   - prompt: string 必填
   待生成图像的文本描述，非空字符串，最多 4000 字符。可通过「 [布局生图](https://platform.mosi.cn/docs/reference/layout-image-generation) 」指定文本和对象的位置、大小及排列关系。
  -  prompt_enhance: boolean 可选 默认 `true`
   是否在同一个 Image 任务内先增强提示词再生图。
   false 直接使用原始 prompt 生图。
   true 先增强提示词，再将完整增强文本用于生图。
  - size: string 可选 ,参考 `"1024x1024"`
   图片尺寸，格式为宽x高。每边 256–2048，且为 16 的倍数；总像素不超过 2097152。最大边是 2048 的图片比例尺寸。
   默认是1K 的分辨率尺寸，最大边1024；还有 1.5K 与 2K 两种，分别是1.5K最大边 1440 ；2K，最大边2048。
  - n: integer 可选
   生成图片数量，仅支持 1。
  - response_format: string  默认设置`"url"`
   仅支持 url，不支持 b64_json。
  - output_watermark: object 可选 默认设置 `{"enabled": false}`
   输出水印设置。 `enabled` 为布尔值，省略时默认开启可见水印；传 `{"enabled": false}` 关闭可见水印。
   请求体
   ```json
   {
     "model": "moss-image-sft-1.0",
     "prompt_enhance": true,
     "prompt": "一只橘猫坐在窗边，窗外是雨后的花园，柔和的自然光，温暖细腻的摄影风格。",
     "negative_prompt": "nsfw, worst quality, bad anatomy, watermark, jpeg artifact",
     "size": "1024x1024",
     "n": 1,
     "response_format": "url",
     "output_watermark": { "enabled": false }
   }
   ```
  
3. ## 发起图像生成请求
   向 `/v1/images/generations` 发起请求。生成完成后，接口返回 JSON。
   请求示例
   ```bash
   curl --max-time 900 -X POST "https://api.mosi.cn/v1/images/generations" \
     -H "Authorization: Bearer $MOSS_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
     "model": "moss-image-sft-1.0",
     "prompt_enhance": true,
     "prompt": "一只橘猫坐在窗边，窗外是雨后的花园，柔和的自然光，温暖细腻的摄影风格。",
     "negative_prompt": "nsfw, worst quality, bad anatomy, watermark, jpeg artifact",
     "size": "2048x2048",
     "n": 1,
     "response_format": "url",
     "output_watermark": {"enabled": false}
   }'
   ```
   示例超时为 900 秒，不代表固定服务端超时。
4. ## 获取图片结果
   成功后，从响应的 `data[0].url` 读取图片地址，可直接打开或下载 PNG。 `usage.generated_images` 、 `usage.output_width` 、 `usage.output_height` 分别表示实际生成张数、图片宽度和高度。
   请求示例
   ```bash
   # 将示例 URL 替换为 data[0].url
   curl --fail --location "https://example.com/generated-image.png" \
     --output image.png
   ```
5. ## 验证成功
   成功标志：拿到结果图片 URL，可查看或下载生成的 PNG 图片。


POST `https://api.mosi.cn/v1/images/generations`

布局生图接口，通过元素描述和边界框指定文本和对象的位置、大小及排列关系，引导模型生成复杂图文画面。请求字段、返回值及错误码同文生图页面一致。

## 布局 JSON 结构

布局 JSON 是 `prompt` 字段的输入内容。请将完整布局 JSON 序列化为字符串后传入，其他请求参数与 [文生图]一致。

字段 类型 说明

summary.caption: string

整体场景和风格。

items: array

各元素的类型（ `label` ）、描述（ `caption` ）、边界框（ `bbox` ），以及需要渲染的文字（ `text` ）。

bbox_format: string

设为 `"yxyx"` ，边界框按 `[y_min, x_min, y_max, x_max]` 排列。

bbox_coord_space: string

设为 `"abs_centralized"` ，使用相对于画布中心的像素坐标。坐标以画布中心为原点，x 轴向右递增，y 轴向下递增。1024×1024 画布的两个坐标轴范围均为 -512 至 512。对于宽 W、高 H 的画布，将左上角坐标转换为中心坐标时，x 减去 W/2，y 减去 H/2。

### 布局 JSON 示例

JSON

```json
{
  "summary": {
    "meta": ["poster"],
    "canvas": "single",
    "caption": "A minimalist travel poster with a cream background, a blue mountain illustration, and the title EXPLORE at the top."
  },
  "items": [
    {
      "label": "text",
      "caption": "Large dark-blue uppercase title centered at the top.",
      "text": "EXPLORE",
      "bbox": [-416, -384, -288, 384]
    },
    {
      "label": "object",
      "caption": "A flat blue mountain illustration in the lower center.",
      "bbox": [-192, -288, 384, 288]
    }
  ],
  "bbox_coord_space": "abs_centralized",
  "bbox_format": "yxyx"
}
```

