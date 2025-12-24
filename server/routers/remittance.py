"""
汇款管理路由
处理汇款记录的增删改查功能
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
    RemittanceCreate,
    RemittanceUpdate,
    RemittanceResponse,
    BaseResponse,
    PaginationParams,
    PaginatedResponse,
    DateRangeFilter
)
from server.services.audit_log_service import AuditLogService

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/remittance", tags=["汇款管理"])


@router.get("", response_model=BaseResponse)
async def get_remittance_records(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=10000, description="每页数量（最大 10000）"),
    search: Optional[str] = Query(None, description="搜索关键词（备注）"),
    start_date: Optional[str] = Query(None, description="开始日期（ISO8601格式）"),
    end_date: Optional[str] = Query(None, description="结束日期（ISO8601格式）"),
    supplier_id: Optional[int] = Query(None, description="供应商ID筛选"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取汇款记录列表（支持分页、搜索、日期筛选）
    
    Args:
        page: 页码
        page_size: 每页数量
        search: 搜索关键词
        start_date: 开始日期
        end_date: 结束日期
        supplier_id: 供应商ID筛选
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        汇款记录列表（分页）
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
                where_conditions.append("note LIKE ?")
                params.append(f"%{search}%")
            
            # 日期范围筛选
            if start_date:
                where_conditions.append("date(remittanceDate) >= date(?)")
                params.append(start_date)
            
            if end_date:
                where_conditions.append("date(remittanceDate) <= date(?)")
                params.append(end_date)
            
            # 供应商筛选
            if supplier_id is not None:
                if supplier_id == 0:
                    where_conditions.append("(supplierId IS NULL OR supplierId = 0)")
                else:
                    where_conditions.append("supplierId = ?")
                    params.append(supplier_id)
            
            where_clause = " AND ".join(where_conditions)
            
            # 获取总数
            count_cursor = conn.execute(
                f"SELECT COUNT(*) FROM remittance WHERE {where_clause}",
                tuple(params)
            )
            total = count_cursor.fetchone()[0]
            
            # 计算分页
            offset = (page - 1) * page_size
            total_pages = (total + page_size - 1) // page_size
            
            # 获取汇款记录列表
            cursor = conn.execute(
                f"""
                SELECT id, userId, remittanceDate, supplierId, amount, employeeId,
                       paymentMethod, note, created_at
                FROM remittance
                WHERE {where_clause}
                ORDER BY remittanceDate DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                tuple(params) + (page_size, offset)
            )
            rows = cursor.fetchall()
            
            # 转换为响应模型
            remittance_records = []
            for row in rows:
                remittance = RemittanceResponse(
                    id=row[0],
                    userId=row[1],
                    remittanceDate=row[2],
                    supplierId=row[3],
                    amount=row[4],
                    employeeId=row[5],
                    paymentMethod=row[6],
                    note=row[7],
                    created_at=row[8]
                )
                remittance_records.append(remittance.model_dump())
            
            paginated_data = PaginatedResponse(
                items=remittance_records,
                total=total,
                page=page,
                page_size=page_size,
                total_pages=total_pages
            )
            
            return BaseResponse(
                success=True,
                message="获取汇款记录列表成功",
                data=paginated_data.model_dump()
            )
            
    except Exception as e:
        logger.error(f"获取汇款记录列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取汇款记录列表失败: {str(e)}"
        )


@router.get("/{remittance_id}", response_model=BaseResponse)
async def get_remittance_record(
    remittance_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取单个汇款记录详情
    
    Args:
        remittance_id: 汇款记录ID
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        汇款记录详情
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
                params = (remittance_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (remittance_id, user_id)
            
            cursor = conn.execute(
                f"""
                SELECT id, userId, remittanceDate, supplierId, amount, employeeId,
                       paymentMethod, note, created_at
                FROM remittance
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="汇款记录不存在或无权限访问"
                )
            
            remittance = RemittanceResponse(
                id=row[0],
                userId=row[1],
                remittanceDate=row[2],
                supplierId=row[3],
                amount=row[4],
                employeeId=row[5],
                paymentMethod=row[6],
                note=row[7],
                created_at=row[8]
            )
            
            return BaseResponse(
                success=True,
                message="获取汇款记录详情成功",
                data=remittance.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取汇款记录详情失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取汇款记录详情失败: {str(e)}"
        )


@router.post("", response_model=BaseResponse, status_code=status.HTTP_201_CREATED)
async def create_remittance_record(
    remittance_data: RemittanceCreate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    创建汇款记录
    
    Args:
        remittance_data: 汇款数据
        workspace_id: Workspace ID（可选，如果提供则创建到该workspace）
        current_user: 当前用户信息
    
    Returns:
        创建的汇款记录
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
                # 验证供应商是否存在（如果提供了supplierId，必须属于同一workspace）
                if remittance_data.supplierId is not None:
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND workspaceId = ?",
                        (remittance_data.supplierId, workspace_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或不属于该 Workspace"
                        )
                
                # 验证员工是否存在（如果提供了employeeId，必须属于同一workspace）
                if remittance_data.employeeId is not None:
                    employee_cursor = conn.execute(
                        "SELECT id FROM employees WHERE id = ? AND workspaceId = ?",
                        (remittance_data.employeeId, workspace_id)
                    )
                    if employee_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="员工不存在或不属于该 Workspace"
                        )
                
                # 插入汇款记录（包含workspaceId）
                cursor = conn.execute(
                    """
                    INSERT INTO remittance (userId, workspaceId, remittanceDate, supplierId, amount, employeeId, paymentMethod, note, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                    (
                        user_id,
                        workspace_id,
                        remittance_data.remittanceDate,
                        remittance_data.supplierId,
                        remittance_data.amount,
                        remittance_data.employeeId,
                        remittance_data.paymentMethod.value,
                        remittance_data.note
                    )
                )
            else:
                # 向后兼容：不设置workspaceId
                # 验证供应商是否存在（如果提供了 supplierId）
                if remittance_data.supplierId is not None:
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND userId = ?",
                        (remittance_data.supplierId, user_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或无权限访问"
                        )
                
                # 验证员工是否存在（如果提供了 employeeId）
                if remittance_data.employeeId is not None:
                    employee_cursor = conn.execute(
                        "SELECT id FROM employees WHERE id = ? AND userId = ?",
                        (remittance_data.employeeId, user_id)
                    )
                    if employee_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="员工不存在或无权限访问"
                        )
                
                # 插入汇款记录（不包含workspaceId）
                cursor = conn.execute(
                    """
                    INSERT INTO remittance (userId, remittanceDate, supplierId, amount, employeeId, paymentMethod, note, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                    (
                        user_id,
                        remittance_data.remittanceDate,
                        remittance_data.supplierId,
                        remittance_data.amount,
                        remittance_data.employeeId,
                        remittance_data.paymentMethod.value,
                        remittance_data.note
                    )
                )
            remittance_id = cursor.lastrowid
            conn.commit()
            
            # 获取创建的汇款记录
            cursor = conn.execute(
                """
                SELECT id, userId, remittanceDate, supplierId, amount, employeeId,
                       paymentMethod, note, created_at
                FROM remittance
                WHERE id = ?
                """,
                (remittance_id,)
            )
            row = cursor.fetchone()
            
            remittance = RemittanceResponse(
                id=row[0],
                userId=row[1],
                remittanceDate=row[2],
                supplierId=row[3],
                amount=row[4],
                employeeId=row[5],
                paymentMethod=row[6],
                note=row[7],
                created_at=row[8]
            )
            
            logger.info(
                f"创建汇款记录成功: 金额 {remittance_data.amount} (ID: {remittance_id}, 用户: {user_id})"
            )
            
            # 记录操作日志
            try:
                entity_name = f"汇款记录 (金额: ¥{remittance_data.amount})"
                AuditLogService.log_create(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="remittance",
                    entity_id=remittance_id,
                    entity_name=entity_name,
                    new_data=remittance.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录汇款创建日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="创建汇款记录成功",
                data=remittance.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"创建汇款记录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"创建汇款记录失败: {str(e)}"
        )


@router.put("/{remittance_id}", response_model=BaseResponse)
async def update_remittance_record(
    remittance_id: int,
    remittance_data: RemittanceUpdate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    更新汇款记录
    
    Args:
        remittance_id: 汇款记录ID
        remittance_data: 汇款更新数据
        workspace_id: Workspace ID（可选，如果提供则只更新该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        更新后的汇款记录
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
                params = (remittance_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (remittance_id, user_id)
            
            # 获取当前汇款记录完整信息用于日志记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, remittanceDate, supplierId, amount, employeeId,
                       paymentMethod, note, created_at
                FROM remittance
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="汇款记录不存在或无权限访问"
                )
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "remittanceDate": row[2],
                "supplierId": row[3],
                "amount": row[4],
                "employeeId": row[5],
                "paymentMethod": row[6],
                "note": row[7],
                "created_at": row[8]
            }
            
            # 验证供应商是否存在（如果修改了供应商）
            if remittance_data.supplierId is not None:
                if remittance_data.supplierId != 0:
                    if workspace_id is not None:
                        supplier_cursor = conn.execute(
                            "SELECT id FROM suppliers WHERE id = ? AND workspaceId = ?",
                            (remittance_data.supplierId, workspace_id)
                        )
                    else:
                        supplier_cursor = conn.execute(
                            "SELECT id FROM suppliers WHERE id = ? AND userId = ?",
                            (remittance_data.supplierId, user_id)
                        )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或不属于该 Workspace"
                        )
            
            # 验证员工是否存在（如果修改了员工）
            if remittance_data.employeeId is not None:
                if remittance_data.employeeId != 0:
                    if workspace_id is not None:
                        employee_cursor = conn.execute(
                            "SELECT id FROM employees WHERE id = ? AND workspaceId = ?",
                            (remittance_data.employeeId, workspace_id)
                        )
                    else:
                        employee_cursor = conn.execute(
                            "SELECT id FROM employees WHERE id = ? AND userId = ?",
                            (remittance_data.employeeId, user_id)
                        )
                    if employee_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="员工不存在或不属于该 Workspace"
                        )
            
            # 构建更新字段
            update_fields = []
            update_values = []
            
            if remittance_data.remittanceDate is not None:
                update_fields.append("remittanceDate = ?")
                update_values.append(remittance_data.remittanceDate)
            
            if remittance_data.supplierId is not None:
                update_fields.append("supplierId = ?")
                update_values.append(remittance_data.supplierId if remittance_data.supplierId != 0 else None)
            
            if remittance_data.amount is not None:
                update_fields.append("amount = ?")
                update_values.append(remittance_data.amount)
            
            if remittance_data.employeeId is not None:
                update_fields.append("employeeId = ?")
                update_values.append(remittance_data.employeeId if remittance_data.employeeId != 0 else None)
            
            if remittance_data.paymentMethod is not None:
                update_fields.append("paymentMethod = ?")
                update_values.append(remittance_data.paymentMethod.value)
            
            if remittance_data.note is not None:
                update_fields.append("note = ?")
                update_values.append(remittance_data.note)
            
            if not update_fields:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="没有提供要更新的字段"
                )
            
            update_values.append(remittance_id)
            
            # 执行更新
            if workspace_id is not None:
                update_sql = f"""
                    UPDATE remittance
                    SET {', '.join(update_fields)}
                    WHERE id = ? AND workspaceId = ?
                """
                update_values.append(workspace_id)
            else:
                update_sql = f"""
                    UPDATE remittance
                    SET {', '.join(update_fields)}
                    WHERE id = ? AND userId = ?
                """
                update_values.append(user_id)
            
            conn.execute(update_sql, tuple(update_values))
            conn.commit()
            
            # 获取更新后的汇款记录
            cursor = conn.execute(
                """
                SELECT id, userId, remittanceDate, supplierId, amount, employeeId,
                       paymentMethod, note, created_at
                FROM remittance
                WHERE id = ?
                """,
                (remittance_id,)
            )
            row = cursor.fetchone()
            
            remittance = RemittanceResponse(
                id=row[0],
                userId=row[1],
                remittanceDate=row[2],
                supplierId=row[3],
                amount=row[4],
                employeeId=row[5],
                paymentMethod=row[6],
                note=row[7],
                created_at=row[8]
            )
            
            logger.info(f"更新汇款记录成功: {remittance_id} (用户: {user_id})")
            
            # 记录操作日志
            try:
                entity_name = f"汇款记录 (金额: ¥{remittance.amount})"
                AuditLogService.log_update(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="remittance",
                    entity_id=remittance_id,
                    entity_name=entity_name,
                    old_data=old_data,
                    new_data=remittance.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录汇款更新日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="更新汇款记录成功",
                data=remittance.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"更新汇款记录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新汇款记录失败: {str(e)}"
        )


@router.delete("/{remittance_id}", response_model=BaseResponse)
async def delete_remittance_record(
    remittance_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    删除汇款记录
    
    Args:
        remittance_id: 汇款记录ID
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
                params = (remittance_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (remittance_id, user_id)
            
            # 获取汇款记录完整信息用于日志记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, remittanceDate, supplierId, amount, employeeId,
                       paymentMethod, note, created_at
                FROM remittance
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="汇款记录不存在或无权限访问"
                )
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "remittanceDate": row[2],
                "supplierId": row[3],
                "amount": row[4],
                "employeeId": row[5],
                "paymentMethod": row[6],
                "note": row[7],
                "created_at": row[8]
            }
            amount = row[4]
            
            # 删除汇款记录
            conn.execute(
                f"DELETE FROM remittance WHERE {where_clause}",
                params
            )
            conn.commit()
            
            logger.info(f"删除汇款记录成功: 金额 {amount} (ID: {remittance_id}, 用户: {user_id})")
            
            # 记录操作日志
            try:
                entity_name = f"汇款记录 (金额: ¥{amount})"
                AuditLogService.log_delete(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="remittance",
                    entity_id=remittance_id,
                    entity_name=entity_name,
                    old_data=old_data,
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录汇款删除日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="删除汇款记录成功"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"删除汇款记录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"删除汇款记录失败: {str(e)}"
        )


