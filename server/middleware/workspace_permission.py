"""
Workspace 权限检查中间件
提供 Workspace 访问权限验证和权限检查功能
"""

import logging
from typing import Optional
from fastapi import HTTPException, status, Header, Depends
from server.database import get_pool
from server.middleware.core import get_current_user

logger = logging.getLogger(__name__)

# 权限定义
PERMISSIONS = {
    'owner': {
        'read': True,
        'create': True,
        'update': True,
        'delete': True,
        'manage_members': True,
        'manage_settings': True,
    },
    'admin': {
        'read': True,
        'create': True,
        'update': True,
        'delete': True,
        'manage_members': True,
        'manage_settings': False,
    },
    'editor': {
        'read': True,
        'create': True,
        'update': True,
        'delete': False,
        'manage_members': False,
        'manage_settings': False,
    },
    'viewer': {
        'read': True,
        'create': False,
        'update': False,
        'delete': False,
        'manage_members': False,
        'manage_settings': False,
    }
}


async def get_workspace_id(
    x_workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID")
) -> Optional[int]:
    """
    从请求头获取 Workspace ID
    
    Args:
        x_workspace_id: X-Workspace-ID 请求头
    
    Returns:
        Workspace ID，如果未提供则返回 None
    """
    return x_workspace_id


async def check_workspace_access(
    workspace_id: int,
    user_id: int
) -> bool:
    """
    检查用户是否有访问指定 Workspace 的权限
    
    Args:
        workspace_id: Workspace ID
        user_id: 用户 ID
    
    Returns:
        是否有访问权限
    """
    pool = get_pool()
    try:
        with pool.get_connection() as conn:
            # 检查用户是否是 workspace 的成员
            cursor = conn.execute(
                "SELECT role FROM workspace_members WHERE workspaceId = ? AND userId = ?",
                (workspace_id, user_id)
            )
            member = cursor.fetchone()
            
            if member:
                return True
            
            # 检查用户是否是 workspace 的拥有者（通过 workspaces 表）
            cursor = conn.execute(
                "SELECT id FROM workspaces WHERE id = ? AND ownerId = ?",
                (workspace_id, user_id)
            )
            owner = cursor.fetchone()
            
            return owner is not None
    except Exception as e:
        logger.error(f"检查 workspace 访问权限失败: {e}", exc_info=True)
        return False


async def get_workspace_role(
    workspace_id: int,
    user_id: int
) -> Optional[str]:
    """
    获取用户在指定 Workspace 中的角色
    
    Args:
        workspace_id: Workspace ID
        user_id: 用户 ID
    
    Returns:
        用户角色（'owner', 'admin', 'editor', 'viewer'），如果用户不是成员则返回 None
    """
    pool = get_pool()
    try:
        with pool.get_connection() as conn:
            # 首先检查是否是拥有者
            cursor = conn.execute(
                "SELECT id FROM workspaces WHERE id = ? AND ownerId = ?",
                (workspace_id, user_id)
            )
            if cursor.fetchone():
                return 'owner'
            
            # 检查是否是成员
            cursor = conn.execute(
                "SELECT role FROM workspace_members WHERE workspaceId = ? AND userId = ?",
                (workspace_id, user_id)
            )
            member = cursor.fetchone()
            
            if member:
                return member[0]
            
            return None
    except Exception as e:
        logger.error(f"获取 workspace 角色失败: {e}", exc_info=True)
        return None


async def check_workspace_permission(
    workspace_id: int,
    user_id: int,
    permission: str
) -> bool:
    """
    检查用户是否有指定 Workspace 的特定权限
    
    Args:
        workspace_id: Workspace ID
        user_id: 用户 ID
        permission: 权限名称（'read', 'create', 'update', 'delete', 'manage_members', 'manage_settings'）
    
    Returns:
        是否有权限
    
    Raises:
        HTTPException: 如果用户没有访问权限
    """
    # 首先检查访问权限
    has_access = await check_workspace_access(workspace_id, user_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问该 Workspace"
        )
    
    # 获取用户角色
    role = await get_workspace_role(workspace_id, user_id)
    if role is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问该 Workspace"
        )
    
    # 检查权限
    role_permissions = PERMISSIONS.get(role, {})
    return role_permissions.get(permission, False)


async def require_workspace_permission(
    workspace_id: Optional[int],
    user_id: int,
    permission: str
) -> int:
    """
    要求用户必须有指定 Workspace 的特定权限（依赖注入函数）
    
    Args:
        workspace_id: Workspace ID（从请求头获取）
        user_id: 用户 ID
        permission: 权限名称
    
    Returns:
        Workspace ID
    
    Raises:
        HTTPException: 如果未提供 workspace_id 或没有权限
    """
    if workspace_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="缺少 X-Workspace-ID 请求头"
        )
    
    has_permission = await check_workspace_permission(workspace_id, user_id, permission)
    if not has_permission:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"无{permission}权限"
        )
    
    return workspace_id


async def get_workspace_storage_type(
    workspace_id: int
) -> Optional[str]:
    """
    获取 Workspace 的存储类型
    
    Args:
        workspace_id: Workspace ID
    
    Returns:
        存储类型（'local' 或 'server'），如果 workspace 不存在则返回 None
    """
    pool = get_pool()
    try:
        with pool.get_connection() as conn:
            cursor = conn.execute(
                "SELECT storage_type FROM workspaces WHERE id = ?",
                (workspace_id,)
            )
            row = cursor.fetchone()
            
            if row:
                return row[0]
            return None
    except Exception as e:
        logger.error(f"获取 workspace 存储类型失败: {e}", exc_info=True)
        return None


async def require_server_storage(
    workspace_id: Optional[int],
    user_id: int
) -> int:
    """
    要求 Workspace 必须是服务器存储类型（用于业务数据操作）
    
    Args:
        workspace_id: Workspace ID（从请求头获取）
        user_id: 用户 ID
    
    Returns:
        Workspace ID
    
    Raises:
        HTTPException: 如果未提供 workspace_id、workspace 不存在或 storage_type='local'
    """
    if workspace_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="缺少 X-Workspace-ID 请求头"
        )
    
    # 检查访问权限
    has_access = await check_workspace_access(workspace_id, user_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问该 Workspace"
        )
    
    # 获取存储类型
    storage_type = await get_workspace_storage_type(workspace_id)
    if storage_type is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workspace 不存在"
        )
    
    if storage_type == 'local':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="本地 Workspace 的数据存储在客户端，请使用客户端操作。服务器只存储元数据（workspace 信息和成员信息）。"
        )
    
    return workspace_id


async def get_workspace_context(
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
) -> dict:
    """
    获取 Workspace 上下文信息（依赖注入函数）
    
    Args:
        workspace_id: Workspace ID（从请求头获取）
        current_user: 当前用户信息
    
    Returns:
        Workspace 上下文字典，包含 workspace_id 和用户角色
    
    Raises:
        HTTPException: 如果未提供 workspace_id 或没有访问权限
    """
    if workspace_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="缺少 X-Workspace-ID 请求头"
        )
    
    if current_user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="未认证"
        )
    
    user_id = current_user["user_id"]
    
    # 检查访问权限
    has_access = await check_workspace_access(workspace_id, user_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问该 Workspace"
        )
    
    # 获取用户角色
    role = await get_workspace_role(workspace_id, user_id)
    if role is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问该 Workspace"
        )
    
    return {
        "workspace_id": workspace_id,
        "user_id": user_id,
        "role": role,
        "permissions": PERMISSIONS.get(role, {})
    }

