"""
用户设置管理路由
处理用户设置的获取和更新
"""

import logging
from fastapi import APIRouter, HTTPException, status, Depends

from server.database import get_pool
from server.middleware import get_current_user
from server.models import (
    UserSettingsUpdate,
    UserSettingsResponse,
    BaseResponse,
    ImportDataRequest
)

# 配置日志
logger = logging.getLogger(__name__)

# 创建路由
router = APIRouter(prefix="/api/settings", tags=["用户设置"])


@router.get("", response_model=BaseResponse)
async def get_user_settings(
    current_user: dict = Depends(get_current_user)
):
    """
    获取当前用户设置
    
    Args:
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        用户设置信息
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT id, userId, deepseek_api_key, deepseek_model, deepseek_temperature,
                       deepseek_max_tokens, dark_mode, auto_backup_enabled, auto_backup_interval,
                       auto_backup_max_count, last_backup_time, show_online_users,
                       notify_device_online, notify_device_offline,
                       created_at, updated_at
                FROM user_settings
                WHERE userId = ?
                """,
                (user_id,)
            )
            row = cursor.fetchone()
            
            if row is None:
                # 如果用户设置不存在，创建默认设置
                cursor = conn.execute(
                    """
                    INSERT INTO user_settings (userId, created_at, updated_at)
                    VALUES (?, datetime('now'), datetime('now'))
                    """,
                    (user_id,)
                )
                conn.commit()
                
                # 再次查询
                cursor = conn.execute(
                    """
                    SELECT id, userId, deepseek_api_key, deepseek_model, deepseek_temperature,
                           deepseek_max_tokens, dark_mode, auto_backup_enabled, auto_backup_interval,
                           auto_backup_max_count, last_backup_time, show_online_users,
                           notify_device_online, notify_device_offline,
                           created_at, updated_at
                    FROM user_settings
                    WHERE userId = ?
                    """,
                    (user_id,)
                )
                row = cursor.fetchone()
            
            settings = UserSettingsResponse(
                id=row[0],
                userId=row[1],
                deepseek_api_key=row[2],
                deepseek_model=row[3] if row[3] else "deepseek-chat",
                deepseek_temperature=row[4] if row[4] is not None else 0.7,
                deepseek_max_tokens=row[5] if row[5] is not None else 2000,
                dark_mode=row[6] if row[6] is not None else 0,
                auto_backup_enabled=row[7] if row[7] is not None else 0,
                auto_backup_interval=row[8] if row[8] is not None else 15,
                auto_backup_max_count=row[9] if row[9] is not None else 20,
                last_backup_time=row[10],
                show_online_users=row[11] if row[11] is not None else 1,
                notify_device_online=row[12] if len(row) > 12 and row[12] is not None else 1,
                notify_device_offline=row[13] if len(row) > 13 and row[13] is not None else 1,
                created_at=row[14] if len(row) > 14 else row[12],
                updated_at=row[15] if len(row) > 15 else row[13]
            )
            
            return BaseResponse(
                success=True,
                message="获取用户设置成功",
                data=settings.model_dump()
            )
            
    except Exception as e:
        logger.error(f"获取用户设置失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"获取用户设置失败: {str(e)}"
        )


@router.put("", response_model=BaseResponse)
async def update_user_settings(
    settings_data: UserSettingsUpdate,
    current_user: dict = Depends(get_current_user)
):
    """
    更新用户设置
    
    Args:
        settings_data: 设置更新数据
        current_user: 当前用户信息（从 Token 获取）
    
    Returns:
        更新后的用户设置
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 检查用户设置是否存在
            cursor = conn.execute(
                "SELECT id FROM user_settings WHERE userId = ?",
                (user_id,)
            )
            existing = cursor.fetchone()
            
            if existing is None:
                # 如果不存在，先创建
                cursor = conn.execute(
                    """
                    INSERT INTO user_settings (userId, created_at, updated_at)
                    VALUES (?, datetime('now'), datetime('now'))
                    """,
                    (user_id,)
                )
                conn.commit()
            
            # 构建更新字段
            update_fields = []
            update_values = []
            
            if settings_data.deepseek_api_key is not None:
                update_fields.append("deepseek_api_key = ?")
                update_values.append(settings_data.deepseek_api_key)
            
            if settings_data.deepseek_model is not None:
                update_fields.append("deepseek_model = ?")
                update_values.append(settings_data.deepseek_model)
            
            if settings_data.deepseek_temperature is not None:
                update_fields.append("deepseek_temperature = ?")
                update_values.append(settings_data.deepseek_temperature)
            
            if settings_data.deepseek_max_tokens is not None:
                update_fields.append("deepseek_max_tokens = ?")
                update_values.append(settings_data.deepseek_max_tokens)
            
            if settings_data.dark_mode is not None:
                update_fields.append("dark_mode = ?")
                update_values.append(settings_data.dark_mode)
            
            if settings_data.auto_backup_enabled is not None:
                update_fields.append("auto_backup_enabled = ?")
                update_values.append(settings_data.auto_backup_enabled)
            
            if settings_data.auto_backup_interval is not None:
                update_fields.append("auto_backup_interval = ?")
                update_values.append(settings_data.auto_backup_interval)
            
            if settings_data.auto_backup_max_count is not None:
                update_fields.append("auto_backup_max_count = ?")
                update_values.append(settings_data.auto_backup_max_count)
            
            if settings_data.show_online_users is not None:
                update_fields.append("show_online_users = ?")
                update_values.append(settings_data.show_online_users)
            if settings_data.notify_device_online is not None:
                update_fields.append("notify_device_online = ?")
                update_values.append(settings_data.notify_device_online)
            if settings_data.notify_device_offline is not None:
                update_fields.append("notify_device_offline = ?")
                update_values.append(settings_data.notify_device_offline)
            
            if settings_data.last_backup_time is not None:
                update_fields.append("last_backup_time = ?")
                update_values.append(settings_data.last_backup_time)
            
            if not update_fields:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="没有提供要更新的字段"
                )
            
            # 更新更新时间
            update_fields.append("updated_at = datetime('now')")
            update_values.append(user_id)
            
            # 执行更新
            update_sql = f"""
                UPDATE user_settings
                SET {', '.join(update_fields)}
                WHERE userId = ?
            """
            conn.execute(update_sql, tuple(update_values))
            conn.commit()
            
            # 获取更新后的设置
            cursor = conn.execute(
                """
                SELECT id, userId, deepseek_api_key, deepseek_model, deepseek_temperature,
                       deepseek_max_tokens, dark_mode, auto_backup_enabled, auto_backup_interval,
                       auto_backup_max_count, last_backup_time, show_online_users,
                       notify_device_online, notify_device_offline,
                       created_at, updated_at
                FROM user_settings
                WHERE userId = ?
                """,
                (user_id,)
            )
            row = cursor.fetchone()
            
            settings = UserSettingsResponse(
                id=row[0],
                userId=row[1],
                deepseek_api_key=row[2],
                deepseek_model=row[3] if row[3] else "deepseek-chat",
                deepseek_temperature=row[4] if row[4] is not None else 0.7,
                deepseek_max_tokens=row[5] if row[5] is not None else 2000,
                dark_mode=row[6] if row[6] is not None else 0,
                auto_backup_enabled=row[7] if row[7] is not None else 0,
                auto_backup_interval=row[8] if row[8] is not None else 15,
                auto_backup_max_count=row[9] if row[9] is not None else 20,
                last_backup_time=row[10],
                show_online_users=row[11] if row[11] is not None else 1,
                notify_device_online=row[12] if len(row) > 12 and row[12] is not None else 1,
                notify_device_offline=row[13] if len(row) > 13 and row[13] is not None else 1,
                created_at=row[14] if len(row) > 14 else row[12],
                updated_at=row[15] if len(row) > 15 else row[13]
            )
            
            logger.info(f"更新用户设置成功: {user_id}")
            
            return BaseResponse(
                success=True,
                message="更新用户设置成功",
                data=settings.model_dump()
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"更新用户设置失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"更新用户设置失败: {str(e)}"
        )


@router.post("/import-data", response_model=BaseResponse)
async def import_data(
    import_request: ImportDataRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    批量导入数据（覆盖模式）
    
    删除当前用户的所有业务数据，然后导入新数据。
    注意：不会影响用户设置（user_settings）。
    
    Args:
        import_request: 导入数据请求
        current_user: 当前用户信息
    
    Returns:
        导入结果统计
    """
    pool = get_pool()
    user_id = current_user["user_id"]
    
    try:
        with pool.get_connection() as conn:
            # 在事务中执行数据导入
            conn.execute("BEGIN")
            
            try:
                # 1. 删除当前用户的所有业务数据（不包括 user_settings）
                conn.execute("DELETE FROM remittance WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM income WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM returns WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM sales WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM purchases WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM products WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM employees WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM customers WHERE userId = ?", (user_id,))
                conn.execute("DELETE FROM suppliers WHERE userId = ?", (user_id,))
                
                # 2. 创建 ID 映射表（旧ID -> 新ID）
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
                        supplier_dict = {
                            'name': supplier_data.get('name', ''),
                            'note': supplier_data.get('note')
                        }
                        cursor = conn.execute(
                            """
                            INSERT INTO suppliers (userId, name, note, created_at, updated_at)
                            VALUES (?, ?, ?, datetime('now'), datetime('now'))
                            """,
                            (user_id, supplier_dict['name'], supplier_dict['note'])
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
                        customer_dict = {
                            'name': customer_data.get('name', ''),
                            'note': customer_data.get('note')
                        }
                        cursor = conn.execute(
                            """
                            INSERT INTO customers (userId, name, note, created_at, updated_at)
                            VALUES (?, ?, ?, datetime('now'), datetime('now'))
                            """,
                            (user_id, customer_dict['name'], customer_dict['note'])
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
                        employee_dict = {
                            'name': employee_data.get('name', ''),
                            'note': employee_data.get('note')
                        }
                        cursor = conn.execute(
                            """
                            INSERT INTO employees (userId, name, note, created_at, updated_at)
                            VALUES (?, ?, ?, datetime('now'), datetime('now'))
                            """,
                            (user_id, employee_dict['name'], employee_dict['note'])
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
                        # 处理 supplierId 映射
                        supplier_id = product_data.get('supplierId')
                        if supplier_id and supplier_id in supplier_id_map:
                            supplier_id = supplier_id_map[supplier_id]
                        elif supplier_id and supplier_id not in supplier_id_map:
                            supplier_id = None
                        
                        # 处理 unit（可能是字符串或已经是正确的值）
                        unit = product_data.get('unit', '公斤')
                        if isinstance(unit, str):
                            # 确保单位值正确
                            if unit not in ['斤', '公斤', '袋']:
                                unit = '公斤'
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO products (userId, name, description, stock, unit, supplierId, version, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                            """,
                            (
                                user_id,
                                product_data.get('name', ''),
                                product_data.get('description'),
                                product_data.get('stock', 0),
                                unit,
                                supplier_id
                            )
                        )
                        new_id = cursor.lastrowid
                        if original_id:
                            product_id_map[original_id] = new_id
                        product_count += 1
                
                # 7. 导入 purchases
                purchase_count = 0
                if 'purchases' in data and data['purchases']:
                    for purchase_data in data['purchases']:
                        # 处理 supplierId 映射
                        # 如果 supplierId 为 0 或 None，表示未分配供应商，设置为 None
                        supplier_id = purchase_data.get('supplierId')
                        if supplier_id == 0:
                            supplier_id = None
                        elif supplier_id and supplier_id in supplier_id_map:
                            supplier_id = supplier_id_map[supplier_id]
                        elif supplier_id and supplier_id not in supplier_id_map:
                            supplier_id = None
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO purchases (userId, productName, quantity, purchaseDate, supplierId, totalPurchasePrice, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (
                                user_id,
                                purchase_data.get('productName', ''),
                                purchase_data.get('quantity', 0),
                                purchase_data.get('purchaseDate'),
                                supplier_id,
                                purchase_data.get('totalPurchasePrice'),
                                purchase_data.get('note')
                            )
                        )
                        purchase_count += 1
                
                # 8. 导入 sales
                sale_count = 0
                if 'sales' in data and data['sales']:
                    for sale_data in data['sales']:
                        # 处理 customerId 映射
                        customer_id = sale_data.get('customerId')
                        if customer_id and customer_id in customer_id_map:
                            customer_id = customer_id_map[customer_id]
                        elif customer_id and customer_id not in customer_id_map:
                            customer_id = None
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO sales (userId, productName, quantity, saleDate, customerId, totalSalePrice, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (
                                user_id,
                                sale_data.get('productName', ''),
                                sale_data.get('quantity', 0),
                                sale_data.get('saleDate'),
                                customer_id,
                                sale_data.get('totalSalePrice'),
                                sale_data.get('note')
                            )
                        )
                        sale_count += 1
                
                # 9. 导入 returns
                return_count = 0
                if 'returns' in data and data['returns']:
                    for return_data in data['returns']:
                        # 处理 customerId 映射
                        customer_id = return_data.get('customerId')
                        if customer_id and customer_id in customer_id_map:
                            customer_id = customer_id_map[customer_id]
                        elif customer_id and customer_id not in customer_id_map:
                            customer_id = None
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO returns (userId, productName, quantity, returnDate, customerId, totalReturnPrice, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (
                                user_id,
                                return_data.get('productName', ''),
                                return_data.get('quantity', 0),
                                return_data.get('returnDate'),
                                customer_id,
                                return_data.get('totalReturnPrice'),
                                return_data.get('note')
                            )
                        )
                        return_count += 1
                
                # 10. 导入 income
                income_count = 0
                if 'income' in data and data['income']:
                    for income_data in data['income']:
                        # 处理 customerId 和 employeeId 映射
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
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO income (userId, incomeDate, customerId, amount, discount, employeeId, paymentMethod, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (
                                user_id,
                                income_data.get('incomeDate'),
                                customer_id,
                                income_data.get('amount', 0),
                                income_data.get('discount', 0),
                                employee_id,
                                income_data.get('paymentMethod', '现金'),
                                income_data.get('note')
                            )
                        )
                        income_count += 1
                
                # 11. 导入 remittance
                remittance_count = 0
                if 'remittance' in data and data['remittance']:
                    for remittance_data in data['remittance']:
                        # 处理 supplierId 和 employeeId 映射
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
                        
                        cursor = conn.execute(
                            """
                            INSERT INTO remittance (userId, remittanceDate, supplierId, amount, employeeId, paymentMethod, note, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (
                                user_id,
                                remittance_data.get('remittanceDate'),
                                supplier_id,
                                remittance_data.get('amount', 0),
                                employee_id,
                                remittance_data.get('paymentMethod', '现金'),
                                remittance_data.get('note')
                            )
                        )
                        remittance_count += 1
                
                # 提交事务
                conn.execute("COMMIT")
                
                logger.info(f"数据导入成功: 用户 {user_id}, 供应商: {supplier_count}, 客户: {customer_count}, 员工: {employee_count}, 产品: {product_count}, 采购: {purchase_count}, 销售: {sale_count}, 退货: {return_count}, 进账: {income_count}, 汇款: {remittance_count}")
                
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
                # 回滚事务
                conn.execute("ROLLBACK")
                raise e
                
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"数据导入失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"数据导入失败: {str(e)}"
        )

