#!/bin/bash

# Installs Wordpress app with a clean db.
install_command () {
    docker-compose run composer create-project
}

# Deploys Dockerfile changes to the app.
deploy_command () {
 docker-compose up -d --force-recreate --build
}

BASE_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IFS=$'\n' read -rd '' -a COMMAND_LIST <<<"$(perl -ne '/^([a-z_-]+)_command ?\(/ and print "$1\n"' "${BASH_SOURCE[0]}")"

# Executes a shell command in a running container, leave arguments empty to enter a new shell.
exec_command () {
    if [[ "$1" != "" ]]; then
        docker compose exec wordpress "$@"
    else
        docker compose exec wordpress bash -l
    fi
}

# Executes a composer command over the app container.
composer_command () {
   docker-compose run composer "$@"
}

# Executes a composer command to install Elementor.
install_elementor_command () {
   composer_command require wpackagist-plugin/elementor
   cli_command plugin activate elementor
}

# Displays this help text.
help_command () {
    local project_name=$(cd "$(dirname "${BASH_SOURCE[0]}")" && basename $PWD)
    local file_contents=$(<"${BASH_SOURCE[0]}")
    local base_name=$(basename "${BASH_SOURCE[0]}")

    local command
    local text
    local help_text
    local section

    for command in "${COMMAND_LIST[@]}"; do
        text=$(echo -e "$file_contents" \
            | perl -0777 -ne "/^((?:#[^\n]*\n)+)^${command}_command\ ?\(/m and print \$1;" \
            | perl -pe 's/^[#\t ]+|[#\t ]$//g;' -pe 's/[\t\n]| {2,}/ /g;' \
            | perl -pe 's/ +$//;' )
        if [[ "$text" == "" ]]; then
            text="No documentation available."
        fi
        if [[ "$text" =~ ^\[ ]]; then
            section=$(echo "$text" | perl -ne '/^\[([^\n\]]+)\]/ and print $1')
            if [[ "$section" != "" ]]; then
                text=$(echo "$text" | perl -ne '/\] *(.+)/ and print $1')
                help_text="$help_text\n"
                help_text="$help_text\n\033[33m$section:\033[0m"
            fi
        fi
        help_text="$help_text\n  \033[32m${command/_/:}\033[0m\t$text"

    done

    {
        echo -e "\033[32m[$project_name] $base_name\033[0m"
        echo ""
        echo -e "\033[33mUsage:\033[0m"
        echo "  ./$base_name [command=sh] <arguments>"
        if [[ "$(echo -e "$help_text" | tail -n+2 | head -n1 | grep $'\t')" != "" ]]; then
            echo ""
            echo -e "\033[33mCommands:\033[0m"
        fi
        echo -e "$help_text" | column -t -s $'\t' | perl -pe 's/^ {7}+//' | perl -pe "s/(\033\[33m)/\n\1/"
        echo ""
    } >&2
}

# Runs a one-off command in a self-removing container.
run_command () {
    docker compose run --rm wordpress "$@"
}

# Executes a shell command in a self-removing container, leave arguments empty to enter a new shell.
sh_command () {
    if [[ "$1" != "" ]]; then
        run_command bash -lc "$@"
    else
        run_command bash -lll
    fi
}

# Enter the app container as root.
shell_command () {
    if [ -z "$1" ]
    then
        docker compose exec wordpress bash
    else
        docker compose exec --user $@ wordpress bash
    fi
}

# Executes a wp-cli shell command leave arguments empty to enter a new shell.
cli_command () {
    if [[ "$1" != "" ]]; then
        exec_command wp --allow-root "$@"
    else
        exec_command
    fi
}


# Starts containers.
start_command () {
    # exit early if the service is already started
    if `docker compose exec wordpress hostname >/dev/null 2>&1`; then
        return 1
    fi

    docker-compose up -d
}

# Stops containers.
stop_command () {
    docker compose stop
}

# Removes containers.
down_command () {
    docker compose down
}

# Resets environment by removing containers and volumes.
reset_command () {
    docker-compose rm -v
}

# Start Docker CTOP to view container metrics.
ctop_command () {
    docker run --rm -ti --name=ctop -v /var/run/docker.sock:/var/run/docker.sock quay.io/vektorlab/ctop:latest
}
# Enable MySQL General Log file.
dblog_enable_command () {
  docker compose exec db mysql -u root -proot -e "SET global general_log = on"
  docker compose exec db mysql -u root -proot -e "show variables like '%general_log%'"
}

# Disable MySQL General Log file.
dblog_disable_command () {
  docker compose exec db mysql -u root -proot -e "SET global general_log = off"
  docker compose exec db mysql -u root -proot -e "show variables like '%general_log%'"
}

# Show MySQL General Log file.
dblog_show_command () {
  docker compose exec db cat /tmp/query.log
}

#
# Execute the command(s)
#

main () {
    local command=${1/:/_}
    local args=("${@:2}")

    if [[ ! " ${COMMAND_LIST[@]} " =~ " $command " ]]; then
        if [[ "$command" != "" ]]; then
            #make a new default command for now we'll just print help
            command=help
            args=""
        else
            command=help
            args=""
        fi
    fi

    "${command}_command" "${args[@]}"
}

pushd "${BASE_PATH}" >/dev/null
main "$@"
popd >/dev/null
