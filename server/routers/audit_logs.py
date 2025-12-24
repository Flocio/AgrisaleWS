"""
操作日志路由
提供操作日志的查询、详情查看等功能
"""

import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends, Query, Header
from math import ceil

from server.database import get_pool
from server.middleware import get_current_user
from server.middleware.workspace_permission import (
    check_workspace_access,
    check_workspace_permission
)
from server.models import (
    BaseResponse,
    AuditLogResponse,
    AuditLogFilter,
    AuditLogListResponse,
    OperationType
)
from server.services.audit_log_service import AuditLogService

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/audit-logs", tags=["操作日志"])


@router.get("", response_model=BaseResponse)
async def get_audit_logs(
    page: int = Query(1, ge=1, description="页码，从1开始"),
    page_size: int = Query(20, ge=1, le=100, description="每页数量（最大100）"),
    operation_type: Optional[str] = Query(None, description="操作类型筛选（CREATE/UPDATE/DELETE）"),
    entity_type: Optional[str] = Query(None, description="实体类型筛选"),
    start_time: Optional[str] = Query(None, description="开始时间（ISO8601格式，如：2025-01-01T00:00:00）"),
    end_time: Optional[str] = Query(None, description="结束时间（ISO8601格式，如：2025-01-31T23:59:59）"),
    search: Optional[str] = Query(None, description="搜索关键词（实体名称、备注）"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取操作日志列表（支持分页和筛选）
    
    Args:
        page: 页码
        page_size: 每页数量
        operation_type: 操作类型筛选
        entity_type: 实体类型筛选
        start_time: 开始时间
        end_time: 结束时间
        search: 搜索关键词
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的日志）
        current_user: 当前用户信息
    
    Returns:
        操作日志列表（分页）
    """
    try:
        user_id = current_user["user_id"]
        
        # 如果提供了workspace_id，检查权限
        if workspace_id is not None:
            # 检查workspace访问权限
            has_access = await check_workspace_access(workspace_id, user_id)
            if not has_access:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无权访问该 Workspace"
                )
            # 检查读取权限
            can_read = await check_workspace_permission(workspace_id, user_id, 'read')
            if not can_read:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无读取权限"
                )
        
        # 验证操作类型
        if operation_type and operation_type not in ["CREATE", "UPDATE", "DELETE"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="无效的操作类型，必须是 CREATE、UPDATE 或 DELETE"
            )
        
        # 查询日志
        logs, total = AuditLogService.get_logs(
            user_id=user_id,
            workspace_id=workspace_id,
            page=page,
            page_size=page_size,
            operation_type=operation_type,
            entity_type=entity_type,
            start_time=start_time,
            end_time=end_time,
            search=search
        )
        
        # 转换为响应模型
        log_responses = [AuditLogResponse(**log) for log in logs]
        
        # 计算总页数
        total_pages = ceil(total / page_size) if page_size > 0 else 0
        
        return BaseResponse(
            success=True,
            message="查询成功",
            data=AuditLogListResponse(
                logs=log_responses,
                total=total,
                page=page,
                page_size=page_size,
                total_pages=total_pages
            ).model_dump()
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"查询操作日志失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"查询操作日志失败: {str(e)}"
        )


@router.get("/{log_id}", response_model=BaseResponse)
async def get_audit_log_detail(
    log_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取操作日志详情
    
    Args:
        log_id: 日志ID
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的日志）
        current_user: 当前用户信息
    
    Returns:
        操作日志详情
    """
    try:
        user_id = current_user["user_id"]
        
        # 如果提供了workspace_id，检查权限
        if workspace_id is not None:
            # 检查workspace访问权限
            has_access = await check_workspace_access(workspace_id, user_id)
            if not has_access:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无权访问该 Workspace"
                )
            # 检查读取权限
            can_read = await check_workspace_permission(workspace_id, user_id, 'read')
            if not can_read:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无读取权限"
                )
        
        log_detail = AuditLogService.get_log_detail(log_id, user_id, workspace_id)
        
        if not log_detail:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="操作日志不存在或无权限访问"
            )
        
        return BaseResponse(
            success=True,
            message="查询成功",
            data=AuditLogResponse(**log_detail).model_dump()
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"查询操作日志详情失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"查询操作日志详情失败: {str(e)}"
        )


@router.post("/cleanup", response_model=BaseResponse)
async def cleanup_old_logs(
    days: int = Query(730, ge=1, le=3650, description="保留天数（默认730天，即2年，最大3650天）"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    清理指定天数之前的旧日志（可选功能，用于管理员维护）
    
    Args:
        days: 保留天数
        workspace_id: Workspace ID（可选，如果提供则只清理该workspace的日志）
        current_user: 当前用户信息
    
    Returns:
        清理结果
    """
    try:
        user_id = current_user["user_id"]
        
        # 如果提供了workspace_id，检查权限
        if workspace_id is not None:
            # 检查workspace访问权限
            has_access = await check_workspace_access(workspace_id, user_id)
            if not has_access:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无权访问该 Workspace"
                )
            # 检查管理权限（只有owner和admin可以清理日志）
            can_manage = await check_workspace_permission(workspace_id, user_id, 'manage_settings')
            if not can_manage:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="无权限清理该 Workspace 的日志"
                )
        
        # 注意：这里可以根据需要添加管理员权限检查
        # 目前允许所有用户清理自己的日志（或workspace的日志）
        
        deleted_count = AuditLogService.cleanup_old_logs(days=days, user_id=user_id, workspace_id=workspace_id)
        
        return BaseResponse(
            success=True,
            message=f"清理完成，删除了 {deleted_count} 条 {days} 天前的日志",
            data={"deleted_count": deleted_count}
        )
    except Exception as e:
        logger.error(f"清理旧日志失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"清理旧日志失败: {str(e)}"
        )

