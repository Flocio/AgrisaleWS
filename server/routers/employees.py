"""
员工管理路由
处理员工的增删改查功能
"""

import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends, Query, Header

from server.database import get_pool
from server.middleware import get_current_user
from server.middleware.workspace_permission import (
    check_workspace_access,
    check_workspace_permission,
    require_server_storage
)
from server.models import (
    EmployeeCreate,
    EmployeeUpdate,
    EmployeeResponse,
    BaseResponse,
    PaginationParams,
    PaginatedResponse
)
from server.services.audit_log_service import AuditLogService

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/employees", tags=["员工管理"])


@router.get("", response_model=BaseResponse)
async def get_employees(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=10000, description="每页数量（最大 10000）"),
    search: Optional[str] = Query(None, description="搜索关键词（员工名称或备注）"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取员工列表（支持分页、搜索）
    
    Args:
        page: 页码
        page_size: 每页数量
        search: 搜索关键词
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        员工列表（分页）
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 构建查询条件
            # 如果提供了workspace_id，使用workspace过滤；否则使用userId过滤（向后兼容）
            if workspace_id is not None:
                # 检查是否为服务器存储类型（本地 workspace 的业务数据存储在客户端）
                await require_server_storage(workspace_id, user_id)
                # 检查读取权限
                can_read = await check_workspace_permission(workspace_id, user_id, 'read')
                if not can_read:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="无读取权限"
                    )
                where_conditions = ["workspaceId = ?"]
                params = [workspace_id]
            else:
                # 向后兼容：使用userId过滤
                where_conditions = ["userId = ?"]
                params = [user_id]
            
            # 搜索条件
            if search:
                where_conditions.append("(name LIKE ? OR note LIKE ?)")
                search_pattern = f"%{search}%"
                params.extend([search_pattern, search_pattern])
            
            where_clause = " AND ".join(where_conditions)
            
            # 获取总数
            count_cursor = conn.execute(
                f"SELECT COUNT(*) FROM employees WHERE {where_clause}",
                tuple(params)
            )
            total = count_cursor.fetchone()[0]
            
            # 计算分页
            offset = (page - 1) * page_size
            total_pages = (total + page_size - 1) // page_size
            
            # 获取员工列表
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, note, created_at, updated_at
                FROM employees
                WHERE {where_clause}
                ORDER BY updated_at DESC, name ASC
                LIMIT ? OFFSET ?
                """,
                tuple(params) + (page_size, offset)
            )
            rows = cursor.fetchall()
            
            # 转换为响应模型
            employees = []
            for row in rows:
                employee = EmployeeResponse(
                    id=row[0],
                    userId=row[1],
                    name=row[2],
                    note=row[3],
                    created_at=row[4],
                    updated_at=row[5]
                )
                employees.append(employee.model_dump())
            
            paginated_data = PaginatedResponse(
                items=employees,
                total=total,
                page=page,
                page_size=page_size,
                total_pages=total_pages
            )
            
            return BaseResponse(
                success=True,
                message="获取员工列表成功",
                data=paginated_data.model_dump()
            )
            
    except Exception as e:
        logger.error(f"获取员工列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取员工列表失败: {str(e)}"
        )


@router.get("/all", response_model=BaseResponse)
async def get_all_employees(
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取所有员工（不分页，用于下拉选择等场景）
    
    Args:
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        所有员工列表
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 如果提供了workspace_id，检查权限
    if workspace_id is not None:
        await require_server_storage(workspace_id, user_id)
        can_read = await check_workspace_permission(workspace_id, user_id, 'read')
        if not can_read:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="无读取权限"
            )
    
    try:
        with pool.get_connection() as conn:
            if workspace_id is not None:
                cursor = conn.execute(
                    """
                    SELECT id, userId, name, note, created_at, updated_at
                    FROM employees
                    WHERE workspaceId = ?
                    ORDER BY name ASC
                    """,
                    (workspace_id,)
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT id, userId, name, note, created_at, updated_at
                    FROM employees
                    WHERE userId = ?
                    ORDER BY name ASC
                    """,
                    (user_id,)
                )
            rows = cursor.fetchall()
            
            employees = []
            for row in rows:
                employee = EmployeeResponse(
                    id=row[0],
                    userId=row[1],
                    name=row[2],
                    note=row[3],
                    created_at=row[4],
                    updated_at=row[5]
                )
                employees.append(employee.model_dump())
            
            return BaseResponse(
                success=True,
                message="获取员工列表成功",
                data={"employees": employees, "count": len(employees)}
            )
            
    except Exception as e:
        logger.error(f"获取员工列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取员工列表失败: {str(e)}"
        )


@router.get("/{employee_id}", response_model=BaseResponse)
async def get_employee(
    employee_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取单个员工详情
    
    Args:
        employee_id: 员工ID
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        员工详情
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 构建查询条件
            if workspace_id is not None:
                # 检查是否为服务器存储类型（本地 workspace 的业务数据存储在客户端）
                await require_server_storage(workspace_id, user_id)
                # 检查读取权限
                can_read = await check_workspace_permission(workspace_id, user_id, 'read')
                if not can_read:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="无读取权限"
                    )
                where_clause = "id = ? AND workspaceId = ?"
                params = (employee_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (employee_id, user_id)
            
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, note, created_at, updated_at
                FROM employees
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="员工不存在或无权限访问"
                )
            
            employee = EmployeeResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                note=row[3],
                created_at=row[4],
                updated_at=row[5]
            )
            
            return BaseResponse(
                success=True,
                message="获取员工详情成功",
                data=employee.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取员工详情失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取员工详情失败: {str(e)}"
        )


@router.post("", response_model=BaseResponse, status_code=status.HTTP_201_CREATED)
async def create_employee(
    employee_data: EmployeeCreate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    创建员工
    
    Args:
        employee_data: 员工数据
        workspace_id: Workspace ID（可选，如果提供则创建到该workspace）
        current_user: 当前用户信息
    
    Returns:
        创建的员工信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 如果提供了workspace_id，检查权限
            if workspace_id is not None:
                # 检查是否为服务器存储类型（本地 workspace 的业务数据存储在客户端）
                await require_server_storage(workspace_id, user_id)
                # 检查创建权限
                can_create = await check_workspace_permission(workspace_id, user_id, 'create')
                if not can_create:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="无创建权限"
                    )
                # 检查同一workspace下员工名称是否已存在
                cursor = conn.execute(
                    "SELECT id FROM employees WHERE workspaceId = ? AND name = ?",
                    (workspace_id, employee_data.name)
                )
                existing = cursor.fetchone()
                
                if existing:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"员工名称 '{employee_data.name}' 已存在"
                    )
                
                # 插入员工（包含workspaceId）
                cursor = conn.execute(
                    """
                    INSERT INTO employees (userId, workspaceId, name, note, created_at, updated_at)
                    VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                    """,
                    (
                        user_id,
                        workspace_id,
                        employee_data.name,
                        employee_data.note
                    )
                )
            else:
                # 向后兼容：不设置workspaceId
                # 检查同一用户下员工名称是否已存在
                cursor = conn.execute(
                    "SELECT id FROM employees WHERE userId = ? AND name = ?",
                    (user_id, employee_data.name)
                )
                existing = cursor.fetchone()
                
                if existing:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"员工名称 '{employee_data.name}' 已存在"
                    )
                
                # 插入员工（不包含workspaceId）
                cursor = conn.execute(
                    """
                    INSERT INTO employees (userId, name, note, created_at, updated_at)
                    VALUES (?, ?, ?, datetime('now'), datetime('now'))
                    """,
                    (
                        user_id,
                        employee_data.name,
                        employee_data.note
                    )
                )
            employee_id = cursor.lastrowid
            conn.commit()
            
            # 获取创建的员工
            cursor = conn.execute(
                """
                SELECT id, userId, name, note, created_at, updated_at
                FROM employees
                WHERE id = ?
                """,
                (employee_id,)
            )
            row = cursor.fetchone()
            
            employee = EmployeeResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                note=row[3],
                created_at=row[4],
                updated_at=row[5]
            )
            
            logger.info(f"创建员工成功: {employee_data.name} (ID: {employee_id}, 用户: {user_id})")
            
            # 记录操作日志
            try:
                AuditLogService.log_create(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="employee",
                    entity_id=employee_id,
                    entity_name=employee_data.name,
                    new_data=employee.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录员工创建日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="创建员工成功",
                data=employee.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"创建员工失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"创建员工失败: {str(e)}"
        )


@router.put("/{employee_id}", response_model=BaseResponse)
async def update_employee(
    employee_id: int,
    employee_data: EmployeeUpdate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    更新员工
    
    Args:
        employee_id: 员工ID
        employee_data: 员工更新数据
        workspace_id: Workspace ID（可选，如果提供则只更新该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        更新后的员工信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 构建查询条件
            if workspace_id is not None:
                # 检查是否为服务器存储类型（本地 workspace 的业务数据存储在客户端）
                await require_server_storage(workspace_id, user_id)
                # 检查更新权限
                can_update = await check_workspace_permission(workspace_id, user_id, 'update')
                if not can_update:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="无更新权限"
                    )
                where_clause = "id = ? AND workspaceId = ?"
                params = (employee_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (employee_id, user_id)
            
            # 获取当前员工完整信息用于日志记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, note, created_at, updated_at
                FROM employees
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="员工不存在或无权限访问"
                )
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "name": row[2],
                "note": row[3],
                "created_at": row[4],
                "updated_at": row[5]
            }
            
            # 检查员工名称唯一性（如果修改了名称）
            if employee_data.name and employee_data.name != row[2]:
                if workspace_id is not None:
                    name_cursor = conn.execute(
                        "SELECT id FROM employees WHERE workspaceId = ? AND name = ? AND id != ?",
                        (workspace_id, employee_data.name, employee_id)
                    )
                else:
                    name_cursor = conn.execute(
                        "SELECT id FROM employees WHERE userId = ? AND name = ? AND id != ?",
                        (user_id, employee_data.name, employee_id)
                    )
                if name_cursor.fetchone():
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"员工名称 '{employee_data.name}' 已存在"
                    )
            
            # 构建更新字段
            update_fields = []
            update_values = []
            
            if employee_data.name is not None:
                update_fields.append("name = ?")
                update_values.append(employee_data.name)
            
            if employee_data.note is not None:
                update_fields.append("note = ?")
                update_values.append(employee_data.note)
            
            if not update_fields:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="没有提供要更新的字段"
                )
            
            # 更新更新时间
            update_fields.append("updated_at = datetime('now')")
            update_values.append(employee_id)
            
            # 执行更新
            if workspace_id is not None:
                update_sql = f"""
                    UPDATE employees
                    SET {', '.join(update_fields)}
                    WHERE id = ? AND workspaceId = ?
                """
                update_values.append(workspace_id)
            else:
                update_sql = f"""
                    UPDATE employees
                    SET {', '.join(update_fields)}
                    WHERE id = ? AND userId = ?
                """
                update_values.append(user_id)
            
            conn.execute(update_sql, tuple(update_values))
            conn.commit()
            
            # 获取更新后的员工
            cursor = conn.execute(
                """
                SELECT id, userId, name, note, created_at, updated_at
                FROM employees
                WHERE id = ?
                """,
                (employee_id,)
            )
            row = cursor.fetchone()
            
            employee = EmployeeResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                note=row[3],
                created_at=row[4],
                updated_at=row[5]
            )
            
            logger.info(f"更新员工成功: {employee_id} (用户: {user_id})")
            
            # 记录操作日志
            try:
                AuditLogService.log_update(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="employee",
                    entity_id=employee_id,
                    entity_name=employee.name,
                    old_data=old_data,
                    new_data=employee.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录员工更新日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="更新员工成功",
                data=employee.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"更新员工失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新员工失败: {str(e)}"
        )


@router.delete("/{employee_id}", response_model=BaseResponse)
async def delete_employee(
    employee_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    删除员工
    
    注意：删除员工不会删除相关的进账、汇款记录，这些记录的 employeeId 会被设置为 NULL
    
    Args:
        employee_id: 员工ID
        workspace_id: Workspace ID（可选，如果提供则只删除该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        删除成功响应
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 构建查询条件
            if workspace_id is not None:
                # 检查是否为服务器存储类型（本地 workspace 的业务数据存储在客户端）
                await require_server_storage(workspace_id, user_id)
                # 检查删除权限
                can_delete = await check_workspace_permission(workspace_id, user_id, 'delete')
                if not can_delete:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="无删除权限"
                    )
                where_clause = "id = ? AND workspaceId = ?"
                params = (employee_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (employee_id, user_id)
            
            # 获取员工完整信息用于日志记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, note, created_at, updated_at
                FROM employees
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="员工不存在或无权限访问"
                )
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "name": row[2],
                "note": row[3],
                "created_at": row[4],
                "updated_at": row[5]
            }
            employee_name = row[2]
            
            # 删除员工（外键约束会自动将相关记录的 employeeId 设置为 NULL）
            conn.execute(
                f"DELETE FROM employees WHERE {where_clause}",
                params
            )
            conn.commit()
            
            logger.info(f"删除员工成功: {employee_name} (ID: {employee_id}, 用户: {user_id})")
            
            # 记录操作日志
            try:
                AuditLogService.log_delete(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="employee",
                    entity_id=employee_id,
                    entity_name=employee_name,
                    old_data=old_data,
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录员工删除日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="删除员工成功"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"删除员工失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"删除员工失败: {str(e)}"
        )


@router.get("/search/all", response_model=BaseResponse)
async def search_all_employees(
    search: str = Query(..., min_length=1, description="搜索关键词"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    搜索所有员工（不分页，用于下拉选择等场景）
    
    Args:
        search: 搜索关键词
        workspace_id: Workspace ID（可选，如果提供则只搜索该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        匹配的员工列表
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 如果提供了workspace_id，检查权限
    if workspace_id is not None:
        await require_server_storage(workspace_id, user_id)
        can_read = await check_workspace_permission(workspace_id, user_id, 'read')
        if not can_read:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="无读取权限"
            )
    
    try:
        with pool.get_connection() as conn:
            search_pattern = f"%{search}%"
            if workspace_id is not None:
                cursor = conn.execute(
                    """
                    SELECT id, userId, name, note, created_at, updated_at
                    FROM employees
                    WHERE workspaceId = ? AND (name LIKE ? OR note LIKE ?)
                    ORDER BY name
                    LIMIT 50
                    """,
                    (workspace_id, search_pattern, search_pattern)
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT id, userId, name, note, created_at, updated_at
                    FROM employees
                    WHERE userId = ? AND (name LIKE ? OR note LIKE ?)
                    ORDER BY name
                    LIMIT 50
                    """,
                    (user_id, search_pattern, search_pattern)
                )
            rows = cursor.fetchall()
            
            employees = []
            for row in rows:
                employee = EmployeeResponse(
                    id=row[0],
                    userId=row[1],
                    name=row[2],
                    note=row[3],
                    created_at=row[4],
                    updated_at=row[5]
                )
                employees.append(employee.model_dump())
            
            return BaseResponse(
                success=True,
                message="搜索员工成功",
                data={"employees": employees, "count": len(employees)}
            )
            
    except Exception as e:
        logger.error(f"搜索员工失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"搜索员工失败: {str(e)}"
        )


