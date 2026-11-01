`POST https://ark.cn-beijing.volces.com/api/v3/embeddings/multimodal`  [ ](https://api.volcengine.com/api-explorer/?action=CreateContentsGenerationsTasks&data=%7B%7D&groupName=%E8%A7%86%E9%A2%91%E7%94%9F%E6%88%90API&query=%7B%7D&serviceCode=ark&version=2024-01-01)[运行](https://api.volcengine.com/api-explorer/?action=EmbeddingsMultimodal&data=%7B%7D&groupName=%E5%90%91%E9%87%8F%E5%8C%96%20API&query=%7B%7D&serviceCode=ark&version=2024-01-01)
当您需通过语义来处理视频、图像和文本，如以图搜图、语义检索等，可以调用多模态向量化服务，将视频、图像和文本转化为向量，来分析其语义关系。本文为您提供接口的参数详细说明供您查阅。

```mixin-react
return (<Tabs>
<Tabs.TabPane title="快速入口" key="C8u4908B"><RenderMd content={` <span>![图片](https://portal.volccdn.com/obj/volcfe/cloud-universal-doc/upload_2abecd05ca2779567c6d32f0ddc7874d.png =20x) </span>[模型列表](https://www.volcengine.com/docs/82379/1330310?lang=zh#ee5ec35c)       <span>![图片](https://portal.volccdn.com/obj/volcfe/cloud-universal-doc/upload_a5fdd3028d35cc512a10bd71b982b6eb.png =20x) </span>[模型计费](https://www.volcengine.com/docs/82379/1099320#%E6%96%87%E6%9C%AC%E5%90%91%E9%87%8F%E6%A8%A1%E5%9E%8B)       <span>![图片](https://portal.volccdn.com/obj/volcfe/cloud-universal-doc/upload_afbcf38bdec05c05089d5de5c3fd8fc8.png =20x) </span>[API Key](https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey?apikey=%7B%7D)
 <span>![图片](https://portal.volccdn.com/obj/volcfe/cloud-universal-doc/upload_f45b5cd5863d1eed3bc3c81b9af54407.png =20x) </span>[接口文档](https://www.volcengine.com/docs/82379/1523520)       <span>![图片](https://portal.volccdn.com/obj/volcfe/cloud-universal-doc/upload_1609c71a747f84df24be1e6421ce58f0.png =20x) </span>[常见问题](https://www.volcengine.com/docs/82379/1359411)      <span>![图片](https://portal.volccdn.com/obj/volcfe/cloud-universal-doc/upload_bef4bc3de3535ee19d0c5d6c37b0ffdd.png =20x) </span>[开通模型](https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&OpenTokenDrawer=false)
`}></RenderMd></Tabs.TabPane>
<Tabs.TabPane title="鉴权说明" key="MXNMn1Vz"><RenderMd content={`本接口支持 API Key 鉴权，详见[鉴权认证方式](https://www.volcengine.com/docs/82379/1298459)。
> 如需使用 Access Key 来鉴权，推荐使用 SDK 的方式，具体请参见 [SDK概述](https://www.volcengine.com/docs/82379/1302007)。
`}></RenderMd></Tabs.TabPane></Tabs>);
```


---


<span id="RxN8G2nH"></span>
## 请求参数 
> 跳转 [响应参数](#L9tzcCyD)

<span id="BJ5XLFqM"></span>
### 请求体

---


**model** `string` `必选`
您需要调用的模型的 ID （Model ID），[开通模型服务](https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&OpenTokenDrawer=false)，并[查询 Model ID](https://www.volcengine.com/docs/82379/1330310) 。
您也可通过 Endpoint ID 来调用模型，获得限流、计费类型（前付费/后付费）、运行状态查询、监控、安全等高级能力，可参考[获取 Endpoint ID](https://www.volcengine.com/docs/82379/1099522)。

---


**input** `object[]` `必选`
需要向量化的内容列表。列表元素支持文本信息和图片信息以及视频信息。
不同模型的支持情况不同，详情请查询[文档](https://www.volcengine.com/docs/82379/1409291?lang=zh)。

属性
**文本信息 ** `object`
输入给模型转化为向量的内容，文本内容部分。

属性

---


input.**type ** `string` `必选`
输入内容的类型，此处应为 `text`。

---


input.**text ** `string` `必选`
输入给模型的文本内容。
单条文本以 utf\-8 编码，长度不超过模型的最大输入 token 数。


---


**图片信息** `object`
输入给模型转化成向量的内容，图片信息部分。
传入图片需要满足的条件请参见[文档](https://www.volcengine.com/docs/82379/1409291?lang=zh#a256838b)。

属性

---


input.**type ** `string` `必选`
输入内容的类型，此处应为 `image_url`。

---


input.**image_url ** `object` `必选`
输入给模型的图片对象。

属性

---


input.image_url.**url ** `string` `必选`
图片信息，可以是图片URL或图片Base64编码。

* 图片URL：请确保图片URL可被访问。
* Base64编码：请遵循此格式`data:image/{图片格式};base64,{图片Base64编码}`。



---


**视频信息** `object`
输入给模型转化成向量的内容，视频信息部分。
:::tip
传入视频需要满足以下条件：

* 格式：`.mp4`、`.avi`、 `.mov`，视频格式需小写。
* 传入 Base64 编码时使用：[Base64 编码输入](https://www.volcengine.com/docs/82379/1362931?lang=zh#477e51ce)。 
* 单视频文件需在 50MB 以内。 
* 暂不支持对视频文件中的音频信息进行理解。 


:::
---


input.**type ** `string` `必选`
输入内容的类型，此处应为 `video_url`。

---


input.**video_url** ** ** `object` `必选`
输入给模型的视频对象。

属性
input.video_url.**url ** `string` `必选`
支持传入视频链接或视频的Base64编码。具体使用请参见[文档](https://www.volcengine.com/docs/82379/1362931?lang=zh#477e51ce)。



---


**encoding_format** `string / null ` `默认值 float`
取值范围： `float`、`base64`、`null`。
embedding 返回的格式。

---


**dimensions** `integer` `默认值 2048`
取值范围： `1024` 或 `2048`。
用于指定输出的向量维度。

---


**instructions** `string`
推理提示词，用户传入时直接使用，未传入时按输入模态生成默认值。详情请参见 [配置instructions](https://www.volcengine.com/docs/82379/1409291?lang=zh#96894c46)。

---


**sparse_embedding** `object`
稀疏向量开关配置，仅纯文本输入支持配置此字段。
取值范围：

* type="disabled"：仅输出稠密向量，不输出稀疏向量；
* type="enabled"：同时输出稠密向量和稀疏向量。

<span id="L9tzcCyD"></span>
## 响应参数
> 跳转 [请求参数](#RxN8G2nH)


---


**id ** `string`
本次请求的唯一标识 。

---


**model** `string`
本次请求实际使用的模型名称和版本。

---


**created** `integer`
本次请求创建时间的 Unix 时间戳（秒）。

---


**object** `string`
固定为 `list`。

---


**data** `object`
本次请求的算法输出内容。

属性

---


data.**embedding** `float[]`
对应内容的向量化结果。

---


data.**sparse_embedding**`array`
稀疏向量，仅sparse_embedding.type="enabled"时返回；每个成员为` {"index": 维度索引, "value": 非零值}`结构，仅返回非零元素。

---


data.**object** `string`
固定为 `embedding`。


---


**usage** `object`
本次请求的 token 用量。

属性

---


usage.**prompt_tokens** `integer`
输入内容 token 数量。

---


usage.**total_tokens** `integer`
本次请求消耗的总 token 数量（输入 + 输出）。

---


usage.**prompt_tokens_details ** `object`
输入的内容使用 token 量的细节信息。

属性

---


usage.prompt_tokens_details.**text_tokens ** `integer`
输入内容中，文本内容对应的 token 量，以及视频内容时间轴产生的 token 量。
为保证模型效果，当图片或视频传入时，会生成少量的预设文本 token，产生额外的 **text_tokens**。

---


usage.prompt_tokens_details.**image_tokens ** `integer`
输入内容中，图片内容以及视频内容抽帧图片对应的 token 量。


&nbsp;


