############################################################
# kube runtime
############################################################

function k
    set tmp (mktemp)

    printf "%s\n" "$KUBE_DATA_CACHE" > $tmp

    env KUBECONFIG=$tmp kubectl $argv
    set rc $status

    rm -f $tmp
    return $rc
end

function kctx
    set tmp (mktemp)

    printf "%s\n" "$KUBE_DATA_CACHE" > $tmp

    env KUBECONFIG=$tmp kubectx $argv
    set rc $status

    rm -f $tmp
    return $rc
end

function kns
    set tmp (mktemp)

    printf "%s\n" "$KUBE_DATA_CACHE" > $tmp

    env KUBECONFIG=$tmp kubens $argv
    set rc $status

    rm -f $tmp
    return $rc
end

function k-logout
    op signout
    set -e KUBE_DATA_CACHE
    rm -f $KUBE_RUNTIME_CONFIG
    echo "Logged out and cache cleared."
end

function k-select

    set item_id (
        op item list --tags k8s-config --format json |
        jq -r '.[] | [.id, .title, .vault.name, (.tags|join(","))] | @tsv' |
        sort -k2 |
        fzf --delimiter='\t' --with-nth=2,3,4 --tabstop=30 |
        cut -f1
    )

    if test -z "$item_id"
        return
    end

    set item_title (op item get "$item_id" --format json | jq -r '.title')
    set vault_name (op item get "$item_id" --format json | jq -r '.vault.name')

    printf "Loading config for: %s\n" "$item_title"

    set raw_data (op read "op://$vault_name/$item_id/k8s config" 2>/dev/null | string collect)

    if test -z "$raw_data"
        set raw_data (op read "op://$vault_name/$item_id/text" 2>/dev/null | string collect)
    end

    if test -z "$raw_data"
        set file_id (op item get "$item_id" --format json | grep -oE '"files" ?: ?\[\{"id" ?: ?"[^"]+"' | cut -d'"' -f8)

        if test -n "$file_id"
            set raw_data (op read "op://$vault_name/$item_id/$file_id" 2>/dev/null | string collect)
        end
    end

    if test -z "$raw_data"
        printf "Error: Data not found in fields (k8s config, text) or files.\n"
        return
    end

    set -gx KUBE_DATA_CACHE "$raw_data"

    printf "Success! Context set for: %s\n" "$item_title"

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
