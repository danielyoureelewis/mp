#!/bin/bash

ACTION=$1
VM_NAME=$2

if [ -z "$ACTION" ] || [ -z "$VM_NAME" ]; then
    echo "Usage:"
    echo "  mp create [vmname]"
    echo "  mp destroy [vmname]"
    echo "  mp cp [vmname] [file_in_vm] [destination_on_mac]"
    exit 1
fi

KEY_PATH="$HOME/.ssh/multipass_ed25519"
CLOUD_INIT="/tmp/${VM_NAME}_cloud_init.yaml"
SSH_CONFIG="$HOME/.ssh/config"

VM_API_BASE="${OPENAI_API_BASE:-http://127.0.0.1:4000/v1}"
VM_API_KEY="${OPENAI_API_KEY:-sk-placeholder-key}"

if [ "$ACTION" == "create" ]; then
    echo "[*] Initializing Harness Research VM: $VM_NAME..."

    if [ ! -f "$KEY_PATH" ]; then
        echo "[*] Generating ed25519 key..."
        ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
    fi
    PUB_KEY=$(cat "${KEY_PATH}.pub")

    cat <<EOF > "$CLOUD_INIT"
groups:
  - vscode
users:
  - name: ubuntu
    groups: [vscode, docker]
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - $PUB_KEY

write_files:
  - path: /home/ubuntu/.bashrc
    append: true
    content: |
      export OPENAI_API_BASE="$VM_API_BASE"
      export OPENAI_API_KEY="$VM_API_KEY"
      export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$PATH"

  - path: /home/ubuntu/README.md
    permissions: "0644"
    content: |
      # Research Harness
      
      Welcome to the ephemeral analysis environment.
      
      ## 1. Directory Structure
      - \`~/workspace/\`: The shared boundary. Files here are visible to both the host (OpenCode) and the Kali container.
      - \`~/workspace/justfile\`: The operational interface bridging the host and the container.
      
      ## 2. Manual Tool Execution
      **NEVER** drop into the Kali container shell manually. Run all reverse engineering tools from this host terminal via the bridge:
      \`\`\`bash
      cd ~/workspace
      just kali binwalk target.bin
      just kali r2 -A target.bin
      \`\`\`
      
      ## 3. Automated Agent Execution
      Launch OpenCode from the workspace and anchor it to the guardrails:
      \`\`\`bash
      cd ~/workspace
      opencode "Read AGENTS.md. Our objective is to analyze target.bin. ONLY use 'just kali' to run tools."
      \`\`\`
      
      ## 4. Data Extraction
      To retrieve evidence and logs, run this on your Mac host terminal (do not use scp):
      \`\`\`bash
      mp cp $VM_NAME /home/ubuntu/workspace/research/threads/thr-001/index.md ./
      \`\`\`

  - path: /home/ubuntu/workspace/AGENTS.md
    permissions: "0644"
    content: |
      # Research Harness Protocol
      - You are operating on an Ubuntu host. The security tools (radare2, binwalk, gdb) are inside an isolated Kali container.
      - NEVER use \`docker exec\` directly. ALWAYS use the \`just kali\` command from the justfile to run tools.
      - Write all findings to \`research/threads/\`.
      - Filter output using \`jq\` or \`grep\` before reading it into context.

  - path: /home/ubuntu/workspace/justfile
    permissions: "0644"
    content: |
      default:
          @just --list

      lab-up:
          #!/usr/bin/env bash
          if ! docker ps -a | grep -q "kali-workspace"; then
              echo "[*] Initializing Kali container with core RE tools..."
              docker run --name kali-workspace -itd -v /home/ubuntu/workspace:/workspace kalilinux/kali-rolling /bin/bash
              docker exec kali-workspace apt update
              docker exec kali-workspace env DEBIAN_FRONTEND=noninteractive apt install -y radare2 binwalk yara gdb strace python3-pwntools nmap netcat-traditional
          else
              docker start kali-workspace
          fi
          echo "[*] Kali container is running."

      kali +ARGS:
          @docker exec -w /workspace kali-workspace {{ARGS}}

      lab-status:
          @docker ps | grep kali-workspace || echo "Kali container is OFFLINE"

  - path: /home/ubuntu/workspace/record
    permissions: "0755"
    content: |
      #!/bin/bash
      TOOL="\$1"
      shift
      CMD="\$*"
      START=\$(date +%s%3N)
      eval "\$CMD"
      STATUS=\$?
      END=\$(date +%s%3N)
      DUR=\$((END - START))
      jq -nc --arg ts "\$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --arg tool "\$TOOL" --arg cmd "\$CMD" --argjson dur "\$DUR" --argjson exit "\$STATUS" '{timestamp: \$ts, tool: \$tool, command: \$cmd, duration_ms: \$dur, exit_code: \$exit}' >> /home/ubuntu/workspace/ledger.jsonl
      exit \$STATUS

packages:
  - docker.io
  - just
  - jq
  - curl
  - ripgrep

runcmd:
  - systemctl enable --now docker
  - usermod -aG docker ubuntu
  
  - mkdir -p /home/ubuntu/workspace/research/threads/thr-001/evidence
  - mkdir -p /home/ubuntu/workspace/skills
  - touch /home/ubuntu/workspace/ledger.jsonl
  
  - chown -R ubuntu:ubuntu /home/ubuntu
  
  - su - ubuntu -c 'curl -fsSL https://opencode.ai/install | bash'
  - ln -s /home/ubuntu/.opencode/bin/opencode /usr/local/bin/opencode
EOF

    if ! multipass launch --name "$VM_NAME" --cpus 4 --memory 8G --disk 15G --cloud-init "$CLOUD_INIT"; then
        echo "[-] ERROR: VM launch failed. Aborting."
        rm -f "$CLOUD_INIT"
        exit 1
    fi

    VM_IP=$(multipass info "$VM_NAME" | grep IPv4 | awk '{print $2}')
    if [ -z "$VM_IP" ]; then
        echo "[-] ERROR: Could not retrieve IP."
        exit 1
    fi

    sed -i '' "/^Host $VM_NAME$/,/^$/d" "$SSH_CONFIG" 2>/dev/null

    cat <<EOF >> "$SSH_CONFIG"
Host $VM_NAME
    HostName $VM_IP
    User ubuntu
    IdentityFile $KEY_PATH
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

EOF

    echo "====================================================="
    echo "✅ Harness VM '$VM_NAME' Setup Complete!"
    echo "🔗 To connect via SSH, simply run:"
    echo "   ssh $VM_NAME"
    echo "====================================================="

elif [ "$ACTION" == "destroy" ]; then
    echo "[*] Tearing down VM: $VM_NAME..."
    if multipass info "$VM_NAME" &>/dev/null; then
        multipass delete "$VM_NAME"
        multipass purge
    fi
    rm -f "$CLOUD_INIT"
    sed -i '' "/^Host $VM_NAME$/,/^$/d" "$SSH_CONFIG" 2>/dev/null
    echo "🗑️  Environment '$VM_NAME' destroyed."

elif [ "$ACTION" == "cp" ]; then
    SOURCE="$3"
    DEST="$4"
    if [ -z "$SOURCE" ] || [ -z "$DEST" ]; then
        echo "Usage: mp cp [vmname] [vm_path] [mac_destination]"
        exit 1
    fi
    multipass transfer "$VM_NAME:$SOURCE" "$DEST"
    echo "✅ Transferred to $DEST"
else
    echo "Usage: mp [create|destroy|cp] [vmname]"
    exit 1
fi
