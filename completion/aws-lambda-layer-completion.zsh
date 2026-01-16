#compdef aws-lambda-layer-cli

_aws-lambda-layer-cli() {
    local -a commands runtime_opts common_opts node_opts python_opts
    
    commands=(
        'zip:Create and package a Lambda layer as zip file'
        'publish:Create and publish a Lambda layer to AWS (uses IAM credentials)'
        'help:Show help message'
        '--help:Show help message'
        '--version:Show version information'
    )
    
    runtime_opts=(
        '--nodejs:Node.js runtime'
        '--node:Node.js runtime'
        '-n:Node.js runtime'
        '--python:Python runtime'
        '--py:Python runtime'
        '-p:Python runtime'
        '--runtime:runtime:(nodejs python)'
    )
    
    common_opts=(
        '--name:name:'
        '--help'
        '-h'
    )
    
    publish_opts=(
        '--description:description:'
        '--layer-name:layer-name:'
        '--profile:profile:'
        '--region:region:'
    )
    
    node_opts=(
        '--node-version:version:'
    )
    
    python_opts=(
        '--python-version:version:'
        '--platform:platform:'
    )
    
    _arguments -C \
        '1: :->command' \
        '2: :->runtime_or_option' \
        '3: :->packages' \
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
        packages)
            # After runtime, expect packages as positional argument
            _message 'comma-separated packages (e.g., express@4.18.2,lodash)'
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
                # Check if this is publish command for extra options
                local cmd_opts=()
                if [[ $words[2] == "publish" ]]; then
                    cmd_opts=($common_opts $publish_opts)
                else
                    cmd_opts=($common_opts)
                fi
                
                case $runtime in
                    nodejs)
                        _arguments -s \
                            $cmd_opts \
                            $node_opts
                        ;;
                    python)
                        _arguments -s \
                            $cmd_opts \
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

# _aws-lambda-layer-cli "$@"
