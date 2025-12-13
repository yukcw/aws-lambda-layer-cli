# bash completion for aws-lambda-layer

_aws_lambda_layer() {
    local cur prev words cword
    _init_completion || return

    local commands="zip publish help --help --version"
    local runtime_opts="--nodejs --node -n --python --py -p --runtime"
    local common_opts="-i --packages --name -h --help"
    local node_opts="--node-version"
    local python_opts="--python-version --no-uv"

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
                    case ${runtime} in
                        nodejs)
                            COMPREPLY=($(compgen -W "${common_opts} ${node_opts}" -- "${cur}"))
                            ;;
                        python)
                            COMPREPLY=($(compgen -W "${common_opts} ${python_opts}" -- "${cur}"))
                            ;;
                    esac
                fi
            fi
            ;;
    esac
}

complete -F _aws_lambda_layer aws-lambda-layer