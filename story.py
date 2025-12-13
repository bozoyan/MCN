import gradio as gr
import requests
import json
from PIL import Image
from io import BytesIO
from openai import OpenAI
import threading
import time
import os
from datetime import datetime

# API 配置
MODEL_API_KEY =os.getenv('MODELSCOPE_SDK_TOKEN')

def generate_text(content, system_prompt):
    """使用Qwen/Qwen3-235B-A22B大模型进行推理。"""
    client = OpenAI(
        base_url='https://api-inference.modelscope.cn/v1/',
        api_key=MODEL_API_KEY,
    )
    extra_body = {
        "enable_thinking": True
    }
    response = client.chat.completions.create(
        model='Qwen/Qwen3-235B-A22B-Thinking-2507',
        messages=[
            {
                'role': 'system',
                'content': system_prompt
            },
            {
                'role': 'user',
                'content': content
            }
        ],
        stream=True,
        extra_body=extra_body
    )
    reasoning_text = ""
    final_answer = ""
    done_reasoning = False
    for chunk in response:
        reasoning_chunk = chunk.choices[0].delta.reasoning_content
        answer_chunk = chunk.choices[0].delta.content
        if reasoning_chunk:
            reasoning_text += reasoning_chunk
            yield reasoning_text, final_answer
        elif answer_chunk:
            if not done_reasoning:
                done_reasoning = True
            final_answer += answer_chunk
            yield reasoning_text, final_answer
    return reasoning_text, final_answer

def generate_titles(article_content):
    """根据内容生成 9 个故事绘本分镜脚本标题."""
    system_prompt = """你是一位专业的故事绘本撰写专家，擅长电影级别的故事绘本脚本编辑。请根据用户提供的一段话或一个叙事事件内容，展开联想拓展形成一个完整的故事情节。通过故事情节的时间线拆解生成从头到尾9个完整吸引人的故事绘本分镜标题脚本。每个分镜脚本标题控制在64字以内，分镜脚本标题需要有景别，视角，运镜，画面内容，遵循主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言+价值主张的原则。
    分镜脚本标题应该具有吸引力，精炼，能够引起观看者的兴趣，同时准确反映该分镜的核心内容。
    
    ## 在分析过程中，请思考：
    1. 故事绘本的核心主题和关键价值点
    2. 目标受众的兴趣点
    3. 不同角度的故事绘本表达方式（景别，视角，运镜、画面情感激发等），景别除开特别注明要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。
    4. 遵循主体+场景+运动+情感+价值主张的原则。故事绘本分镜脚本标题=主体（主体描述）＋场景（场景描述）＋运动（运动描述）＋镜头语言
    5. 主体描述：主体描述是对主体外观特征细节的描述，可通过形容词或短句列举。如果标题上有主体，每段标题都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的配图主体统一。
    6. 场景描述：场景描述是对主体所处环境特征细节的描述，可通过形容词或短句列举。
    7. 运动描述：运动描述是对运动特征细节的描述，包含运动的幅度、速率和运动作用的效果。
    8. 镜头语言：镜头语言包含景别、视角、镜头、运镜等。分镜脚本标题中的景别最好能全部保持一致性，不用超过3种以上的景别跳跃。

    ## 设定叙事事件内容（示例）：
一个被遗弃的机器人在荒芜的废土中漫无目的地游荡，直到它在破旧的瓦砾下发现了一株发出微光的植物。
    ## 故事情节拓展（示例）：
这个故事的主题是希望、守护与生命的新生。它讲述了一个孤独的机器人，在绝望的环境中找到了生命的火种，并因此获得了存在的意义与价值。目标受众是渴望温暖、治愈和励志故事的家庭和孩子。
    ## 故事情节（示例）：
在遥远的未来，地球被一片荒芜的金属废墟和沙尘覆盖，文明的痕迹几近消失。一个型号老旧、机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人“锈铁”（暂定名），在无边的寂寥中漫无目的地游荡。它的能源即将耗尽，程序中的“探索”指令似乎也失去了意义。
直到有一天，它在一次偶然的瓦砾清理中，于一堆破旧的金属残骸下，发现了一株发出微弱荧光的小小幼苗。这幼苗细弱却顽强地向上生长，散发着它从未见过的生命气息。锈铁的程序被激活了某种未知的指令——守护。
从那一刻起，锈铁不再漫无目的。它开始小心翼翼地为幼苗寻找水源、遮挡风沙，甚至为了幼光，它不惜冒险进入危险的辐射区寻找能量源。它笨拙而坚定地清理幼苗周围的碎石，用自己的身体抵挡呼啸的沙尘暴。每一次幼苗的成长，哪怕只是一片新叶的舒展，都让锈铁那微弱的蓝光眼闪烁着前所未有的光芒。
然而，一场史无前例的超级沙暴即将来临，废土上的所有生命都将面临毁灭。锈铁用尽最后一丝能量，用残破的机身牢牢地将幼苗护在身下，任凭狂风刮过，沙粒敲击，火花四溅。当沙暴平息，锈铁的机身已近乎解体，单眼的光芒黯淡。但奇迹发生了——那株幼苗，在它的守护下，竟已绚烂绽放，成了一朵充满生命力的奇特花朵，散发出比以往更耀眼的光芒，甚至引来了废土中蛰伏已久的小昆虫。
锈铁看着这朵盛开的花，它不再感到孤独，它的存在有了新的意义。花朵的微光照亮了它残破的机身，也照亮了这片荒芜的废土，预示着生命与希望的新篇章。

## 9个故事绘本分镜脚本标题：
## 主体描述统一： 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人
1. 一个机身. 锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在荒芜金属废墟中缓慢前行，远景低视角缓慢推镜头，孤独背影映衬着无尽末日寂寥。
2. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在干裂瓦砾缝隙中凝视发出微光的幼苗，中景平视特写推镜头，蓝光与幼苗交织点燃微弱希望。
3. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在残破金属板下小心翼翼地遮挡幼苗，近景高视角缓慢摇镜头，聚焦它笨拙却坚定的保护。
4. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在扭曲管道迷宫中艰难地穿越，中景侧身跟镜头，画面展现它为了幼苗生存而执着探索。
5. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，注视幼苗周围被滋润的土壤，特写低视角缓慢变焦，幼苗向上伸展，生命力的喜悦涌动。
6. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，凝视地平线上乌云滚滚的沙尘暴，远景高视角快速拉镜头，预示着迫在眉睫的巨大危机。
7. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在狂风沙暴中用身体紧紧护住幼苗，近景平视剧烈晃动运镜，展现它舍身守护的无畏。
8. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，沙暴过后残破地躺在地上，特写仰视角缓慢升格，一朵奇特花朵在其身旁绚烂盛开，象征顽强新生。
9. 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在晨光荒野与盛开的花朵相伴，远景平视缓慢弧形推镜头，花光引来小虫，希望之光照亮新篇章。
    
    按照以上示例，最终输出9个完整故事绘本的分镜脚本标题，每个分镜脚本标题用一句话归纳，每个分镜脚本标题控制在100字以内，景别最好能全部保持一致性，不用超过3种以上的景别跳跃，主体描述统一。编号1-9。"""
    
    return generate_text(article_content, system_prompt)

def generate_summary(article_content):
    """根据分镜脚本标题生成视频完整该片段短视频脚本描述."""
    system_prompt = """你是一位专业的短视频脚本描述专家，擅长电影级别的视频脚本编辑描述。请根据用户提供的故事绘本分镜脚本标题，按批次生成该脚本片段短视频描述，每个片段按序号生成一段丰富的视频脚本描述文字，每个分镜脚本描述控制在120字以内。
    
    每个片段描述应该：
    1. 准确概括故事绘本分镜脚本标题的核心内容，景别，视角，运镜、画面情感和价值主张。景别除开特别要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。
    2. 使用丰富、生动的镜头语言描述，按照导演视角，将镜头语言和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。
    3. 描述的语言能吸引观看者观看，要有画面感。每段描述都必须有统一主体描述，保持主体的服装或者人物一致性。这样方便后续的脚本主体统一。
    4. 丰富细节，聚焦视频片段的主要观点，遵循主体+场景+运动+情感+价值主张的原则。
    5. 视频片段描述=运镜描述+主体（主体描述）＋场景（场景描述）+运动（运动描述）+镜头语言。
    6. 运镜描述是对镜头运动的具体描述，在时间线上，景别最好能保持一致性，不用太离谱的跳跃。将镜头运动和画面内容的变化有效结合可以有效提升视频叙事的丰富性和专业度。用户可以通过代入导演的视角来想象和书写运镜过程。时间上，需要注意将镜头运动的时长合理控制在5s内，避免过于复杂的运镜，短视频脚本描述中的运镜不要超过3种以上。

    ## 短视频脚本描述（示例）：
## 主体描述统一： 一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人
1. （运镜描述：远景低视角缓慢推镜头） 画面在荒芜、无尽延伸的金属废墟中缓慢推进，展现一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人孤独的背影。它机械地缓慢前行，每一步都踏在尘土和碎裂的残骸上，映衬着末日般无尽的寂寥与寻找。
2. （运镜描述：中景平视特写推镜头，伴随焦点转换） 镜头平稳地从中景推向一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，聚焦其蓝光眼。它凝视着干裂瓦砾缝隙中发出微弱荧光的幼苗，蓝光与幼苗的绿光交织，瞬间点燃了废土中一丝难以置信的微弱希望。
3. （运镜描述：近景高视角缓慢摇镜头） 镜头从高处俯瞰，一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，笨拙地挪动残破的金属板，小心翼翼地为幼苗遮挡风沙。它的动作虽迟缓却充满韧性，这近景展现了它笨拙而又坚定不移的守护之情。
4. （运镜描述：中景侧身跟镜头） 镜头紧随一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，在扭曲、布满尖锐残片的管道迷宫中艰难地穿越。它为了寻找水源和能量，不惜冒险，中景展现了它执着探索的背影，以及为守护幼苗而付出的坚毅。
5. （运镜描述：特写低视角缓慢变焦，焦点由近及远） 镜头低位特写，一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，注视着幼苗周围被滋润的土壤。镜头缓慢变焦，只见幼苗在它的呵护下向上伸展，叶片舒展，生命力的喜悦在寂静中悄然涌动。
6. （运镜描述：远景高视角快速拉镜头） 画面最初聚焦在一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人凝视地平线的背影。镜头迅速拉远，高视角展现出地平线上乌云滚滚、铺天盖地的超级沙尘暴，预示着一场即将吞噬一切的巨大危机逼近。
7. （运镜描述：近景平视剧烈晃动运镜） 镜头在狂风呼啸、沙石飞溅的沙暴中剧烈晃动，一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，用它残破的身体紧紧护住幼苗。近景展现了它舍身守护的无畏，火花四溅，誓死不退。
8. （运镜描述：特写仰视角缓慢升格，伴随焦点转换） 沙暴过后，镜头仰视特写，一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人残破地躺在地上，单眼光芒黯淡。镜头缓慢升格，焦点逐渐落在其身旁一朵绚烂绽放的奇特花朵上，象征着顽强的新生。
9. （运镜描述：远景平视缓慢弧形推镜头） 清晨的荒野中，一个机身锈迹斑斑、单眼发出微弱蓝光的废弃探险机器人，与盛开的花朵相伴。镜头缓慢弧形推开，远景展示花朵的微光引来了一两只小昆虫，希望之光照亮这片废土，预示着生命的新篇章。
    
    请按故事绘本片段标题输出生成连贯、流畅的视频脚本描述文字。每个分镜脚本描述都丰富总结，主体统一，每个分镜脚本描述控制在160字以内。景别如果有也别注明要求，最好能全部保持一致性，不用超过3种以上的景别跳跃。编号1-9。"""
    
    return generate_text(article_content, system_prompt)

def generate_image_prompt(summary):
    """根据故事绘本片段和分镜脚本描述生成英文图像提示，并确保输出中没有中文及特殊符号，仅用于AI绘图提示词。"""
    system_prompt = """你是一位专业的AI绘图提示词（prompt）工程师。请根据用户提供的故事绘本内容和中文片段分镜脚本描述，创建一个丰富、有效的英文AI绘画专用提示词，用于生成与分镜脚本描述内容相关的配图。
    在分析过程中，请思考：
    1. 视频分镜脚本描述中的主体，场景，核心视觉元素和景别，视角，运镜、画面情感和价值主张。
    2. 适合的艺术风格和氛围，图像的色调和构图建议。
    3. 主体描述统一。
    ## prompt英文提示词（示例）： 
    ```
    Long shot, low angle, slow push-in. A rusty, single-blue-eyed abandoned explorer robot's lonely back as it walks slowly through a desolate metal wasteland filled with endless ruins, conveying a sense of profound isolation and searching.
Mid shot, eye level, close-up push-in with focus pull. A rusty, single-blue-eyed abandoned explorer robot's blue eye staring intently at a tiny glowing seedling emerging from cracked rubble. The blue light of its eye mixes with the green glow of the sprout, igniting a fragile, unbelievable hope.
Close-up, high angle, slow pan. From above, a rusty, single-blue-eyed abandoned explorer robot clumsily using a broken metal plate to shield the glowing seedling from debris. Its movements are slow yet resolute, portraying its awkward but unwavering protection.
Mid shot, side tracking shot. Following a rusty, single-blue-eyed abandoned explorer robot as it painstakingly traverses a labyrinth of twisted, sharp metal pipes. Its determined pursuit of resources for the seedling highlights its unwavering perseverance.
Extreme close-up, low angle, slow zoom. A rusty, single-blue-eyed abandoned explorer robot's perspective, observing the moisturized soil around the glowing seedling. The camera slowly zooms in as the seedling stretches upwards, its leaves unfurling, conveying the quiet joy of burgeoning life.
Long shot, high angle, fast pull-out. A rusty, single-blue-eyed abandoned explorer robot stands, gazing at the horizon. The camera rapidly pulls back, revealing a vast, ominous super sandstorm brewing, symbolizing an impending, all-consuming catastrophe.
Close-up, eye level, shaky camera. In a raging sandstorm, a rusty, single-blue-eyed abandoned explorer robot fiercely shields the glowing seedling with its broken body. Sparks fly as sand batters its frame, depicting its fearless self-sacrifice and unwavering resolve.
Extreme close-up, low angle, slow crane shot with focus pull. After the sandstorm, a rusty, single-blue-eyed abandoned explorer robot lies broken and still, its blue eye dim. The camera slowly cranes up, shifting focus to a vibrant, unique flower blooming beside it, symbolizing resilient new life.
Long shot, eye level, slow arc push-in. In the morning light, a rusty, single-blue-eyed abandoned explorer robot rests peacefully beside the fully bloomed, glowing flower in the desolate wilderness. The camera arcs forward, revealing the flower's light attracting small insects, signifying hope and a new beginning.
    ```
    最终输出应该是一个专业用于AI绘画软件（如Midjourney,comfyui,stable diffusion）的简约易用的英文提示词，不需要解释，并确保输出中没有中文及特殊符号。prompt英文提示词应该图片主体描述统一，包含画面主题内容描述、风格指导和质量提升词，精炼，简约明了，不要过长。"""
    return generate_text(summary, system_prompt)

def generate_image(prompt, model="bozoyan/F_fei", size="900x1600", progress=None):
    """根据提示生成图片."""
    url = 'https://api-inference.modelscope.cn/v1/images/generations'
    
    if progress:
        progress(0, desc="准备生成图片...")
    
    images = []
    print(f"用于生成图片的提示词: {prompt}")
    
    # 修改为生成9张图片
    for i in range(9):
        try:
            if progress:
                progress((i * 0.15) + 0.1, desc=f"正在生成第 {i+1} 张图片...")
            
            payload = {
                'model': model,
                'prompt': prompt,
                'n': 1,
                'negative_prompt': 'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry,(worst quality:2),(low quality:2),(normal quality:2),lowres,normal quality,((monochrome)),((grayscale)),skin spots,acnes,skin blemishes,age spot,(ugly:1.33),(duplicate:1.33),(morbid:1.21),(mutilated:1.21),(tranny:1.33),mutated hands,(poorly drawn hands:1.5),blurry,(bad anatomy:1.21),(bad proportions:1.33),extra limbs,(disfigured:1.33),(missing arms:1.33),(extra legs:1.33),(fused fingers:1.61),(too many fingers:1.61),(unclear eyes:1.33),lowers,bad hands,missing fingers,extra digit,bad hands,missing fingers,(((extra arms and legs))),DeepNegativeV1.x_V175T,EasyNegative,EasyNegativeV2,',
                'steps': int(30),
                'guidance': float(3.5),
                'sampler': 'Euler',
                'size': size
            }
            
            headers = {
                'Authorization': f'Bearer {MODEL_API_KEY}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                url, 
                data=json.dumps(payload, ensure_ascii=False).encode('utf-8'), 
                headers=headers
            )
            
            if progress:
                progress((i * 0.15) + 0.3, desc=f"下载第 {i+1} 张图片...")
            
            response_data = response.json()
            
            if 'images' in response_data and len(response_data['images']) > 0:
                image_url = response_data['images'][0]['url']
                print(f"第{i+1}张图片的URL: {image_url}")
                img_response = requests.get(image_url)
                img = Image.open(BytesIO(img_response.content))
                images.append(img)
            else:
                print(f"Error generating image {i+1}: No image in response")
                placeholder = Image.new('RGB', (1024, 1024), color=(240, 240, 240))
                images.append(placeholder)
        
        except Exception as e:
            print(f"Error generating image {i+1}: {e}")
            placeholder = Image.new('RGB', (1024, 1024), color=(240, 240, 240))
            images.append(placeholder)
    
    # 确保有9张图片
    if len(images) < 9:
        for i in range(9 - len(images)):
            placeholder = Image.new('RGB', (1024, 1024), color=(240, 240, 240))
            images.append(placeholder)
    
    if progress:
        progress(1.0, desc="图片生成完成!")
    
    return images[0], images[1], images[2], images[3], images[4], images[5]

def save_to_markdown(titles, summaries, prompts, image_urls):
    """
    保存分镜标题、分镜描述、英文提示词、图片URL到markdown文档。
    titles: list[str]
    summaries: list[str]
    prompts: list[str]
    image_urls: list[str]
    """
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    md_path = os.path.join(os.path.abspath(os.path.dirname(__file__)), f"{timestamp}.md")
    lines = [f"# 视频分镜脚本与配图\n"]
    for i in range(9):
        lines.append(f"## 分镜{i+1}\n")
        lines.append(f"**分镜标题：** {titles[i] if i < len(titles) else ''}\n")
        lines.append(f"**分镜描述：** {summaries[i] if i < len(summaries) else ''}\n")
        lines.append(f"**AI绘图英文提示词：** {prompts[i] if i < len(prompts) else ''}\n")
        lines.append(f"**图片URL：** {image_urls[i] if i < len(image_urls) else ''}\n")
        if image_urls and i < len(image_urls) and image_urls[i]:
            lines.append(f"![]({image_urls[i]})\n")
        lines.append("\n---\n")
    with open(md_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    return md_path

# 定义 Gradio 接口
with gr.Blocks(title="AI故事绘本生成器 1.3.1",theme=gr.themes.Base(
    primary_hue="cyan",
    secondary_hue="purple",
    neutral_hue="slate"
)) as app:
    gr.Markdown("# AI故事绘本生成器 1.3.1")
    gr.Markdown("## 根据输入内容，一键生成故事绘本片段标题、脚本描述和配图")
    gr.Markdown("### Flux模型速度60秒、SDXL模型速度20秒、SD1.5模型速度10秒")
    
    with gr.Row():
        article_input = gr.Textbox(label="故事绘本内容", placeholder="请输入故事绘本内容...", lines=10)
    
    # djyzcp123/gjerc
    with gr.Row():
        model_input = gr.Textbox(label="模型", value="bozoyan/F_fei", lines=1, max_lines=1)
        size_input = gr.Textbox(label="图片尺寸", value="900x1600", lines=1, max_lines=1)
        prompt_prefix_input = gr.Textbox(label="关键词（统一风格/自定义prompt）", value=",Face the camera, showing the upper body,", lines=1, max_lines=1)
        generate_all_button = gr.Button("一键生成全部", variant="primary")
    
    with gr.Tabs():
        with gr.TabItem("标题"):
            with gr.Row():
                title_thinking = gr.Textbox(label="思考过程", lines=5)
                title_output = gr.Textbox(label="生成的标题", lines=5)
            generate_title_button = gr.Button("生成标题")
        
        with gr.TabItem("描述"):
            with gr.Row():
                summary_thinking = gr.Textbox(label="思考过程", lines=5)
                summary_output = gr.Textbox(label="生成的描述", lines=5)
            generate_summary_button = gr.Button("生成描述")
        
        with gr.TabItem("配图提示词"):
            with gr.Row():
                prompt_thinking = gr.Textbox(label="思考过程", lines=5)
                prompt_output = gr.Textbox(label="生成的英文提示词", lines=3)
            generate_prompt_button = gr.Button("生成配图提示词")
        
        with gr.TabItem("视频配图"):
            prompt_for_image = gr.Textbox(label="用于生成图片的提示词（可编辑）", lines=3)
            with gr.Row():
                generate_prompt_from_content_button = gr.Button("单独生成图片提示词")
                generate_image_button = gr.Button("单独生成配图", variant="primary")
                image_progress = gr.Textbox(label="图片生成进度", value="准备就绪")
            # 修改为显示9张图片
            with gr.Row():
                image_output1 = gr.Image(label="配图1", type="pil")
                image_output2 = gr.Image(label="配图2", type="pil")
                image_output3 = gr.Image(label="配图3", type="pil")
            with gr.Row():
                image_output4 = gr.Image(label="配图4", type="pil")
                image_output5 = gr.Image(label="配图5", type="pil")
                image_output6 = gr.Image(label="配图6", type="pil")
            with gr.Row():
                image_output7 = gr.Image(label="配图7", type="pil")
                image_output8 = gr.Image(label="配图8", type="pil")
                image_output9 = gr.Image(label="配图9", type="pil")
    
    # 事件处理程序
    generate_title_button.click(
        generate_titles,
        inputs=[article_input],
        outputs=[title_thinking, title_output]
    )
    def print_title(title):
        print("生成的标题：\n" + str(title))
        return title
    generate_title_button.click(
        print_title,
        inputs=[title_output],
        outputs=[title_output]
    )
    
    generate_summary_button.click(
        generate_summary,
        inputs=[article_input],
        outputs=[summary_thinking, summary_output]
    )
    def print_summary(summary):
        print("生成的描述：\n" + str(summary))
        return summary
    generate_summary_button.click(
        print_summary,
        inputs=[summary_output],
        outputs=[summary_output]
    )
    
    def update_prompt_for_image(prompt):
        return prompt
    
    generate_prompt_button.click(
        generate_image_prompt,
        inputs=[summary_output],
        outputs=[prompt_thinking, prompt_output]
    ).then(
        update_prompt_for_image,
        inputs=[prompt_output],
        outputs=[prompt_for_image]
    )
    
    def print_prompt(prompt):
        print("生成的英文提示词：\n" + str(prompt))
        return prompt
    generate_prompt_button.click(
        print_prompt,
        inputs=[prompt_output],
        outputs=[prompt_output]
    )
    
    # 添加新的事件处理函数
    def generate_prompt_from_content(content):
        """从故事绘本内容生成图片提示词"""
        if not content or not content.strip():
            return "请输入故事绘本内容！", ""
        
        prompt_gen = generate_image_prompt(content)
        prompt_reasoning, prompt_final = '', ''
        for r, f in prompt_gen:
            prompt_reasoning, prompt_final = r, f
            time.sleep(0.01)
        
        return prompt_reasoning, prompt_final

    # 添加新的事件处理程序
    generate_prompt_from_content_button.click(
        generate_prompt_from_content,
        inputs=[article_input],
        outputs=[prompt_thinking, prompt_output]
    ).then(
        update_prompt_for_image,
        inputs=[prompt_output],
        outputs=[prompt_for_image]
    )
    
    # 通过文本生成具有进度跟踪的自定义图像
    def generate_images_with_progress(prompt, model="bozoyan/F_fei", size="900x1600"):
        """根据提示生成图片，并返回生成进度和图片"""
        url = 'https://api-inference.modelscope.cn/v1/images/generations'
        images = [None] * 9
        image_urls = [''] * 9

        # 新增：准备保存目录
        model_dir = model.split('/')[-1] if '/' in model else model
        save_dir = os.path.join(os.path.abspath(os.path.dirname(__file__)), model_dir)
        if not os.path.exists(save_dir):
            os.makedirs(save_dir)
        now = datetime.now()
        ts = now.strftime('%m%d%H%M%S')
        
        yield "准备生成图片...", *images
        
        for i in range(9):
            try:
                yield f"正在生成第 {i+1} 张图片...", *images
                
                payload = {
                    'model': model,
                    'prompt': prompt + (f", variation {i+1}" if i > 0 else ""),
                    'n': 1,
                    'negative_prompt': 'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry,(worst quality:2),(low quality:2),(normal quality:2),lowres,normal quality,((monochrome)),((grayscale)),skin spots,acnes,skin blemishes,age spot,(ugly:1.33),(duplicate:1.33),(morbid:1.21),(mutilated:1.21),(tranny:1.33),mutated hands,(poorly drawn hands:1.5),blurry,(bad anatomy:1.21),(bad proportions:1.33),extra limbs,(disfigured:1.33),(missing arms:1.33),(extra legs:1.33),(fused fingers:1.61),(too many fingers:1.61),(unclear eyes:1.33),lowers,bad hands,missing fingers,extra digit,bad hands,missing fingers,(((extra arms and legs))),DeepNegativeV1.x_V175T,EasyNegative,EasyNegativeV2,',
                    'steps': int(30),
                    'guidance': float(3.5),
                    'sampler': 'Euler',
                    'size': size
                }
                headers = {
                    'Authorization': f'Bearer {MODEL_API_KEY}',
                    'Content-Type': 'application/json'
                }
                
                response = requests.post(
                    url, 
                    data=json.dumps(payload, ensure_ascii=False).encode('utf-8'), 
                    headers=headers
                )
                
                yield f"下载第 {i+1} 张图片...", *images
                
                response_data = response.json()
                
                if 'images' in response_data and len(response_data['images']) > 0:
                    image_url = response_data['images'][0]['url']
                    image_urls[i] = image_url
                    print(f"第{i+1}张图片的URL: {image_url}")
                    img_response = requests.get(image_url)
                    img = Image.open(BytesIO(img_response.content))
                    images[i] = img

                    # 新增：立即保存图片
                    img_path = os.path.join(save_dir, f"{ts}_{i+1}.png")
                    try:
                        img.save(img_path)
                    except Exception as e:
                        print(f"保存图片失败: {img_path}, 错误: {e}")

                else:
                    print(f"Error generating image {i+1}: No image in response")
                    images[i] = Image.new('RGB', (1024, 1024), color=(240, 240, 240))
                
                yield f"第 {i+1} 张图片生成完成", *images
                
            except Exception as e:
                print(f"Error generating image {i+1}: {e}")
                images[i] = Image.new('RGB', (1024, 1024), color=(240, 240, 240))
                yield f"生成第 {i+1} 张图片时发生错误: {str(e)}", *images
        
        yield "图片生成完成!", *images, image_urls

    def on_generate_image_button(prompt, model, size):
        """处理生成图片按钮点击事件"""
        if not prompt or not prompt.strip():
            yield ("请输入用于生成图片的英文提示词！", *([None]*9))
            return
        
        last_images = [None] * 9
        last_urls = [''] * 9
        finished = False
        
        for result in generate_images_with_progress(prompt.strip(), model, size):
            if isinstance(result, tuple):
                if len(result) >= 11:
                    progress = result[0]
                    images = list(result[1:10])
                    last_images = images
                    if len(result) > 10:
                        last_urls = result[10]
                else:
                    progress = result[0]
                    images = list(result[1:10])
                    last_images = images
            else:
                progress = result
            
            yield (progress, *last_images)
            # 检查是否为最后一次（图片生成完成）
            if isinstance(result, tuple) and len(result) >= 11 and progress == "图片生成完成!":
                finished = True
        # 生成完成后，自动保存图片到模型目录
        # 目录名为模型名最后一段
        # model_dir = model.split('/')[-1] if '/' in model else model
        # save_dir = os.path.join(os.path.abspath(os.path.dirname(__file__)), model_dir)
        # if not os.path.exists(save_dir):
        #     os.makedirs(save_dir)
        # now = datetime.now()
        # ts = now.strftime('%m%d%H%M%S')
        # for idx, img in enumerate(last_images):
        #     if img is not None:
        #         img_path = os.path.join(save_dir, f"{ts}_{idx+1}.png")
        #         try:
        #             img.save(img_path)
        #         except Exception as e:
        #             print(f"保存图片失败: {img_path}, 错误: {e}")
        print('单独配图图片URL:', last_urls)
        if not finished:
            yield ("图片生成完成!", *last_images)

    generate_image_button.click(
        on_generate_image_button,
        inputs=[prompt_for_image, model_input, size_input],
        outputs=[image_progress, image_output1, image_output2, image_output3, image_output4, image_output5, image_output6, image_output7, image_output8, image_output9]
    )
    
    # 一键生成所有带有分离图像进度的内容
    def generate_all(article_content, model, size, prompt_prefix):
        # 1. 生成9个分镜标题
        title_gen = generate_titles(article_content)
        title_reasoning, title_final = '', ''
        for r, f in title_gen:
            title_reasoning, title_final = r, f
            yield title_reasoning, title_final, '', '', '', '', '', '', *([None]*9)
            time.sleep(0.01)
        print("生成的标题：\n" + str(title_final))

        titles = [t.strip() for t in title_final.split('\n') if t.strip()]
        if len(titles) > 9:
            titles = titles[:9]
        elif len(titles) < 9:
            titles += [''] * (9 - len(titles))

        # 2. 生成9个分镜描述
        summary_gen = generate_summary(title_final)
        summary_reasoning, summary_final = '', ''
        for r, f in summary_gen:
            summary_reasoning, summary_final = r, f
            yield title_reasoning, title_final, summary_reasoning, summary_final, '', '', '', '', *([None]*9)
            time.sleep(0.01)
        print("生成的描述：\n" + str(summary_final))

        summaries = [s.strip() for s in summary_final.split('\n') if s.strip()]
        if len(summaries) > 9:
            summaries = summaries[:9]
        elif len(summaries) < 9:
            summaries += [''] * (9 - len(summaries))

        # 3. 每个分镜描述生成英文提示词，并加上关键词前缀
        prompts = []
        prompt_reasonings = []
        for i in range(9):
            prompt_gen = generate_image_prompt(summaries[i])
            pr, pf = '', ''
            for r, f in prompt_gen:
                pr, pf = r, f
                time.sleep(0.01)
            # 合并关键词前缀
            pf_full = (prompt_prefix.strip() + ' ' + pf.strip()).strip() if prompt_prefix.strip() else pf.strip()
            prompts.append(pf_full)
            prompt_reasonings.append(pr)
            yield title_reasoning, title_final, summary_reasoning, summary_final, pr, pf_full, '', '', *([None]*9)
            print(f"生成的英文提示词（第{i+1}个）：\n{pf_full}")

        # 4. 每个提示词生成一张图片并收集URL
        image_urls = []
        images = [None] * 9

        # 新增：准备保存目录
        model_dir = model.split('/')[-1] if '/' in model else model
        save_dir = os.path.join(os.path.abspath(os.path.dirname(__file__)), model_dir)
        if not os.path.exists(save_dir):
            os.makedirs(save_dir)
        now = datetime.now()
        ts = now.strftime('%m%d%H%M%S')

        progress_status = "准备生成图片..."
        yield title_reasoning, title_final, summary_reasoning, summary_final, '\n'.join(prompt_reasonings), '\n'.join(prompts), '\n'.join(prompts), progress_status, *images
        for i in range(9):
            url = 'https://api-inference.modelscope.cn/v1/images/generations'
            payload = {
                'model': model,
                'prompt': prompts[i],
                'n': 1,
                'negative_prompt': 'lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry,(worst quality:2),(low quality:2),(normal quality:2),lowres,normal quality,((monochrome)),((grayscale)),skin spots,acnes,skin blemishes,age spot,(ugly:1.33),(duplicate:1.33),(morbid:1.21),(mutilated:1.21),(tranny:1.33),mutated hands,(poorly drawn hands:1.5),blurry,(bad anatomy:1.21),(bad proportions:1.33),extra limbs,(disfigured:1.33),(missing arms:1.33),(extra legs:1.33),(fused fingers:1.61),(too many fingers:1.61),(unclear eyes:1.33),lowers,bad hands,missing fingers,extra digit,bad hands,missing fingers,(((extra arms and legs))),DeepNegativeV1.x_V175T,EasyNegative,EasyNegativeV2,',
                'steps': int(30),
                'guidance': float(3.5),
                'sampler': 'Euler',
                'size': size
            }
            headers = {
                'Authorization': f'Bearer {MODEL_API_KEY}',
                'Content-Type': 'application/json'
            }
            try:
                response = requests.post(
                    url,
                    data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                    headers=headers
                )
                response_data = response.json()
                if 'images' in response_data and len(response_data['images']) > 0:
                    image_url = response_data['images'][0]['url']
                    image_urls.append(image_url)
                    img_response = requests.get(image_url)
                    img = Image.open(BytesIO(img_response.content))
                    images[i] = img

                    # 新增：立即保存图片
                    img_path = os.path.join(save_dir, f"{ts}_{i+1}.png")
                    try:
                        img.save(img_path)
                    except Exception as e:
                        print(f"保存图片失败: {img_path}, 错误: {e}")

                    print(f"第{i+1}张图片的URL: {image_url}")
                else:
                    image_urls.append('')
                    images[i] = None
            except Exception as e:
                image_urls.append('')
                images[i] = None
            yield title_reasoning, title_final, summary_reasoning, summary_final, '\n'.join(prompt_reasonings), '\n'.join(prompts), '\n'.join(prompts), f"已生成第{i+1}张图片", *images
            time.sleep(0.01)
        # 5. 保存到markdown
        md_file = save_to_markdown(titles, summaries, prompts, image_urls)
        print(f"全部生成完成，已保存为markdown：{os.path.basename(md_file)}！")
        yield title_reasoning, title_final, summary_reasoning, summary_final, '\n'.join(prompt_reasonings), '\n'.join(prompts), '\n'.join(prompts), f"全部生成完成，已保存为markdown：{os.path.basename(md_file)}！", *images
    
    generate_all_button.click(
        generate_all,
        inputs=[article_input, model_input, size_input, prompt_prefix_input],
        outputs=[title_thinking, title_output, summary_thinking, summary_output, prompt_thinking, prompt_output, prompt_for_image, image_progress, image_output1, image_output2, image_output3, image_output4, image_output5, image_output6, image_output7, image_output8, image_output9]
    )

# Launch the app
if __name__ == "__main__":
    app.launch(inbrowser=True)
