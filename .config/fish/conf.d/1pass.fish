function _k_require_selection
    if test -z "$KUBE_ITEM_ID" -o -z "$KUBE_VAULT_NAME"
        echo "Error: No kubeconfig selected. Run 'k-select' first." >&2
        return 1
    end
end

function _k_fetch_raw_config
    _k_require_selection
    or return 1

    set -l raw_data ""
    set -l file_id ""

    set raw_data (op read "op://$KUBE_VAULT_NAME/$KUBE_ITEM_ID/k8s config" 2>/dev/null | string collect)

    if test -z "$raw_data"
        set raw_data (op read "op://$KUBE_VAULT_NAME/$KUBE_ITEM_ID/text" 2>/dev/null | string collect)
    end

    if test -z "$raw_data"
        set file_id (op item get "$KUBE_ITEM_ID" --format json | jq -r '.files[0].id // empty')
        if test -n "$file_id"
            set raw_data (op read "op://$KUBE_VAULT_NAME/$KUBE_ITEM_ID/$file_id" 2>/dev/null | string collect)
        end
    end

    if test -z "$raw_data"
        echo "Error: Data not found in fields (k8s config, text) or files." >&2
        return 1
    end

    printf "%s" "$raw_data"
end

function _k_with_temp_config
    _k_require_selection
    or return 1

    set -l tmp (mktemp)
    or return 1

    chmod 600 $tmp 2>/dev/null

    _k_fetch_raw_config > $tmp
    set -l rc $status

    if test $rc -ne 0
        rm -f $tmp
        return $rc
    end

    env KUBECONFIG=$tmp $argv
    set rc $status

    rm -f $tmp
    return $rc
end

function k-select
    set -l selection (
        op item list --tags k8s-config --format json |
        jq -r '.[] | [.id, .title, .vault.name, (.tags|join(","))] | @tsv' |
        sort -k2 |
        fzf --delimiter='\t' --with-nth=2,3,4 --tabstop=30 --reverse --inline-info
    )

    if test -z "$selection"
        return 1
    end

    set -l fields (string split \t -- $selection)

    set -gx KUBE_ITEM_ID $fields[1]
    set -gx KUBE_ITEM_TITLE $fields[2]
    set -gx KUBE_VAULT_NAME $fields[3]

    set -e KUBE_CONTEXT_NAME
    set -e KUBE_NAMESPACE

    echo "Selected kubeconfig: $KUBE_ITEM_TITLE"
end

function k
    _k_require_selection
    or return 1

    set -l extra_args

    if test -n "$KUBE_CONTEXT_NAME"
        set extra_args $extra_args --context "$KUBE_CONTEXT_NAME"
    end

    if test -n "$KUBE_NAMESPACE"
        set -l has_ns 0
        for arg in $argv
            if test "$arg" = "-n" -o "$arg" = "--namespace" -o "$arg" = "-A" -o "$arg" = "--all-namespaces"
                set has_ns 1
                break
            end
        end

        if test $has_ns -eq 0
            set extra_args $extra_args -n "$KUBE_NAMESPACE"
        end
    end

    _k_with_temp_config kubectl $extra_args $argv
end

function ctx
    _k_require_selection
    or return 1

    set -l current (_k_with_temp_config kubectl config current-context 2>/dev/null)
    set -l contexts (_k_with_temp_config kubectl config get-contexts -o name)

    set -l ordered (
        printf "%s\n%s\n" "$current" $contexts | awk 'NF && !seen[$0]++'
    )

    set -l target (
        printf "%s\n" $ordered | fzf \
            --reverse \
            --header "Select Cluster Context (current: $current)" \
            --height 80%
    )

    if test -n "$target"
        set -gx KUBE_CONTEXT_NAME "$target"
        echo "Context selected: $target"
    end
end

function kctx
    if test (count $argv) -eq 0
        ctx
        return $status
    end

    set -gx KUBE_CONTEXT_NAME "$argv[1]"
    echo "Context selected: $KUBE_CONTEXT_NAME"
end

function kns
    _k_require_selection
    or return 1

    if test (count $argv) -gt 0
        set -gx KUBE_NAMESPACE "$argv[1]"
        echo "Namespace selected: $KUBE_NAMESPACE"
        return 0
    end

    set -l current_ns default
    if test -n "$KUBE_NAMESPACE"
        set current_ns "$KUBE_NAMESPACE"
    end

    set -l target_ns (
        k get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null |
        fzf \
            --reverse \
            --header "Select Namespace (current: $current_ns)" \
            --height 80%
    )

    if test -n "$target_ns"
        set -gx KUBE_NAMESPACE "$target_ns"
        echo "Namespace selected: $target_ns"
    end
end

function k-logout
    set -e KUBE_ITEM_ID
    set -e KUBE_ITEM_TITLE
    set -e KUBE_VAULT_NAME
    set -e KUBE_CONTEXT_NAME
    set -e KUBE_NAMESPACE

    op signout >/dev/null 2>/dev/null
    echo "Logged out and selection cleared."
end

function ssh-select
    set -l selection (
        op item list --tags ssh-key --format json |
        jq -r '.[] | [.id, .title, .vault.id, .vault.name, (.tags|join(","))] | @tsv' |
        sort -k2 |
        fzf --delimiter='\t' --with-nth=2,4,5 --tabstop=30 --reverse --inline-info
    )

    if test -z "$selection"
        return 1
    end

    set -l fields (string split \t -- $selection)
    set -l item_id $fields[1]
    set -l item_title $fields[2]
    set -l vault_id $fields[3]

    echo "Adding key: $item_title"

    set -l tmp_key (mktemp)
    or return 1

    op item get "$item_id" --vault "$vault_id" --reveal --format json | \
        jq -r '
            .. | objects
            | select(
                (.id? == "private_key") or
                (.label? == "private key") or
                (.label? == "Private key")
            )
            | .value
        ' | tr -d '\r' > $tmp_key

    if test ! -s $tmp_key
        echo "Error: private key not found"
        rm -f $tmp_key
        return 1
    end

    chmod 600 $tmp_key
    ssh-add -t 1h $tmp_key
    set -l rc $status
    rm -f $tmp_key
    return $rc
end
