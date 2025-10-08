# Backup Sender

**Tunnel + Encryption + A Secret Touch — Security Beyond Imagination.**

**Backup Sender** is a compact Bash utility that encrypts files/folders, stores per-run keys locally, and delivers the encrypted artifact to a Telegram chat. It optionally uses a temporary local tunnel for the Telegram upload flow. Built for simplicity, auditability, and fast red-team-style workflows.

## Features

- **Three encryption options**
  - `gpg` (AES-256 symmetric) — *recommended*
  - `openssl` (AES-256-GCM)
  - `openssl` (AES-256-CBC + PBKDF2)

- **Automatic key management**
  - Per-run key files saved under `keys/`
  - Operation metadata appended to `keys.log`

- **Telegram delivery**
  - Upload encrypted artifact to a Telegram chat using `BOT_TOKEN` & `CHAT_ID`

- **Optional temporary tunnel**
  - Creates a short-lived `socat` TCP tunnel to `api.telegram.org` and tears it down after sending

- **Basic TUI**
  - Simple colored ASCII UI (uses `figlet` if available) for a more pleasant CLI experience

- **Encrypt directories**
  - Directories are tarred before encryption


## Installation

```bash
git clone https://github.com/mhmoudjma/Backup_Sender
cd Backup_Sender
chmod +x backup_sender.sh
./backup_sender.sh
```

## Configuration

Create a `token.env` file in the project root :
```
BOT_TOKEN="123456789:XXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
CHAT_ID="123456789"
```

The script expects token.env in the same directory and will exit with an error if it is missing or incomplete.


## Requirements

•**bash** (POSIX-compatible shell)

•**gpg** (for GPG symmetric encryption)

•**openssl** (for AES-GCM / AES-CBC)

•**curl** (to call Telegram API)

•**socat**(optional — required only if you want the temporary tunnel feature)

•**figlet** (optional — for ASCII heading)

If some tools are missing, the script falls back to sensible behavior where possible (for example it will still use openssl if gpg is unavailable, depending on user choice).

🧠 Behind the Scenes

`Backup Sender` wasn't written as an ordinary tool; it was crafted as a thought experiment — an exploration of how simplicity can protect complexity.  
Behind every `tar` and `curl` command lies a small question: how do we make security a habit, not a burden?


## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)** — see the [LICENSE](LICENSE) file for details.  

The GPLv3 license ensures that this software and any derivatives remain free and open source. You are free to use, modify, and distribute it under the same license terms, but you must include attribution and keep the same licensing for derivative works.
