"""
帮助文档路由
提供用户帮助文档
"""

import logging
from pathlib import Path
from fastapi import APIRouter
from fastapi.responses import PlainTextResponse, FileResponse
from fastapi.responses import HTMLResponse

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/help", tags=["帮助"])

# 帮助文档路径（相对于 server 目录）
HELP_FILE_PATH = Path(__file__).parent.parent / "help.md"


@router.get("", response_class=PlainTextResponse)
async def get_help():
    """
    获取帮助文档（Markdown 格式）
    """
    try:
        if not HELP_FILE_PATH.exists():
            logger.error(f"帮助文档不存在: {HELP_FILE_PATH}")
            return "帮助文档未找到"
        
        with open(HELP_FILE_PATH, "r", encoding="utf-8") as f:
            content = f.read()
        
        return content
    except Exception as e:
        logger.error(f"读取帮助文档失败: {e}")
        return f"读取帮助文档失败: {str(e)}"


@router.get("/html", response_class=HTMLResponse)
async def get_help_html():
    """
    获取帮助文档（HTML 格式，便于在客户端显示）
    """
    try:
        if not HELP_FILE_PATH.exists():
            logger.error(f"帮助文档不存在: {HELP_FILE_PATH}")
            return "<html><body><h1>帮助文档未找到</h1></body></html>"
        
        with open(HELP_FILE_PATH, "r", encoding="utf-8") as f:
            markdown_content = f.read()
        
        # 简单的 Markdown 转 HTML（基础转换）
        html_content = _markdown_to_html(markdown_content)
        
        return html_content
    except Exception as e:
        logger.error(f"读取帮助文档失败: {e}")
        return f"<html><body><h1>读取帮助文档失败: {str(e)}</h1></body></html>"


def _markdown_to_html(markdown: str) -> str:
    """
    简单的 Markdown 转 HTML 转换
    支持标题、列表、粗体、链接等基础格式
    """
    html = markdown
    
    # 标题转换
    html = html.replace("# ", "<h1>").replace("\n# ", "\n</h1>\n<h1>")
    html = html.replace("## ", "<h2>").replace("\n## ", "\n</h2>\n<h2>")
    html = html.replace("### ", "<h3>").replace("\n### ", "\n</h3>\n<h3>")
    html = html.replace("#### ", "<h4>").replace("\n#### ", "\n</h4>\n<h4>")
    
    # 处理最后一个标题
    if html.count("<h1>") > html.count("</h1>"):
        html += "</h1>"
    if html.count("<h2>") > html.count("</h2>"):
        html += "</h2>"
    if html.count("<h3>") > html.count("</h3>"):
        html += "</h3>"
    if html.count("<h4>") > html.count("</h4>"):
        html += "</h4>"
    
    # 粗体
    html = html.replace("**", "<strong>").replace("**", "</strong>")
    
    # 代码块
    html = html.replace("```", "<pre><code>").replace("```", "</code></pre>")
    
    # 链接（简单处理）
    import re
    html = re.sub(r'\[([^\]]+)\]\(([^\)]+)\)', r'<a href="\2">\1</a>', html)
    
    # 换行
    html = html.replace("\n\n", "</p><p>")
    html = "<p>" + html + "</p>"
    
    # 列表（简单处理）
    lines = html.split("\n")
    in_list = False
    result = []
    for line in lines:
        if line.strip().startswith("- "):
            if not in_list:
                result.append("<ul>")
                in_list = True
            result.append(f"<li>{line.strip()[2:]}</li>")
        else:
            if in_list:
                result.append("</ul>")
                in_list = False
            result.append(line)
    if in_list:
        result.append("</ul>")
    html = "\n".join(result)
    
    # 添加样式
    style = """
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            border-bottom: 1px solid #ecf0f1;
            padding-bottom: 5px;
        }
        h3 {
            color: #7f8c8d;
            margin-top: 20px;
        }
        h4 {
            color: #95a5a6;
            margin-top: 15px;
        }
        ul, ol {
            margin: 10px 0;
            padding-left: 30px;
        }
        li {
            margin: 5px 0;
        }
        p {
            margin: 10px 0;
        }
        strong {
            color: #333;
            font-weight: bold;
        }
        code {
            background-color: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: "Courier New", monospace;
        }
        pre {
            background-color: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }
        a {
            color: #3498db;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
    """
    
    return f"<!DOCTYPE html><html><head><meta charset='utf-8'>{style}</head><body>{html}</body></html>"
