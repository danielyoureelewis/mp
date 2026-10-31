# OpenCode RE Harness

An ephemeral environment for automated reverse engineering. This architecture strictly separates an LLM agent (running on an Ubuntu host VM) from security tools (running inside a Kali Linux Docker container). 

## 1. Architecture & Boundaries
* **`~/workspace/`**: The shared analysis boundary. Files placed in this directory on the Ubuntu VM are instantly accessible to the isolated Kali container.
* **`justfile`**: The execution bridge. All commands routed through this file execute out-of-band inside Kali.
* **`ledger.jsonl`**: The telemetry log. Records the timestamp, tool, command, and execution duration for every bridged action.

## 2. Installation & Configuration (Mac Host)

**Step A: Install the Multipass Wrapper**
Create the `mp` executable in your local binaries path to handle provisioning and data extraction:
```bash
sudo nano /usr/local/bin/mp
sudo chmod +x /usr/local/bin/mp
```

**Step B: Export API Credentials**
The script injects your AI proxy credentials into the VM at runtime. Add these to your Mac's `~/.zshrc` (configured for your local LiteLLM proxy):
```bash
export OPENAI_API_BASE="[http://10.1.1.163:4000/v1](http://10.1.1.163:4000/v1)"
export OPENAI_API_KEY="sk-local-ai-key"
```
Reload your profile: `source ~/.zshrc`

## 3. Deployment & Verification

**Deploy a Harness:**
Run the wrapper from your terminal. The script will provision the VM, inject your credentials, build the workspace, and automatically spin up the Kali detonation zone in the background.
```bash
mp create hax
```

**Verify the Environment:**
SSH into the machine and check the container status:
```bash
ssh hax
cd ~/workspace
just lab-status
```
*Verification:* The output displays the active `kali-workspace` Docker container. Run `just kali ls` to verify the container can read the shared workspace.

## 4. Manual Operation

**NEVER** attach a shell directly to the Kali container (`docker exec -it kali /bin/bash`). Interactive shells evade telemetry and desynchronize the agent's state. 

Execute all tools from the Ubuntu VM terminal using the bridge:
```bash
cd ~/workspace
just kali binwalk target.bin
just kali r2 -A target.bin
```
*Verification:* Check `ledger.jsonl` after execution; you should see your exact commands and their execution durations recorded as JSON objects.

## 5. Agent Operation (OpenCode)

Because Node.js CLIs can fail on long, multi-line string arguments, always use the **Task File Pattern** to instruct OpenCode.

**Step A: Create a task file (`task.txt`):**
```text
Read AGENTS.md. Our objective is to perform static analysis on 'target.bin'.
Rules:
1. ONLY use 'just kali <command>' to execute tools.
2. Run 'just kali rabin2 -i target.bin' to extract imports.
3. Write the exact commands used and raw outputs to research/threads/thr-001/evidence/E-001.md.
```

**Step B: Launch the agent:**
```bash
cd ~/workspace
opencode "Follow the exact instructions in task.txt"
```

## 6. Extracting Evidence

Because this environment is stateless, you must pull your research artifacts out before destroying the VM (`mp destroy hax`). Use the wrapper script to securely extract files without setting up persistent mounts.

Run this from your **Mac terminal**:
```bash
# Syntax: mp cp [vm_name] [path_in_vm] [local_mac_path]
mp cp hax /home/ubuntu/workspace/research/threads/thr-001/evidence/E-001.md ./
mp cp hax /home/ubuntu/workspace/ledger.jsonl ./
```
*Verification:* The files will appear in your Mac's current working directory, untouched by any container escape risks.
