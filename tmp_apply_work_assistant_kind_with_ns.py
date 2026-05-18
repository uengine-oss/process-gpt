import paramiko
from pathlib import Path

HOST = "ai-server.dream-flow.com"
PORT = 50022
USER = "ungine"
PASSWORD = "dbdpswls123!"
CTX = "kind-process-gpt-0402"

deploy_yaml = Path(r"C:\Users\user\Desktop\process-gpt-k8s\deployments\work-assistant-agent-deployment.yaml").read_text(encoding="utf-8")
svc_yaml = Path(r"C:\Users\user\Desktop\process-gpt-k8s\services\work-assistant-agent-service.yaml").read_text(encoding="utf-8")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=20)

commands = [
    f"kubectl --context {CTX} create ns dev --dry-run=client -o yaml | kubectl --context {CTX} apply -f -",
]

for cmd in commands:
    print(f"\n===== {cmd} =====")
    _, so, se = ssh.exec_command(cmd, timeout=120)
    print(so.read().decode("utf-8", errors="ignore"))
    print(se.read().decode("utf-8", errors="ignore"))

# apply deployment via stdin
cmd_apply_dep = f"kubectl --context {CTX} apply -f -"
print(f"\n===== {cmd_apply_dep} (deployment) =====")
stdin, so, se = ssh.exec_command(cmd_apply_dep, timeout=180)
stdin.write(deploy_yaml)
stdin.channel.shutdown_write()
print(so.read().decode("utf-8", errors="ignore"))
print(se.read().decode("utf-8", errors="ignore"))

# apply service in dev via stdin
cmd_apply_svc = f"kubectl --context {CTX} apply -n dev -f -"
print(f"\n===== {cmd_apply_svc} (service) =====")
stdin2, so2, se2 = ssh.exec_command(cmd_apply_svc, timeout=180)
stdin2.write(svc_yaml)
stdin2.channel.shutdown_write()
print(so2.read().decode("utf-8", errors="ignore"))
print(se2.read().decode("utf-8", errors="ignore"))

checks = [
    f"kubectl --context {CTX} get deploy work-assistant-agent -n dev -o wide",
    f"kubectl --context {CTX} get pods -n dev -l app=work-assistant-agent -o wide",
    f"kubectl --context {CTX} get svc work-assistant-agent-service -n dev -o wide",
    f"kubectl --context {CTX} get endpoints work-assistant-agent-service -n dev",
    f"kubectl --context {CTX} get deploy work-assistant-agent -n dev -o jsonpath='{{.spec.template.spec.containers[0].image}}'",
]
for c in checks:
    print(f"\n===== {c} =====")
    _, so3, se3 = ssh.exec_command(c, timeout=120)
    print(so3.read().decode("utf-8", errors="ignore"))
    print(se3.read().decode("utf-8", errors="ignore"))

ssh.close()
