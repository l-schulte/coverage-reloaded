import os


def restore_vscode_folder():
    current_timestamp = os.getenv("timestamp")
    if not current_timestamp:
        raise ValueError("Environment variable 'timestamp' must be set.")

    logs_dir = "/app/data/logs"
    if not os.path.exists(logs_dir):
        raise FileNotFoundError(f"Logs directory {logs_dir} does not exist.")

    # Get all log files and sort by timestamp
    log_files = [f for f in os.listdir(logs_dir) if f.endswith(".txt")]
    timestamps = sorted([int(f.split(".")[0]) for f in log_files])

    # Find closest previous and next timestamps
    prev_ts = next_ts = None
    for ts in timestamps:
        if ts <= int(current_timestamp):
            prev_ts = ts
        else:
            if next_ts is None or ts < next_ts:
                next_ts = ts

    os.makedirs("/app/repo/.vscode-test", exist_ok=True)

    # Restore closest previous version
    if prev_ts is not None:
        with open(os.path.join(logs_dir, f"{prev_ts}.txt"), "r") as f:
            foldername = f.read().strip()
        src = os.path.join("/app/data", foldername)
        dst = os.path.join("/app/repo/.vscode-test", f"{foldername}")
        if os.path.exists(src):
            os.system(f"cp -r {src} {dst}")
            print(
                f"Restored previous vscode version: {foldername} (timestamp: {prev_ts})"
            )
        else:
            print(f"Warning: Previous vscode folder {src} does not exist.")

    # Restore closest next version
    if next_ts is not None:
        with open(os.path.join(logs_dir, f"{next_ts}.txt"), "r") as f:
            foldername = f.read().strip()
        src = os.path.join("/app/data", foldername)
        dst = os.path.join("/app/repo/.vscode-test", f"{foldername}")
        if os.path.exists(src):
            os.system(f"cp -r {src} {dst}")
            print(f"Restored next vscode version: {foldername} (timestamp: {next_ts})")
        else:
            print(f"Warning: Next vscode folder {src} does not exist.")

    if prev_ts is None and next_ts is None:
        raise ValueError("No matching versions found in logs.")


restore_vscode_folder()
