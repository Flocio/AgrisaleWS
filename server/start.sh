#!/bin/bash
# 服务器启动脚本

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查虚拟环境是否存在，如果存在则激活
if [ -d "venv" ]; then
    echo "检测到虚拟环境，正在激活..."
    source venv/bin/activate
else
    echo "警告：未找到虚拟环境，使用系统 Python"
    echo "建议创建虚拟环境：python3 -m venv venv"
fi

# 设置环境变量（可选，也可以从 .env 文件读取）
# 默认路径为 data/agrisalews.db（相对于server目录）
# 如果从项目根目录运行，会自动解析为 server/data/agrisalews.db
# 如果server目录是独立的，使用 data/agrisalews.db
export DB_PATH="${DB_PATH:-data/agrisalews.db}"
export DB_MAX_CONNECTIONS="${DB_MAX_CONNECTIONS:-10}"
export DB_BUSY_TIMEOUT="${DB_BUSY_TIMEOUT:-5000}"
export SECRET_KEY="${SECRET_KEY:-your-secret-key-change-this-in-production}"
export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-9000}"  # 默认端口 9000

# 检查是否在 server 目录中，如果是则切换到父目录
# 因为代码使用 from server.xxx import，需要从项目根目录运行
if [ "$(basename "$SCRIPT_DIR")" = "server" ]; then
    # 如果在 server 目录中，切换到父目录
    PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    # 检查父目录下是否有 server 目录（说明传输了整个项目）
    if [ -d "$PARENT_DIR/server" ] && [ "$(cd "$PARENT_DIR/server" && pwd)" = "$SCRIPT_DIR" ]; then
        # 父目录下有 server 目录，切换到父目录（正常情况）
        cd "$PARENT_DIR"
        echo "已切换到项目根目录: $(pwd)"
    else
        # 如果只传输了 server 目录（没有父项目目录）
        # 需要在父目录创建一个符号链接，或者将 server 目录添加到 PYTHONPATH
        # 方案：在父目录创建 server 符号链接指向当前目录
        if [ ! -e "$PARENT_DIR/server" ]; then
            echo "检测到只传输了 server 目录，正在创建符号链接..."
            ln -s "$SCRIPT_DIR" "$PARENT_DIR/server" 2>/dev/null || {
                echo "无法创建符号链接，使用 PYTHONPATH 方式"
                cd "$PARENT_DIR"
                export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"
            }
        fi
        cd "$PARENT_DIR"
        echo "工作目录: $(pwd)"
    fi
else
    # 如果不在 server 目录中，使用当前目录
    export PYTHONPATH="${PYTHONPATH}:$(pwd)"
fi

# 启动服务器
python -m uvicorn server.main:app --host "$HOST" --port "$PORT" --reload

