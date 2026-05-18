import time
import paramiko

HOST = "ai-server.dream-flow.com"
PORT = 50022
USER = "ungine"
PASSWORD = "dbdpswls123!"
CTX = "kind-process-gpt-0402"

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=20)

time.sleep(12)

commands = [
    f"kubectl --context {CTX} get pods -n dev -l app=work-assistant-agent -o wide",
    f"kubectl --context {CTX} get endpoints work-assistant-agent-service -n dev",
    f"kubectl --context {CTX} get deploy work-assistant-agent -n dev -o jsonpath='{{range .spec.template.spec.containers[0].env[*]}}{{.name}}={{.value}}{{\"\\n\"}}{{end}}'",
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
