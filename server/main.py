"""
FastAPI 应用主文件
整合所有路由、中间件和配置
"""

import logging
import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.cors import CORSMiddleware

from server.database import init_database, get_pool
from server.constants import APP_VERSION
from server.middleware import setup_middleware
from server.routers import (
    auth,
    users,
    products,
    purchases,
    sales,
    returns,
    customers,
    suppliers,
    employees,
    income,
    remittance,
    settings,
    help,
    audit_logs,
    workspaces
)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 从环境变量获取配置，如果没有则使用默认值
# 默认路径为 data/agrisalews.db，相对于server目录
# 如果从项目根目录运行，可以使用 server/data/agrisalews.db
# 如果server目录是独立的，使用 data/agrisalews.db
DB_PATH = os.getenv("DB_PATH", "data/agrisalews.db")
DB_MAX_CONNECTIONS = int(os.getenv("DB_MAX_CONNECTIONS", "10"))
DB_BUSY_TIMEOUT = int(os.getenv("DB_BUSY_TIMEOUT", "5000"))
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-change-this-in-production")
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "9000"))  # 默认端口 9000


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    应用生命周期管理
    在启动时初始化数据库，在关闭时清理资源
    """
    # 启动时执行
    logger.info("正在启动应用...")
    
    # 初始化数据库连接池
    try:
        pool = init_database(
            db_path=DB_PATH,
            max_connections=DB_MAX_CONNECTIONS,
            busy_timeout=DB_BUSY_TIMEOUT
        )
        logger.info(f"数据库连接池初始化成功: {DB_PATH}")
        logger.info(f"最大连接数: {DB_MAX_CONNECTIONS}, 繁忙超时: {DB_BUSY_TIMEOUT}ms")
    except Exception as e:
        logger.error(f"数据库初始化失败: {e}", exc_info=True)
        raise
    
    # 更新 JWT 密钥（如果从环境变量获取）
    if SECRET_KEY != "your-secret-key-change-this-in-production":
        from server.middleware import update_secret_key
        update_secret_key(SECRET_KEY)
        logger.info("JWT 密钥已从环境变量更新")
    else:
        logger.warning("⚠️  警告: 使用默认 JWT 密钥，生产环境请设置 SECRET_KEY 环境变量")
    
    # 启动后台任务：定期清理过期的在线用户
    async def cleanup_task():
        """后台任务：定期清理过期的在线用户"""
        from server.routers.users import _cleanup_expired_users
        cleanup_interval = 15  # 每15秒清理一次
        
        while True:
            try:
                await asyncio.sleep(cleanup_interval)
                pool = get_pool()
                if pool:
                    with pool.get_connection() as conn:
                        deleted_count = _cleanup_expired_users(conn)
                        if deleted_count > 0:
                            logger.debug(f"后台清理过期在线用户: 删除了 {deleted_count} 条记录")
            except Exception as e:
                logger.error(f"后台清理任务出错: {e}", exc_info=True)
                # 出错后等待更长时间再重试
                await asyncio.sleep(60)
    
    # 启动后台清理任务
    cleanup_task_handle = asyncio.create_task(cleanup_task())
    logger.info("后台清理任务已启动（每15秒清理一次过期在线用户）")
    
    yield
    
    # 停止后台任务
    cleanup_task_handle.cancel()
    try:
        await cleanup_task_handle
    except asyncio.CancelledError:
        logger.info("后台清理任务已停止")
    
    # 关闭时执行
    logger.info("正在关闭应用...")
    try:
        pool = get_pool()
        if pool:
            pool.close_all()
            logger.info("数据库连接池已关闭")
    except Exception as e:
        logger.error(f"关闭数据库连接池时出错: {e}")


# 创建 FastAPI 应用实例
app = FastAPI(
    title="AgrisaleWS API",
    description="AgrisaleWS后端 API 服务",
    version=APP_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan
)

# 设置中间件
setup_middleware(app)

# 添加响应压缩中间件（提高 Cloudflare Tunnel 传输效率）
app.add_middleware(GZipMiddleware, minimum_size=1000)  # 只压缩大于 1KB 的响应

# 添加 CORS 中间件（如果需要）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境应该限制具体域名
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(workspaces.router)
app.include_router(products.router)
app.include_router(purchases.router)
app.include_router(sales.router)
app.include_router(returns.router)
app.include_router(customers.router)
app.include_router(suppliers.router)
app.include_router(employees.router)
app.include_router(income.router)
app.include_router(remittance.router)
app.include_router(settings.router)
app.include_router(help.router)
app.include_router(audit_logs.router)

logger.info("所有路由已注册")


@app.get("/", tags=["系统"])
async def root():
    """
    根路径，返回 API 信息
    """
    return {
        "name": "AgrisaleWS API",
        "version": APP_VERSION,
        "status": "running",
        "docs": "/docs",
        "redoc": "/redoc"
    }


@app.get("/health", tags=["系统"])
async def health_check():
    """
    健康检查端点
    用于监控系统状态
    """
    try:
        # 检查数据库连接
        pool = get_pool()
        with pool.get_connection() as conn:
            conn.execute("SELECT 1").fetchone()
        
        return JSONResponse(
            status_code=200,
            content={
                "status": "healthy",
                "database": "connected",
                "version": "1.1.0"
            }
        )
    except Exception as e:
        logger.error(f"健康检查失败: {e}")
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "database": "disconnected",
                "error": str(e)
            }
        )


@app.get("/api/info", tags=["系统"])
async def api_info():
    """
    获取 API 信息
    """
    return {
        "name": "AgrisaleWS API",
        "version": APP_VERSION,
        "description": "AgrisaleWS后端 API 服务",
        "endpoints": {
            "auth": "/api/auth",
            "users": "/api/users",
            "products": "/api/products",
            "purchases": "/api/purchases",
            "sales": "/api/sales",
            "returns": "/api/returns",
            "customers": "/api/customers",
            "suppliers": "/api/suppliers",
            "employees": "/api/employees",
            "income": "/api/income",
            "remittance": "/api/remittance",
            "settings": "/api/settings",
            "audit-logs": "/api/audit-logs"
        },
        "docs": "/docs",
        "redoc": "/redoc"
    }


if __name__ == "__main__":
    import uvicorn
    
    logger.info(f"启动服务器: {HOST}:{PORT}")
    logger.info(f"数据库路径: {DB_PATH}")
    logger.info(f"API 文档: http://{HOST}:{PORT}/docs")
    
    uvicorn.run(
        "server.main:app",
        host=HOST,
        port=PORT,
        reload=True,  # 开发模式自动重载
        log_level="info"
    )

