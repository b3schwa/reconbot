#!/bin/bash

echo -e "    ▄████████    ▄████████  ▄████████  ▄██████▄  ███▄▄▄▄   ▀█████████▄   ▄██████▄      ███     "
echo -e "  ███    ███   ███    ███ ███    ███ ███    ███ ███▀▀▀██▄   ███    ███ ███    ███ ▀█████████▄ "
echo -e "  ███    ███   ███    █▀  ███    █▀  ███    ███ ███   ███   ███    ███ ███    ███    ▀███▀▀██ "
echo -e " ▄███▄▄▄▄██▀  ▄███▄▄▄     ███        ███    ███ ███   ███  ▄███▄▄▄██▀  ███    ███     ███   ▀ "
echo -e "▀▀███▀▀▀▀▀   ▀▀███▀▀▀     ███        ███    ███ ███   ███ ▀▀███▀▀▀██▄  ███    ███     ███     "
echo -e "▀███████████   ███    █▄  ███    █▄  ███    ███ ███   ███   ███    ██▄ ███    ███     ███     "
echo -e "  ███    ███   ███    ███ ███    ███ ███    ███ ███   ███   ███    ███ ███    ███     ███     "
echo -e "  ███    ███   ██████████ ████████▀   ▀██████▀   ▀█   █▀  ▄█████████▀   ▀██████▀     ▄████▀   "
echo -e "  ███    ███                                                                                  "
echo -e "\n\n\n"

# Ensure the script is run with root privileges for modifying /etc/hosts
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root."
  exit
fi

# Get user input for IP and lab name
read -p "Enter the target IP: " TARGET_IP
read -p "Enter the name of the lab: " LAB_NAME

# Create output directory
OUTPUT_DIR="$HOME/htb/$LAB_NAME"
mkdir -p $OUTPUT_DIR

# Define nmap output file
NMAP_OUTPUT="$OUTPUT_DIR/nmap.txt"

# Run nmap scan silently, redirecting progress output to /dev/null
echo "Running nmap scan..."
nmap -sCV $TARGET_IP > $NMAP_OUTPUT 2>&1 &
SCAN_PID=$!  # Capture the PID of the nmap process

# Wait for the nmap scan to complete
wait $SCAN_PID

# Parse nmap output to find open ports and redirects
OPEN_PORTS=$(grep 'open' $NMAP_OUTPUT)
REDIRECT=$(grep 'http-title: Did not follow redirect to' $NMAP_OUTPUT | sed -n 's/^.*redirect to http:\/\/\([^\/]*\.htb\)\(\/.*\)*$/\1/p')

# Debug output
echo "Raw redirect extraction: $REDIRECT"

# Remove scheme and trailing slashes from redirect URL
REDIRECT=$(echo "$REDIRECT" | sed 's/^http:\/\///' | sed 's:/*$::')

# Debug output
echo "Cleaned redirect URL: $REDIRECT"

echo "Open ports found:"
echo "$OPEN_PORTS"

if [ -n "$REDIRECT" ]; then
  echo "Redirect found to $REDIRECT"

  # Update /etc/hosts
  if ! grep -q "$TARGET_IP $REDIRECT" /etc/hosts; then
    echo "$TARGET_IP $REDIRECT" >> /etc/hosts
    echo "/etc/hosts file has been updated with: $TARGET_IP $REDIRECT"
  else
    echo "Entry $TARGET_IP $REDIRECT already exists in /etc/hosts"
  fi

  HOSTNAME=$REDIRECT
else
  HOSTNAME=$TARGET_IP
fi

# Check if HTTP port is open and run dirbuster and ffuf if it is
if echo "$OPEN_PORTS" | grep -q 'http'; then
  echo "HTTP port found. Running dirbuster and ffuf scans."

  # Define the wordlist path
  GB_WORDLIST_PATH="$HOME/gobuster_wordlists/subdirectories-discover/dsplusleakypaths.txt"
  FF_WORDLIST_PATH="$HOME/gobuster_wordlists/subdirectories-discover/subdomains-top1million-110000.txt"

  # Run dirbuster with Gobuster
  DIRBUSTER_OUTPUT="$OUTPUT_DIR/dirbuster.txt"
  gobuster dir -u http://$HOSTNAME -w $GB_WORDLIST_PATH -o $DIRBUSTER_OUTPUT -s 200,301,403,500 -b ""

  # Run ffuf
  FFUF_OUTPUT="$OUTPUT_DIR/ffuf.txt"
  ffuf -u http://$HOSTNAME -w $FF_WORDLIST_PATH -o $FFUF_OUTPUT -mc 200 -H "HOST: FUZZ.$HOSTNAME"

  echo "Scans completed. Results saved in $OUTPUT_DIR"
else
  echo "No HTTP port found. Skipping dirbuster and ffuf scans."
fi
