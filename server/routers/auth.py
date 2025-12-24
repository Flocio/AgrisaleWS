"""
认证路由
处理用户注册、登录、登出等认证相关功能
"""

import logging
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends
from fastapi.security import HTTPAuthorizationCredentials

from server.database import get_pool
from server.middleware import (
    get_password_hash,
    verify_password,
    create_access_token,
    get_current_user,
    security
)
from server.models import (
    UserCreate,
    UserLogin,
    UserResponse,
    UserInfo,
    ChangePasswordRequest,
    LogoutRequest,
    DeleteAccountRequest,
    BaseResponse,
    ErrorResponse
)

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/auth", tags=["认证"])


@router.post("/register", response_model=BaseResponse, status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate):
    """
    用户注册
    
    Args:
        user_data: 用户注册数据（用户名和密码）
    
    Returns:
        注册成功响应，包含用户信息和 Token
    """
    pool = get_pool()
    
    try:
        with pool.get_connection() as conn:
            # 检查用户名是否已存在
            cursor = conn.execute(
                "SELECT id FROM users WHERE username = ?",
                (user_data.username,)
            )
            existing_user = cursor.fetchone()
            
            if existing_user:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="用户名已存在，请选择其他用户名"
                )
            
            # 加密密码
            hashed_password = get_password_hash(user_data.password)
            
            # 创建用户
            cursor = conn.execute(
                """
                INSERT INTO users (username, password, created_at)
                VALUES (?, ?, datetime('now'))
                """,
                (user_data.username, hashed_password)
            )
            user_id = cursor.lastrowid
            
            # 创建用户设置记录
            conn.execute(
                """
                INSERT INTO user_settings (userId, created_at, updated_at)
                VALUES (?, datetime('now'), datetime('now'))
                """,
                (user_id,)
            )
            
            conn.commit()
            
            # 生成 Token
            token_data = {
                "user_id": user_id,
                "username": user_data.username
            }
            token = create_access_token(data=token_data)
            
            # 不在这里创建在线用户记录，让客户端在心跳时创建（避免出现默认设备）
            conn.commit()
            
            # 构建响应
            user_response = UserResponse(
                id=user_id,
                username=user_data.username,
                created_at=datetime.now().isoformat()
            )
            
            user_info = UserInfo(
                user=user_response,
                token=token,
                expires_in=60 * 24 * 60  # 24 小时（秒）
            )
            
            logger.info(f"用户注册成功: {user_data.username} (ID: {user_id})")
            
            return BaseResponse(
                success=True,
                message="注册成功",
                data=user_info.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"用户注册失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"注册失败: {str(e)}"
        )


@router.post("/login", response_model=BaseResponse)
async def login(login_data: UserLogin):
    """
    用户登录
    
    Args:
        login_data: 登录数据（用户名和密码）
    
    Returns:
        登录成功响应，包含用户信息和 Token
    """
    pool = get_pool()
    
    try:
        with pool.get_connection() as conn:
            # 查询用户
            cursor = conn.execute(
                "SELECT id, username, password FROM users WHERE username = ?",
                (login_data.username,)
            )
            user = cursor.fetchone()
            
            if user is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="用户名或密码错误"
                )
            
            user_id, username, hashed_password = user
            
            # 验证密码
            if not verify_password(login_data.password, hashed_password):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="用户名或密码错误"
                )
            
            # 更新最后登录时间
            conn.execute(
                "UPDATE users SET last_login_at = datetime('now') WHERE id = ?",
                (user_id,)
            )
            
            # 不在这里创建在线用户记录，让客户端在心跳时创建（避免出现默认设备）
            # 同时清理可能存在的旧默认设备记录
            conn.execute(
                "DELETE FROM online_users WHERE userId = ? AND deviceId = 'default'",
                (user_id,)
            )
            
            conn.commit()
            
            # 生成 Token
            token_data = {
                "user_id": user_id,
                "username": username
            }
            token = create_access_token(data=token_data)
            
            # 构建响应
            user_response = UserResponse(
                id=user_id,
                username=username,
                last_login_at=datetime.now().isoformat()
            )
            
            user_info = UserInfo(
                user=user_response,
                token=token,
                expires_in=60 * 24 * 60  # 24 小时（秒）
            )
            
            logger.info(f"用户登录成功: {username} (ID: {user_id})")
            
            return BaseResponse(
                success=True,
                message="登录成功",
                data=user_info.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"用户登录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"登录失败: {str(e)}"
        )


@router.post("/logout", response_model=BaseResponse)
async def logout(
    logout_data: Optional[LogoutRequest] = None,
    current_user: dict = Depends(get_current_user)
):
    """
    用户登出（只删除当前设备的记录）
    
    Args:
        logout_data: 可选的登出数据（包含 device_id）
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        登出成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    username = current_user["username"]
    
    # 获取设备ID（如果客户端提供了）
    device_id = logout_data.device_id if logout_data and logout_data.device_id else None
    
    try:
        with pool.get_connection() as conn:
            if device_id:
                # 只删除当前设备的记录
                conn.execute(
                    "DELETE FROM online_users WHERE userId = ? AND deviceId = ?",
                    (user_id, device_id)
                )
                logger.info(f"用户登出: {username} (ID: {user_id}), 设备: {device_id}")
            else:
                # 如果没有提供设备ID，不删除任何记录（让心跳超时自动清理）
                # 这样可以避免误删其他设备的记录
                logger.info(f"用户登出: {username} (ID: {user_id}), 未提供设备ID，等待心跳超时")
            
            conn.commit()
            
            return BaseResponse(
                success=True,
                message="登出成功"
            )
            
    except Exception as e:
        logger.error(f"用户登出失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"登出失败: {str(e)}"
        )


@router.get("/me", response_model=BaseResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """
    获取当前用户信息
    
    Args:
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        当前用户信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            cursor = conn.execute(
                "SELECT id, username, created_at, last_login_at FROM users WHERE id = ?",
                (user_id,)
            )
            user = cursor.fetchone()
            
            if user is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="用户不存在"
                )
            
            user_response = UserResponse(
                id=user[0],
                username=user[1],
                created_at=user[2],
                last_login_at=user[3]
            )
            
            return BaseResponse(
                success=True,
                message="获取用户信息成功",
                data=user_response.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取用户信息失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取用户信息失败: {str(e)}"
        )


@router.post("/refresh", response_model=BaseResponse)
async def refresh_token(current_user: dict = Depends(get_current_user)):
    """
    刷新 Token（延长过期时间）
    
    Args:
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        新的 Token
    """
    try:
        # 生成新 Token
        token_data = {
            "user_id": current_user["user_id"],
            "username": current_user["username"]
        }
        token = create_access_token(data=token_data)
        
        logger.info(f"Token 刷新成功: {current_user['username']} (ID: {current_user['user_id']})")
        
        return BaseResponse(
            success=True,
            message="Token 刷新成功",
            data={
                "token": token,
                "expires_in": 60 * 24 * 60  # 24 小时（秒）
            }
        )
        
    except Exception as e:
        logger.error(f"Token 刷新失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Token 刷新失败: {str(e)}"
        )


@router.post("/change-password", response_model=BaseResponse)
async def change_password(
    password_data: ChangePasswordRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    修改密码
    
    Args:
        password_data: 密码修改数据（旧密码和新密码）
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        修改密码成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 查询当前密码
            cursor = conn.execute(
                "SELECT password FROM users WHERE id = ?",
                (user_id,)
            )
            user = cursor.fetchone()
            
            if user is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="用户不存在"
                )
            
            hashed_password = user[0]
            
            # 验证旧密码
            if not verify_password(password_data.old_password, hashed_password):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="当前密码不正确"
                )
            
            # 更新密码
            new_hashed_password = get_password_hash(password_data.new_password)
            conn.execute(
                "UPDATE users SET password = ? WHERE id = ?",
                (new_hashed_password, user_id)
            )
            conn.commit()
            
            logger.info(f"用户修改密码成功: {current_user['username']} (ID: {user_id})")
            
            return BaseResponse(
                success=True,
                message="密码修改成功"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"修改密码失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"修改密码失败: {str(e)}"
        )


@router.post("/account/delete", response_model=BaseResponse)
async def delete_account(
    password_data: DeleteAccountRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    删除账户（注销账户）
    
    注意：此操作不可恢复，将删除用户的所有数据，包括：
    - 用户账户信息
    - 所有 Workspace（包括成员关系）
    - 所有业务数据（产品、销售、采购等）
    - 用户设置
    - 在线状态记录
    
    Args:
        password_data: 删除账户请求（包含密码用于确认身份）
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        删除账户成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    username = current_user["username"]
    
    try:
        with pool.get_connection() as conn:
            # 查询用户密码
            cursor = conn.execute(
                "SELECT password FROM users WHERE id = ?",
                (user_id,)
            )
            user = cursor.fetchone()
            
            if user is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="用户不存在"
                )
            
            hashed_password = user[0]
            
            # 验证密码
            if not verify_password(password_data.password, hashed_password):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="密码不正确，无法注销账户"
                )
            
            # 处理用户拥有的 Workspace：
            # 1. 如果 Workspace 有其他成员（无论是共享还是非共享），转移所有权给第一个成员（按加入时间排序）
            # 2. 如果 Workspace 没有其他成员，保留 Workspace 但标记为待删除（通过 CASCADE 删除）
            cursor = conn.execute('''
                SELECT id, name, is_shared
                FROM workspaces
                WHERE ownerId = ?
            ''', (user_id,))
            owned_workspaces = cursor.fetchall()
            
            transferred_workspaces = []
            deleted_workspaces = []
            
            for workspace_row in owned_workspaces:
                workspace_id = workspace_row[0]
                workspace_name = workspace_row[1]
                is_shared = bool(workspace_row[2])
                
                # 查找该 Workspace 的其他成员（排除当前用户）
                cursor = conn.execute('''
                    SELECT userId, role, joined_at
                    FROM workspace_members
                    WHERE workspaceId = ? AND userId != ?
                    ORDER BY joined_at ASC
                    LIMIT 1
                ''', (workspace_id, user_id))
                other_member = cursor.fetchone()
                
                if other_member:
                    # 有其他成员，转移所有权（无论是否共享）
                    new_owner_id = other_member[0]
                    
                    # 先更新 Workspace 的 ownerId（必须在删除用户之前，避免 CASCADE 删除）
                    conn.execute('''
                        UPDATE workspaces
                        SET ownerId = ?, updated_at = datetime('now')
                        WHERE id = ?
                    ''', (new_owner_id, workspace_id))
                    
                    # 将新 owner 的成员角色更新为 'owner'（如果存在）
                    conn.execute('''
                        UPDATE workspace_members
                        SET role = 'owner'
                        WHERE workspaceId = ? AND userId = ?
                    ''', (workspace_id, new_owner_id))
                    
                    # 如果新 owner 还不是成员，添加为 owner
                    cursor_check = conn.execute('''
                        SELECT id FROM workspace_members
                        WHERE workspaceId = ? AND userId = ?
                    ''', (workspace_id, new_owner_id))
                    if not cursor_check.fetchone():
                        conn.execute('''
                            INSERT INTO workspace_members (workspaceId, userId, role, joined_at)
                            VALUES (?, ?, 'owner', datetime('now'))
                        ''', (workspace_id, new_owner_id))
                    
                    transferred_workspaces.append((workspace_id, workspace_name, new_owner_id))
                    logger.info(f"Workspace '{workspace_name}' (ID: {workspace_id}) 所有权已转移给用户 ID: {new_owner_id}")
                else:
                    # 没有其他成员，Workspace 将在删除用户时通过 CASCADE 删除
                    deleted_workspaces.append((workspace_id, workspace_name))
                    logger.info(f"Workspace '{workspace_name}' (ID: {workspace_id}) 将被删除（无其他成员）")
            
            # 删除用户（由于外键约束设置了 ON DELETE CASCADE，相关数据会自动删除）
            # 注意：已转移所有权的 Workspace 不会被删除（因为 ownerId 已更新）
            # 包括：
            # - workspaces (ownerId) -> ON DELETE CASCADE（但已转移所有权的不会删除）
            # - workspace_members (userId) -> ON DELETE CASCADE
            # - workspace_invitations (invited_by) -> ON DELETE SET NULL
            # - 所有业务表 (userId) -> ON DELETE CASCADE
            # - user_settings (userId) -> ON DELETE CASCADE
            # - online_users (userId) -> ON DELETE CASCADE
            conn.execute(
                "DELETE FROM users WHERE id = ?",
                (user_id,)
            )
            conn.commit()
            
            # 记录转移和删除的 Workspace 信息
            if transferred_workspaces:
                logger.info(f"用户 {username} (ID: {user_id}) 注销账户，已转移 {len(transferred_workspaces)} 个 Workspace 的所有权")
            if deleted_workspaces:
                logger.info(f"用户 {username} (ID: {user_id}) 注销账户，已删除 {len(deleted_workspaces)} 个 Workspace")
            
            logger.warning(f"用户注销账户: {username} (ID: {user_id})")
            
            return BaseResponse(
                success=True,
                message="账户已成功注销，所有数据已删除"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"注销账户失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"注销账户失败: {str(e)}"
        )

