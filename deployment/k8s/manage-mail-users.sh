#!/bin/bash
# This script helps manage mail users for the Mailbag system

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check if context.json exists
if [ ! -f /etc/mailbag/context.json ]; then
  echo "Error: /etc/mailbag/context.json not found."
  echo "Please run ./generate-context.sh first."
  exit 1
fi

# Extract domain and mail path from context.json
DOMAIN=$(grep -o '"zone": "[^"]*"' /etc/mailbag/context.json | cut -d'"' -f4)
MAIL_PATH=$(grep -o '"mail_path_host": "[^"]*"' /etc/mailbag/context.json | cut -d'"' -f4)
AUTH_PATH="/mailbag/config/authlib"

# Function to add a new user
add_user() {
  local username=$1
  local password=$2
  
  # Create userdb entry
  cd $AUTH_PATH
  mkdir -p userdb
  echo $password | userdbpw -hmac-md5 | userdb -f userdb $username@$DOMAIN set hmac-md5pw
  userdb -f userdb $username@$DOMAIN set gid=300
  userdb -f userdb $username@$DOMAIN set uid=300
  userdb -f userdb $username@$DOMAIN set home=$MAIL_PATH/$username
  makeuserdb
  
  # Create maildir
  mkdir -p $MAIL_PATH/$username
  maildirmake $MAIL_PATH/$username/Maildir
  chown -R vmail:vmail $MAIL_PATH/$username
  
  echo "User $username@$DOMAIN created successfully"
}

# Function to delete a user
delete_user() {
  local username=$1
  
  # Remove userdb entry
  cd $AUTH_PATH
  userdb -f userdb $username@$DOMAIN del
  makeuserdb
  
  # Confirm before deleting mailbox
  read -p "Delete mailbox data for $username@$DOMAIN? (y/n): " confirm
  if [ "$confirm" = "y" ]; then
    rm -rf $MAIL_PATH/$username
    echo "User $username@$DOMAIN and mailbox deleted"
  else
    echo "User $username@$DOMAIN deleted, mailbox preserved"
  fi
}

# Function to list users
list_users() {
  cd $AUTH_PATH
  if [ -f userdb ]; then
    echo "Mail users:"
    grep -o '[^[:space:]]*@[^[:space:]]*' userdb | sort | uniq
  else
    echo "No users found"
  fi
}

# Main menu
show_menu() {
  echo "================================"
  echo "Mailbag User Management"
  echo "================================"
  echo "1) Add a new mail user"
  echo "2) Delete a mail user"
  echo "3) List all mail users"
  echo "4) Exit"
  echo "================================"
  read -p "Enter choice [1-4]: " choice
  
  case $choice in
    1)
      read -p "Enter username (without @$DOMAIN): " username
      read -s -p "Enter password: " password
      echo
      add_user $username $password
      ;;
    2)
      read -p "Enter username to delete (without @$DOMAIN): " username
      delete_user $username
      ;;
    3)
      list_users
      ;;
    4)
      exit 0
      ;;
    *)
      echo "Invalid option"
      ;;
  esac
  
  read -p "Press Enter to continue..."
  show_menu
}

# Start the menu
show_menu
