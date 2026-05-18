import paramiko

HOST = "ai-server.dream-flow.com"
PORT = 50022
USER = "ungine"
PASSWORD = "dbdpswls123!"

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=15)

commands = [
    "kubectl config get-contexts",
    "kubectl config current-context",
    "kubectl --context kind-process-gpt-0402 get deploy -A | grep -i work-assistant || true",
    "kubectl --context kind-process-gpt-0402 get svc -A | grep -i work-assistant || true",
    "kubectl --context kind-process-gpt-0402 get pods -A | grep -i work-assistant || true",
    "kubectl --context kind-process-gpt-0402 get deploy -n dev | sed -n '1,200p'",
]

for cmd in commands:
    print(f"\n===== {cmd} =====")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=120)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    if out:
        print(out)
    if err:
        print(err)

ssh.close()
