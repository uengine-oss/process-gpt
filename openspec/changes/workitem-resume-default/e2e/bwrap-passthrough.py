#!/usr/bin/python3
"""e2e 전용 bwrap 대역 — 네임스페이스·마운트 격리 없이 명령만 실행한다.

이 개발 머신(arm64 VM + Rosetta 로 도는 amd64 codex 이미지)에서는 bubblewrap 0.12 가
새 마운트 API 를 쓰지 못해 "Can't open source /: Function not implemented" 로 모든 셸 명령이
실패한다(2026-09-16 기록과 같은 한계). codex 의 셸 샌드박스 정책은 코드에 고정돼 있으므로,
e2e 이미지에서만 bwrap 을 이 대역으로 바꿔 재개 경로를 검증한다. 운영 이미지에는 넣지 않는다.
`--help`/`--version`(codex 의 기능 확인)은 진짜 bwrap 에 넘긴다.
"""
import os
import sys

args = sys.argv[1:]
if args and args[0] in ("--help", "--version"):
    os.execv("/usr/bin/bwrap.real", ["bwrap", *args])

TWO = {"--ro-bind", "--bind", "--dev-bind", "--ro-bind-try", "--bind-try", "--dev-bind-try", "--symlink",
       "--chmod", "--file", "--bind-data", "--ro-bind-data", "--setenv"}
ONE = {"--tmpfs", "--dev", "--proc", "--dir", "--remount-ro", "--argv0", "--chdir", "--unsetenv", "--cap-drop",
       "--cap-add", "--uid", "--gid", "--hostname", "--seccomp", "--add-seccomp-fd", "--info-fd", "--json-status-fd",
       "--block-fd", "--userns-block-fd", "--sync-fd", "--lock-file", "--exec-label", "--file-label", "--perms",
       "--size", "--userns", "--userns2", "--pidns", "--mqueue"}
argv0 = chdir = None
i = 0
while i < len(args):
    t = args[i]
    if t == "--":
        i += 1
        break
    if t == "--argv0":
        argv0 = args[i + 1]
    elif t == "--chdir":
        chdir = args[i + 1]
    elif t == "--setenv":
        os.environ[args[i + 1]] = args[i + 2]
    elif t == "--unsetenv":
        os.environ.pop(args[i + 1], None)
    i += 3 if t in TWO else 2 if t in ONE else 1
cmd = args[i:]
# codex 는 bwrap 안에서 자기 바이너리를 seccomp helper 로 다시 실행한다
#   <codex> --sandbox-policy-cwd D --command-cwd D --permission-profile P --apply-seccomp-then-exec -- <명령>
# 이 helper 도 같은 이유로 이 머신에서 돌지 않으므로 건너뛰고 <명령> 을 바로 실행한다.
if "--apply-seccomp-then-exec" in cmd:
    j = cmd.index("--apply-seccomp-then-exec")
    if "--command-cwd" in cmd[:j]:
        chdir = cmd[cmd.index("--command-cwd") + 1]
    rest = cmd[j + 1:]
    cmd = rest[1:] if rest[:1] == ["--"] else rest
    argv0 = None
if chdir:
    os.chdir(chdir)
os.execvp(cmd[0], [argv0 or cmd[0], *cmd[1:]])
