#!/usr/bin/env bash
# 게이트웨이를 http://localhost:18088 로. 파드가 바뀌어 끊기면 다시 붙는다.
# 호스트 이름이 localhost 라야 화면이 테넌트 localhost 로 동작한다.
while true; do kubectl --context kind-kind -n resume-e2e port-forward svc/gateway 18088:8088; sleep 1; done
