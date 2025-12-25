"""
采购管理路由
处理采购记录的增删改查、库存联动等功能
"""

import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends, Query, Header

from server.database import get_pool, DatabaseBusyError
from server.middleware import get_current_user
from server.middleware.workspace_permission import (
    check_workspace_access,
    check_workspace_permission,
    require_server_storage
)
from server.models import (
    PurchaseCreate,
    PurchaseUpdate,
    PurchaseResponse,
    BaseResponse,
    PaginationParams,
    PaginatedResponse,
    DateRangeFilter
)
from server.services.audit_log_service import AuditLogService

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/purchases", tags=["采购管理"])


@router.get("", response_model=BaseResponse)
async def get_purchases(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=10000, description="每页数量（最大 10000）"),
    search: Optional[str] = Query(None, description="搜索关键词（产品名称）"),
    start_date: Optional[str] = Query(None, description="开始日期（ISO8601格式）"),
    end_date: Optional[str] = Query(None, description="结束日期（ISO8601格式）"),
    supplier_id: Optional[int] = Query(None, description="供应商ID筛选"),
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取采购记录列表（支持分页、搜索、日期筛选）
    
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
        采购记录列表（分页）
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
                where_conditions.append("productName LIKE ?")
                params.append(f"%{search}%")
            
            # 日期范围筛选
            if start_date:
                where_conditions.append("date(purchaseDate) >= date(?)")
                params.append(start_date)
            
            if end_date:
                where_conditions.append("date(purchaseDate) <= date(?)")
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
                f"SELECT COUNT(*) FROM purchases WHERE {where_clause}",
                tuple(params)
            )
            total = count_cursor.fetchone()[0]
            
            # 计算分页
            offset = (page - 1) * page_size
            total_pages = (total + page_size - 1) // page_size
            
            # 获取采购记录列表
            cursor = conn.execute(
                f"""
                SELECT id, userId, productName, quantity, purchaseDate, supplierId,
                       totalPurchasePrice, note, created_at
                FROM purchases
                WHERE {where_clause}
                ORDER BY purchaseDate DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                tuple(params) + (page_size, offset)
            )
            rows = cursor.fetchall()
            
            # 转换为响应模型
            purchases = []
            for row in rows:
                purchase = PurchaseResponse(
                    id=row[0],
                    userId=row[1],
                    productName=row[2],
                    quantity=row[3],
                    purchaseDate=row[4],
                    supplierId=row[5],
                    totalPurchasePrice=row[6],
                    note=row[7],
                    created_at=row[8]
                )
                purchases.append(purchase.model_dump())
            
            paginated_data = PaginatedResponse(
                items=purchases,
                total=total,
                page=page,
                page_size=page_size,
                total_pages=total_pages
            )
            
            return BaseResponse(
                success=True,
                message="获取采购记录列表成功",
                data=paginated_data.model_dump()
            )
            
    except Exception as e:
        logger.error(f"获取采购记录列表失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取采购记录列表失败: {str(e)}"
        )


@router.get("/{purchase_id}", response_model=BaseResponse)
async def get_purchase(
    purchase_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    获取单个采购记录详情
    
    Args:
        purchase_id: 采购记录ID
        workspace_id: Workspace ID（可选，如果提供则只查询该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        采购记录详情
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
                params = (purchase_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (purchase_id, user_id)
            
            cursor = conn.execute(
                f"""
                SELECT id, userId, productName, quantity, purchaseDate, supplierId,
                       totalPurchasePrice, note, created_at
                FROM purchases
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="采购记录不存在或无权限访问"
                )
            
            purchase = PurchaseResponse(
                id=row[0],
                userId=row[1],
                productName=row[2],
                quantity=row[3],
                purchaseDate=row[4],
                supplierId=row[5],
                totalPurchasePrice=row[6],
                note=row[7],
                created_at=row[8]
            )
            
            return BaseResponse(
                success=True,
                message="获取采购记录详情成功",
                data=purchase.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"获取采购记录详情失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取采购记录详情失败: {str(e)}"
        )


@router.post("", response_model=BaseResponse, status_code=status.HTTP_201_CREATED)
async def create_purchase(
    purchase_data: PurchaseCreate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    创建采购记录
    
    采购时会自动更新产品库存：
    - 正数数量：增加库存
    - 负数数量：减少库存（采购退货，需要检查库存是否足够）
    
    Args:
        purchase_data: 采购数据
        workspace_id: Workspace ID（可选，如果提供则创建到该workspace）
        current_user: 当前用户信息
    
    Returns:
        创建的采购记录
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
                # 验证产品是否存在（必须属于同一workspace）
                product_cursor = conn.execute(
                    "SELECT id, name, stock, version FROM products WHERE workspaceId = ? AND name = ?",
                    (workspace_id, purchase_data.productName)
                )
                product = product_cursor.fetchone()
                
                if product is None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品 '{purchase_data.productName}' 不存在或不属于该 Workspace"
                    )
                
                product_id, product_name, current_stock, product_version = product
                
                # 验证供应商是否存在（如果提供了有效的 supplierId，必须属于同一workspace）
                supplier_id = purchase_data.supplierId if purchase_data.supplierId and purchase_data.supplierId != 0 else None
                if supplier_id is not None:
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND workspaceId = ?",
                        (supplier_id, workspace_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或不属于该 Workspace"
                        )
            else:
                # 向后兼容：不设置workspaceId
                # 验证产品是否存在
                product_cursor = conn.execute(
                    "SELECT id, name, stock, version FROM products WHERE userId = ? AND name = ?",
                    (user_id, purchase_data.productName)
                )
                product = product_cursor.fetchone()
                
                if product is None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品 '{purchase_data.productName}' 不存在"
                    )
                
                product_id, product_name, current_stock, product_version = product
                
                # 验证供应商是否存在（如果提供了有效的 supplierId）
                supplier_id = purchase_data.supplierId if purchase_data.supplierId and purchase_data.supplierId != 0 else None
                if supplier_id is not None:
                    supplier_cursor = conn.execute(
                        "SELECT id FROM suppliers WHERE id = ? AND userId = ?",
                        (supplier_id, user_id)
                    )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或无权限访问"
                        )
            
            # 如果是负数（采购退货），检查库存是否足够
            if purchase_data.quantity < 0:
                if current_stock < abs(purchase_data.quantity):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"库存不足，当前库存: {current_stock}，无法退货 {abs(purchase_data.quantity)}"
                    )
            
            # 在事务中执行：插入采购记录 + 更新库存
            try:
                # 插入采购记录
                if workspace_id is not None:
                    purchase_cursor = conn.execute(
                        """
                        INSERT INTO purchases (userId, workspaceId, productName, quantity, purchaseDate, supplierId, totalPurchasePrice, note, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                        """,
                        (
                            user_id,
                            workspace_id,
                            purchase_data.productName,
                            purchase_data.quantity,
                            purchase_data.purchaseDate,
                            supplier_id,
                            purchase_data.totalPurchasePrice,
                            purchase_data.note
                        )
                    )
                else:
                    purchase_cursor = conn.execute(
                        """
                        INSERT INTO purchases (userId, productName, quantity, purchaseDate, supplierId, totalPurchasePrice, note, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                        """,
                        (
                            user_id,
                            purchase_data.productName,
                            purchase_data.quantity,
                            purchase_data.purchaseDate,
                            supplier_id,
                            purchase_data.totalPurchasePrice,
                            purchase_data.note
                        )
                    )
                purchase_id = purchase_cursor.lastrowid
                
                # 更新产品库存（使用乐观锁）
                new_stock = current_stock + purchase_data.quantity
                if new_stock < 0:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="库存不足"
                    )
                
                if workspace_id is not None:
                    update_cursor = conn.execute(
                        """
                        UPDATE products
                        SET stock = ?, version = version + 1, updated_at = datetime('now')
                        WHERE id = ? AND workspaceId = ? AND version = ?
                        """,
                        (new_stock, product_id, workspace_id, product_version)
                    )
                else:
                    update_cursor = conn.execute(
                        """
                        UPDATE products
                        SET stock = ?, version = version + 1, updated_at = datetime('now')
                        WHERE id = ? AND userId = ? AND version = ?
                        """,
                        (new_stock, product_id, user_id, product_version)
                    )
                
                # 检查是否更新成功（乐观锁）
                if update_cursor.rowcount == 0:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="产品库存已被其他操作修改，请刷新后重试"
                    )
                
                conn.commit()
                
            except HTTPException:
                conn.rollback()
                raise
            except Exception as e:
                conn.rollback()
                logger.error(f"创建采购记录时数据库操作失败: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"创建采购记录失败: {str(e)}"
                )
            
            # 获取创建的采购记录
            cursor = conn.execute(
                """
                SELECT id, userId, productName, quantity, purchaseDate, supplierId,
                       totalPurchasePrice, note, created_at
                FROM purchases
                WHERE id = ?
                """,
                (purchase_id,)
            )
            row = cursor.fetchone()
            
            purchase = PurchaseResponse(
                id=row[0],
                userId=row[1],
                productName=row[2],
                quantity=row[3],
                purchaseDate=row[4],
                supplierId=row[5],
                totalPurchasePrice=row[6],
                note=row[7],
                created_at=row[8]
            )
            
            logger.info(
                f"创建采购记录成功: {purchase_data.productName} "
                f"数量: {purchase_data.quantity} (ID: {purchase_id}, 用户: {user_id})"
            )
            
            # 记录操作日志
            try:
                AuditLogService.log_create(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="purchase",
                    entity_id=purchase_id,
                    entity_name=f"{purchase_data.productName} (数量: {purchase_data.quantity})",
                    new_data=purchase.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录采购创建日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="创建采购记录成功",
                data=purchase.model_dump()
            )
            
    except HTTPException:
        raise
    except DatabaseBusyError as e:
        logger.warning(f"创建采购记录时数据库繁忙: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="数据库暂时繁忙，请稍后重试"
        )
    except Exception as e:
        logger.error(f"创建采购记录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"创建采购记录失败: {str(e)}"
        )


@router.put("/{purchase_id}", response_model=BaseResponse)
async def update_purchase(
    purchase_id: int,
    purchase_data: PurchaseUpdate,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    更新采购记录
    
    更新时会计算库存变化差值并更新产品库存
    
    Args:
        purchase_id: 采购记录ID
        purchase_data: 采购更新数据
        workspace_id: Workspace ID（可选，如果提供则只更新该workspace的数据）
        current_user: 当前用户信息
    
    Returns:
        更新后的采购记录
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
                params = (purchase_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (purchase_id, user_id)
            
            # 获取当前采购记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, productName, quantity, purchaseDate, supplierId,
                       totalPurchasePrice, note
                FROM purchases
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="采购记录不存在或无权限访问"
                )
            
            old_quantity = row[3]
            old_product_name = row[2]
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "productName": row[2],
                "quantity": row[3],
                "purchaseDate": row[4],
                "supplierId": row[5],
                "totalPurchasePrice": row[6],
                "note": row[7]
            }
            
            # 确定新的数量（如果提供了）
            new_quantity = purchase_data.quantity if purchase_data.quantity is not None else old_quantity
            new_product_name = purchase_data.productName if purchase_data.productName else old_product_name
            
            # 如果产品名称改变了，需要验证新产品是否存在
            if purchase_data.productName and purchase_data.productName != old_product_name:
                if workspace_id is not None:
                    product_cursor = conn.execute(
                        "SELECT id, stock, version FROM products WHERE workspaceId = ? AND name = ?",
                        (workspace_id, purchase_data.productName)
                    )
                else:
                    product_cursor = conn.execute(
                        "SELECT id, stock, version FROM products WHERE userId = ? AND name = ?",
                        (user_id, purchase_data.productName)
                    )
                new_product = product_cursor.fetchone()
                if new_product is None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品 '{purchase_data.productName}' 不存在或不属于该 Workspace"
                    )
            else:
                # 获取原产品信息
                if workspace_id is not None:
                    product_cursor = conn.execute(
                        "SELECT id, stock, version FROM products WHERE workspaceId = ? AND name = ?",
                        (workspace_id, old_product_name)
                    )
                else:
                    product_cursor = conn.execute(
                        "SELECT id, stock, version FROM products WHERE userId = ? AND name = ?",
                        (user_id, old_product_name)
                    )
                new_product = product_cursor.fetchone()
                if new_product is None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"产品 '{old_product_name}' 不存在或不属于该 Workspace"
                    )
            
            product_id, current_stock, product_version = new_product
            
            # 计算库存变化差值
            quantity_diff = new_quantity - old_quantity
            
            # 如果产品名称改变了，需要分别检查原产品和新产品的库存
            product_changed = purchase_data.productName and purchase_data.productName != old_product_name
            
            if product_changed:
                # 如果产品名称改变，需要检查：
                # 1. 原产品库存是否足够恢复（减去原数量）
                # 2. 新产品库存是否足够（如果新数量是负数，即采购退货）
                
                # 检查原产品库存
                if workspace_id is not None:
                    old_product_cursor = conn.execute(
                        "SELECT id, stock, version FROM products WHERE workspaceId = ? AND name = ?",
                        (workspace_id, old_product_name)
                    )
                else:
                    old_product_cursor = conn.execute(
                        "SELECT id, stock, version FROM products WHERE userId = ? AND name = ?",
                        (user_id, old_product_name)
                    )
                old_product = old_product_cursor.fetchone()
                if old_product:
                    old_product_stock = old_product[1]
                    if old_product_stock < old_quantity:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"原产品 '{old_product_name}' 库存不足，当前库存: {old_product_stock}，无法恢复 {old_quantity}"
                        )
                
                # 如果新数量是负数（采购退货），检查新产品库存是否足够
                if new_quantity < 0:
                    if current_stock < abs(new_quantity):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"新产品 '{purchase_data.productName}' 库存不足，当前库存: {current_stock}，无法退货 {abs(new_quantity)}"
                        )
            else:
                # 产品名称没变，只检查数量差值
                # 如果是负数变化（减少库存），检查库存是否足够
                if quantity_diff < 0:
                    if current_stock < abs(quantity_diff):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"库存不足，当前库存: {current_stock}，无法减少 {abs(quantity_diff)}"
                        )
            
            # 验证供应商（如果修改了供应商）
            # 如果 supplierId 为 0 或 None，表示未分配供应商，允许更新
            supplier_id = None
            if purchase_data.supplierId is not None:
                if purchase_data.supplierId != 0:
                    supplier_id = purchase_data.supplierId
                    if workspace_id is not None:
                        supplier_cursor = conn.execute(
                            "SELECT id FROM suppliers WHERE id = ? AND workspaceId = ?",
                            (supplier_id, workspace_id)
                        )
                    else:
                        supplier_cursor = conn.execute(
                            "SELECT id FROM suppliers WHERE id = ? AND userId = ?",
                            (supplier_id, user_id)
                        )
                    if supplier_cursor.fetchone() is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="供应商不存在或不属于该 Workspace"
                        )
            
            # 在事务中执行：更新采购记录 + 更新库存
            try:
                # 构建更新字段
                update_fields = []
                update_values = []
                
                if purchase_data.productName is not None:
                    update_fields.append("productName = ?")
                    update_values.append(purchase_data.productName)
                
                if purchase_data.quantity is not None:
                    update_fields.append("quantity = ?")
                    update_values.append(purchase_data.quantity)
                
                if purchase_data.purchaseDate is not None:
                    update_fields.append("purchaseDate = ?")
                    update_values.append(purchase_data.purchaseDate)
                
                if purchase_data.supplierId is not None:
                    update_fields.append("supplierId = ?")
                    update_values.append(supplier_id)
                
                if purchase_data.totalPurchasePrice is not None:
                    update_fields.append("totalPurchasePrice = ?")
                    update_values.append(purchase_data.totalPurchasePrice)
                
                if purchase_data.note is not None:
                    update_fields.append("note = ?")
                    update_values.append(purchase_data.note)
                
                if not update_fields:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="没有提供要更新的字段"
                    )
                
                update_values.append(purchase_id)
                
                # 更新采购记录
                if workspace_id is not None:
                    update_sql = f"""
                        UPDATE purchases
                        SET {', '.join(update_fields)}
                        WHERE id = ? AND workspaceId = ?
                    """
                    update_values.append(workspace_id)
                else:
                    update_sql = f"""
                        UPDATE purchases
                        SET {', '.join(update_fields)}
                        WHERE id = ? AND userId = ?
                    """
                    update_values.append(user_id)
                
                conn.execute(update_sql, tuple(update_values))
                
                # 更新产品库存
                # product_changed 已在上面计算过
                quantity_changed = quantity_diff != 0
                
                if product_changed or quantity_changed:
                    # 如果产品名称改变了，需要恢复原产品的库存并更新新产品库存
                    if product_changed:
                        # 恢复原产品库存（减去原采购数量）
                        if workspace_id is not None:
                            old_product_cursor = conn.execute(
                                "SELECT id, stock, version FROM products WHERE workspaceId = ? AND name = ?",
                                (workspace_id, old_product_name)
                            )
                        else:
                            old_product_cursor = conn.execute(
                                "SELECT id, stock, version FROM products WHERE userId = ? AND name = ?",
                                (user_id, old_product_name)
                            )
                        old_product = old_product_cursor.fetchone()
                        if old_product:
                            old_product_id, old_product_stock, old_product_version = old_product
                            old_new_stock = old_product_stock - old_quantity
                            if old_new_stock < 0:
                                raise HTTPException(
                                    status_code=status.HTTP_400_BAD_REQUEST,
                                    detail="原产品库存不足，无法恢复"
                                )
                            if workspace_id is not None:
                                old_update_cursor = conn.execute(
                                    """
                                    UPDATE products
                                    SET stock = ?, version = version + 1, updated_at = datetime('now')
                                    WHERE id = ? AND workspaceId = ? AND version = ?
                                    """,
                                    (old_new_stock, old_product_id, workspace_id, old_product_version)
                                )
                            else:
                                old_update_cursor = conn.execute(
                                    """
                                    UPDATE products
                                    SET stock = ?, version = version + 1, updated_at = datetime('now')
                                    WHERE id = ? AND userId = ? AND version = ?
                                    """,
                                    (old_new_stock, old_product_id, user_id, old_product_version)
                                )
                            # 检查原产品库存更新是否成功（乐观锁）
                            if old_update_cursor.rowcount == 0:
                                raise HTTPException(
                                    status_code=status.HTTP_409_CONFLICT,
                                    detail="原产品库存已被其他操作修改，请刷新后重试"
                                )
                        
                        # 更新新产品库存（加上新采购数量）
                        new_stock = current_stock + new_quantity
                    else:
                        # 产品名称没变，只更新数量差值
                        new_stock = current_stock + quantity_diff
                    
                    # 检查库存是否足够
                    if new_stock < 0:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail="库存不足"
                        )
                    
                    # 更新产品库存（使用乐观锁）
                    update_cursor = conn.execute(
                        """
                        UPDATE products
                        SET stock = ?, version = version + 1, updated_at = datetime('now')
                        WHERE id = ? AND userId = ? AND version = ?
                        """,
                        (new_stock, product_id, user_id, product_version)
                    )
                    
                    # 检查是否更新成功（乐观锁）
                    if update_cursor.rowcount == 0:
                        raise HTTPException(
                            status_code=status.HTTP_409_CONFLICT,
                            detail="产品库存已被其他操作修改，请刷新后重试"
                        )
                
                conn.commit()
                
            except HTTPException:
                conn.rollback()
                raise
            except Exception as e:
                conn.rollback()
                logger.error(f"更新采购记录时数据库操作失败: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"更新采购记录失败: {str(e)}"
                )
            
            # 获取更新后的采购记录
            cursor = conn.execute(
                """
                SELECT id, userId, productName, quantity, purchaseDate, supplierId,
                       totalPurchasePrice, note, created_at
                FROM purchases
                WHERE id = ?
                """,
                (purchase_id,)
            )
            row = cursor.fetchone()
            
            purchase = PurchaseResponse(
                id=row[0],
                userId=row[1],
                productName=row[2],
                quantity=row[3],
                purchaseDate=row[4],
                supplierId=row[5],
                totalPurchasePrice=row[6],
                note=row[7],
                created_at=row[8]
            )
            
            logger.info(f"更新采购记录成功: {purchase_id} (用户: {user_id})")
            
            # 记录操作日志
            try:
                entity_name = f"{purchase.productName} (数量: {purchase.quantity})"
                AuditLogService.log_update(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="purchase",
                    entity_id=purchase_id,
                    entity_name=entity_name,
                    old_data=old_data,
                    new_data=purchase.model_dump(),
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录采购更新日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="更新采购记录成功",
                data=purchase.model_dump()
            )
            
    except HTTPException:
        raise
    except DatabaseBusyError as e:
        logger.warning(f"更新采购记录时数据库繁忙: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="数据库暂时繁忙，请稍后重试"
        )
    except Exception as e:
        logger.error(f"更新采购记录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新采购记录失败: {str(e)}"
        )


@router.delete("/{purchase_id}", response_model=BaseResponse)
async def delete_purchase(
    purchase_id: int,
    workspace_id: Optional[int] = Header(None, alias="X-Workspace-ID"),
    current_user: dict = Depends(get_current_user)
):
    """
    删除采购记录
    
    删除时会自动恢复产品库存（减去采购数量）
    
    Args:
        purchase_id: 采购记录ID
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
                params = (purchase_id, workspace_id)
            else:
                # 向后兼容：使用userId过滤
                where_clause = "id = ? AND userId = ?"
                params = (purchase_id, user_id)
            
            # 获取采购记录完整信息用于日志记录
            cursor = conn.execute(
                f"""
                SELECT id, userId, productName, quantity, purchaseDate, supplierId,
                       totalPurchasePrice, note, created_at
                FROM purchases
                WHERE {where_clause}
                """,
                params
            )
            row = cursor.fetchone()
            
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="采购记录不存在或无权限访问"
                )
            
            # 保存旧数据用于日志记录
            old_data = {
                "id": row[0],
                "userId": row[1],
                "productName": row[2],
                "quantity": row[3],
                "purchaseDate": row[4],
                "supplierId": row[5],
                "totalPurchasePrice": row[6],
                "note": row[7],
                "created_at": row[8]
            }
            
            product_name = row[2]
            quantity = row[3]
            
            # 获取产品信息
            if workspace_id is not None:
                product_cursor = conn.execute(
                    "SELECT id, stock, version FROM products WHERE workspaceId = ? AND name = ?",
                    (workspace_id, product_name)
                )
            else:
                product_cursor = conn.execute(
                    "SELECT id, stock, version FROM products WHERE userId = ? AND name = ?",
                    (user_id, product_name)
                )
            product = product_cursor.fetchone()
            
            if product is None:
                # 产品不存在，只删除采购记录
                logger.warning(f"删除采购记录时产品不存在: {product_name}")
            else:
                product_id, current_stock, product_version = product
                
                # 在事务中执行：删除采购记录 + 恢复库存
                try:
                    # 恢复产品库存（减去采购数量，即增加库存）
                    new_stock = current_stock - quantity
                    
                    # 更新产品库存（使用乐观锁）
                    if workspace_id is not None:
                        update_cursor = conn.execute(
                            """
                            UPDATE products
                            SET stock = ?, version = version + 1, updated_at = datetime('now')
                            WHERE id = ? AND workspaceId = ? AND version = ?
                            """,
                            (new_stock, product_id, workspace_id, product_version)
                        )
                    else:
                        update_cursor = conn.execute(
                            """
                            UPDATE products
                            SET stock = ?, version = version + 1, updated_at = datetime('now')
                            WHERE id = ? AND userId = ? AND version = ?
                            """,
                            (new_stock, product_id, user_id, product_version)
                        )
                    
                    # 检查是否更新成功（乐观锁）
                    if update_cursor.rowcount == 0:
                        raise HTTPException(
                            status_code=status.HTTP_409_CONFLICT,
                            detail="产品库存已被其他操作修改，请刷新后重试"
                        )
                
                except HTTPException:
                    conn.rollback()
                    raise
                except Exception as e:
                    conn.rollback()
                    logger.error(f"删除采购记录时恢复库存失败: {e}")
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail=f"删除采购记录失败: {str(e)}"
                    )
            
            # 删除采购记录
            conn.execute(
                f"DELETE FROM purchases WHERE {where_clause}",
                params
            )
            conn.commit()
            
            logger.info(f"删除采购记录成功: {product_name} 数量: {quantity} (ID: {purchase_id}, 用户: {user_id})")
            
            # 记录操作日志
            try:
                entity_name = f"{product_name} (数量: {quantity})"
                AuditLogService.log_delete(
                    user_id=user_id,
                    username=current_user.get("username", "unknown"),
                    entity_type="purchase",
                    entity_id=purchase_id,
                    entity_name=entity_name,
                    old_data=old_data,
                    workspace_id=workspace_id
                )
            except Exception as e:
                logger.warning(f"记录采购删除日志失败: {e}")
            
            return BaseResponse(
                success=True,
                message="删除采购记录成功"
            )
            
    except HTTPException:
        raise
    except DatabaseBusyError as e:
        logger.warning(f"删除采购记录时数据库繁忙: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="数据库暂时繁忙，请稍后重试"
        )
    except Exception as e:
        logger.error(f"删除采购记录失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"删除采购记录失败: {str(e)}"
        )


