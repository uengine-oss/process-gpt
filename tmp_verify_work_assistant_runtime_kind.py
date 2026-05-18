import paramiko

HOST = "ai-server.dream-flow.com"
PORT = 50022
USER = "ungine"
PASSWORD = "dbdpswls123!"
CTX = "kind-process-gpt-0402"

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=20)

commands = [
    f"kubectl --context {CTX} exec -n dev deploy/work-assistant-agent -- sh -lc \"printenv | grep -E 'MODEL_PROVIDER|MODEL_NAME|LLM_MODEL|LLM_PROXY_URL|LLM_PROXY_API_KEY|OPENAI_API_KEY|OPENAI_BASE_URL|OPENAI_MODEL'\"",
    f"kubectl --context {CTX} run -n dev tmp-curl-wa --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- curl -sS http://work-assistant-agent-service:8000/health",
]

for cmd in commands:
    print(f"\n===== {cmd} =====")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=240)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    if out:
        print(out)
    if err:
        print(err)

ssh.close()
