"""
数据模型定义
使用 Pydantic 进行数据验证和序列化
"""

from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum
import json


# ==================== 枚举类型 ====================

class ProductUnit(str, Enum):
    """产品单位"""
    JIN = "斤"
    KILOGRAM = "公斤"
    BAG = "袋"


class PaymentMethod(str, Enum):
    """支付方式"""
    CASH = "现金"
    WECHAT = "微信转账"
    BANK_CARD = "银行卡"


# ==================== 基础模型 ====================

class BaseResponse(BaseModel):
    """基础响应模型"""
    success: bool = True
    message: str = "操作成功"
    data: Optional[Any] = None


class ErrorResponse(BaseModel):
    """错误响应模型"""
    success: bool = False
    message: str
    error_code: Optional[str] = None
    details: Optional[Dict[str, Any]] = None


class PaginationParams(BaseModel):
    """分页参数"""
    page: int = Field(1, ge=1, description="页码，从1开始")
    page_size: int = Field(20, ge=1, le=10000, description="每页数量（最大 10000，用于报表等需要获取大量数据的场景）")


class PaginatedResponse(BaseModel):
    """分页响应"""
    items: List[Any]
    total: int
    page: int
    page_size: int
    total_pages: int


# ==================== 用户相关模型 ====================

class UserCreate(BaseModel):
    """创建用户请求"""
    username: str = Field(..., min_length=1, max_length=50, description="用户名")
    password: str = Field(..., min_length=3, max_length=72, description="密码（bcrypt 限制最大 72 字节）")
    
    @validator('password')
    def validate_password_length(cls, v):
        """验证密码字节长度不超过 72 字节"""
        password_bytes = v.encode('utf-8')
        if len(password_bytes) > 72:
            raise ValueError('密码长度不能超过 72 字节（UTF-8 编码）')
        return v


class UserLogin(BaseModel):
    """用户登录请求"""
    username: str = Field(..., description="用户名")
    password: str = Field(..., description="密码")


class UserResponse(BaseModel):
    """用户响应"""
    id: int
    username: str
    created_at: Optional[str] = None
    last_login_at: Optional[str] = None

    model_config = {"from_attributes": True}


class UserInfo(BaseModel):
    """用户信息（包含 Token）"""
    user: UserResponse
    token: str
    expires_in: int = 3600  # Token 过期时间（秒）


class ChangePasswordRequest(BaseModel):
    """修改密码请求"""
    old_password: str = Field(..., min_length=1, description="当前密码")
    new_password: str = Field(..., min_length=3, max_length=72, description="新密码（bcrypt 限制最大 72 字节）")


class LogoutRequest(BaseModel):
    """登出请求"""
    device_id: Optional[str] = Field(None, max_length=100, description="设备ID（可选，如果提供则只删除该设备的记录）")


class DeleteAccountRequest(BaseModel):
    """删除账户请求"""
    password: str = Field(..., min_length=1, description="用户密码（用于确认身份）")


# ==================== Workspace 相关模型 ====================

class WorkspaceCreate(BaseModel):
    """创建 Workspace 请求"""
    name: str = Field(..., min_length=1, max_length=100, description="Workspace 名称")
    description: Optional[str] = Field(None, max_length=500, description="Workspace 描述")
    storage_type: str = Field('server', description="存储类型（'local' 或 'server'）")


class WorkspaceUpdate(BaseModel):
    """更新 Workspace 请求"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    is_shared: Optional[bool] = Field(None, description="是否共享")
    
    class Config:
        populate_by_name = True  # 允许使用字段名或别名


class WorkspaceDeleteRequest(BaseModel):
    """删除 Workspace 请求"""
    password: str = Field(..., min_length=1, description="用户密码")


class WorkspaceResponse(BaseModel):
    """Workspace 响应"""
    id: int
    name: str
    description: Optional[str] = None
    ownerId: int
    storage_type: str
    is_shared: bool
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = {"from_attributes": True}


class WorkspaceMemberResponse(BaseModel):
    """Workspace 成员响应"""
    id: int
    workspaceId: int
    userId: int
    username: str
    role: str
    joined_at: Optional[str] = None

    model_config = {"from_attributes": True}


class WorkspaceInviteRequest(BaseModel):
    """邀请用户加入 Workspace 请求"""
    username: Optional[str] = Field(None, description="邀请用户名（如果用户已存在）")
    email: Optional[str] = Field(None, description="邀请邮箱（如果用户不存在，用于将来扩展）")
    userId: Optional[int] = Field(None, description="邀请的用户ID（如果用户已存在）")
    role: str = Field('editor', description="角色（'admin', 'editor', 'viewer'）")
    
    @validator('role')
    def validate_role(cls, v):
        """验证角色值"""
        valid_roles = ['admin', 'editor', 'viewer']
        if v not in valid_roles:
            raise ValueError(f"角色必须是以下之一: {', '.join(valid_roles)}")
        return v


class WorkspaceMemberUpdate(BaseModel):
    """更新 Workspace 成员权限请求"""
    role: str = Field(..., description="角色（'admin', 'editor', 'viewer'）")
    
    @validator('role')
    def validate_role(cls, v):
        """验证角色值"""
        valid_roles = ['admin', 'editor', 'viewer']
        if v not in valid_roles:
            raise ValueError(f"角色必须是以下之一: {', '.join(valid_roles)}")
        return v


# ==================== 产品相关模型 ====================

class ProductCreate(BaseModel):
    """创建产品请求"""
    name: str = Field(..., min_length=1, max_length=200, description="产品名称")
    description: Optional[str] = Field(None, max_length=1000, description="产品描述")
    stock: float = Field(0.0, ge=0, description="库存数量")
    unit: ProductUnit = Field(..., description="单位")
    supplierId: Optional[int] = Field(None, description="供应商ID")


class ProductUpdate(BaseModel):
    """更新产品请求"""
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    stock: Optional[float] = Field(None, ge=0)
    unit: Optional[ProductUnit] = None
    supplierId: Optional[int] = None
    version: Optional[int] = Field(None, description="版本号（乐观锁）")


class ProductResponse(BaseModel):
    """产品响应"""
    id: int
    userId: int
    name: str
    description: Optional[str] = None
    stock: float
    unit: str
    supplierId: Optional[int] = None
    version: int = 1
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = {"from_attributes": True}


class ProductStockUpdate(BaseModel):
    """库存更新请求（带乐观锁）"""
    quantity: float = Field(..., description="数量变化（正数增加，负数减少）")
    version: int = Field(..., description="当前版本号")


# ==================== 供应商相关模型 ====================

class SupplierCreate(BaseModel):
    """创建供应商请求"""
    name: str = Field(..., min_length=1, max_length=200, description="供应商名称")
    note: Optional[str] = Field(None, max_length=1000, description="备注")


class SupplierUpdate(BaseModel):
    """更新供应商请求"""
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    note: Optional[str] = Field(None, max_length=1000)


class SupplierResponse(BaseModel):
    """供应商响应"""
    id: int
    userId: int
    name: str
    note: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 客户相关模型 ====================

class CustomerCreate(BaseModel):
    """创建客户请求"""
    name: str = Field(..., min_length=1, max_length=200, description="客户名称")
    note: Optional[str] = Field(None, max_length=1000, description="备注")


class CustomerUpdate(BaseModel):
    """更新客户请求"""
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    note: Optional[str] = Field(None, max_length=1000)


class CustomerResponse(BaseModel):
    """客户响应"""
    id: int
    userId: int
    name: str
    note: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 员工相关模型 ====================

class EmployeeCreate(BaseModel):
    """创建员工请求"""
    name: str = Field(..., min_length=1, max_length=200, description="员工名称")
    note: Optional[str] = Field(None, max_length=1000, description="备注")


class EmployeeUpdate(BaseModel):
    """更新员工请求"""
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    note: Optional[str] = Field(None, max_length=1000)


class EmployeeResponse(BaseModel):
    """员工响应"""
    id: int
    userId: int
    name: str
    note: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 采购相关模型 ====================

class PurchaseCreate(BaseModel):
    """创建采购记录请求"""
    productName: str = Field(..., min_length=1, max_length=200, description="产品名称")
    quantity: float = Field(..., description="采购数量（可为负数表示退货）")
    purchaseDate: Optional[str] = Field(None, description="采购日期（ISO8601格式）")
    supplierId: Optional[int] = Field(None, description="供应商ID")
    totalPurchasePrice: Optional[float] = Field(None, description="总进价（可为负数表示退货退款）")
    note: Optional[str] = Field(None, max_length=1000, description="备注")

    @validator('purchaseDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class PurchaseUpdate(BaseModel):
    """更新采购记录请求"""
    productName: Optional[str] = Field(None, min_length=1, max_length=200)
    quantity: Optional[float] = None
    purchaseDate: Optional[str] = None
    supplierId: Optional[int] = None
    totalPurchasePrice: Optional[float] = None
    note: Optional[str] = Field(None, max_length=1000)

    @validator('purchaseDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class PurchaseResponse(BaseModel):
    """采购记录响应"""
    id: int
    userId: int
    productName: str
    quantity: float
    purchaseDate: Optional[str] = None
    supplierId: Optional[int] = None
    totalPurchasePrice: Optional[float] = None
    note: Optional[str] = None
    created_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 销售相关模型 ====================

class SaleCreate(BaseModel):
    """创建销售记录请求"""
    productName: str = Field(..., min_length=1, max_length=200, description="产品名称")
    quantity: float = Field(..., gt=0, description="销售数量（必须大于0）")
    customerId: Optional[int] = Field(None, description="客户ID")
    saleDate: Optional[str] = Field(None, description="销售日期（ISO8601格式）")
    totalSalePrice: Optional[float] = Field(None, ge=0, description="总售价")
    note: Optional[str] = Field(None, max_length=1000, description="备注")

    @validator('saleDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class SaleUpdate(BaseModel):
    """更新销售记录请求"""
    productName: Optional[str] = Field(None, min_length=1, max_length=200)
    quantity: Optional[float] = Field(None, gt=0)
    customerId: Optional[int] = None
    saleDate: Optional[str] = None
    totalSalePrice: Optional[float] = Field(None, ge=0)
    note: Optional[str] = Field(None, max_length=1000)

    @validator('saleDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class SaleResponse(BaseModel):
    """销售记录响应"""
    id: int
    userId: int
    productName: str
    quantity: float
    customerId: Optional[int] = None
    saleDate: Optional[str] = None
    totalSalePrice: Optional[float] = None
    note: Optional[str] = None
    created_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 退货相关模型 ====================

class ReturnCreate(BaseModel):
    """创建退货记录请求"""
    productName: str = Field(..., min_length=1, max_length=200, description="产品名称")
    quantity: float = Field(..., gt=0, description="退货数量（必须大于0）")
    customerId: Optional[int] = Field(None, description="客户ID")
    returnDate: Optional[str] = Field(None, description="退货日期（ISO8601格式）")
    totalReturnPrice: Optional[float] = Field(None, ge=0, description="总退货金额")
    note: Optional[str] = Field(None, max_length=1000, description="备注")

    @validator('returnDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class ReturnUpdate(BaseModel):
    """更新退货记录请求"""
    productName: Optional[str] = Field(None, min_length=1, max_length=200)
    quantity: Optional[float] = Field(None, gt=0)
    customerId: Optional[int] = None
    returnDate: Optional[str] = None
    totalReturnPrice: Optional[float] = Field(None, ge=0)
    note: Optional[str] = Field(None, max_length=1000)

    @validator('returnDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class ReturnResponse(BaseModel):
    """退货记录响应"""
    id: int
    userId: int
    productName: str
    quantity: float
    customerId: Optional[int] = None
    returnDate: Optional[str] = None
    totalReturnPrice: Optional[float] = None
    note: Optional[str] = None
    created_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 进账相关模型 ====================

class IncomeCreate(BaseModel):
    """创建进账记录请求"""
    incomeDate: str = Field(..., description="进账日期（ISO8601格式）")
    customerId: Optional[int] = Field(None, description="客户ID")
    amount: float = Field(..., gt=0, description="进账金额（必须大于0）")
    discount: float = Field(0.0, ge=0, description="优惠金额")
    employeeId: Optional[int] = Field(None, description="经手人ID（员工ID）")
    paymentMethod: PaymentMethod = Field(..., description="支付方式")
    note: Optional[str] = Field(None, max_length=1000, description="备注")

    @validator('incomeDate')
    def validate_date(cls, v):
        try:
            datetime.fromisoformat(v.replace('Z', '+00:00'))
        except ValueError:
            raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class IncomeUpdate(BaseModel):
    """更新进账记录请求"""
    incomeDate: Optional[str] = None
    customerId: Optional[int] = None
    amount: Optional[float] = Field(None, gt=0)
    discount: Optional[float] = Field(None, ge=0)
    employeeId: Optional[int] = None
    paymentMethod: Optional[PaymentMethod] = None
    note: Optional[str] = Field(None, max_length=1000)

    @validator('incomeDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class IncomeResponse(BaseModel):
    """进账记录响应"""
    id: int
    userId: int
    incomeDate: str
    customerId: Optional[int] = None
    amount: float
    discount: float = 0.0
    employeeId: Optional[int] = None
    paymentMethod: str
    note: Optional[str] = None
    created_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 汇款相关模型 ====================

class RemittanceCreate(BaseModel):
    """创建汇款记录请求"""
    remittanceDate: str = Field(..., description="汇款日期（ISO8601格式）")
    supplierId: Optional[int] = Field(None, description="供应商ID")
    amount: float = Field(..., gt=0, description="汇款金额（必须大于0）")
    employeeId: Optional[int] = Field(None, description="经手人ID（员工ID）")
    paymentMethod: PaymentMethod = Field(..., description="支付方式")
    note: Optional[str] = Field(None, max_length=1000, description="备注")

    @validator('remittanceDate')
    def validate_date(cls, v):
        try:
            datetime.fromisoformat(v.replace('Z', '+00:00'))
        except ValueError:
            raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class RemittanceUpdate(BaseModel):
    """更新汇款记录请求"""
    remittanceDate: Optional[str] = None
    supplierId: Optional[int] = None
    amount: Optional[float] = Field(None, gt=0)
    employeeId: Optional[int] = None
    paymentMethod: Optional[PaymentMethod] = None
    note: Optional[str] = Field(None, max_length=1000)

    @validator('remittanceDate')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class RemittanceResponse(BaseModel):
    """汇款记录响应"""
    id: int
    userId: int
    remittanceDate: str
    supplierId: Optional[int] = None
    amount: float
    employeeId: Optional[int] = None
    paymentMethod: str
    note: Optional[str] = None
    created_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 用户设置相关模型 ====================

class UserSettingsUpdate(BaseModel):
    """更新用户设置请求"""
    deepseek_api_key: Optional[str] = Field(None, max_length=200)
    deepseek_model: Optional[str] = Field(None, max_length=50)
    deepseek_temperature: Optional[float] = Field(None, ge=0.0, le=1.0)
    deepseek_max_tokens: Optional[int] = Field(None, ge=500, le=4000)
    dark_mode: Optional[int] = Field(None, ge=0, le=1)
    auto_backup_enabled: Optional[int] = Field(None, ge=0, le=1)
    auto_backup_interval: Optional[int] = Field(None, ge=1)
    auto_backup_max_count: Optional[int] = Field(None, ge=1)
    last_backup_time: Optional[str] = Field(None, description="最后备份时间（ISO8601格式）")
    show_online_users: Optional[int] = Field(None, ge=0, le=1, description="显示在线用户提示")
    notify_device_online: Optional[int] = Field(None, ge=0, le=1, description="设备上线通知")
    notify_device_offline: Optional[int] = Field(None, ge=0, le=1, description="设备下线通知")


class UserSettingsResponse(BaseModel):
    """用户设置响应"""
    id: int
    userId: int
    deepseek_api_key: Optional[str] = None
    deepseek_model: str = "deepseek-chat"
    deepseek_temperature: float = 0.7
    deepseek_max_tokens: int = 2000
    dark_mode: int = 0
    auto_backup_enabled: int = 0
    auto_backup_interval: int = 15
    auto_backup_max_count: int = 20
    last_backup_time: Optional[str] = None
    show_online_users: int = 1
    notify_device_online: int = 1
    notify_device_offline: int = 1
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 在线用户相关模型 ====================

class OnlineUserUpdate(BaseModel):
    """更新在线用户状态请求"""
    device_id: Optional[str] = Field(None, max_length=100, description="设备ID（用于区分同一用户的不同设备）")
    current_action: Optional[str] = Field(None, max_length=200, description="当前操作描述")
    platform: Optional[str] = Field(None, max_length=50, description="设备平台（如：Android、iOS、macOS、Windows、Linux）")
    device_name: Optional[str] = Field(None, max_length=200, description="设备名称（如：iPhone 14 Pro、MacBook Pro等）")


class OnlineUserResponse(BaseModel):
    """在线用户响应"""
    userId: int
    deviceId: str
    username: str
    last_heartbeat: str
    current_action: Optional[str] = None
    platform: Optional[str] = None
    device_name: Optional[str] = None

    model_config = {"from_attributes": True}


# ==================== 报表查询相关模型 ====================

class DateRangeFilter(BaseModel):
    """日期范围筛选"""
    start_date: Optional[str] = Field(None, description="开始日期（ISO8601格式）")
    end_date: Optional[str] = Field(None, description="结束日期（ISO8601格式）")

    @validator('start_date', 'end_date')
    def validate_date(cls, v):
        if v:
            try:
                datetime.fromisoformat(v.replace('Z', '+00:00'))
            except ValueError:
                raise ValueError('日期格式错误，请使用 ISO8601 格式')
        return v


class ProductFilter(BaseModel):
    """产品筛选"""
    product_name: Optional[str] = None
    supplier_id: Optional[int] = None


class CustomerFilter(BaseModel):
    """客户筛选"""
    customer_name: Optional[str] = None
    customer_id: Optional[int] = None


class SupplierFilter(BaseModel):
    """供应商筛选"""
    supplier_name: Optional[str] = None
    supplier_id: Optional[int] = None


class EmployeeFilter(BaseModel):
    """员工筛选"""
    employee_name: Optional[str] = None
    employee_id: Optional[int] = None


# ==================== 数据导出相关模型 ====================

class ExportDataResponse(BaseModel):
    """数据导出响应"""
    exportInfo: Dict[str, Any]
    data: Dict[str, List[Any]]


class ImportDataRequest(BaseModel):
    """数据导入请求"""
    exportInfo: Dict[str, Any]
    data: Dict[str, List[Any]]
    source: Optional[str] = Field(None, description="导入来源：'backup' 表示备份恢复，'manual' 表示手动导入，None 表示未指定（默认为手动导入）")


# ==================== 辅助函数 ====================

def row_to_dict(row) -> dict:
    """
    将数据库行对象转换为字典
    
    Args:
        row: sqlite3.Row 对象
    
    Returns:
        字典
    """
    if row is None:
        return None
    return dict(row)


def rows_to_dicts(rows) -> List[dict]:
    """
    将数据库行对象列表转换为字典列表
    
    Args:
        rows: sqlite3.Row 对象列表
    
    Returns:
        字典列表
    """
    return [dict(row) for row in rows] if rows else []


# ==================== 操作日志相关模型 ====================

class OperationType(str, Enum):
    """操作类型"""
    CREATE = "CREATE"
    UPDATE = "UPDATE"
    DELETE = "DELETE"
    COVER = "COVER"


class EntityType(str, Enum):
    """实体类型"""
    PRODUCT = "product"
    CUSTOMER = "customer"
    SUPPLIER = "supplier"
    EMPLOYEE = "employee"
    PURCHASE = "purchase"
    SALE = "sale"
    RETURN = "return"
    INCOME = "income"
    REMITTANCE = "remittance"
    WORKSPACE_DATA = "workspace_data"


class AuditLogCreate(BaseModel):
    """创建操作日志请求"""
    operation_type: OperationType = Field(..., description="操作类型")
    entity_type: str = Field(..., description="实体类型")
    entity_id: Optional[int] = Field(None, description="实体ID")
    entity_name: Optional[str] = Field(None, description="实体名称")
    old_data: Optional[Dict[str, Any]] = Field(None, description="修改前的数据（JSON格式）")
    new_data: Optional[Dict[str, Any]] = Field(None, description="修改后的数据（JSON格式）")
    changes: Optional[Dict[str, Any]] = Field(None, description="变更摘要（JSON格式）")
    ip_address: Optional[str] = Field(None, description="操作IP地址")
    device_info: Optional[str] = Field(None, description="设备信息")
    note: Optional[str] = Field(None, description="备注信息")


class AuditLogResponse(BaseModel):
    """操作日志响应"""
    id: int
    userId: int
    username: str
    operation_type: str
    entity_type: str
    entity_id: Optional[int] = None
    entity_name: Optional[str] = None
    old_data: Optional[Dict[str, Any]] = None
    new_data: Optional[Dict[str, Any]] = None
    changes: Optional[Dict[str, Any]] = None
    ip_address: Optional[str] = None
    device_info: Optional[str] = None
    operation_time: str
    note: Optional[str] = None

    model_config = {"from_attributes": True}


class AuditLogFilter(BaseModel):
    """操作日志筛选参数"""
    operation_type: Optional[OperationType] = Field(None, description="操作类型筛选")
    entity_type: Optional[str] = Field(None, description="实体类型筛选")
    start_time: Optional[str] = Field(None, description="开始时间（ISO8601格式）")
    end_time: Optional[str] = Field(None, description="结束时间（ISO8601格式）")
    search: Optional[str] = Field(None, description="搜索关键词（实体名称、备注）")


class AuditLogListResponse(BaseModel):
    """操作日志列表响应"""
    logs: List[AuditLogResponse]
    total: int
    page: int
    page_size: int
    total_pages: int

