# bash completion for aws-lambda-layer-cli

_aws_lambda_layer_cli() {
    local cur prev words cword
    # Use fallback variables for older bash versions
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local commands="zip publish help --help --version"
    local runtime_opts="--nodejs --node -n --python --py -p --runtime"
    local common_opts="--name -h --help"
    local publish_opts="--description --layer-name --profile --region"
    local node_opts="--node-version"
    local python_opts="--python-version --platform"

    case ${cword} in
        1)
            # First argument: main command
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            ;;
        2)
            if [[ ${words[1]} == "zip" ]] || [[ ${words[1]} == "publish" ]]; then
                # Second argument for zip/publish: runtime
                COMPREPLY=($(compgen -W "${runtime_opts}" -- "${cur}"))
            fi
            ;;
        3)
            # Third argument: packages (positional)
            if [[ ${words[1]} == "zip" ]] || [[ ${words[1]} == "publish" ]]; then
                # Suggest package format based on runtime
                local has_runtime=""
                for word in "${words[@]:2}"; do
                    case ${word} in
                        --nodejs|--node|-n|--runtime=nodejs)
                            COMPREPLY=("express@4.18.2,lodash")
                            return
                            ;;
                        --python|--py|-p|--runtime=python)
                            COMPREPLY=("numpy==1.26.0,pandas")
                            return
                            ;;
                    esac
                done
            fi
            ;;
        *)
            if [[ ${words[1]} == "zip" ]] || [[ ${words[1]} == "publish" ]]; then
                # Determine runtime
                local runtime=""
                for word in "${words[@]:2}"; do
                    case ${word} in
                        --nodejs|--node|-n)
                            runtime="nodejs"
                            break
                            ;;
                        --python|--py|-p)
                            runtime="python"
                            break
                            ;;
                        --runtime=nodejs)
                            runtime="nodejs"
                            break
                            ;;
                        --runtime=python)
                            runtime="python"
                            break
                            ;;
                        --runtime)
                            # Check next word for runtime value
                            local next_word="${words[cword]}"
                            if [[ ${next_word} == "nodejs" || ${next_word} == "python" ]]; then
                                runtime="${next_word}"
                            fi
                            break
                            ;;
                    esac
                done

                if [[ -z ${runtime} ]]; then
                    # Still need to choose runtime
                    COMPREPLY=($(compgen -W "${runtime_opts}" -- "${cur}"))
                else
                    # Runtime chosen, now show appropriate options
                    local cmd_opts="${common_opts}"
                    if [[ ${words[1]} == "publish" ]]; then
                        cmd_opts="${cmd_opts} ${publish_opts}"
                    fi
                    
                    case ${runtime} in
                        nodejs)
                            COMPREPLY=($(compgen -W "${cmd_opts} ${node_opts}" -- "${cur}"))
                            ;;
                        python)
                            COMPREPLY=($(compgen -W "${cmd_opts} ${python_opts}" -- "${cur}"))
                            ;;
                    esac
                fi
            fi
            ;;
    esac
}

complete -F _aws_lambda_layer_cli aws-lambda-layer-cli