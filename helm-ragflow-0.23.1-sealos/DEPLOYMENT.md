# Web-Visitor 子域访问 Ragflow01 部署说明

## 文件说明

### 配置文件
1. **nginx-custom.conf** - 自定义 nginx 配置文件（参考用）
2. **web-visitor-configmap.yaml** - ConfigMap 资源，存储 nginx 配置
3. **web-visitor-deployment.yaml** - 更新后的 Deployment，挂载 ConfigMap
4. **web-visitor-ingress.yaml** - 更新后的 Ingress，添加子域名规则

### 部署脚本
1. **deploy-web-visitor.bat** - Windows 批处理脚本
2. **deploy-web-visitor.sh** - Linux/Mac Shell 脚本

## 部署步骤

### 方法一：使用部署脚本（推荐）

#### Windows
```bash
deploy-web-visitor.bat
```

#### Linux/Mac
```bash
chmod +x deploy-web-visitor.sh
./deploy-web-visitor.sh
```

### 方法二：手动部署

```bash
# 1. 创建 ConfigMap
kubectl apply -f web-visitor-configmap.yaml

# 2. 更新 Deployment
kubectl apply -f web-visitor-deployment.yaml

# 3. 更新 Ingress
kubectl apply -f web-visitor-ingress.yaml

# 4. 等待部署完成
kubectl rollout status deployment/web-visitor
```

## 访问地址

部署完成后，可以通过以下地址访问：

- **主域名**: https://sbtlphdeilvf.sealosbja.site/ (显示默认 nginx 页面)
- **Ragflow**: https://ragflow.sbtlphdeilvf.sealosbja.site/ (访问 ragflow01 服务)

## 配置说明

### Nginx 配置
- 默认服务器：处理主域名 `sbtlphdeilvf.sealosbja.site`
- 子域名服务器：处理 `ragflow.sbtlphdeilvf.sealosbja.site`，代理到 `ragflow01:80`

### Ingress 配置
- 添加了子域名 `ragflow.sbtlphdeilvf.sealosbja.site` 规则
- TLS 证书包含两个域名
- 两个域名都指向同一个 web-visitor 服务

## 故障排查

### 检查 Pod 状态
```bash
kubectl get pods -l app=web-visitor
kubectl logs -l app=web-visitor
```

### 检查 Ingress 状态
```bash
kubectl get ingress
kubectl describe ingress network-ehcnmaovftal
```

### 检查 ConfigMap
```bash
kubectl get configmap web-visitor-nginx-config
kubectl describe configmap web-visitor-nginx-config
```

### 测试 nginx 配置
```bash
kubectl exec -it $(kubectl get pod -l app=web-visitor -o jsonpath='{.items[0].metadata.name}') -- nginx -t
```

## 回滚操作

如果需要回滚到原始配置：

```bash
# 回滚 Deployment
kubectl rollout undo deployment/web-visitor

# 恢复原始 Ingress（需要手动编辑或使用备份）
kubectl delete ingress network-ehcnmaovftal
# 然后重新应用原始 Ingress 配置
```
