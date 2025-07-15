FROM node:18-alpine AS editor_build
WORKDIR /app
COPY ./blossom-editor .
RUN npm ci
RUN npm run build

FROM node:18-alpine AS web_build
WORKDIR /app
COPY ./blossom-web .
RUN npm ci
RUN npm run build

# 第一阶段：编译构建Java项目
FROM maven:3.8.8-eclipse-temurin-8-alpine AS build
WORKDIR /build

# 复制项目源码到容器，假定在 blossom-backend 下有 pom.xml
COPY ./blossom-backend .
RUN mvn install
RUN mvn clean package

# 第二阶段：提取 Spring Boot layers
FROM eclipse-temurin:8-jre-alpine as builder
WORKDIR application
# 复制 jar 包（假设 blossom-backend/target 下生成 jar）
COPY --from=build /build/backend/target/backend-blossom.jar application.jar
RUN java -Djarmode=layertools -jar application.jar extract

FROM eclipse-temurin:8-jre-alpine
MAINTAINER li-guohao <git@liguohao.cn>
WORKDIR application
COPY --from=builder application/dependencies/ ./
COPY --from=builder application/spring-boot-loader/ ./
COPY --from=builder application/snapshot-dependencies/ ./
COPY --from=builder application/application/ ./

COPY --from=editor_build /app/out/renderer ./BOOT-INF/classes/static/editor/
COPY --from=web_build /app/dist ./BOOT-INF/classes/static/blog/

ENV JVM_OPTS="-Xmx256m -Xms256m" \
    BLOSSOM_WORK_DIR="/home/bl" \
    SPRING_CONFIG_LOCATION="optional:classpath:/;optional:classpath:/config/;optional:file:/home/bl/" \
    TZ=Asia/Shanghai

RUN ln -sf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

EXPOSE 9999

ENTRYPOINT ["sh", "-c", "java ${JVM_OPTS} org.springframework.boot.loader.JarLauncher ${0} ${@}"]
