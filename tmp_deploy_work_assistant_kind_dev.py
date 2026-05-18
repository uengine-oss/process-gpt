import posixpath
from pathlib import Path

import paramiko

HOST = "ai-server.dream-flow.com"
PORT = 50022
USER = "ungine"
PASSWORD = "dbdpswls123!"

LOCAL_ROOT = Path(r"C:\Users\user\Desktop\process-gpt-k8s")
REMOTE_ROOT = "/home/ungine/process-gpt-k8s"

files = [
    "deployments/work-assistant-agent-deployment.yaml",
    "services/work-assistant-agent-service.yaml",
]

transport = paramiko.Transport((HOST, PORT))
transport.connect(username=USER, password=PASSWORD)
sftp = paramiko.SFTPClient.from_transport(transport)
for rel in files:
    sftp.put(str(LOCAL_ROOT / rel), posixpath.join(REMOTE_ROOT, rel))
sftp.close()
transport.close()

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=15)

commands = [
    "kubectl --context kind-process-gpt-0402 apply -f /home/ungine/process-gpt-k8s/deployments/work-assistant-agent-deployment.yaml",
    "kubectl --context kind-process-gpt-0402 apply -n dev -f /home/ungine/process-gpt-k8s/services/work-assistant-agent-service.yaml",
    "kubectl --context kind-process-gpt-0402 get deploy work-assistant-agent -n dev -o wide",
    "kubectl --context kind-process-gpt-0402 get pods -n dev -l app=work-assistant-agent -o wide",
    "kubectl --context kind-process-gpt-0402 get svc work-assistant-agent-service -n dev -o wide",
    "kubectl --context kind-process-gpt-0402 get endpoints work-assistant-agent-service -n dev",
    "kubectl --context kind-process-gpt-0402 get deploy work-assistant-agent -n dev -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}{.spec.template.spec.containers[0].env}'",
]

for cmd in commands:
    print(f"\n===== {cmd} =====")
    _, so, se = ssh.exec_command(cmd, timeout=180)
    out = so.read().decode("utf-8", errors="ignore")
    err = se.read().decode("utf-8", errors="ignore")
    if out:
        print(out)
    if err:
        print(err)

ssh.close()
