@echo off
echo ========================================
echo 部署 web-visitor 配置以支持子域访问 ragflow01
echo ========================================
echo.

echo [1/4] 创建 ConfigMap...
kubectl apply -f web-visitor-configmap.yaml
if %errorlevel% neq 0 (
    echo 创建 ConfigMap 失败
    pause
    exit /b 1
)
echo ConfigMap 创建成功
echo.

echo [2/4] 更新 web-visitor Deployment...
kubectl apply -f web-visitor-deployment.yaml
if %errorlevel% neq 0 (
    echo 更新 Deployment 失败
    pause
    exit /b 1
)
echo Deployment 更新成功
echo.

echo [3/4] 更新 Ingress 配置...
kubectl apply -f web-visitor-ingress.yaml
if %errorlevel% neq 0 (
    echo 更新 Ingress 失败
    pause
    exit /b 1
)
echo Ingress 更新成功
echo.

echo [4/4] 等待 Pod 重新部署...
kubectl rollout status deployment/web-visitor
if %errorlevel% neq 0 (
    echo 等待部署完成失败
    pause
    exit /b 1
)
echo 部署完成
echo.

echo ========================================
echo 部署成功！
echo 现在可以通过以下地址访问：
echo - 主域名: https://sbtlphdeilvf.sealosbja.site/
echo - ragflow: https://ragflow.sbtlphdeilvf.sealosbja.site/
echo ========================================
pause
