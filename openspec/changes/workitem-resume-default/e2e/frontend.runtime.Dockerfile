# vue3 저장소 Dockerfile 의 실행 스테이지와 같다. 빌드 스테이지의 npm ci 는 저장소의
# package-lock.json 이 package.json 과 어긋나 실패하므로(2026-10-07 기준 커밋 상태),
# 호스트에서 이미 설치된 node_modules 로 만든 dist(.frontend-dist)를 넣는다(build-images.sh frontend).
# run.sh 는 vue3 저장소의 것을 빌드 컨텍스트(vue3)에서 그대로 가져온다.
FROM sanghoon01/spa-http-server:v1
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
COPY .frontend-dist /opt/www-dist
COPY --from=vue3 run.sh /opt/run.sh
RUN sed -i 's/\r$//' /opt/run.sh && mkdir -p /opt/www && chown -R 1000:1000 /opt/www
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["sh","/opt/run.sh"]
