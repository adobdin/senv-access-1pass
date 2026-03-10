set -g KUBE_RUNTIME_CONFIG /tmp/kube_runtime_config


function k
    kubectl $argv --kubeconfig $KUBE_RUNTIME_CONFIG
end


function kctx
    env KUBECONFIG=$KUBE_RUNTIME_CONFIG kubectx $argv
end


function kns
    env KUBECONFIG=$KUBE_RUNTIME_CONFIG kubens $argv
end


function k-logout
    op signout
    set -e KUBE_DATA_CACHE
    rm -f $KUBE_RUNTIME_CONFIG
    echo "Logged out and cache cleared."
end

function k-select

    set selection (
        op item list --tags k8s-config --format json |
        jq -r '.[] | [.id, .title, .vault.id, .vault.name, (.tags|join(","))] | @tsv' |
        fzf --delimiter='\t' --with-nth=2,4,5 --tabstop=30
    )

    if test -z "$selection"
        return
    end

    set fields (string split \t $selection)

    set item_id $fields[1]
    set item_title $fields[2]
    set vault_id $fields[3]

    echo "Loading config for: $item_title"

    set raw_data (op read "op://$vault_id/$item_id/k8s config" 2>/dev/null | string collect)

    if test -z "$raw_data"
        set raw_data (op read "op://$vault_id/$item_id/text" 2>/dev/null | string collect)
    end

    printf "%s\n" "$raw_data" > /tmp/kube_runtime_config
    set -gx KUBE_DATA_CACHE "$raw_data"

    echo "Success! Context set for: $item_title"

end

function ssh-select

    set selection (
        op item list --tags ssh-key --format json |
        jq -r '.[] | [.id, .title, .vault.id, .vault.name, (.tags|join(","))] | @tsv' |
        fzf --delimiter='\t' --with-nth=2,4,5 --tabstop=30 --reverse --inline-info
    )

    if test -z "$selection"
        return
    end

    set fields (string split \t $selection)

    set item_id $fields[1]
    set item_title $fields[2]
    set vault_id $fields[3]

    echo "Adding key: $item_title"

    set tmp_key "/tmp/op_ssh_key_$fish_pid"

    op read "op://$vault_id/$item_id/private key" > $tmp_key

    chmod 600 $tmp_key

    ssh-add -t 1h $tmp_key

    rm -f $tmp_key

end
