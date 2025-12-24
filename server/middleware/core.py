"""
中间件和依赖注入
包含认证、错误处理、CORS、请求日志等
"""

import time
import logging
import traceback
from typing import Optional, Annotated
from datetime import datetime, timedelta
from functools import wraps

from fastapi import Request, HTTPException, status, Depends, Header
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext

from server.database import get_pool, DatabaseBusyError, ConnectionTimeoutError
from server.models import ErrorResponse

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# JWT 配置
SECRET_KEY = "your-secret-key-change-this-in-production"  # 生产环境必须更改
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 小时

# 密码加密上下文
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# HTTP Bearer Token 安全方案
security = HTTPBearer()


# ==================== 密码加密 ====================

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    验证密码
    
    Args:
        plain_password: 明文密码
        hashed_password: 哈希密码
    
    Returns:
        是否匹配
    """
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """
    生成密码哈希
    
    Args:
        password: 明文密码
    
    Returns:
        哈希密码
    
    Note:
        bcrypt 限制密码最大长度为 72 字节，超长密码会被截断
    """
    # bcrypt 限制密码最大长度为 72 字节
    # 将密码编码为 UTF-8 字节，检查长度
    password_bytes = password.encode('utf-8')
    if len(password_bytes) > 72:
        # 截断到 72 字节
        # 为了安全，从后往前找到最后一个完整的 UTF-8 字符边界
        truncated = password_bytes[:72]
        # 尝试找到最后一个完整的 UTF-8 字符
        while len(truncated) > 0:
            try:
                password = truncated.decode('utf-8')
                break
            except UnicodeDecodeError:
                truncated = truncated[:-1]
        else:
            # 如果全部失败，使用原始密码的前 24 个字符（安全截断）
            password = password[:24]
    
    return pwd_context.hash(password)


# ==================== JWT Token 管理 ====================

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    创建 JWT 访问令牌
    
    Args:
        data: 要编码的数据（通常包含 user_id 和 username）
        expires_delta: 过期时间增量
    
    Returns:
        JWT Token 字符串
    """
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire, "iat": datetime.utcnow()})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def decode_access_token(token: str) -> Optional[dict]:
    """
    解码 JWT 访问令牌
    
    Args:
        token: JWT Token 字符串
    
    Returns:
        解码后的数据，失败返回 None
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError as e:
        logger.warning(f"JWT 解码失败: {e}")
        return None


# ==================== 认证依赖 ====================

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> dict:
    """
    从 Token 获取当前用户信息（依赖注入）
    
    Args:
        credentials: HTTP Bearer Token 凭证
    
    Returns:
        用户信息字典（包含 user_id 和 username）
    
    Raises:
        HTTPException: Token 无效或用户不存在
    """
    token = credentials.credentials
    payload = decode_access_token(token)
    
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="无效的认证令牌",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    user_id: int = payload.get("user_id")
    username: str = payload.get("username")
    
    if user_id is None or username is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="令牌中缺少用户信息",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 验证用户是否仍然存在
    pool = get_pool()
    try:
        with pool.get_connection() as conn:
            cursor = conn.execute(
                "SELECT id, username FROM users WHERE id = ? AND username = ?",
                (user_id, username)
            )
            user = cursor.fetchone()
            
            if user is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="用户不存在或已被删除",
                    headers={"WWW-Authenticate": "Bearer"},
                )
            
            return {
                "user_id": user_id,
                "username": username
            }
    except Exception as e:
        logger.error(f"验证用户时出错: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="验证用户时发生错误"
        )


async def get_current_user_optional(
    authorization: Optional[str] = Header(None)
) -> Optional[dict]:
    """
    可选的身份验证（用于某些不需要强制登录的接口）
    
    Args:
        authorization: Authorization 请求头
    
    Returns:
        用户信息字典，如果未提供 Token 则返回 None
    """
    if authorization is None:
        return None
    
    try:
        # 提取 Bearer Token
        scheme, token = authorization.split()
        if scheme.lower() != "bearer":
            return None
        
        payload = decode_access_token(token)
        if payload is None:
            return None
        
        user_id: int = payload.get("user_id")
        username: str = payload.get("username")
        
        if user_id is None or username is None:
            return None
        
        return {
            "user_id": user_id,
            "username": username
        }
    except Exception:
        return None


# ==================== 中间件 ====================

async def logging_middleware(request: Request, call_next):
    """
    请求日志中间件
    记录所有请求的详细信息
    """
    start_time = time.time()
    
    # 记录请求信息
    logger.info(
        f"请求: {request.method} {request.url.path} - "
        f"客户端: {request.client.host if request.client else 'unknown'}"
    )
    
    # 处理请求
    try:
        response = await call_next(request)
        
        # 计算处理时间
        process_time = time.time() - start_time
        
        # 记录响应信息
        logger.info(
            f"响应: {request.method} {request.url.path} - "
            f"状态码: {response.status_code} - "
            f"耗时: {process_time:.3f}秒"
        )
        
        # 添加处理时间到响应头
        response.headers["X-Process-Time"] = str(process_time)
        
        return response
    except Exception as e:
        process_time = time.time() - start_time
        logger.error(
            f"请求处理异常: {request.method} {request.url.path} - "
            f"错误: {str(e)} - 耗时: {process_time:.3f}秒"
        )
        raise


async def error_handler_middleware(request: Request, call_next):
    """
    全局错误处理中间件
    捕获所有异常并返回统一的错误响应
    """
    try:
        response = await call_next(request)
        return response
    except DatabaseBusyError as e:
        logger.warning(f"数据库繁忙: {e}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=ErrorResponse(
                success=False,
                message="数据库暂时繁忙，请稍后重试",
                error_code="DATABASE_BUSY",
                details={"retry_after": 1}
            ).model_dump()
        )
    except ConnectionTimeoutError as e:
        logger.error(f"连接超时: {e}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=ErrorResponse(
                success=False,
                message="数据库连接超时，请稍后重试",
                error_code="CONNECTION_TIMEOUT"
            ).model_dump()
        )
    except HTTPException as e:
        # FastAPI 的 HTTPException 直接返回
        raise e
    except Exception as e:
        # 其他未预期的异常
        logger.error(f"未处理的异常: {e}\n{traceback.format_exc()}")
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=ErrorResponse(
                success=False,
                message="服务器内部错误",
                error_code="INTERNAL_SERVER_ERROR",
                details={"error": str(e)} if logger.level == logging.DEBUG else None
            ).model_dump()
        )


async def cors_middleware(request: Request, call_next):
    """
    CORS 中间件
    处理跨域请求
    """
    # 处理预检请求
    if request.method == "OPTIONS":
        response = JSONResponse(content={})
    else:
        response = await call_next(request)
    
    # 添加 CORS 头
    response.headers["Access-Control-Allow-Origin"] = "*"  # 生产环境应该限制具体域名
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS, PATCH"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Requested-With"
    response.headers["Access-Control-Allow-Credentials"] = "true"
    response.headers["Access-Control-Max-Age"] = "3600"
    
    # 添加性能优化响应头
    # 对于 GET 请求，添加缓存控制（可根据需要调整）
    if request.method == "GET":
        # 对于 API 数据，使用较短的缓存时间（5分钟），避免数据不一致
        response.headers["Cache-Control"] = "private, max-age=300"
        response.headers["Vary"] = "Accept-Encoding"
    
    return response


# ==================== 用户 ID 提取辅助函数 ====================

def get_user_id_from_token(request: Request) -> Optional[int]:
    """
    从请求中提取用户 ID（用于日志记录等）
    
    Args:
        request: FastAPI 请求对象
    
    Returns:
        用户 ID，如果无法提取则返回 None
    """
    try:
        auth_header = request.headers.get("Authorization")
        if auth_header:
            scheme, token = auth_header.split()
            if scheme.lower() == "bearer":
                payload = decode_access_token(token)
                if payload:
                    return payload.get("user_id")
    except Exception:
        pass
    return None


# ==================== 装饰器 ====================

def require_auth(func):
    """
    需要认证的装饰器（用于非 FastAPI 路由的函数）
    
    Usage:
        @require_auth
        def some_function(user_id: int, ...):
            ...
    """
    @wraps(func)
    async def wrapper(*args, **kwargs):
        # 这个装饰器主要用于非 FastAPI 路由
        # FastAPI 路由应该使用 Depends(get_current_user)
        return await func(*args, **kwargs)
    return wrapper


# ==================== 速率限制（可选） ====================

from collections import defaultdict
from datetime import datetime, timedelta

_rate_limit_store = defaultdict(list)
_rate_limit_window = timedelta(minutes=1)
_rate_limit_max_requests = 60


def check_rate_limit(identifier: str) -> bool:
    """
    检查速率限制
    
    Args:
        identifier: 标识符（通常是 IP 地址或用户 ID）
    
    Returns:
        是否允许请求
    """
    now = datetime.utcnow()
    
    # 清理过期记录
    _rate_limit_store[identifier] = [
        timestamp for timestamp in _rate_limit_store[identifier]
        if now - timestamp < _rate_limit_window
    ]
    
    # 检查是否超过限制
    if len(_rate_limit_store[identifier]) >= _rate_limit_max_requests:
        return False
    
    # 记录本次请求
    _rate_limit_store[identifier].append(now)
    return True


async def rate_limit_middleware(request: Request, call_next):
    """
    速率限制中间件（可选，根据需要启用）
    """
    # 获取客户端标识符
    client_ip = request.client.host if request.client else "unknown"
    
    # 检查速率限制
    if not check_rate_limit(client_ip):
        logger.warning(f"速率限制: {client_ip} 请求过于频繁")
        return JSONResponse(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            content=ErrorResponse(
                success=False,
                message="请求过于频繁，请稍后再试",
                error_code="RATE_LIMIT_EXCEEDED"
            ).model_dump()
        )
    
    return await call_next(request)


# ==================== 配置函数 ====================

def setup_middleware(app):
    """
    设置所有中间件到 FastAPI 应用
    
    Args:
        app: FastAPI 应用实例
    """
    # 注意：中间件的顺序很重要，后添加的中间件会先执行
    
    # 1. CORS 中间件（最外层）
    app.middleware("http")(cors_middleware)
    
    # 2. 错误处理中间件
    app.middleware("http")(error_handler_middleware)
    
    # 3. 日志中间件
    app.middleware("http")(logging_middleware)
    
    # 4. 速率限制中间件（可选，根据需要启用）
    # app.middleware("http")(rate_limit_middleware)
    
    logger.info("中间件设置完成")


def update_secret_key(new_secret_key: str):
    """
    更新 JWT 密钥（用于生产环境配置）
    
    Args:
        new_secret_key: 新的密钥
    """
    global SECRET_KEY
    SECRET_KEY = new_secret_key
    logger.info("JWT 密钥已更新")

