#compdef aws-lambda-layer

_aws-lambda-layer() {
    local -a commands runtime_opts common_opts node_opts python_opts
    
    commands=(
        'zip:Create and package a Lambda layer as zip file'
        'publish:Create and publish a Lambda layer to AWS (uses IAM credentials)'
        'help:Show help message'
        '--help:Show help message'
        '--version:Show version information'
    )
    
    runtime_opts=(
        '--nodejs[Create Node.js layer]'
        '--node[Create Node.js layer]'
        '-n[Create Node.js layer]'
        '--python[Create Python layer]'
        '--py[Create Python layer]'
        '-p[Create Python layer]'
        '--runtime[Specify runtime]:runtime:(nodejs python)'
        '--runtime=-[Specify runtime]:runtime:(nodejs python)'
    )
    
    common_opts=(
        '--packages[Comma-separated packages with versions]:packages:'
        '-i[Comma-separated packages with versions]:packages:'
        '--name[Output file name]:name:'
        '--help[Show help]'
        '-h[Show help]'
    )
    
    node_opts=(
        '--node-version[Node.js version (default: 24)]:version:'
    )
    
    python_opts=(
        '--python-version[Python version (default: 3.14)]:version:'
        '--no-uv[Use pip/venv instead of uv]'
    )
    
    _arguments -C \
        '1: :->command' \
        '2: :->runtime_or_option' \
        '*: :->options'
    
    case $state in
        command)
            _describe 'command' commands
            ;;
        runtime_or_option)
            if [[ $words[2] == "zip" ]] || [[ $words[2] == "publish" ]]; then
                _describe 'runtime' runtime_opts
            fi
            ;;
        options)
            # Check if runtime is already specified
            local runtime=""
            for word in ${words[@]}; do
                case $word in
                    --nodejs|--node|-n|--runtime=nodejs)
                        runtime="nodejs"
                        break
                        ;;
                    --python|--py|-p|--runtime=python)
                        runtime="python"
                        break
                        ;;
                esac
            done
            
            if [[ -n $runtime ]]; then
                case $runtime in
                    nodejs)
                        _arguments -s \
                            $common_opts \
                            $node_opts
                        ;;
                    python)
                        _arguments -s \
                            $common_opts \
                            $python_opts
                        ;;
                esac
            else
                # Still need runtime
                _describe 'runtime' runtime_opts
            fi
            ;;
    esac
}

_aws-lambda-layer "$@"