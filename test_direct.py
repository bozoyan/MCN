#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""直接测试TextGenerationWorker"""
import sys
import time
from openai import OpenAI

# API配置
api_key = ""
base_url = "https://api-inference.modelscope.cn/v1"
model_id = "Qwen/Qwen3-Coder-480B-A35B-Instruct"

def test_direct_generation():
    """直接测试API生成"""
    print("=== 直接测试API生成 ===")

    content = "请生成一个关于小明捡到一只神奇铅笔的儿童故事的5个分镜标题"
    system_prompt = "你是一位专业的儿童故事分镜专家，请生成简洁明了的分镜标题。"

    client = OpenAI(
        base_url=base_url,
        api_key=api_key,
    )

    try:
        print(f"[{time.strftime('%H:%M:%S')}] 开始生成...")
        print(f"内容: {content}")
        print("-" * 50)

        response = client.chat.completions.create(
            model=model_id,
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
            stream=True
        )

        content_text = ""
        for chunk in response:
            if chunk.choices and len(chunk.choices) > 0:
                delta = chunk.choices[0].delta
                if hasattr(delta, 'content') and delta.content:
                    content_text += delta.content
                    print(delta.content, end='', flush=True)

        print("\n" + "-" * 50)
        print(f"[{time.strftime('%H:%M:%S')}] 生成完成!")
        print(f"总长度: {len(content_text)} 字符")
        return content_text

    except Exception as e:
        print(f"错误: {str(e)}")
        return None

if __name__ == "__main__":
    result = test_direct_generation()
    if result:
        print("\n测试成功!")
    else:
        print("\n测试失败!")