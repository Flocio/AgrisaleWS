"""
产品管理路由
处理产品的增删改查、库存更新等功能
"""

import logging
from typing import Optional, List
from fastapi import APIRouter, HTTPException, status, Depends, Query, Header

from server.database import get_pool, DatabaseBusyError
from server.middleware import get_current_user
from server.middleware.workspace_permission import (
    get_workspace_id,
    check_workspace_access,
    check_workspace_permission,
    require_server_storage
)
from server.models import (
    ProductCreate,
    ProductUpdate,
    ProductResponse,
    ProductStockUpdate,
    BaseResponse,
    PaginationParams,
    PaginatedResponse,
    ProductFilter
)
from server.services.audit_log_service import AuditLogService

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/products", tags=["产品管理"])


@router.get("", response_model=BaseResponse)
async def get_products(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=10000, description="每页数量（最大 10000）"),
    search: Optional[str] = Query(None, description="搜索关键词（产品名称或描述）"),
    supplier_id: Optional[int] = Query(None, description="供应商ID筛选"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取产品列表（支持分页、搜索、筛选）
    
    Args:
        page: 页码
        page_size: 每页数量
        search: 搜索关键词
        supplier_id: 供应商ID筛选
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        产品列表（分页）
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
                where_conditions.append("(name LIKE ? OR description LIKE ?)")
                search_pattern = f"%{search}%"
                params.extend([search_pattern, search_pattern])
            
            # 供应商筛选
            if supplier_id is not None:
                if supplier_id == 0:
                    # 0 表示"未分配供应商"
                    where_conditions.append("(supplierId IS NULL OR supplierId = 0)")
                else:
                    where_conditions.append("supplierId = ?")
                    params.append(supplier_id)
            
            where_clause = " AND ".join(where_conditions)
            
            # 获取总数
            count_cursor = conn.execute(
                f"SELECT COUNT(*) FROM products WHERE {where_clause}",
                tuple(params)
            )
            total = count_cursor.fetchone()[0]
            
            # 计算分页
            offset = (page - 1) * page_size
            total_pages = (total + page_size - 1) // page_size
            
            # 获取产品列表
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, description, stock, unit, supplierId, version, 
                       created_at, updated_at
                FROM products
                WHERE {where_clause}
                ORDER BY updated_at DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                tuple(params) + (page_size, offset)
            )
            rows = cursor.fetchall()
            
            # 转换为响应模型
            products = []
            for row in rows:
                product = ProductResponse(
                    id=row[0],
                    userId=row[1],
                    name=row[2],
                    description=row[3],
                    stock=row[4],
                    unit=row[5],
                    supplierId=row[6],
                    version=row[7] if row[7] else 1,
                    created_at=row[8],
                    updated_at=row[9]
                )
                products.append(product.model_dump())
            
            paginated_data = PaginatedResponse(
                items=products,
                total=total,
                page=page,
                page_size=page_size,
                total_pages=total_pages
            )
            
            return BaseResponse(
                success=True,
                message="获取产品列表成功",
                data=paginated_data.model_dump()
            )
            
    except Exception as e:
        logger.error(f"获取产品列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取产品列表失败: {str(e)}"
        )


@router.get("/{product_id}", response_model=BaseResponse)
async def get_product(
    product_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取单个产品详情
    
    Args:
        product_id: 产品ID
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        产品详情
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
                params = (product_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (product_id, user_id)
            
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, description, stock, unit, supplierId, version,
                       created_at, updated_at
                FROM products
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="产品不存在或无权限访问"
                )
            
            product = ProductResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                description=row[3],
                stock=row[4],
                unit=row[5],
                supplierId=row[6],
                version=row[7] if row[7] else 1,
                created_at=row[8],
                updated_at=row[9]
            )
            
            return BaseResponse(
                success=True,
                message="获取产品详情成功",
                data=product.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取产品详情失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取产品详情失败: {str(e)}"
        )


@router.post("", response_model=BaseResponse, status_code=status.HTTP_201_CREATED)
async def create_product(
    product_data: ProductCreate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    创建产品
    
    Args:
        product_data: 产品数据
        workspace_id: Workspace ID（可选，如果提供则创建到该workspace）
        current_user: 当前用户信息
    
    Returns:
        创建的产品信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 如果提供了workspace_id，检查权限和存储类型
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
                # 检查同一workspace下产品名称是否已存在
                cursor = conn.execute(
                    "SELECT id FROM products WHERE workspaceId = ? AND name = ?",
                    (workspace_id, product_data.name)
                )
                existing = cursor.fetchone()
                
                if existing:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品名称 '{product_data.name}' 已存在"
                    )
                
                # 验证供应商是否存在（如果提供了 supplierId）
                if product_data.supplierId is not None:
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND workspaceId = ?",
                        (product_data.supplierId, workspace_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或无权限访问"
                        )
                
                # 插入产品（包含workspaceId）
                cursor = conn.execute(
                    """
                    INSERT INTO products (userId, workspaceId, name, description, stock, unit, supplierId, version, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                    """,
                    (
                        user_id,
                        workspace_id,
                        product_data.name,
                        product_data.description,
                        product_data.stock,
                        product_data.unit.value,
                        product_data.supplierId
                    )
                )
            else:
                # 向后兼容：不设置workspaceId
                # 检查同一用户下产品名称是否已存在
                cursor = conn.execute(
                    "SELECT id FROM products WHERE userId = ? AND name = ?",
                    (user_id, product_data.name)
                )
                existing = cursor.fetchone()
                
                if existing:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品名称 '{product_data.name}' 已存在"
                    )
                
                # 验证供应商是否存在（如果提供了 supplierId）
                if product_data.supplierId is not None:
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND userId = ?",
                        (product_data.supplierId, user_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或无权限访问"
                        )
                
                # 插入产品（不包含workspaceId）
                cursor = conn.execute(
                    """
                    INSERT INTO products (userId, name, description, stock, unit, supplierId, version, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                    """,
                    (
                        user_id,
                        product_data.name,
                        product_data.description,
                        product_data.stock,
                        product_data.unit.value,
                        product_data.supplierId
                    )
                )
            product_id = cursor.lastrowid
            conn.commit()
            
            # 获取创建的产品
            cursor = conn.execute(
                """
                SELECT id, userId, name, description, stock, unit, supplierId, version,
                       created_at, updated_at
                FROM products
                WHERE id = ?
                """,
                (product_id,)
            )
            row = cursor.fetchone()
            
            product = ProductResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                description=row[3],
                stock=row[4],
                unit=row[5],
                supplierId=row[6],
                version=row[7] if row[7] else 1,
                created_at=row[8],
                updated_at=row[9]
            )
            
            logger.info(f"创建产品成功: {product_data.name} (ID: {product_id}, 用户: {user_id})")
            
            # 记录操作日志
            try:
                AuditLogService.log_create(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="product",
                    entity_id=product_id,
                    entity_name=product_data.name,
                    new_data=product.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录产品创建日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="创建产品成功",
                data=product.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"创建产品失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"创建产品失败: {str(e)}"
        )


@router.put("/{product_id}", response_model=BaseResponse)
async def update_product(
    product_id: int,
    product_data: ProductUpdate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    更新产品（使用乐观锁）
    
    Args:
        product_id: 产品ID
        product_data: 产品更新数据
        workspace_id: Workspace ID（可选，如果提供则只更新该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        更新后的产品信息
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
                params = (product_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (product_id, user_id)
            
            # 获取当前产品信息
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, description, stock, unit, supplierId, version
                FROM products
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="产品不存在或无权限访问"
                )
            
            current_version = row[7] if row[7] else 1
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "name": row[2],
                "description": row[3],
                "stock": row[4],
                "unit": row[5],
                "supplierId": row[6],
                "version": current_version
            }
            
            # 乐观锁检查
            if product_data.version is not None and product_data.version != current_version:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"产品已被其他操作修改，当前版本: {current_version}，您的版本: {product_data.version}。请刷新后重试。"
                )
            
            # 检查产品名称唯一性（如果修改了名称）
            if product_data.name and product_data.name != row[2]:
                name_cursor = conn.execute(
                    "SELECT id FROM products WHERE userId = ? AND name = ? AND id != ?",
                    (user_id, product_data.name, product_id)
                )
                if name_cursor.fetchone():
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品名称 '{product_data.name}' 已存在"
                    )
            
            # 验证供应商（如果修改了供应商）
            if product_data.supplierId is not None and product_data.supplierId != row[6]:
                if product_data.supplierId != 0:  # 0 表示未分配
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND userId = ?",
                        (product_data.supplierId, user_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或无权限访问"
                        )
            
            # 构建更新字段
            update_fields = []
            update_values = []
            
            if product_data.name is not None:
                update_fields.append("name = ?")
                update_values.append(product_data.name)
            
            if product_data.description is not None:
                update_fields.append("description = ?")
                update_values.append(product_data.description)
            
            if product_data.stock is not None:
                update_fields.append("stock = ?")
                update_values.append(product_data.stock)
            
            if product_data.unit is not None:
                update_fields.append("unit = ?")
                update_values.append(product_data.unit.value)
            
            if product_data.supplierId is not None:
                update_fields.append("supplierId = ?")
                update_values.append(product_data.supplierId if product_data.supplierId != 0 else None)
            
            if not update_fields:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="没有提供要更新的字段"
                )
            
            # 更新版本号（乐观锁）
            update_fields.append("version = version + 1")
            update_fields.append("updated_at = datetime('now')")
            update_values.append(product_id)
            
            # 执行更新
            if workspace_id is not None:
                update_sql = f"""
                    UPDATE products
                    SET {', '.join(update_fields)}
                    WHERE id = ? AND workspaceId = ?
                """
                update_values.append(workspace_id)
            else:
                update_sql = f"""
                    UPDATE products
                    SET {', '.join(update_fields)}
                    WHERE id = ? AND userId = ?
                """
                update_values.append(user_id)
            
            conn.execute(update_sql, tuple(update_values))
            conn.commit()
            
            # 获取更新后的产品
            cursor = conn.execute(
                """
                SELECT id, userId, name, description, stock, unit, supplierId, version,
                       created_at, updated_at
                FROM products
                WHERE id = ?
                """,
                (product_id,)
            )
            row = cursor.fetchone()
            
            product = ProductResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                description=row[3],
                stock=row[4],
                unit=row[5],
                supplierId=row[6],
                version=row[7] if row[7] else 1,
                created_at=row[8],
                updated_at=row[9]
            )
            
            logger.info(f"更新产品成功: {product_id} (用户: {user_id})")
            
            # 记录操作日志
            try:
                AuditLogService.log_update(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="product",
                    entity_id=product_id,
                    entity_name=product.name,
                    old_data=old_data,
                    new_data=product.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录产品更新日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="更新产品成功",
                data=product.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"更新产品失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新产品失败: {str(e)}"
        )


@router.delete("/{product_id}", response_model=BaseResponse)
async def delete_product(
    product_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    删除产品
    
    Args:
        product_id: 产品ID
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
                params = (product_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (product_id, user_id)
            
            # 获取产品完整信息用于日志记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, description, stock, unit, supplierId, version,
                       created_at, updated_at
                FROM products
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="产品不存在或无权限访问"
                )
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "name": row[2],
                "description": row[3],
                "stock": row[4],
                "unit": row[5],
                "supplierId": row[6],
                "version": row[7] if row[7] else 1,
                "created_at": row[8],
                "updated_at": row[9]
            }
            product_name = row[2]
            
            # 删除产品（外键约束会自动处理关联数据）
            conn.execute(
                f"DELETE FROM products WHERE {where_clause}",
                params
            )
            conn.commit()
            
            logger.info(f"删除产品成功: {product_name} (ID: {product_id}, 用户: {user_id})")
            
            # 记录操作日志
            try:
                AuditLogService.log_delete(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="product",
                    entity_id=product_id,
                    entity_name=product_name,
                    old_data=old_data,
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录产品删除日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="删除产品成功"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"删除产品失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"删除产品失败: {str(e)}"
        )


@router.post("/{product_id}/stock", response_model=BaseResponse)
async def update_product_stock(
    product_id: int,
    stock_data: ProductStockUpdate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    更新产品库存（使用乐观锁，防止并发冲突）
    
    用于采购、销售、退货等操作时的库存更新
    
    Args:
        product_id: 产品ID
        stock_data: 库存更新数据（包含数量变化和版本号）
        workspace_id: Workspace ID（可选，如果提供则只更新该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        更新后的产品信息
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
                params = (product_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (product_id, user_id)
            
            # 获取当前产品信息
            cursor = conn.execute(
                f"""
                SELECT id, userId, name, stock, version
                FROM products
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="产品不存在或无权限访问"
                )
            
            current_stock = row[3]
            current_version = row[4] if row[4] else 1
            
            # 乐观锁检查
            if stock_data.version != current_version:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"产品库存已被其他操作修改，当前版本: {current_version}，您的版本: {stock_data.version}。请刷新后重试。"
                )
            
            # 计算新库存
            new_stock = current_stock + stock_data.quantity
            
            # 检查库存不能为负
            if new_stock < 0:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"库存不足，当前库存: {current_stock}，无法减少 {abs(stock_data.quantity)}"
                )
            
            # 更新库存和版本号
            if workspace_id is not None:
                conn.execute(
                    """
                    UPDATE products
                    SET stock = ?, version = version + 1, updated_at = datetime('now')
                    WHERE id = ? AND workspaceId = ? AND version = ?
                    """,
                    (new_stock, product_id, workspace_id, current_version)
                )
            else:
                conn.execute(
                    """
                    UPDATE products
                    SET stock = ?, version = version + 1, updated_at = datetime('now')
                    WHERE id = ? AND userId = ? AND version = ?
                    """,
                    (new_stock, product_id, user_id, current_version)
                )
            
            # 检查是否更新成功（乐观锁）
            if conn.total_changes == 0:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="产品库存已被其他操作修改，请刷新后重试"
                )
            
            conn.commit()
            
            # 获取更新后的产品
            cursor = conn.execute(
                """
                SELECT id, userId, name, description, stock, unit, supplierId, version,
                       created_at, updated_at
                FROM products
                WHERE id = ?
                """,
                (product_id,)
            )
            row = cursor.fetchone()
            
            product = ProductResponse(
                id=row[0],
                userId=row[1],
                name=row[2],
                description=row[3],
                stock=row[4],
                unit=row[5],
                supplierId=row[6],
                version=row[7] if row[7] else 1,
                created_at=row[8],
                updated_at=row[9]
            )
            
            logger.info(
                f"更新产品库存成功: {row[2]} (ID: {product_id}), "
                f"库存变化: {current_stock} -> {new_stock} (变化: {stock_data.quantity})"
            )
            
            return BaseResponse(
                success=True,
                message="更新库存成功",
                data=product.model_dump()
            )
            
    except HTTPException:
        raise
    except DatabaseBusyError as e:
        logger.warning(f"更新库存时数据库繁忙: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="数据库暂时繁忙，请稍后重试"
        )
    except Exception as e:
        logger.error(f"更新产品库存失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新产品库存失败: {str(e)}"
        )


@router.get("/search/all", response_model=BaseResponse)
async def search_all_products(
    search: str = Query(..., min_length=1, description="搜索关键词"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    搜索所有产品（不分页，用于下拉选择等场景）
    
    Args:
        search: 搜索关键词
        workspace_id: Workspace ID（可选，如果提供则只搜索该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        匹配的产品列表
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    # 如果提供了workspace_id，检查权限
    if workspace_id is not None:
        has_access = await check_workspace_access(workspace_id, user_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="无权访问该 Workspace"
            )
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
                    SELECT id, userId, name, description, stock, unit, supplierId, version,
                           created_at, updated_at
                    FROM products
                    WHERE workspaceId = ? AND (name LIKE ? OR description LIKE ?)
                    ORDER BY name
                    LIMIT 50
                    """,
                    (workspace_id, search_pattern, search_pattern)
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT id, userId, name, description, stock, unit, supplierId, version,
                           created_at, updated_at
                    FROM products
                    WHERE userId = ? AND (name LIKE ? OR description LIKE ?)
                    ORDER BY name
                    LIMIT 50
                    """,
                    (user_id, search_pattern, search_pattern)
                )
            rows = cursor.fetchall()
            
            products = []
            for row in rows:
                product = ProductResponse(
                    id=row[0],
                    userId=row[1],
                    name=row[2],
                    description=row[3],
                    stock=row[4],
                    unit=row[5],
                    supplierId=row[6],
                    version=row[7] if row[7] else 1,
                    created_at=row[8],
                    updated_at=row[9]
                )
                products.append(product.model_dump())
            
            return BaseResponse(
                success=True,
                message="搜索产品成功",
                data={"products": products, "count": len(products)}
            )
            
    except Exception as e:
        logger.error(f"搜索产品失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"搜索产品失败: {str(e)}"
        )


