#!/usr/bin/env bash
# Global configuration
# shellcheck disable=SC1091,SC2015

VERSION=0.0.1
NAME="admin tool"
# Get the full path of the current script's directory
script_dir=$(dirname "$(realpath "${BASH_SOURCE[@]}")")
# Remove the last folder from the path and rename it to KLITE_HOME
KLITE_HOME=$(dirname "$script_dir")
path_line="export PATH=\"$script_dir:\$PATH\""

export PODMAN_COMPOSE_WARNING_LOGS=false

# Append path_line to shell configuration files
append_path_to_shell_configs() {
  for file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$file" ] && ! grep -Fxq "$path_line" "$file"; then
      echo "$path_line" >> "$file"
    fi
  done
}

# Function definitions
install_dependencies() {
  [[ -f "./.dependency_installation_status" ]] && return 0

  os_name="$(uname -s)"
  case "${os_name}" in
    Linux*)
      source /etc/os-release
      case "${ID}" in
        ubuntu|debian)
          if ! sudo apt-get update && sudo apt-get install -y gpg curl gawk; then return 1; fi
          if ! sudo mkdir -p /etc/apt/keyrings; then return 1; fi
          if [[ ! -f /etc/apt/keyrings/charm.gpg ]] && ! curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg; then return 1; fi
          if ! echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list; then return 1; fi
          if ! sudo apt-get update || ! sudo apt-get install -y gum; then return 1; fi
          ;;
        *)
          echo "Unsupported Linux distribution for automatic installation."
          return 1
          ;;
      esac
      ;;
    *)
      echo "Unsupported operating system."
      return 1
      ;;
  esac

  touch "./.dependency_installation_status"
  echo "Dependencies installed successfully."
}



# Check Podman function
check_podman() {
  # Check if podman command is available and outputs a version
  podman_version=$(podman --version 2>/dev/null | grep "podman version")
  if [ -z "${podman_version}" ]; then
    echo -e "\nPodman not installed.\n"
    if gum confirm --unselected.foreground 231 --unselected.background 39 --selected.bold --selected.background 121 --selected.foreground 231 "Would you like to install Podman now?"; then
      podman_install
    else
      return 1
    fi
  # Check if Podman is running by executing a test container
  else
    # Check if Podman is running
    if ! podman run --rm hello-world > /dev/null 2>&1; then
      echo -e "\nPodman is not running.\n"
      if gum confirm --unselected.foreground 231 --unselected.background 39 --selected.bold --selected.background 121 --selected.foreground 231 "Would you like to try starting Podman now?"; then
        echo "Attempting to start Podman..."
        # Starting Podman based on OS
        os_name="$(uname -s)"
        case "${os_name}" in
          Linux*)
            gum spin --spinner dot --title "Starting Podman..." -- echo && sudo systemctl start podman
            ;;
          *)
            echo "Cannot start Podman automatically on this OS."                  
            return 1
            ;;
        esac
        # Recheck if Podman starts successfully
        sleep 30  # Wait a bit before rechecking
        if ! podman info > /dev/null 2>&1; then
          echo -e "\nFailed to start Podman.\n"
          return 1
        else
          echo "Podman started successfully."
        fi
      else
        return 1
      fi
    fi
  fi
  # echo "Podman is running."
  return 0
}

podman_status(){
  # Prepare the Podman status message
  podman_status=$(if check_podman; then
    gum style --foreground 121 --margin 1 "🐳 ${podman_version} Installed and Working"
  else
    echo "🐳 🔻";
  fi)

  # Function to check the status of a Podman container
  check_container_status() {
    local container_name="$1"
    local up_icon="$2"
    local down_icon="$3"
    if [[ -n $(podman ps -qf "name=${container_name}" 2>/dev/null) ]]; then
      if podman ps -f "name=${container_name}" | grep -q -e '(unhealthy)' -e '(health: ' ; then
        echo "${up_icon} $(gum style --foreground 160 " ${container_name}" 2>/dev/null) $(gum style --bold --foreground 160 " UP (unhealthy)" 2>/dev/null)";
      else
        echo "${up_icon} $(gum style --foreground 121 " ${container_name}" 2>/dev/null) $(gum style --bold --foreground 121 " UP" 2>/dev/null)";
      fi
    else
      echo "${down_icon} $(gum style --foreground 160 " ${container_name}" 2>/dev/null) $(gum style --faint --foreground 160 " DOWN" 2>/dev/null)";
    fi
  }

  # Check for specific Podman containers
  node_container=$(check_container_status "cardano-node" "🧊 " "🔻 ")
  postgres_container=$(check_container_status "postgress" "🔹 " "🔻 ")
  db_sync_container=$(check_container_status "cardano-db-sync" "🥽 " "🔻 ")
  postgrest_container=$(check_container_status "postgrest" "🪢 " "🔻 ")
  haproxy_container=$(check_container_status "haproxy" "🧢 " "🔻 ")

  # Combine elements into one layout
  combined_layout=$(gum join --vertical --align center\
    "$podman_status " \
    "$node_container" \
    "$postgres_container " \
    "$db_sync_container " \
    "$postgrest_container " \
    "$haproxy_container " \
    "$(echo)")

  gum style \
    --border none \
    --border-foreground 121 \
    --margin "1 0" \
    --padding "0 10" \
    --background black \
    --foreground 121 \
    "$combined_layout"    
}

# Podman Innstall function
podman_install() {
  # Check if Podman was already installed
  if command -v podman > /dev/null 2>&1 && podman compose version > /dev/null 2>&1 ; then
    echo "Podman is already installed."
    return 0
  fi

  os_name="$(uname -s)"
  case "${os_name}" in
    Linux*)
      source /etc/os-release
      case "${ID}" in
        debian)
          # Add Podman's official GPG key:
          sudo rm -rf ~/.local/share/containers
          sudo apt-get install -y ca-certificates curl gpg
          echo 'deb http://download.opensuse.org/repositories/home:/alvistack/Debian_12/ /' | sudo tee /etc/apt/sources.list.d/home:alvistack.list > /dev/null
          curl -fsSL https://download.opensuse.org/repositories/home:alvistack/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_alvistack.gpg > /dev/null
          gum spin --spinner dot --title "Updating..." -- sudo apt-get update
          gum spin --spinner dot --title "Installing Podman..." -- echo && sudo apt-get -y install podman uidmap slirp4netns netavark passt && sh -c "$(curl -sSL https://raw.githubusercontent.com/containers/podman-compose/main/scripts/download_and_build_podman-compose.sh)" && sudo mv ./podman-compose /usr/bin/
          ;;
        *)
          echo "Unsupported Linux distribution for automatic Podman installation."
          return 1
          ;;
      esac
      sudo loginctl enable-linger $(id -u)
      ;;
    *)
      echo "Unsupported operating system."
      return 1
      ;;
  esac
}

# Function to check and create or copy .env file
check_env_file() {
  if [ ! -f ".env" ]; then  # Check if .env does not exist
    if [ -f ".env.example" ]; then  # Check if .env.example exists
      cp .env.example .env  # Copy .env.example to .env
      echo ".env file created from .env.example... please inspect the .env file and adjust variables (e.g. network) accordingly"
      echo -e "\nCurrent default settings:\n"
      cat .env
      read -r -p "Press enter to continue"
    else
      touch .env  # Create a new .env file
      echo "New .env file created."
    fi
  fi
}

# Function to reset .env file
reset_env_file() {
  if [ -f ".env" ]; then  # Check if .env  
    if gum confirm --unselected.foreground 231 --unselected.background 39 --selected.bold --selected.background 121 --selected.foreground 231 "Are you sure you want to reset the .env file?"; then
      backup_name=".env.$(date +%Y%m%d%H%M%S)"  # Create a backup name with timestamp
      mv .env "$backup_name"  # Move .env to backup
      echo "Reset .env file. Backup created: $backup_name"
    else
      echo "Reset cancelled."
    fi
  else
    echo "No .env file to reset. Creating a new one with defaults..." 
    cp .env.example .env  # Copy .env.example to.env
  fi
}

# Function to handle .env file (create or edit)
handle_env_file() {
  if [ ! -f ".env" ]; then
    echo "Creating new .env file..."
    touch .env
  fi
  while true; do
    action=$(gum choose --height 15 --item.foreground 39 --cursor.foreground 121 "Add Entry" "Edit Entry" "Remove Entry" "View File" "Reset Config" "$(gum style --foreground 208 "Back")")
    case "$action" in
      "Add Entry")
        key=$(gum input --placeholder "Enter key")
        value=$(gum input --placeholder "Enter value")
        # Check if key or value is empty
        if [[ -z "$key" || -z "$value" ]]; then
          echo "Key or value cannot be empty. Entry not added."
        else
          printf "%s=%s\n" "$key" "$value" >> .env
          clear
          gum style --border rounded --border-foreground 121 --padding "1" --margin "1" --foreground green "Current .env content:" "$(cat "${KLITE_HOME}"/.env)"
        fi
        ;;
      "Edit Entry")
        line_to_edit="$(gum filter < "${KLITE_HOME}"/.env)"
        key=$(echo "$line_to_edit" | cut -d '=' -f 1)
        existing_value=$(echo "$line_to_edit" | cut -d '=' -f 2-)
        # Check if key is empty
        if [[ -z "$key" ]]; then
          echo "No key selected for editing."
        else
          new_value=$(gum input --placeholder "Enter new value for $key")
          # Check if new value is empty or the same as the existing value
          if [[ -z "$new_value" ]]; then
            echo "New value cannot be empty. Entry not edited."
          elif [[ "$new_value" == "$existing_value" ]]; then
            echo "New value is the same as the existing value. Entry not edited."
          else
            sed -i '' "s/^$key=.*/$key=$new_value/" .env
          fi
        fi
        ;;
      "Remove Entry")
          line_to_remove="$(gum filter < "${KLITE_HOME}"/.env)"
          key_to_remove=$(echo "$line_to_remove" | cut -d '=' -f 1)
          if [[ -z "$key_to_remove" ]]; then
            echo "No key selected for removal."
          else
            # Remove the line from .env file
            sed -i '' "/^$key_to_remove=/d" .env
            clear
            gum style --border rounded --border-foreground 121 --padding "1" --margin "1" --foreground green "Current .env content:" "$(cat "${KLITE_HOME}"/.env)"
          fi
          ;;
      "View File")
          clear
          gum style --border rounded --border-foreground 121 --padding "1" --margin "1" --foreground green "Current .env content:" "$(cat "${KLITE_HOME}"/.env)"
          ;;
      "Reset Config")
          # Logic for reset config
          reset_env_file
          ;;
      "Back")
          show_splash_screen
          break
          ;;
    esac
  done
}

# Menu function with improved UI and submenus
menu() {
    while true; do
        choice=$(gum choose --height 15 --item.foreground 121 --cursor.foreground 39 "Tools" "Podman" "Setup" "Advanced" "Config" "$(gum style --foreground 160 "Exit")")

        case "$choice" in
            "Tools")
            setup_choice=$(gum choose --height 15 --cursor.foreground 229 --item.foreground 39 "$(gum style --foreground 87 "gLiveView")" "$(gum style --foreground 87 "cntools")"  "$(gum style --foreground 117 "Enter PSQL")" "$(gum style --foreground 117 "DBs Lists")" "$(gum style --foreground 208 "Back")")
            case "$setup_choice" in
                "gLiveView")
                    # Find the Podman container ID with 'postgres' in the name
                    container_id=$(podman ps -qf "name=cardano-node")
                    if [ -z "$container_id" ]; then
                        echo "No running Node container found."
                        read -r -p "Press enter to continue"
                    else
                        # Executing commands in the found container
                        podman exec -it "$container_id" bash -c "/opt/cardano/cnode/scripts/gLiveView.sh"
                    fi
                    show_splash_screen           
                    ;;
                "cntools")
                    # Find the Podman container ID with 'postgres' in the name
                    container_id=$(podman ps -qf "name=cardano-node")
                    if [ -z "$container_id" ]; then
                        echo "No running Node container found."
                        read -r -p "Press enter to continue"
                    else
                        # Executing commands in the found container
                        podman exec -it "$container_id" bash -c "/opt/cardano/cnode/scripts/cntools.sh"
                    fi
                    show_splash_screen           
                    ;;
                "Enter PSQL")
                    # Logic for Enter Postgres
                    container_id=$(podman ps -qf "name=postgress")
                    if [ -z "$container_id" ]; then
                        echo "No running PostgreSQL found."
                        read -r -p "Press enter to continue"
                    else
                        # Executing commands in the found container
                        podman exec -it "$container_id" bash -c "/usr/bin/psql -U $POSTGRES_USER -d $POSTGRES_DB"
                    fi
                    show_splash_screen
                    ;;
                "DBs Lists")
                    # Logic for Enter Postgres
                    container_id=$(podman ps -qf "name=postgress")
                    if [ -z "$container_id" ]; then
                        echo "No running PostgreSQL found."
                        read -r -p "Press enter to continue"
                    else
                        # Executing commands in the found container
                        podman exec -it -u postgres "$container_id" bash -c "/scripts/kltables.sh > /scripts/TablesAndIndexesList.txt"
                        echo "TablesAndIndexesList.txt File created in your script folder."
                    fi
                    show_splash_screen
                    ;;
            esac
            ;;

            "Setup")
              # Submenu for Setup with plain text options
              setup_choice=$(gum choose --height 15 --cursor.foreground 229 --item.foreground 39 "Initialise Postgres" "$(gum style --foreground 208 "Back")")

              case "$setup_choice" in
                "Initialise Postgres")
                  # Logic for installing Postgres
                  container_id=$(podman ps -qf "name=postgress")
                  if [ -z "$container_id" ]; then
                    echo "No running PostgreSQL container found."
                    read -r -p "Press enter to continue"
                  else
                    # Executing commands in the found container
                    podman exec "$container_id" bash -c "/scripts/lib/install_postgres.sh"
                    echo -e "SQL scripts have finished processing, following scripts were executed successfully:\n"
                    podman exec "$container_id" bash -c "cat /scripts/sql/rpc/Ok.txt"
                    echo -e "\n\nThe following errors were encountered during processing:\n"
                    podman exec "$container_id" bash -c "cat /scripts/sql/rpc/NotOk.txt"
                    echo -e "\n\n"
                    read -r -p "Press enter to continue"
                  fi
                  show_splash_screen
                  ;;
                "Back")
                  ;;
              esac
              ;;

              "$(gum style --foreground green "Podman")")
              # Submenu for Podman
              podman_choice=$(gum choose --height 15 --item.foreground 39 --cursor.foreground 121 \
                "Podman Status" \
                "Podman Up/Reload" \
                "Podman Down" \
                "$(gum style --foreground 208 "Back")")

              case "$podman_choice" in
                "Podman Status")
                    # Logic for Podman Status
                    clear
                    show_splash_screen
                    podman_status
                    # gum style --border rounded --border-foreground 121 --padding "1" --margin "1" --foreground 121 "$(podman compose ps | awk '{print $4, $8}')"
                    ;;
                "Podman Up/Reload")
                    # Logic for Podman Up
                    clear
                    show_splash_screen
                    gum spin --spinner dot --spinner.bold --show-output --title.align center --title.bold --spinner.foreground 121 --title.foreground 121  --title "Koios Lite Starting services..." -- echo && podman compose -f "${KLITE_HOME}"/podman-compose.yml up -d --quiet-pull --pull --remove-orphans
                    ;;
                "Podman Down")
                    # Logic for Podman Down
                    clear
                    show_splash_screen
                    gum spin --spinner dot --spinner.bold --show-output --title.align center --title.bold --spinner.foreground 202 --title.foreground 202 --title "Koios Lite Stopping services..." -- echo && podman compose -f "${KLITE_HOME}"/podman-compose.yml down
                    ;;
                "Back")
                    # Back to Main Menu
                    ;;
              esac
              ;;

            "Config")
              # Submenu for Config
              handle_env_file
              ;;

            "Advanced")
              setup_choice=$(gum choose --height 15 --cursor.foreground 229 --item.foreground 39 "$(gum style --foreground 82  "Enter Cardano Node")" "$(gum style --foreground 85  "Logs Cardano Node")" "$(gum style --foreground 82 "Enter Postgres")" "$(gum style --foreground 85 "Logs Postgres")" "$(gum style --foreground 82 "Enter Dbsync")" "$(gum style --foreground 85 "Logs Dbsync")" "$(gum style --foreground 85 "Logs PostgREST")" "$(gum style --foreground 82 "Enter HAProxy")" "$(gum style --foreground 85 "Logs HAProxy")" "$(gum style --foreground 208 "Back")")
              case "$setup_choice" in
                "Enter Cardano Node")
                  # Enter
                  container_id=$(podman ps -qf "name=cardano-node")
                  if [ -z "$container_id" ]; then
                    echo "No running Node container found."
                    read -r -p "Press enter to continue"
                  else
                    # Executing commands in the found container
                    podman exec -it "$container_id" bash -c "bash"
                  fi
                  show_splash_screen                  
                  ;;
                "Logs Cardano Node")
                  # Enter
                  container_id=$(podman ps -qf "name=cardano-node")
                  if [ -z "$container_id" ]; then
                    echo "No running Node container found."
                    read -r -p "Press enter to continue"
                  else
                    # Logs
                    podman logs "$container_id" | more
                    read -r -p "End of logs reached, press enter to continue"
                  fi
                  show_splash_screen                  
                  ;;
                "Enter Postgres")
                  # Logic for Enter Postgres
                  container_id=$(podman ps -qf "name=postgress")
                  if [ -z "$container_id" ]; then
                    echo "No running PostgreSQL container found."
                    red -p "Press enter to continue"
                  else
                    # Executing commands in the found container
                    podman exec -it "$container_id" bash -c "bash"
                  fi
                  show_splash_screen
                  ;;
                "Logs Postgres")
                  # Logic for Enter Postgres
                  container_id=$(podman ps -qf "name=postgress")
                  if [ -z "$container_id" ]; then
                    echo "No running PostgreSQL container found."
                    read -r -p "Press enter to continue"
                  else
                    # Logs
                    podman logs "$container_id" | more
                    read -r -p "End of logs reached, press enter to continue"
                  fi
                  show_splash_screen
                  ;;
                "Enter Dbsync")
                  # Logic for Enter Dbsync
                  container_id=$(podman ps -qf "name=${PROJ_NAME}-cardano-db-sync")
                  if [ -z "$container_id" ]; then
                    echo "No running Dbsync container found."
                    read -r -p "Press enter to continue"
                  else
                    # Executing commands in the found container
                    podman exec -it "$container_id" bash -c "bash"
                  fi
                  show_splash_screen
                  ;;
                "Logs Dbsync")
                  # Logic for Enter Dbsync
                  container_id=$(podman ps -qf "name=${PROJ_NAME}-cardano-db-sync")
                  if [ -z "$container_id" ]; then
                    echo "No running Dbsync container found."
                    read -r -p "Press enter to continue"
                  else
                    # Logs
                    podman logs "$container_id" | more
                    read -r -p "End of logs reached, press enter to continue"
                  fi
                  show_splash_screen
                  ;;
                "Logs PostgREST")
                  # Logic for Enter PostgREST
                  container_id=$(podman ps -qf "name=${PROJ_NAME}-postgrest")
                  if [ -z "$container_id" ]; then
                    echo "No running PostgREST container found."
                    read -r -p "Press enter to continue"
                  else
                    # Logs
                    podman logs "$container_id" | more
                    read -r -p "End of logs reached, press enter to continue"
                  fi
                  show_splash_screen
                  ;;
                "Enter HAProxy")
                  # Logic for Enter HAProxy
                  container_id=$(podman ps -qf "name=${PROJ_NAME}-haproxy")
                  if [ -z "$container_id" ]; then
                    echo "No running HAProxy container found."
                    read -r -p "Press enter to continue"
                  else
                    # Executing commands in the found container
                    podman exec -it "$container_id" bash -c "bash"
                  fi
                  show_splash_screen
                  ;;
                "Logs HAProxy")
                  # Logic for Enter HAProxy
                  container_id=$(podman ps -qf "name=${PROJ_NAME}-haproxy")
                  if [ -z "$container_id" ]; then
                    echo "No running HAProxy container found."
                    read -r -p "Press enter to continue"
                  else
                    # Logs
                    podman logs "$container_id" | more
                    read -r -p "End of logs reached, press enter to continue"
                  fi
                  show_splash_screen
                  ;;
              esac
              ;;
            "Exit")
              clear
              echo "Thanks for using Koios Lite Node."
              exit 0  # Exit the menu loop
              ;;
        esac
    done
}

# Enhanced display UI function using gum layout
display_ui() {
  install_dependencies || { echo "Failed to install dependencies."; exit 0; }

  show_splash_screen
  # Wait for gum style commands to complete
  menu
}

about(){
  gum style --foreground 121 --border-foreground 121 --align center "$(gum join --vertical \
    "$(show_splash_screen)" \
    "$(gum style --align center --width 50 --margin "1 2" --padding "2 2" 'About: ' ' Koios Lite Node administration tool.')" \
    "$(gum style --align center --width 50 'https://github.com/koios-official/Lite-Node')")"
}

show_splash_screen(){
  # Clear the screen before displaying UI
  clear
  combined_layout1=$(gum style --foreground 121 --align center "$(cat ./scripts/.logo)")

  combined_layout2=$(gum join --horizontal \
    "$(gum style --bold --align center "Koios Lite Node")" \
    "$(gum style --faint --foreground 229 --align center " - $NAME v$VERSION")")

  combined_layout=$(gum join --vertical \
    "$combined_layout1 " \
    "$combined_layout2")

  # Display the combined layout with a border
  gum style \
    --border none \
    --border-foreground 121 \
    --margin "1" \
    --padding "1 2" \
    --background black \
    --foreground 121 \
    "$combined_layout"

}

display_help_usage() {
  echo "Koios Administration Tool Help Menu:"
  echo -e "------------------------------------\n"
  echo -e "Welcome to the Koios Administration Tool Help Menu.\n"
  echo -e "Below are the available commands and their descriptions:\n"
  echo -e "--about: \t\t\t Displays information about the Koios administration tool."
  echo -e "--install-dependencies: \t Installs necessary dependencies."
  echo -e "--check-podman: \t\t Checks if Podman is running."
  echo -e "--handle-env-file: \t\t Manage .env file."
  echo -e "--reset-env: \t\t\t Resets the .env file to defaults."
  echo -e "--podman-status: \t\t Shows the status of Podman containers."
  echo -e "--podman-up: \t\t\t Starts Podman containers defined in podman-compose.yml."
  echo -e "--podman-down: \t\t\t Stops Podman containers defined in podman-compose.yml."
  echo -e "--enter-node: \t\t\t Accesses the Cardano Node container."
  echo -e "--logs-node: \t\t\t Displays logs for the Cardano Node container."
  echo -e "--gliveview: \t\t\t Executes gLiveView in the Cardano Node container."
  echo -e "--cntools: \t\t\t Runs CNTools in the Cardano Node container."
  echo -e "--enter-postgres: \t\t Accesses the Postgres container."
  echo -e "--logs-postgres: \t\t Displays logs for the Postgres container."
  echo -e "--enter-dbsync: \t\t Accesses the DBSync container."
  echo -e "--logs-dbsync: \t\t\t Displays logs for the DBSync container."
  echo -e "--enter-haproxy: \t\t Accesses the HAProxy container."
}

# Function to process command line arguments
process_args() {
  case "$1" in
    --about)
      about
      show_ui=false
      ;;
    --install-dependencies)
      rm -f ./.dependency_installation_status 
      install_dependencies && echo -e "\nDone!!\n"
      ;;
    --check-podman)
      check_podman
      ;;
    --handle-env-file)
      handle_env_file
      ;;
    --reset-env)
      reset_env_file
      ;;
    --podman-status)
      podman_status
      ;;
    --podman-up)
      podman compose -f "${KLITE_HOME}"/podman-compose.yml up -d --quiet-pull --pull --remove-orphans
      ;;
    --podman-down)
      podman compose -f "${KLITE_HOME}"/podman-compose.yml down
      ;;
    --enter-node)
      container_id=$(podman ps -qf "name=cardano-node")
      [ -z "$container_id" ] && echo "No running Node container found." || podman exec -it "$container_id" bash
      ;;
    --logs-node)
      container_id=$(podman ps -qf "name=cardano-node")
      [ -z "$container_id" ] && echo "No running Node container found." || podman logs "$container_id" | more
      ;;
    --gliveview)
      container_id=$(podman ps -qf "name=cardano-node")
      [ -z "$container_id" ] && echo "No running Node container found." || podman exec -it "$container_id" /opt/cardano/cnode/scripts/gLiveView.sh
      ;;
    --cntools)
      container_id=$(podman ps -qf "name=cardano-node")
      [ -z "$container_id" ] && echo "No running Node container found." || podman exec -it "$container_id" /opt/cardano/cnode/scripts/cntools.sh
      ;;
    --enter-postgres)
      execute_in_container "postgress" "bash"
      ;;
    --logs-postgres)
      show_logs "postgress"
      ;;
    --enter-dbsync)
      execute_in_container "${PROJ_NAME}-cardano-db-sync" "bash"
      ;;
    --logs-dbsync)
      show_logs "${PROJ_NAME}-cardano-db-sync"
      ;;
    --enter-haproxy)
      execute_in_container "${PROJ_NAME}-haproxy" "bash"
      ;;
    --logs-haproxy)
      show_logs "${PROJ_NAME}-haproxy"
      ;;
    --help|-h)
      display_help_usage
      ;;
    *)
      # Check if the number of arguments is zero
      if [ $# -eq 0 ]; then
        check_env_file
        display_ui  # Call the display function
      else
        echo "Unknown command: '$1'"
        echo "Use --help to see available commands."
        sleep 3
      fi
      ;;
  esac
}

execute_in_container() {
  local container_name=$1
  local command=$2
  local container_id;container_id=$(podman ps -qf "name=${container_name}")
  if [ -z "$container_id" ]; then
    echo "No running ${container_name} container found."
  else
    podman exec -it "${container_id}" "${command}"
  fi
}

show_logs() {
  local container_name=$1
  local container_id;container_id=$(podman ps -qf "name=${container_name}")
  if [ -z "${container_id}" ]; then
    echo "No running ${container_name} container found."
  else
    podman logs "$container_id" | more
  fi
}

# To find the right color's code
show_colors(){
  for i in {0..255}; do
    printf "\e[38;5;${i}m%3d\e[0m " "${i}"
    if (( (i + 1) % 16 == 0 )); then
      echo
    fi
  done
}

# Main function to orchestrate script execution
main() {
  append_path_to_shell_configs
  cd "$KLITE_HOME" || exit
  source .env
  process_args "$@"  # Process any provided command line arguments
  install_dependencies || { echo "Failed to install dependencies."; exit 0; }
  if [ "$show_ui" = true ]; then
    display_ui
  fi
  #show_colors # Just a color code viewing function for testing
}

# Execute the main function
main "$@"
