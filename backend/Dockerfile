# 后端运行镜像：直接使用本地已经打好的 jar，服务器上不需要 Maven
FROM eclipse-temurin:17-jre

WORKDIR /app
COPY target/campus-ledger-backend-1.0.0.jar app.jar

ENV TZ=Asia/Shanghai
EXPOSE 8080

ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "/app/app.jar"]
