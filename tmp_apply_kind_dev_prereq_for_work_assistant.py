from pathlib import Path
import paramiko

HOST = "ai-server.dream-flow.com"
PORT = 50022
USER = "ungine"
PASSWORD = "dbdpswls123!"
CTX = "kind-process-gpt-0402"

files = [
    r"C:\Users\user\Desktop\process-gpt-k8s\secrets\anthropic-secret.from-gke.yaml",
    r"C:\Users\user\Desktop\process-gpt-k8s\secrets\my-config.from-gke.yaml",
    r"C:\Users\user\Desktop\process-gpt-k8s\secrets\my-secrets.from-gke.yaml",
]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=20)

for file_path in files:
    yaml_text = Path(file_path).read_text(encoding="utf-8")
    cmd = f"kubectl --context {CTX} apply -f -"
    print(f"\n===== apply {Path(file_path).name} =====")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=180)
    stdin.write(yaml_text)
    stdin.channel.shutdown_write()
    print(stdout.read().decode("utf-8", errors="ignore"))
    print(stderr.read().decode("utf-8", errors="ignore"))

checks = [
    f"kubectl --context {CTX} get cm my-config -n dev -o name",
    f"kubectl --context {CTX} get secret my-secrets -n dev -o name",
    f"kubectl --context {CTX} get secret anthropic-secret -n dev -o name",
    f"kubectl --context {CTX} rollout restart deploy/work-assistant-agent -n dev",
    f"kubectl --context {CTX} rollout status deploy/work-assistant-agent -n dev --timeout=180s",
    f"kubectl --context {CTX} get pods -n dev -l app=work-assistant-agent -o wide",
    f"kubectl --context {CTX} get endpoints work-assistant-agent-service -n dev",
]

for cmd in checks:
    print(f"\n===== {cmd} =====")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=240)
    print(stdout.read().decode("utf-8", errors="ignore"))
    print(stderr.read().decode("utf-8", errors="ignore"))

ssh.close()
