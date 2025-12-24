"""
操作日志服务
提供日志记录、查询、对比等功能
"""

import json
import logging
from typing import Optional, Dict, Any, List, Tuple
from datetime import datetime, timedelta
import sqlite3

from server.database import get_pool

logger = logging.getLogger(__name__)

# 获取本地时区的当前时间字符串
def get_local_time_str() -> str:
    """
    获取本地时区的当前时间字符串（格式：YYYY-MM-DD HH:MM:SS）
    
    SQLite 的 datetime('now') 返回 UTC 时间，我们需要本地时间（CST，UTC+8）
    使用 Python 的 datetime.now() 获取本地时间
    """
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def convert_utc_to_local_time_str(utc_time_str: str) -> str:
    """
    将 UTC 时间字符串转换为本地时间字符串
    
    Args:
        utc_time_str: UTC 时间字符串（格式：YYYY-MM-DD HH:MM:SS）
    
    Returns:
        本地时间字符串（格式：YYYY-MM-DD HH:MM:SS）
    """
    try:
        # 尝试解析为 UTC 时间
        # SQLite 的 datetime('now') 返回格式通常是 "YYYY-MM-DD HH:MM:SS"
        # 我们需要将其视为 UTC 时间，然后转换为本地时间
        if len(utc_time_str) == 19 and ' ' in utc_time_str and 'T' not in utc_time_str:
            # 格式：YYYY-MM-DD HH:MM:SS（UTC）
            parts = utc_time_str.split(' ')
            if len(parts) == 2:
                date_parts = parts[0].split('-')
                time_parts = parts[1].split(':')
                if len(date_parts) == 3 and len(time_parts) == 3:
                    # 创建 UTC 时间的 datetime 对象
                    utc_dt = datetime(
                        int(date_parts[0]),
                        int(date_parts[1]),
                        int(date_parts[2]),
                        int(time_parts[0]),
                        int(time_parts[1]),
                        int(time_parts[2])
                    )
                    # 转换为本地时间（Python 会自动处理时区）
                    local_dt = utc_dt.replace(tzinfo=None)  # 移除时区信息，因为 SQLite 存储的是 UTC
                    # 由于 SQLite 的 datetime('now') 实际上是 UTC，我们需要手动加 8 小时
                    local_dt = local_dt + timedelta(hours=8)
                    return local_dt.strftime('%Y-%m-%d %H:%M:%S')
    except Exception as e:
        logger.warning(f"转换 UTC 时间失败: {utc_time_str}, 错误: {e}")
    
    # 如果转换失败，返回原值
    return utc_time_str

def convert_time_fields_in_data(data: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    转换数据字典中的时间字段（created_at, updated_at 等）从 UTC 到本地时间
    
    Args:
        data: 数据字典
    
    Returns:
        转换后的数据字典
    """
    if data is None:
        return None
    
    # 创建副本，避免修改原字典
    converted_data = data.copy()
    
    # 时间字段列表
    time_fields = ['created_at', 'updated_at', 'operation_time', 'saleDate', 'purchaseDate', 'returnDate', 'incomeDate', 'remittanceDate']
    
    for field in time_fields:
        if field in converted_data and converted_data[field] is not None:
            time_value = converted_data[field]
            if isinstance(time_value, str):
                converted_data[field] = convert_utc_to_local_time_str(time_value)
    
    return converted_data


class AuditLogService:
    """操作日志服务类"""
    
    @staticmethod
    def log_operation(
        user_id: int,
        username: str,
        operation_type: str,
        entity_type: str,
        entity_id: Optional[int] = None,
        entity_name: Optional[str] = None,
        old_data: Optional[Dict[str, Any]] = None,
        new_data: Optional[Dict[str, Any]] = None,
        changes: Optional[Dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        device_info: Optional[str] = None,
        note: Optional[str] = None,
        workspace_id: Optional[int] = None
    ) -> int:
        """
        记录操作日志
        
        Args:
            user_id: 用户ID
            username: 用户名
            operation_type: 操作类型（CREATE/UPDATE/DELETE）
            entity_type: 实体类型（product/sale/purchase等）
            entity_id: 实体ID
            entity_name: 实体名称
            old_data: 修改前的数据（字典）
            new_data: 修改后的数据（字典）
            changes: 变更摘要（字典）
            ip_address: IP地址
            device_info: 设备信息
            note: 备注
        
        Returns:
            日志ID
        """
        pool = get_pool()
        
        try:
            with pool.get_connection() as conn:
                # 转换时间字段从 UTC 到本地时间
                old_data_converted = convert_time_fields_in_data(old_data)
                new_data_converted = convert_time_fields_in_data(new_data)
                
                # 如果 changes 中包含时间字段，也需要转换
                changes_converted = None
                if changes:
                    changes_converted = {}
                    for key, change_info in changes.items():
                        if isinstance(change_info, dict):
                            change_info_copy = change_info.copy()
                            # 转换 old 和 new 值中的时间字段
                            if 'old' in change_info_copy and isinstance(change_info_copy['old'], str):
                                if any(time_field in key.lower() for time_field in ['created_at', 'updated_at', 'time', 'date']):
                                    change_info_copy['old'] = convert_utc_to_local_time_str(change_info_copy['old'])
                            if 'new' in change_info_copy and isinstance(change_info_copy['new'], str):
                                if any(time_field in key.lower() for time_field in ['created_at', 'updated_at', 'time', 'date']):
                                    change_info_copy['new'] = convert_utc_to_local_time_str(change_info_copy['new'])
                            changes_converted[key] = change_info_copy
                        else:
                            changes_converted[key] = change_info
                
                # 将字典转换为JSON字符串
                old_data_json = json.dumps(old_data_converted, ensure_ascii=False) if old_data_converted else None
                new_data_json = json.dumps(new_data_converted, ensure_ascii=False) if new_data_converted else None
                changes_json = json.dumps(changes_converted, ensure_ascii=False) if changes_converted else None
                
                # 使用本地时间（CST，UTC+8）而不是 SQLite 的 datetime('now')（UTC）
                local_time = get_local_time_str()
                
                # 如果提供了workspace_id，插入时包含workspaceId
                if workspace_id is not None:
                    cursor = conn.execute(
                        """
                        INSERT INTO operation_logs 
                        (userId, workspaceId, username, operation_type, entity_type, entity_id, entity_name,
                         old_data, new_data, changes, ip_address, device_info, operation_time, note)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            user_id,
                            workspace_id,
                            username,
                            operation_type,
                            entity_type,
                            entity_id,
                            entity_name,
                            old_data_json,
                            new_data_json,
                            changes_json,
                            ip_address,
                            device_info,
                            local_time,
                            note
                        )
                    )
                else:
                    cursor = conn.execute(
                        """
                        INSERT INTO operation_logs 
                        (userId, username, operation_type, entity_type, entity_id, entity_name,
                         old_data, new_data, changes, ip_address, device_info, operation_time, note)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            user_id,
                            username,
                            operation_type,
                            entity_type,
                            entity_id,
                            entity_name,
                            old_data_json,
                            new_data_json,
                            changes_json,
                            ip_address,
                            device_info,
                            local_time,
                            note
                        )
                    )
                log_id = cursor.lastrowid
                conn.commit()
                
                logger.debug(f"操作日志已记录: ID={log_id}, 用户={username}, 操作={operation_type}, 实体={entity_type}")
                return log_id
        except Exception as e:
            logger.error(f"记录操作日志失败: {e}", exc_info=True)
            # 日志记录失败不应影响主业务，只记录错误
            return 0
    
    @staticmethod
    def log_create(
        user_id: int,
        username: str,
        entity_type: str,
        entity_id: int,
        entity_name: Optional[str] = None,
        new_data: Optional[Dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        device_info: Optional[str] = None,
        note: Optional[str] = None,
        workspace_id: Optional[int] = None
    ) -> int:
        """
        记录创建操作
        
        Args:
            user_id: 用户ID
            username: 用户名
            entity_type: 实体类型
            entity_id: 实体ID
            entity_name: 实体名称
            new_data: 新创建的数据
            ip_address: IP地址
            device_info: 设备信息
            note: 备注
        
        Returns:
            日志ID
        """
        return AuditLogService.log_operation(
            user_id=user_id,
            username=username,
            operation_type="CREATE",
            entity_type=entity_type,
            entity_id=entity_id,
            entity_name=entity_name,
            new_data=new_data,
            ip_address=ip_address,
            device_info=device_info,
            note=note,
            workspace_id=workspace_id
        )
    
    @staticmethod
    def log_update(
        user_id: int,
        username: str,
        entity_type: str,
        entity_id: int,
        entity_name: Optional[str] = None,
        old_data: Optional[Dict[str, Any]] = None,
        new_data: Optional[Dict[str, Any]] = None,
        changes: Optional[Dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        device_info: Optional[str] = None,
        note: Optional[str] = None,
        workspace_id: Optional[int] = None
    ) -> int:
        """
        记录更新操作
        
        Args:
            user_id: 用户ID
            username: 用户名
            entity_type: 实体类型
            entity_id: 实体ID
            entity_name: 实体名称
            old_data: 修改前的数据
            new_data: 修改后的数据
            changes: 变更摘要（如果为None，会自动对比old_data和new_data生成）
            ip_address: IP地址
            device_info: 设备信息
            note: 备注
        
        Returns:
            日志ID
        """
        # 如果没有提供changes，自动对比生成
        if changes is None and old_data is not None and new_data is not None:
            changes = AuditLogService.compare_data(old_data, new_data)
        
        return AuditLogService.log_operation(
            user_id=user_id,
            username=username,
            operation_type="UPDATE",
            entity_type=entity_type,
            entity_id=entity_id,
            entity_name=entity_name,
            old_data=old_data,
            new_data=new_data,
            changes=changes,
            ip_address=ip_address,
            device_info=device_info,
            note=note,
            workspace_id=workspace_id
        )
    
    @staticmethod
    def log_delete(
        user_id: int,
        username: str,
        entity_type: str,
        entity_id: int,
        entity_name: Optional[str] = None,
        old_data: Optional[Dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        device_info: Optional[str] = None,
        note: Optional[str] = None,
        workspace_id: Optional[int] = None
    ) -> int:
        """
        记录删除操作
        
        Args:
            user_id: 用户ID
            username: 用户名
            entity_type: 实体类型
            entity_id: 实体ID
            entity_name: 实体名称
            old_data: 删除前的数据
            ip_address: IP地址
            device_info: 设备信息
            note: 备注
        
        Returns:
            日志ID
        """
        return AuditLogService.log_operation(
            user_id=user_id,
            username=username,
            operation_type="DELETE",
            entity_type=entity_type,
            entity_id=entity_id,
            entity_name=entity_name,
            old_data=old_data,
            ip_address=ip_address,
            device_info=device_info,
            note=note,
            workspace_id=workspace_id
        )
    
    @staticmethod
    def compare_data(old_data: Dict[str, Any], new_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        对比两个数据字典，返回变更摘要
        
        Args:
            old_data: 旧数据
            new_data: 新数据
        
        Returns:
            变更摘要字典，格式: {field_name: {"old": old_value, "new": new_value, "delta": delta_value}}
        """
        changes = {}
        all_keys = set(old_data.keys()) | set(new_data.keys())
        
        for key in all_keys:
            old_value = old_data.get(key)
            new_value = new_data.get(key)
            
            # 跳过None值比较（避免记录无意义的变更）
            if old_value is None and new_value is None:
                continue
            
            if old_value != new_value:
                change_info = {
                    "old": old_value,
                    "new": new_value
                }
                
                # 如果是数字，计算差值
                if isinstance(old_value, (int, float)) and isinstance(new_value, (int, float)):
                    change_info["delta"] = new_value - old_value
                
                changes[key] = change_info
        
        return changes
    
    @staticmethod
    def get_logs(
        user_id: int,
        page: int = 1,
        page_size: int = 20,
        operation_type: Optional[str] = None,
        entity_type: Optional[str] = None,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None,
        search: Optional[str] = None,
        workspace_id: Optional[int] = None
    ) -> Tuple[List[Dict[str, Any]], int]:
        """
        获取操作日志列表
        
        Args:
            user_id: 用户ID
            page: 页码（从1开始）
            page_size: 每页数量
            operation_type: 操作类型筛选
            entity_type: 实体类型筛选
            start_time: 开始时间（ISO8601格式）
            end_time: 结束时间（ISO8601格式）
            search: 搜索关键词（实体名称、备注）
        
        Returns:
            (日志列表, 总数)
        """
        pool = get_pool()
        
        try:
            with pool.get_connection() as conn:
                # 构建查询条件
                # 如果提供了workspace_id，使用workspace过滤；否则使用userId过滤（向后兼容）
                if workspace_id is not None:
                    conditions = ["workspaceId = ?"]
                    params = [workspace_id]
                else:
                    conditions = ["userId = ?"]
                    params = [user_id]
                
                if operation_type:
                    conditions.append("operation_type = ?")
                    params.append(operation_type)
                
                if entity_type:
                    conditions.append("entity_type = ?")
                    params.append(entity_type)
                
                if start_time:
                    conditions.append("operation_time >= ?")
                    params.append(start_time)
                
                if end_time:
                    conditions.append("operation_time <= ?")
                    params.append(end_time)
                
                if search:
                    conditions.append("(entity_name LIKE ? OR note LIKE ?)")
                    search_pattern = f"%{search}%"
                    params.extend([search_pattern, search_pattern])
                
                where_clause = " AND ".join(conditions)
                
                # 查询总数
                count_cursor = conn.execute(
                    f"SELECT COUNT(*) FROM operation_logs WHERE {where_clause}",
                    params
                )
                total = count_cursor.fetchone()[0]
                
                # 查询数据（分页）
                offset = (page - 1) * page_size
                cursor = conn.execute(
                    f"""
                    SELECT id, userId, username, operation_type, entity_type, entity_id, entity_name,
                           old_data, new_data, changes, ip_address, device_info, operation_time, note
                    FROM operation_logs
                    WHERE {where_clause}
                    ORDER BY operation_time DESC
                    LIMIT ? OFFSET ?
                    """,
                    params + [page_size, offset]
                )
                
                rows = cursor.fetchall()
                logs = []
                
                for row in rows:
                    log_dict = dict(row)
                    # 解析JSON字段
                    if log_dict.get('old_data'):
                        try:
                            log_dict['old_data'] = json.loads(log_dict['old_data'])
                        except (json.JSONDecodeError, TypeError):
                            log_dict['old_data'] = None
                    else:
                        log_dict['old_data'] = None
                    
                    if log_dict.get('new_data'):
                        try:
                            log_dict['new_data'] = json.loads(log_dict['new_data'])
                        except (json.JSONDecodeError, TypeError):
                            log_dict['new_data'] = None
                    else:
                        log_dict['new_data'] = None
                    
                    if log_dict.get('changes'):
                        try:
                            log_dict['changes'] = json.loads(log_dict['changes'])
                        except (json.JSONDecodeError, TypeError):
                            log_dict['changes'] = None
                    else:
                        log_dict['changes'] = None
                    
                    logs.append(log_dict)
                
                return logs, total
        except Exception as e:
            logger.error(f"查询操作日志失败: {e}", exc_info=True)
            raise
    
    @staticmethod
    def get_log_detail(log_id: int, user_id: int, workspace_id: Optional[int] = None) -> Optional[Dict[str, Any]]:
        """
        获取操作日志详情
        
        Args:
            log_id: 日志ID
            user_id: 用户ID（用于权限验证）
        
        Returns:
            日志详情字典，如果不存在或无权访问则返回None
        """
        pool = get_pool()
        
        try:
            with pool.get_connection() as conn:
                # 构建查询条件
                if workspace_id is not None:
                    cursor = conn.execute(
                        """
                        SELECT id, userId, username, operation_type, entity_type, entity_id, entity_name,
                               old_data, new_data, changes, ip_address, device_info, operation_time, note
                        FROM operation_logs
                        WHERE id = ? AND workspaceId = ?
                        """,
                        (log_id, workspace_id)
                    )
                else:
                    cursor = conn.execute(
                        """
                        SELECT id, userId, username, operation_type, entity_type, entity_id, entity_name,
                               old_data, new_data, changes, ip_address, device_info, operation_time, note
                        FROM operation_logs
                        WHERE id = ? AND userId = ?
                        """,
                        (log_id, user_id)
                    )
                
                row = cursor.fetchone()
                if not row:
                    return None
                
                log_dict = dict(row)
                
                # 解析JSON字段
                if log_dict.get('old_data'):
                    try:
                        log_dict['old_data'] = json.loads(log_dict['old_data'])
                    except (json.JSONDecodeError, TypeError):
                        log_dict['old_data'] = None
                else:
                    log_dict['old_data'] = None
                
                if log_dict.get('new_data'):
                    try:
                        log_dict['new_data'] = json.loads(log_dict['new_data'])
                    except (json.JSONDecodeError, TypeError):
                        log_dict['new_data'] = None
                else:
                    log_dict['new_data'] = None
                
                if log_dict.get('changes'):
                    try:
                        log_dict['changes'] = json.loads(log_dict['changes'])
                    except (json.JSONDecodeError, TypeError):
                        log_dict['changes'] = None
                else:
                    log_dict['changes'] = None
                
                return log_dict
        except Exception as e:
            logger.error(f"查询操作日志详情失败: {e}", exc_info=True)
            raise
    
    @staticmethod
    def cleanup_old_logs(days: int = 730, user_id: Optional[int] = None, workspace_id: Optional[int] = None) -> int:
        """
        清理指定天数之前的旧日志
        
        Args:
            days: 保留天数（默认730天，即2年）
        
        Returns:
            删除的记录数
        """
        pool = get_pool()
        
        try:
            with pool.get_connection() as conn:
                # 构建删除条件
                conditions = ["operation_time < datetime('now', '-' || ? || ' days')"]
                params = [days]
                
                if workspace_id is not None:
                    conditions.append("workspaceId = ?")
                    params.append(workspace_id)
                elif user_id is not None:
                    conditions.append("userId = ?")
                    params.append(user_id)
                
                where_clause = " AND ".join(conditions)
                
                cursor = conn.execute(
                    f"""
                    DELETE FROM operation_logs
                    WHERE {where_clause}
                    """,
                    tuple(params)
                )
                deleted_count = cursor.rowcount
                conn.commit()
                
                logger.info(f"清理了 {deleted_count} 条 {days} 天前的操作日志")
                return deleted_count
        except Exception as e:
            logger.error(f"清理旧日志失败: {e}", exc_info=True)
            raise

