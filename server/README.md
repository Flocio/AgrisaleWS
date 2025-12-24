# AgrisaleWS 服务器端

> **独立配置**：AgrisaleWS 使用独立的配置（端口 9000、独立数据库 `agrisalews.db`、独立 Cloudflare Tunnel `agrisalews-server`、独立 systemd 服务 `agrisalews.service`），可以与其他应用共存。

## FastAPI 服务器

### 1. 创建虚拟环境（推荐，特别是 Ubuntu 24.04）

**注意：** Ubuntu 24.04 及更新版本需要使用虚拟环境，否则会报错 `externally-managed-environment`。

```bash
# 安装 python3-venv（如果还没安装）
sudo apt update
sudo apt install python3-venv python3-full -y

# 创建虚拟环境
python3 -m venv venv

# 激活虚拟环境
source venv/bin/activate

# 激活后，命令行前面会显示 (venv)
```

### 2. 安装依赖

```bash
# 确保虚拟环境已激活（命令行前有 (venv)）
# 安装项目依赖
pip install -r requirements.txt
```
或
```bash
pip install -r requirements.txt \
  -i https://pypi.tuna.tsinghua.edu.cn/simple \
  --timeout 120
```

### 3. 创建数据库目录

```bash
# 在 server 目录下创建 data 目录
mkdir -p data
```

### 4. 配置环境变量（可选）

环境变量用于自定义服务器配置。**如果不配置，会使用默认值，服务器可以正常运行。**

**默认值：**
- `DB_PATH="data/agrisalews.db"` - 数据库文件路径
- `DB_MAX_CONNECTIONS=10` - 数据库连接池大小
- `DB_BUSY_TIMEOUT=5000` - 数据库繁忙超时（毫秒）
- `SECRET_KEY="your-secret-key-change-this-in-production"` - JWT 密钥（**生产环境必须更改**）
- `HOST="0.0.0.0"` - 服务器监听地址
- `PORT=9000` - 服务器监听端口（默认 9000）

**何时需要配置：**
- 自定义数据库路径
- 调整数据库连接池大小（根据并发用户数）
- **生产环境必须设置强随机 SECRET_KEY**
- 需要更改服务器端口

**配置方法：**

创建 `.env` 文件或设置环境变量：

```bash
# 数据库配置（路径相对于server目录）
export DB_PATH="data/agrisalews.db"
export DB_MAX_CONNECTIONS=10
export DB_BUSY_TIMEOUT=5000

# JWT 密钥（生产环境必须更改）
export SECRET_KEY="your-secret-key-change-this-in-production"

# 服务器配置
export HOST="0.0.0.0"
export PORT=9000
```

### 5. 启动服务器

使用启动脚本：

```bash
# 在 server 目录下
cd server

# 运行启动脚本（会自动检测并激活虚拟环境）
chmod +x start.sh
./start.sh
```

启动脚本会自动：
- 检测并激活虚拟环境
- 切换到正确的目录（项目根目录）
- 设置环境变量
- 启动服务器（带自动重载功能）

### 6. 访问 API 文档

- Swagger UI: http://localhost:9000/docs
- ReDoc: http://localhost:9000/redoc

## 内网穿透配置（Cloudflare Tunnel）

**重要说明：** Cloudflare Tunnel 和 FastAPI 服务器是**两个独立的服务**，必须都运行：
- **FastAPI 服务器**（`./start.sh`）：提供实际的 API 服务，监听 `localhost:9000`
- **Cloudflare Tunnel**（`cloudflared tunnel run`）：将外网 HTTPS 请求转发到本地 FastAPI 服务器

**注意**：如果服务器上已有其他应用的 Cloudflare Tunnel，AgrisaleWS 可以使用独立的 Tunnel 和配置文件，互不干扰。

### 1. 安装 cloudflared

```bash
# 下载（ARM64 架构，如树莓派）
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64

# 安装到系统路径
sudo mv cloudflared-linux-arm64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
```

### 2. 登录 Cloudflare

```bash
# 登录（会打开浏览器，需要 Cloudflare 账号）
cloudflared tunnel login
```

登录成功后，证书会保存到 `~/.cloudflared/cert.pem`

### 3. 创建隧道

```bash
# 创建隧道（名称可自定义）
cloudflared tunnel create agrisalews-server
```

创建成功后，会显示隧道 ID 和凭证文件路径（如：`~/.cloudflared/<tunnel-id>.json`）

**注意**：如果服务器上已有其他应用的 Cloudflare Tunnel，AgrisaleWS 可以使用独立的 Tunnel，互不干扰。

### 4. 配置 DNS 路由

```bash
# 将域名指向隧道（需要域名已在 Cloudflare 管理）
cloudflared tunnel route dns agrisalews-server agrisalews.drflo.org
```

### 5. 创建配置文件

```bash
# 创建配置目录（root 用户）
sudo mkdir -p /root/.cloudflared

# 复制证书和凭证文件到 root 目录
sudo cp ~/.cloudflared/cert.pem /root/.cloudflared/
sudo cp ~/.cloudflared/<tunnel-id>.json /root/.cloudflared/

# 创建配置文件（如果服务器上已有其他应用，使用独立的配置文件）
sudo nano /root/.cloudflared/config-agrisalews.yml
```

**重要**：如果服务器上已有其他应用的 Cloudflare Tunnel 配置（`/root/.cloudflared/config.yml`），AgrisaleWS 可以使用独立的配置文件（`config-agrisalews.yml`）以避免冲突。

配置文件内容（替换 `<tunnel-id>` 为实际隧道 ID）：

**基础配置（最小可用）：**
```yaml
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: agrisalews.drflo.org
    service: http://localhost:9000
  - service: http_status:404
```

**推荐配置（性能优化）：**
```yaml
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: agrisalews.drflo.org
    service: http://localhost:9000
    originRequest:
      connectTimeout: 10s
      tcpKeepAlive: 30s
      keepAliveConnections: 100
      keepAliveTimeout: 90s
      compressionQuality: 1
  - service: http_status:404
```

**配置说明：**
- 基础配置：最小可用，适合快速测试
- 推荐配置：包含性能优化参数，提高连接复用和压缩效率
  - `connectTimeout: 10s` - 连接超时
  - `tcpKeepAlive: 30s` - TCP 保活间隔
  - `keepAliveConnections: 100` - 最大空闲连接数
  - `keepAliveTimeout: 90s` - 空闲连接保持时间
  - `compressionQuality: 1` - 压缩质量（1=最快，适合实时 API）

### 6. 测试隧道（可选）

在安装为系统服务之前，可以手动测试隧道是否正常工作：

```bash
# 手动运行隧道（会持续运行，按 Ctrl+C 停止）
# 如果使用独立配置文件，使用 --config 参数
sudo cloudflared tunnel --config /root/.cloudflared/config-agrisalews.yml run

# 或者直接使用 tunnel 名称（如果使用默认配置文件）
sudo cloudflared tunnel run agrisalews-server
```

如果看到类似 `Registered tunnel connection` 的日志，说明隧道连接成功。

### 7. 安装为系统服务

**如果这是服务器上唯一的 Cloudflare Tunnel**，使用默认的 cloudflared 服务：

```bash
# 安装服务
sudo cloudflared service install

# 启动并设置开机自启
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# 检查状态
sudo systemctl status cloudflared
```

**如果服务器上已有其他应用的 Cloudflare Tunnel 服务**，需要创建独立的 systemd 服务以避免冲突：

```bash
sudo nano /etc/systemd/system/cloudflared-agrisalews.service
```

内容：

```ini
[Unit]
Description=Cloudflare Tunnel for AgrisaleWS
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /root/.cloudflared/config-agrisalews.yml run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启用并启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable cloudflared-agrisalews
sudo systemctl start cloudflared-agrisalews
sudo systemctl status cloudflared-agrisalews
```

### 8. 验证配置

```bash
# 测试本地服务器
curl http://localhost:9000/health

# 测试 Cloudflare Tunnel
curl https://agrisalews.drflo.org/health
```

### 性能优化

#### 服务器端（已实施）
- ✅ 响应压缩（GZipMiddleware）
- ✅ 缓存控制头
- ✅ 连接复用支持

#### 客户端（已实施）
- ✅ HTTP 连接复用
- ✅ 响应压缩支持
- ✅ 优化重试策略（超时 20s，重试 2 次）

#### Cloudflare Dashboard 设置
1. **Speed → Optimization**：启用 Auto Minify、Brotli、HTTP/2、HTTP/3
2. **Caching → Configuration**：`/api/*` 设置为 Bypass，`/health` 设置为 Standard
3. **Network**：启用 HTTP/2、HTTP/3、0-RTT Connection Resumption

### 故障排查

```bash
# 查看服务状态
sudo systemctl status cloudflared

# 查看日志
sudo journalctl -u cloudflared -f

# 手动测试隧道（如果使用独立配置文件）
sudo cloudflared tunnel --config /root/.cloudflared/config-agrisalews.yml run

# 或者使用 tunnel 名称
sudo cloudflared tunnel run agrisalews-server
```

## 生产环境部署

完成快速开始和内网穿透配置后，可以将服务配置为 systemd 服务，实现开机自启和自动重启。

**重要提示**：AgrisaleWS 使用独立的配置（端口 9000、独立数据库文件 `agrisalews.db`、独立的 Cloudflare Tunnel `agrisalews-server`、独立的 systemd 服务 `agrisalews.service`），可以与其他应用共存。

### FastAPI 服务器部署

#### 步骤 1：找到虚拟环境的 Python 路径

```bash
cd server
source venv/bin/activate
which python
# 会显示类似：/path/to/server/venv/bin/python
```

#### 步骤 2：创建 systemd 服务文件

```bash
sudo nano /etc/systemd/system/agrisalews.service
```

**如果使用虚拟环境（推荐）：**

```ini
[Unit]
Description=AgrisaleWS API Server
After=network.target

[Service]
Type=simple
User=your-user
# 工作目录设置为项目根目录（server 的父目录）
WorkingDirectory=/path/to/project-root
# PATH 环境变量：包含虚拟环境的 bin 目录，用于找到 Python 和依赖包
Environment="PATH=/path/to/server/venv/bin:/usr/local/bin:/usr/bin:/bin"
# 使用相对路径（相对于server目录）
Environment="DB_PATH=data/agrisalews.db"
# JWT 密钥：生产环境必须使用强随机字符串（生成方法见下方）
Environment="SECRET_KEY=your-production-secret-key"
ExecStart=/path/to/server/venv/bin/python -m uvicorn server.main:app --host 0.0.0.0 --port 9000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**如果不使用虚拟环境（不推荐）：**

```ini
[Unit]
Description=AgrisaleWS API Server
After=network.target

[Service]
Type=simple
User=your-user
# 工作目录设置为项目根目录（server 的父目录）
WorkingDirectory=/path/to/project-root
# 使用相对路径（相对于server目录）
Environment="DB_PATH=data/agrisalews.db"
# JWT 密钥：生产环境必须使用强随机字符串
Environment="SECRET_KEY=your-production-secret-key"
ExecStart=/usr/bin/python3 -m uvicorn server.main:app --host 0.0.0.0 --port 9000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**配置说明：**

1. **替换路径：**
   - `/path/to/project-root` → 你的实际项目根目录路径（server 的父目录）
   - `/path/to/server/venv/bin/python` → 步骤 1 中获取的实际 Python 路径
   - `/path/to/server/venv/bin` → 虚拟环境的 bin 目录路径（用于 PATH）

2. **替换用户：**
   - `your-user` → 你的实际用户名（运行服务的用户）

3. **生成 SECRET_KEY（生产环境必须）：**
   ```bash
   # 方法1：使用 Python 生成
   python3 -c "import secrets; print(secrets.token_urlsafe(32))"
   
   # 方法2：使用 openssl 生成
   openssl rand -hex 32
   ```
   将生成的随机字符串替换 `your-production-secret-key`
   
   **重要**：如果服务器上已有其他应用，`SECRET_KEY` 必须使用不同的密钥。

4. **其他环境变量（可选）：**
   如果需要自定义其他环境变量，在 `[Service]` 部分添加：
   ```ini
   Environment="DB_MAX_CONNECTIONS=10"
   Environment="DB_BUSY_TIMEOUT=5000"
   Environment="PORT=9000"
   ```
   
   **重要**：`PORT=9000` 为默认端口，`DB_PATH=data/agrisalews.db` 为独立的数据库文件。

#### 步骤 3：启用并启动服务

```bash
sudo systemctl daemon-reload
sudo systemctl enable agrisalews
sudo systemctl start agrisalews
sudo systemctl status agrisalews
```

### Cloudflare Tunnel 部署

Cloudflare Tunnel 在"内网穿透配置"章节的第 7 步已经配置为系统服务。

**如果使用独立的 Tunnel 服务**（`cloudflared-agrisalews.service`），检查状态：

```bash
sudo systemctl status cloudflared-agrisalews
```

**如果使用默认的 cloudflared 服务**，检查状态：

```bash
sudo systemctl status cloudflared
```

### 验证服务

```bash
# 检查 FastAPI 服务状态
sudo systemctl status agrisalews

# 检查 Cloudflare Tunnel 服务状态（根据您使用的服务）
sudo systemctl status cloudflared-agrisalews
# 或
sudo systemctl status cloudflared

# 测试本地服务器
curl http://localhost:9000/health

# 测试 Cloudflare Tunnel
curl https://agrisalews.drflo.org/health
```

### 使用 Nginx 反向代理（可选）

如果使用 Cloudflare Tunnel，通常不需要 Nginx。如果需要额外的反向代理：

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```







## 代码和配置更新

### FastAPI 代码更新

修改 `/home/florin/Projects/AgrisaleWS/server/` 下的代码后，需要重启服务使更改生效：

```bash
# 重启 FastAPI 服务
sudo systemctl restart agrisalews

# 查看状态确认
sudo systemctl status agrisalews

# 查看日志确认更新成功
sudo journalctl -u agrisalews -n 20 -f
```

**注意：** 当前生产环境配置不支持自动重载（`--reload`），需要手动重启服务。

### Cloudflare Tunnel 配置更新

修改 Cloudflare Tunnel 配置后，需要重启服务使更改生效：

**如果使用独立的 Tunnel 服务**（`cloudflared-agrisalews.service`）：

```bash
# 1. 修改配置文件
sudo nano /root/.cloudflared/config-agrisalews.yml

# 2. 重启服务使配置生效
sudo systemctl restart cloudflared-agrisalews

# 3. 查看状态确认
sudo systemctl status cloudflared-agrisalews
```

**如果使用默认的 cloudflared 服务**：

```bash
# 1. 修改配置文件
sudo nano /root/.cloudflared/config.yml

# 2. 重启服务使配置生效
sudo systemctl restart cloudflared

# 3. 查看状态确认
sudo systemctl status cloudflared
```

### 开发模式（可选，仅限开发环境）

如果经常修改代码，可以启用自动重载功能（**不建议用于生产环境**）：

1. **修改 systemd 服务配置：**
   ```bash
   sudo nano /etc/systemd/system/agrisalews.service
   ```

2. **在 `ExecStart` 行添加 `--reload` 参数：**
   ```ini
   ExecStart=/path/to/server/venv/bin/python -m uvicorn server.main:app --host 0.0.0.0 --port 9000 --reload
   ```

3. **重新加载并重启服务：**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart agrisalews
   ```

**开发模式的优缺点：**
- ✅ **优点**：代码修改后自动重载，无需手动重启
- ❌ **缺点**：性能影响、不适合生产环境、可能导致短暂服务中断

**推荐方案：**
- **生产环境**：不使用 `--reload`，修改代码后手动重启服务
- **开发环境**：使用 `./start.sh`（已包含 `--reload`）进行本地开发

## API 端点

### 认证相关

- `POST /api/auth/register` - 用户注册
- `POST /api/auth/login` - 用户登录
- `POST /api/auth/logout` - 用户登出
- `GET /api/auth/me` - 获取当前用户信息
- `POST /api/auth/refresh` - 刷新 Token
- `POST /api/auth/change-password` - 修改密码

### 用户状态

- `POST /api/users/heartbeat` - 更新心跳
- `GET /api/users/online` - 获取在线设备列表
- `GET /api/users/online/count` - 获取在线设备数量
- `POST /api/users/online/update-action` - 更新当前操作
- `POST /api/users/online/clear-action` - 清除当前操作

### 产品管理

- `GET /api/products` - 获取产品列表
- `GET /api/products/{id}` - 获取产品详情
- `POST /api/products` - 创建产品
- `PUT /api/products/{id}` - 更新产品
- `DELETE /api/products/{id}` - 删除产品
- `POST /api/products/{id}/stock` - 更新库存

### 采购管理

- `GET /api/purchases` - 获取采购记录列表
- `GET /api/purchases/{id}` - 获取采购记录详情
- `POST /api/purchases` - 创建采购记录
- `PUT /api/purchases/{id}` - 更新采购记录
- `DELETE /api/purchases/{id}` - 删除采购记录

### 销售管理

- `GET /api/sales` - 获取销售记录列表
- `GET /api/sales/{id}` - 获取销售记录详情
- `POST /api/sales` - 创建销售记录
- `PUT /api/sales/{id}` - 更新销售记录
- `DELETE /api/sales/{id}` - 删除销售记录

### 退货管理

- `GET /api/returns` - 获取退货记录列表
- `GET /api/returns/{id}` - 获取退货记录详情
- `POST /api/returns` - 创建退货记录
- `PUT /api/returns/{id}` - 更新退货记录
- `DELETE /api/returns/{id}` - 删除退货记录

### 客户管理

- `GET /api/customers` - 获取客户列表
- `GET /api/customers/all` - 获取所有客户
- `GET /api/customers/{id}` - 获取客户详情
- `POST /api/customers` - 创建客户
- `PUT /api/customers/{id}` - 更新客户
- `DELETE /api/customers/{id}` - 删除客户

### 供应商管理

- `GET /api/suppliers` - 获取供应商列表
- `GET /api/suppliers/all` - 获取所有供应商
- `GET /api/suppliers/{id}` - 获取供应商详情
- `POST /api/suppliers` - 创建供应商
- `PUT /api/suppliers/{id}` - 更新供应商
- `DELETE /api/suppliers/{id}` - 删除供应商

### 员工管理

- `GET /api/employees` - 获取员工列表
- `GET /api/employees/all` - 获取所有员工
- `GET /api/employees/{id}` - 获取员工详情
- `POST /api/employees` - 创建员工
- `PUT /api/employees/{id}` - 更新员工
- `DELETE /api/employees/{id}` - 删除员工

### 进账管理

- `GET /api/income` - 获取进账记录列表
- `GET /api/income/{id}` - 获取进账记录详情
- `POST /api/income` - 创建进账记录
- `PUT /api/income/{id}` - 更新进账记录
- `DELETE /api/income/{id}` - 删除进账记录

### 汇款管理

- `GET /api/remittance` - 获取汇款记录列表
- `GET /api/remittance/{id}` - 获取汇款记录详情
- `POST /api/remittance` - 创建汇款记录
- `PUT /api/remittance/{id}` - 更新汇款记录
- `DELETE /api/remittance/{id}` - 删除汇款记录

### 用户设置

- `GET /api/settings` - 获取用户设置
- `PUT /api/settings` - 更新用户设置
- `POST /api/settings/import-data` - 导入数据

## 系统端点

- `GET /` - API 信息
- `GET /health` - 健康检查
- `GET /api/info` - API 详细信息

## 特性

### 1. 数据安全

- JWT Token 认证
- 密码 bcrypt 加密
- 用户数据隔离（每个用户只能访问自己的数据）

### 2. 并发控制

- SQLite 连接池（支持 3-4 人并发）
- WAL 模式（Write-Ahead Logging）
- 乐观锁（防止并发冲突）
- 自动重试机制

### 3. 数据完整性

- 外键约束
- 事务支持
- 自动回滚

### 4. 错误处理

- 统一的错误响应格式
- 详细的错误日志
- 友好的错误消息

### 5. 性能优化

- 连接池管理
- 数据库索引
- 分页支持
