# e2e 전용: arm64 VM + Rosetta 에서 bubblewrap 이 돌지 않으므로 bwrap 을 격리 없는 대역으로 바꾼다.
# (bwrap-passthrough.py 참고) 운영 이미지에는 쓰지 않는다.
FROM pgpt-e2e/codex:e2e
USER root
RUN mv /usr/bin/bwrap /usr/bin/bwrap.real
COPY bwrap-passthrough.py /usr/bin/bwrap
RUN chmod 0755 /usr/bin/bwrap
