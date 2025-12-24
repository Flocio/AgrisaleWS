"""
中间件模块
"""

# 从 core.py 导入所有必要的函数和类
# 这样其他模块可以从 server.middleware 包中导入这些函数
from server.middleware.core import (
    # 密码加密
    verify_password,
    get_password_hash,
    # JWT Token 管理
    create_access_token,
    decode_access_token,
    # 认证依赖
    get_current_user,
    get_current_user_optional,
    security,
    # 中间件
    logging_middleware,
    error_handler_middleware,
    cors_middleware,
    rate_limit_middleware,
    # 配置函数
    setup_middleware,
    update_secret_key,
    # 辅助函数
    get_user_id_from_token,
    # 装饰器
    require_auth,
    # 速率限制
    check_rate_limit,
)

# 从 workspace_permission 模块导入
from server.middleware.workspace_permission import (
    get_workspace_id,
    check_workspace_access,
    check_workspace_permission,
    get_workspace_role,
    get_workspace_context,
    require_workspace_permission,
    get_workspace_storage_type,
    require_server_storage,
    PERMISSIONS,
)

__all__ = [
    # 密码加密
    "verify_password",
    "get_password_hash",
    # JWT Token 管理
    "create_access_token",
    "decode_access_token",
    # 认证依赖
    "get_current_user",
    "get_current_user_optional",
    "security",
    # 中间件
    "logging_middleware",
    "error_handler_middleware",
    "cors_middleware",
    "rate_limit_middleware",
    # 配置函数
    "setup_middleware",
    "update_secret_key",
    # 辅助函数
    "get_user_id_from_token",
    # 装饰器
    "require_auth",
    # 速率限制
    "check_rate_limit",
    # Workspace 权限
    "get_workspace_id",
    "check_workspace_access",
    "check_workspace_permission",
    "get_workspace_role",
    "get_workspace_context",
    "require_workspace_permission",
    "get_workspace_storage_type",
    "require_server_storage",
    "PERMISSIONS",
]

