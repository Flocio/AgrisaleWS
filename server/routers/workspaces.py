"""
Workspace 管理路由
处理 Workspace 的创建、更新、删除、成员管理等功能
"""

import logging
import secrets
from typing import Optional, List
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, status, Depends, Query, Header

from server.database import get_pool
from server.middleware import get_current_user
from server.middleware.workspace_permission import (
    check_workspace_access,
    check_workspace_permission,
    get_workspace_role,
    get_workspace_storage_type,
    PERMISSIONS
)
from server.models import (
    WorkspaceCreate,
    WorkspaceUpdate,
    WorkspaceDeleteRequest,
    WorkspaceResponse,
    WorkspaceMemberResponse,
    WorkspaceInviteRequest,
    WorkspaceMemberUpdate,
    BaseResponse,
    PaginatedResponse,
    ImportDataRequest
)

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/workspaces", tags=["Workspace管理"])


@router.get("", response_model=BaseResponse)
async def get_workspaces(
    current_user: dict = Depends(get_current_user)
):
    """
    获取当前用户的所有 Workspace 列表
    
    Returns:
        Workspace 列表
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 查询用户拥有的和参与的 workspace
            # 注意：只返回服务器 workspace（storage_type='server'），本地 workspace 的数据存储在客户端，不应在服务器返回
            cursor = conn.execute('''
                SELECT DISTINCT w.id, w.name, w.description, w.ownerId, w.storage_type, 
                       w.is_shared, w.created_at, w.updated_at
                FROM workspaces w
                LEFT JOIN workspace_members wm ON w.id = wm.workspaceId
                WHERE (w.ownerId = ? OR wm.userId = ?) AND w.storage_type = 'server'
                ORDER BY w.created_at DESC
            ''', (user_id, user_id))
            rows = cursor.fetchall()
            
            workspaces = []
            for row in rows:
                workspace = WorkspaceResponse(
                    id=row[0],
                    name=row[1],
                    description=row[2],
                    ownerId=row[3],
                    storage_type=row[4],
                    is_shared=bool(row[5]),
                    created_at=row[6],
                    updated_at=row[7]
                )
                workspaces.append(workspace.model_dump())
            
            return BaseResponse(
                success=True,
                message="获取 Workspace 列表成功",
                data=workspaces
            )
    except Exception as e:
        logger.error(f"获取 Workspace 列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取 Workspace 列表失败: {str(e)}"
        )


@router.post("", response_model=BaseResponse, status_code=status.HTTP_201_CREATED)
async def create_workspace(
    workspace_data: WorkspaceCreate,
    current_user: dict = Depends(get_current_user)
):
    """
    创建新的 Workspace
    
    Args:
        workspace_data: Workspace 创建数据
        current_user: 当前用户信息
    
    Returns:
        创建的 Workspace 信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 创建 workspace
            cursor = conn.execute('''
                INSERT INTO workspaces (name, description, ownerId, storage_type, is_shared, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, datetime('now'), datetime('now'))
            ''', (
                workspace_data.name,
                workspace_data.description,
                user_id,
                workspace_data.storage_type
            ))
            workspace_id = cursor.lastrowid
            
            # 注意：owner 不需要添加到 workspace_members 表中
            # owner 通过 workspaces.ownerId 字段标识，在获取成员列表时会单独处理
            # 只有服务器 workspace 才需要创建成员记录，但 owner 不需要添加
            # （如果添加了 owner 到 workspace_members，会导致在成员列表中显示两次）
            
            conn.commit()
            
            # 获取创建的 workspace
            cursor = conn.execute(
                "SELECT id, name, description, ownerId, storage_type, is_shared, created_at, updated_at FROM workspaces WHERE id = ?",
                (workspace_id,)
            )
            row = cursor.fetchone()
            
            workspace = WorkspaceResponse(
                id=row[0],
                name=row[1],
                description=row[2],
                ownerId=row[3],
                storage_type=row[4],
                is_shared=bool(row[5]),
                created_at=row[6],
                updated_at=row[7]
            )
            
            logger.info(f"用户 {current_user['username']} (ID: {user_id}) 创建 Workspace: {workspace_data.name} (ID: {workspace_id})")
            
            return BaseResponse(
                success=True,
                message="创建 Workspace 成功",
                data=workspace.model_dump()
            )
    except Exception as e:
        logger.error(f"创建 Workspace 失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"创建 Workspace 失败: {str(e)}"
        )


@router.get("/{workspace_id}", response_model=BaseResponse)
async def get_workspace(
    workspace_id: int,
    current_user: dict = Depends(get_current_user)
):
    """
    获取 Workspace 详情
    
    Args:
        workspace_id: Workspace ID
        current_user: 当前用户信息
    
    Returns:
        Workspace 详情
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            cursor = conn.execute(
                "SELECT id, name, description, ownerId, storage_type, is_shared, created_at, updated_at FROM workspaces WHERE id = ?",
                (workspace_id,)
            )
            row = cursor.fetchone()
            
            if not row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Workspace 不存在"
                )
            
            storage_type = row[4]
            
            # 如果是本地 workspace，不允许通过服务器 API 访问（数据在客户端）
            if storage_type == 'local':
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="本地 Workspace 的数据存储在客户端，请通过客户端访问"
                )
            
            # 检查访问权限（仅对服务器 workspace）
            has_access = await check_workspace_access(workspace_id, user_id)
            if not has_access:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无权访问该 Workspace"
                )
            
            workspace = WorkspaceResponse(
                id=row[0],
                name=row[1],
                description=row[2],
                ownerId=row[3],
                storage_type=row[4],
                is_shared=bool(row[5]),
                created_at=row[6],
                updated_at=row[7]
            )
            
            return BaseResponse(
                success=True,
                message="获取 Workspace 详情成功",
                data=workspace.model_dump()
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取 Workspace 详情失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取 Workspace 详情失败: {str(e)}"
        )


@router.put("/{workspace_id}", response_model=BaseResponse)
async def update_workspace(
    workspace_id: int,
    workspace_data: WorkspaceUpdate,
    current_user: dict = Depends(get_current_user)
):
    """
    更新 Workspace
    
    Args:
        workspace_id: Workspace ID
        workspace_data: Workspace 更新数据
        current_user: 当前用户信息
    
    Returns:
        更新后的 Workspace 信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 检查是否有管理权限
    has_permission = await check_workspace_permission(workspace_id, user_id, 'manage_settings')
    if not has_permission:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权限修改 Workspace 设置"
        )
    
    try:
        with pool.get_connection() as conn:
            # 检查是否为本地 workspace（本地 workspace 不能设置为共享）
            storage_type = await get_workspace_storage_type(workspace_id)
            if storage_type == 'local' and workspace_data.is_shared == True:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="本地 Workspace 不支持共享功能"
                )
            
            # 构建更新语句
            updates = []
            params = []
            
            if workspace_data.name is not None:
                updates.append("name = ?")
                params.append(workspace_data.name)
            
            if workspace_data.description is not None:
                updates.append("description = ?")
                params.append(workspace_data.description)
            
            if workspace_data.is_shared is not None:
                updates.append("is_shared = ?")
                params.append(1 if workspace_data.is_shared else 0)
            
            if not updates:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="没有要更新的字段"
                )
            
            updates.append("updated_at = datetime('now')")
            params.append(workspace_id)
            
            conn.execute(
                f"UPDATE workspaces SET {', '.join(updates)} WHERE id = ?",
                tuple(params)
            )
            conn.commit()
            
            # 获取更新后的 workspace
            cursor = conn.execute(
                "SELECT id, name, description, ownerId, storage_type, is_shared, created_at, updated_at FROM workspaces WHERE id = ?",
                (workspace_id,)
            )
            row = cursor.fetchone()
            
            workspace = WorkspaceResponse(
                id=row[0],
                name=row[1],
                description=row[2],
                ownerId=row[3],
                storage_type=row[4],
                is_shared=bool(row[5]),
                created_at=row[6],
                updated_at=row[7]
            )
            
            return BaseResponse(
                success=True,
                message="更新 Workspace 成功",
                data=workspace.model_dump()
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"更新 Workspace 失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新 Workspace 失败: {str(e)}"
        )


@router.post("/{workspace_id}/delete", response_model=BaseResponse)
async def delete_workspace(
    workspace_id: int,
    delete_data: WorkspaceDeleteRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    删除 Workspace（只有 owner 可以删除，需要密码验证）
    
    Args:
        workspace_id: Workspace ID
        delete_data: 删除请求（包含密码）
        current_user: 当前用户信息
    
    Returns:
        删除成功响应
    """
    from server.middleware.core import verify_password
    
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 检查是否是 owner
            cursor = conn.execute(
                "SELECT ownerId FROM workspaces WHERE id = ?",
                (workspace_id,)
            )
            workspace = cursor.fetchone()
            
            if not workspace:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Workspace 不存在"
                )
            
            if workspace[0] != user_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="只有 Workspace 拥有者可以删除"
                )
            
            # 验证密码
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
            if not verify_password(delete_data.password, hashed_password):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="密码不正确，无法删除 Workspace"
                )
            
            # 删除 workspace（外键约束会自动删除相关数据）
            conn.execute("DELETE FROM workspaces WHERE id = ?", (workspace_id,))
            conn.commit()
            
            logger.info(f"用户 {current_user['username']} (ID: {user_id}) 删除 Workspace (ID: {workspace_id})")
            
            return BaseResponse(
                success=True,
                message="删除 Workspace 成功"
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"删除 Workspace 失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"删除 Workspace 失败: {str(e)}"
        )


@router.get("/{workspace_id}/members", response_model=BaseResponse)
async def get_workspace_members(
    workspace_id: int,
    current_user: dict = Depends(get_current_user)
):
    """
    获取 Workspace 成员列表
    
    Args:
        workspace_id: Workspace ID
        current_user: 当前用户信息
    
    Returns:
        成员列表
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 检查访问权限
    has_access = await check_workspace_access(workspace_id, user_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问该 Workspace"
        )
    
    # 检查是否为本地 workspace（本地 workspace 不支持成员管理）
    storage_type = await get_workspace_storage_type(workspace_id)
    if storage_type == 'local':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="本地 Workspace 不支持成员管理功能"
        )
    
    try:
        with pool.get_connection() as conn:
            # 获取 owner
            cursor = conn.execute('''
                SELECT w.id, w.ownerId, u.username
                FROM workspaces w
                JOIN users u ON w.ownerId = u.id
                WHERE w.id = ?
            ''', (workspace_id,))
            owner_row = cursor.fetchone()
            
            members = []
            if owner_row:
                # 添加 owner
                members.append({
                    'id': 0,  # 使用0表示owner，不是真正的member记录ID
                    'workspaceId': workspace_id,
                    'userId': owner_row[1],
                    'username': owner_row[2],
                    'role': 'owner',
                    'joined_at': None
                })
            
            # 获取其他成员（包含邀请者用户名）
            # 注意：排除 role='owner' 的记录，因为 owner 已经通过 workspaces.ownerId 单独处理
            # 这样可以避免 owner 在成员列表中显示两次
            cursor = conn.execute('''
                SELECT wm.id, wm.workspaceId, wm.userId, u.username, wm.role, wm.joined_at, 
                       wm.invited_by, inviter.username as invited_by_username
                FROM workspace_members wm
                JOIN users u ON wm.userId = u.id
                LEFT JOIN users inviter ON wm.invited_by = inviter.id
                WHERE wm.workspaceId = ? AND wm.role != 'owner'
            ''', (workspace_id,))
            rows = cursor.fetchall()
            
            for row in rows:
                members.append({
                    'id': row[0],
                    'workspaceId': row[1],
                    'userId': row[2],
                    'username': row[3],
                    'role': row[4],
                    'joined_at': row[5],
                    'invited_by': row[6],
                    'invited_by_username': row[7] if row[7] else None
                })
            
            return BaseResponse(
                success=True,
                message="获取成员列表成功",
                data=members
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取成员列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取成员列表失败: {str(e)}"
        )


@router.post("/{workspace_id}/members/invite", response_model=BaseResponse)
async def invite_member(
    workspace_id: int,
    invite_data: WorkspaceInviteRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    邀请用户加入 Workspace
    
    Args:
        workspace_id: Workspace ID
        invite_data: 邀请数据
        current_user: 当前用户信息
    
    Returns:
        邀请成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 检查是否为本地 workspace（本地 workspace 不支持成员管理）
    storage_type = await get_workspace_storage_type(workspace_id)
    if storage_type == 'local':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="本地 Workspace 不支持成员管理功能"
        )
    
    # 检查是否有管理成员权限
    has_permission = await check_workspace_permission(workspace_id, user_id, 'manage_members')
    if not has_permission:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权限邀请成员"
        )
    
    if not invite_data.username and not invite_data.email and not invite_data.userId:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="必须提供 username、email 或 userId"
        )
    
    try:
        with pool.get_connection() as conn:
            # 如果提供了 userId，检查用户是否存在
            target_user_id = None
            if invite_data.userId:
                cursor = conn.execute(
                    "SELECT id FROM users WHERE id = ?",
                    (invite_data.userId,)
                )
                user = cursor.fetchone()
                if not user:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail="用户不存在"
                    )
                target_user_id = invite_data.userId
            # 如果提供了 username，通过用户名查找用户
            elif invite_data.username:
                cursor = conn.execute(
                    "SELECT id FROM users WHERE username = ?",
                    (invite_data.username,)
                )
                user = cursor.fetchone()
                if not user:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail=f"用户名 '{invite_data.username}' 不存在"
                    )
                target_user_id = user[0]
                
                # 检查用户是否已经是成员
                cursor = conn.execute(
                    "SELECT id FROM workspace_members WHERE workspaceId = ? AND userId = ?",
                    (workspace_id, target_user_id)
                )
                existing_member = cursor.fetchone()
                if existing_member:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="该用户已经是成员"
                    )
                
                # 检查用户是否是 owner
                cursor = conn.execute(
                    "SELECT id FROM workspaces WHERE id = ? AND ownerId = ?",
                    (workspace_id, target_user_id)
                )
                is_owner = cursor.fetchone()
                if is_owner:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="该用户是 Workspace 拥有者，无需邀请"
                    )
            
            # 如果找到了用户ID（通过username或userId），直接添加为成员（不需要邀请流程）
            if target_user_id:
                # 直接添加为成员
                conn.execute('''
                    INSERT INTO workspace_members 
                    (workspaceId, userId, role, invited_by, joined_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                ''', (
                    workspace_id,
                    target_user_id,
                    invite_data.role,
                    user_id
                ))
                conn.commit()
                
                return BaseResponse(
                    success=True,
                    message="成员已添加"
                )
            
            # 如果没有找到用户（通过email邀请，用于将来扩展），创建邀请记录
            if invite_data.email:
                # 生成邀请令牌
                token = secrets.token_urlsafe(32)
                expires_at = (datetime.now() + timedelta(days=7)).isoformat()
                
                # 创建邀请记录
                conn.execute('''
                    INSERT INTO workspace_invitations 
                    (workspaceId, email, userId, role, token, invited_by, expires_at, status, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'))
                ''', (
                    workspace_id,
                    invite_data.email,
                    None,  # userId 为 None，因为用户不存在
                    invite_data.role,
                    token,
                    user_id,
                    expires_at
                ))
                conn.commit()
                
                return BaseResponse(
                    success=True,
                    message="邀请已发送",
                    data={'token': token}
                )
            
            # 如果既没有找到用户，也没有提供email，返回错误
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="无法找到用户，请检查用户名是否正确"
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"邀请成员失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"邀请成员失败: {str(e)}"
        )


@router.put("/{workspace_id}/members/{member_user_id}", response_model=BaseResponse)
async def update_member_role(
    workspace_id: int,
    member_user_id: int,
    update_data: WorkspaceMemberUpdate,
    current_user: dict = Depends(get_current_user)
):
    """
    更新成员权限
    
    Args:
        workspace_id: Workspace ID
        member_user_id: 成员用户 ID
        update_data: 更新数据
        current_user: 当前用户信息
    
    Returns:
        更新成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 检查是否为本地 workspace（本地 workspace 不支持成员管理）
    storage_type = await get_workspace_storage_type(workspace_id)
    if storage_type == 'local':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="本地 Workspace 不支持成员管理功能"
        )
    
    # 检查是否有管理成员权限
    has_permission = await check_workspace_permission(workspace_id, user_id, 'manage_members')
    if not has_permission:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权限修改成员权限"
        )
    
    # 不能修改 owner 的权限
    with pool.get_connection() as conn:
        cursor = conn.execute(
            "SELECT ownerId FROM workspaces WHERE id = ?",
            (workspace_id,)
        )
        owner = cursor.fetchone()
        if owner and owner[0] == member_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="不能修改 Workspace 拥有者的权限"
            )
    
    try:
        with pool.get_connection() as conn:
            # 检查成员是否存在
            cursor = conn.execute(
                "SELECT id FROM workspace_members WHERE workspaceId = ? AND userId = ?",
                (workspace_id, member_user_id)
            )
            member = cursor.fetchone()
            if not member:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="成员不存在"
                )
            
            conn.execute('''
                UPDATE workspace_members 
                SET role = ? 
                WHERE workspaceId = ? AND userId = ?
            ''', (update_data.role, workspace_id, member_user_id))
            conn.commit()
            
            return BaseResponse(
                success=True,
                message="更新成员权限成功"
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"更新成员权限失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新成员权限失败: {str(e)}"
        )


@router.delete("/{workspace_id}/members/{member_user_id}", response_model=BaseResponse)
async def remove_member(
    workspace_id: int,
    member_user_id: int,
    current_user: dict = Depends(get_current_user)
):
    """
    移除成员
    
    Args:
        workspace_id: Workspace ID
        member_user_id: 成员用户 ID
        current_user: 当前用户信息
    
    Returns:
        移除成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 检查是否为本地 workspace（本地 workspace 不支持成员管理）
    storage_type = await get_workspace_storage_type(workspace_id)
    if storage_type == 'local':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="本地 Workspace 不支持成员管理功能"
        )
    
    # 检查是否有管理成员权限
    has_permission = await check_workspace_permission(workspace_id, user_id, 'manage_members')
    if not has_permission:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权限移除成员"
        )
    
    # 不能移除 owner
    with pool.get_connection() as conn:
        cursor = conn.execute(
            "SELECT ownerId FROM workspaces WHERE id = ?",
            (workspace_id,)
        )
        owner = cursor.fetchone()
        if owner and owner[0] == member_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="不能移除 Workspace 拥有者"
            )
    
    try:
        with pool.get_connection() as conn:
            # 检查成员是否存在
            cursor = conn.execute(
                "SELECT id FROM workspace_members WHERE workspaceId = ? AND userId = ?",
                (workspace_id, member_user_id)
            )
            member = cursor.fetchone()
            if not member:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="成员不存在"
                )
            
            conn.execute('''
                DELETE FROM workspace_members 
                WHERE workspaceId = ? AND userId = ?
            ''', (workspace_id, member_user_id))
            conn.commit()
            
            return BaseResponse(
                success=True,
                message="移除成员成功"
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"移除成员失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"移除成员失败: {str(e)}"
        )


@router.post("/invitations/{token}/accept", response_model=BaseResponse)
async def accept_invitation(
    token: str,
    current_user: dict = Depends(get_current_user)
):
    """
    接受 Workspace 邀请
    
    Args:
        token: 邀请令牌
        current_user: 当前用户信息
    
    Returns:
        接受成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 查找邀请记录
            cursor = conn.execute('''
                SELECT id, workspaceId, userId, role, expires_at, status
                FROM workspace_invitations
                WHERE token = ?
            ''', (token,))
            invitation = cursor.fetchone()
            
            if not invitation:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="邀请不存在或已过期"
                )
            
            inv_id, workspace_id, inv_user_id, role, expires_at, inv_status = invitation
            
            # 检查邀请状态
            if inv_status != 'pending':
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="邀请已被处理"
                )
            
            # 检查是否过期
            if expires_at:
                expires = datetime.fromisoformat(expires_at)
                if datetime.now() > expires:
                    conn.execute('''
                        UPDATE workspace_invitations 
                        SET status = 'expired' 
                        WHERE id = ?
                    ''', (inv_id,))
                    conn.commit()
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="邀请已过期"
                    )
            
            # 如果邀请指定了 userId，检查是否匹配
            if inv_user_id and inv_user_id != user_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="此邀请不是发给您的"
                )
            
            # 检查用户是否已经是成员
            cursor = conn.execute('''
                SELECT id FROM workspace_members 
                WHERE workspaceId = ? AND userId = ?
            ''', (workspace_id, user_id))
            existing_member = cursor.fetchone()
            
            if existing_member:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="您已经是该 Workspace 的成员"
                )
            
            # 添加成员
            conn.execute('''
                INSERT INTO workspace_members (workspaceId, userId, role, joined_at)
                VALUES (?, ?, ?, datetime('now'))
            ''', (workspace_id, user_id, role))
            
            # 更新邀请状态
            conn.execute('''
                UPDATE workspace_invitations 
                SET status = 'accepted' 
                WHERE id = ?
            ''', (inv_id,))
            
            conn.commit()
            
            return BaseResponse(
                success=True,
                message="已成功加入 Workspace"
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"接受邀请失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"接受邀请失败: {str(e)}"
        )


@router.post("/{workspace_id}/import-data", response_model=BaseResponse)
async def import_workspace_data(
    workspace_id: int,
    import_request: ImportDataRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    批量导入数据到指定 Workspace（覆盖模式）
    
    删除指定 Workspace 的所有业务数据，然后导入新数据。
    只有 Workspace 的拥有者和管理员可以执行此操作。
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        # 检查 workspace 访问权限
        has_access = await check_workspace_access(workspace_id, user_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="无权限访问此 Workspace"
            )
        
        # 检查是否为服务器存储类型
        storage_type = await get_workspace_storage_type(workspace_id)
        if storage_type != 'server':
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="本地 Workspace 的数据导入应在客户端执行"
            )
        
        # 检查 manage_settings 权限（只有 owner 和 admin 可以导入）
        can_manage = await check_workspace_permission(workspace_id, user_id, 'manage_settings')
        if not can_manage:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="只有 Workspace 拥有者和管理员可以导入数据"
            )
        
        with pool.get_connection() as conn:
            conn.execute("BEGIN")
            
            try:
                # 1. 删除该 workspace 的所有业务数据
                conn.execute("DELETE FROM remittance WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM income WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM returns WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM sales WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM purchases WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM products WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM employees WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM customers WHERE workspaceId = ?", (workspace_id,))
                conn.execute("DELETE FROM suppliers WHERE workspaceId = ?", (workspace_id,))
                
                # 2. 创建 ID 映射表
                supplier_id_map = {}
                customer_id_map = {}
                employee_id_map = {}
                product_id_map = {}
                
                data = import_request.data
                
                # 3. 导入 suppliers
                supplier_count = 0
                if 'suppliers' in data and data['suppliers']:
                    for supplier_data in data['suppliers']:
                        original_id = supplier_data.get('id')
                        cursor = conn.execute(
                            """
                            INSERT INTO suppliers (userId, workspaceId, name, note, created_at, updated_at)
                            VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                            """,
                            (user_id, workspace_id, supplier_data.get('name', ''), supplier_data.get('note'))
                        )
                        new_id = cursor.lastrowid
                        if original_id:
                            supplier_id_map[original_id] = new_id
                        supplier_count += 1
                
                # 4. 导入 customers
                customer_count = 0
                if 'customers' in data and data['customers']:
                    for customer_data in data['customers']:
                        original_id = customer_data.get('id')
                        cursor = conn.execute(
                            """
                            INSERT INTO customers (userId, workspaceId, name, note, created_at, updated_at)
                            VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                            """,
                            (user_id, workspace_id, customer_data.get('name', ''), customer_data.get('note'))
                        )
                        new_id = cursor.lastrowid
                        if original_id:
                            customer_id_map[original_id] = new_id
                        customer_count += 1
                
                # 5. 导入 employees
                employee_count = 0
                if 'employees' in data and data['employees']:
                    for employee_data in data['employees']:
                        original_id = employee_data.get('id')
                        cursor = conn.execute(
                            """
                            INSERT INTO employees (userId, workspaceId, name, note, created_at, updated_at)
                            VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                            """,
                            (user_id, workspace_id, employee_data.get('name', ''), employee_data.get('note'))
                        )
                        new_id = cursor.lastrowid
                        if original_id:
                            employee_id_map[original_id] = new_id
                        employee_count += 1
                
                # 6. 导入 products
                product_count = 0
                if 'products' in data and data['products']:
                    for product_data in data['products']:
                        original_id = product_data.get('id')
                        supplier_id = product_data.get('supplierId')
                        if supplier_id and supplier_id in supplier_id_map:
                            supplier_id = supplier_id_map[supplier_id]
                        elif supplier_id and supplier_id not in supplier_id_map:
                            supplier_id = None
                        
                        unit = product_data.get('unit', '公斤')
                        if unit not in ['斤', '公斤', '袋']:
                            unit = '公斤'
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO products (userId, workspaceId, name, description, stock, unit, supplierId, version, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                            """,
                            (user_id, workspace_id, product_data.get('name', ''), product_data.get('description'),
                             product_data.get('stock', 0), unit, supplier_id)
                        )
                        new_id = cursor.lastrowid
                        if original_id:
                            product_id_map[original_id] = new_id
                        product_count += 1
                
                # 7. 导入 purchases
                purchase_count = 0
                if 'purchases' in data and data['purchases']:
                    for purchase_data in data['purchases']:
                        supplier_id = purchase_data.get('supplierId')
                        if supplier_id == 0:
                            supplier_id = None
                        elif supplier_id and supplier_id in supplier_id_map:
                            supplier_id = supplier_id_map[supplier_id]
                        elif supplier_id and supplier_id not in supplier_id_map:
                            supplier_id = None
                        
                        conn.execute(
                            """
                            INSERT INTO purchases (userId, workspaceId, productName, quantity, purchaseDate, supplierId, totalPurchasePrice, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (user_id, workspace_id, purchase_data.get('productName', ''), purchase_data.get('quantity', 0),
                             purchase_data.get('purchaseDate'), supplier_id, purchase_data.get('totalPurchasePrice'), purchase_data.get('note'))
                        )
                        purchase_count += 1
                
                # 8. 导入 sales
                sale_count = 0
                if 'sales' in data and data['sales']:
                    for sale_data in data['sales']:
                        customer_id = sale_data.get('customerId')
                        if customer_id and customer_id in customer_id_map:
                            customer_id = customer_id_map[customer_id]
                        elif customer_id and customer_id not in customer_id_map:
                            customer_id = None
                        
                        conn.execute(
                            """
                            INSERT INTO sales (userId, workspaceId, productName, quantity, saleDate, customerId, totalSalePrice, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (user_id, workspace_id, sale_data.get('productName', ''), sale_data.get('quantity', 0),
                             sale_data.get('saleDate'), customer_id, sale_data.get('totalSalePrice'), sale_data.get('note'))
                        )
                        sale_count += 1
                
                # 9. 导入 returns
                return_count = 0
                if 'returns' in data and data['returns']:
                    for return_data in data['returns']:
                        customer_id = return_data.get('customerId')
                        if customer_id and customer_id in customer_id_map:
                            customer_id = customer_id_map[customer_id]
                        elif customer_id and customer_id not in customer_id_map:
                            customer_id = None
                        
                        conn.execute(
                            """
                            INSERT INTO returns (userId, workspaceId, productName, quantity, returnDate, customerId, totalReturnPrice, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (user_id, workspace_id, return_data.get('productName', ''), return_data.get('quantity', 0),
                             return_data.get('returnDate'), customer_id, return_data.get('totalReturnPrice'), return_data.get('note'))
                        )
                        return_count += 1
                
                # 10. 导入 income
                income_count = 0
                if 'income' in data and data['income']:
                    for income_data in data['income']:
                        customer_id = income_data.get('customerId')
                        if customer_id and customer_id in customer_id_map:
                            customer_id = customer_id_map[customer_id]
                        elif customer_id and customer_id not in customer_id_map:
                            customer_id = None
                        
                        employee_id = income_data.get('employeeId')
                        if employee_id and employee_id in employee_id_map:
                            employee_id = employee_id_map[employee_id]
                        elif employee_id and employee_id not in employee_id_map:
                            employee_id = None
                        
                        conn.execute(
                            """
                            INSERT INTO income (userId, workspaceId, incomeDate, customerId, amount, discount, employeeId, paymentMethod, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (user_id, workspace_id, income_data.get('incomeDate'), customer_id, income_data.get('amount', 0),
                             income_data.get('discount', 0), employee_id, income_data.get('paymentMethod', '现金'), income_data.get('note'))
                        )
                        income_count += 1
                
                # 11. 导入 remittance
                remittance_count = 0
                if 'remittance' in data and data['remittance']:
                    for remittance_data in data['remittance']:
                        supplier_id = remittance_data.get('supplierId')
                        if supplier_id and supplier_id in supplier_id_map:
                            supplier_id = supplier_id_map[supplier_id]
                        elif supplier_id and supplier_id not in supplier_id_map:
                            supplier_id = None
                        
                        employee_id = remittance_data.get('employeeId')
                        if employee_id and employee_id in employee_id_map:
                            employee_id = employee_id_map[employee_id]
                        elif employee_id and employee_id not in employee_id_map:
                            employee_id = None
                        
                        conn.execute(
                            """
                            INSERT INTO remittance (userId, workspaceId, remittanceDate, supplierId, amount, employeeId, paymentMethod, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (user_id, workspace_id, remittance_data.get('remittanceDate'), supplier_id,
                             remittance_data.get('amount', 0), employee_id, remittance_data.get('paymentMethod', '现金'), remittance_data.get('note'))
                        )
                        remittance_count += 1
                
                conn.execute("COMMIT")
                
                logger.info(f"Workspace {workspace_id} 数据导入成功: 用户 {user_id}")
                
                return BaseResponse(
                    success=True,
                    message="数据导入成功",
                    data={
                        "counts": {
                            "suppliers": supplier_count,
                            "customers": customer_count,
                            "employees": employee_count,
                            "products": product_count,
                            "purchases": purchase_count,
                            "sales": sale_count,
                            "returns": return_count,
                            "income": income_count,
                            "remittance": remittance_count
                        }
                    }
                )
                
            except Exception as e:
                conn.execute("ROLLBACK")
                raise e
                
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Workspace {workspace_id} 数据导入失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"数据导入失败: {str(e)}"
        )

