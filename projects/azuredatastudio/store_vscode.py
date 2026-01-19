import os


def store_vscode():
    timestamp = os.getenv("timestamp")
    if not timestamp:
        raise ValueError("Environment variable 'timestamp' must be set.")

    logs_dir = "/app/data/logs"
    os.makedirs(logs_dir, exist_ok=True)

    for dirname in os.listdir(".vscode-test"):
        if dirname.startswith("vscode-"):
            src = os.path.join(".vscode-test", dirname)
            dst = os.path.join("/app/data", dirname)

            if not os.path.exists(dst):
                log_file = os.path.join(logs_dir, f"{timestamp}.txt")
                with open(log_file, "w") as f:
                    f.write(dirname)
                os.system(f"cp -r {src} {dst}")
                print(f"Stored folder: {dirname} with timestamp: {timestamp}")


store_vscode()
