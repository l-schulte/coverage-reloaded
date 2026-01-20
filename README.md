# Code Coverage Tool for Causal Coverage in JavaScript/TypeScript Projects

This repository contains scripts and tools to calculate the code coverage of JavaScript/TypeScript projects throughout the history of their development.

## Quick Start

How to run the collection:

1. Clone the WayPack Machine repository:

   ```bash
   git clone https://codeberg.org/l-schulte/waypack-machine.git
   ```

2. Start the docker containers of the WayPack Machine (includes Verdaccio):

   ```bash
   cd waypack-machine
   docker-compose up -d
   ```

3. Install Python dependencies:

   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

4. Run the coverage collection script:

   For a specific project, use the following command, replacing `<project_name>` with the desired project name (see `config.json`):

   ```bash
   python execute.py --max-workers 10 --project <project_name>
   ``` 

   For all projects, omit the `--project` argument:

   ```bash
   python execute.py --max-workers 10
   ```

   Choose an appropriate number for `--max-workers` based on your system's capabilities.
   To limit the number of commits processed, use the `--max-commits` argument.


## Collecting Commits

Collecting commits creates the projects `commits.csv` files. It applies strategies to automatically select relevant node versions for each commit as well as for finding the correct package manager.

The repository already contains the `commits.csv` files for all projects. 

Run this per-project to (re)generate `commits.csv` files:

```bash
python collect_commits.py --project <project_name>
```

or for all projects defined in `config.json`:

```bash
python collect_commits.py
```

## Debugging Coverage Collection

Running the coverage collection for a projects creates `.log` and `.error` files. The first line of those files provides a convinient way to re-run the specific commits collection for debugging purposes.

Example:

```bash
Script called as: /home/user/VCS/causal_coverage/docker-run.sh condo exec 6ba1d41d7a96c5de4ca8f66a26e956c08476c68e 1629283212 npm 14
```

The `docker-run.sh` script can be executed with the following commands:

- `exec`: default, runs the coverage collection for the specified commit
- `shell`: initiates the container and opens a bash shell for manual debugging. In the container there are the following options:
    - Environment variables are set in the container for `revision`, `timestamp`, and `package_manager`. Further environment variables may be set by the `execute.py` script.
    - `bash execute.sh`: checks out the specified commit and runs the full coverage collection
    - `bash install-and-run.sh`: only runs the installation and coverage collection (no commit checkout, no extra environment variables set)
    - `repo`: folder containing the cloned project repository
    - `coverage`: folder where coverage results are stored
- `debug`: DEPRECATED - mounts the code volume... 