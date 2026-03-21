[[ -z "$ORIGINAL_PS1" ]] && ORIGINAL_PS1="$PS1"

(( $+aliases[k] )) && unalias k
(( $+aliases[kctx] )) && unalias kctx
(( $+aliases[kns] )) && unalias kns

k() {
  local tmp
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  KUBECONFIG="$tmp" command kubectl "$@"
  local rc=$?

  rm -f "$tmp"
  return $rc
}

kctx() {
  local tmp rc
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  KUBECONFIG="$tmp" command kubectx "$@"
  rc=$?

  if [[ $rc -eq 0 ]]; then
    KUBE_DATA_CACHE=$(cat "$tmp")
    export KUBE_DATA_CACHE
  fi

  rm -f "$tmp"
  return $rc
}

kns() {
  local tmp rc
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  KUBECONFIG="$tmp" command kubens "$@"
  rc=$?

  if [[ $rc -eq 0 ]]; then
    KUBE_DATA_CACHE=$(cat "$tmp")
    export KUBE_DATA_CACHE
  fi

  rm -f "$tmp"
  return $rc
}

k-logout() {
  op signout
  unset KUBE_DATA_CACHE
  unset K8S_CONTEXT_DISPLAY
  echo "Logged out and cache cleared."
}

k-select() {
  unsetopt nomatch
  set -o noglob

  local item_id

  item_id=$(
    op item list --tags k8s-config --format json |
    jq -r '.[] | [.id, .title, .vault.name, (.tags|join(","))] | @tsv' |
    sort -k2 |
    fzf --delimiter=$'\t' --with-nth=2,3,4 --tabstop=30 --reverse --inline-info |
    cut -f1
  )

  [[ -z "$item_id" ]] && { set +o noglob; return 1; }

  local item_title vault_name raw_data

  item_title=$(op item get "$item_id" --format json | jq -r '.title')
  vault_name=$(op item get "$item_id" --format json | jq -r '.vault.name')

  printf "Loading config for: %s\n" "$item_title"

  raw_data=$(op read "op://$vault_name/$item_id/k8s config" 2>/dev/null)

  [[ -z "$raw_data" ]] && raw_data=$(op read "op://$vault_name/$item_id/text" 2>/dev/null)

  if [[ -z "$raw_data" ]]; then
    local file_id
    file_id=$(op item get "$item_id" --format json |
      grep -oE '"files" ?: ?\[\{"id" ?: ?"[^"]+"' |
      cut -d'"' -f8)

    [[ -n "$file_id" ]] && raw_data=$(op read "op://$vault_name/$item_id/$file_id" 2>/dev/null)
  fi

  [[ -z "$raw_data" ]] && {
    printf "Error: Data not found in fields (k8s config, text) or files.\n"
    set +o noglob
    return 1
  }

  export KUBE_DATA_CACHE="$raw_data"

  export K8S_CONTEXT_DISPLAY="$item_title"

  printf "Success! Context set for: %s\n" "$item_title"

  set +o noglob
  setopt nomatch
}

ctx() {

  if [[ -z "$KUBE_DATA_CACHE" ]]; then
    printf "Error: No kubeconfig loaded. Run 'k-select' first.\n"
    return 1
  fi

  local tmp
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  local current
  current=$(kubectl --kubeconfig "$tmp" config current-context)

  local contexts
  contexts=$(kubectl --kubeconfig "$tmp" config get-contexts -o name)

  local ordered
  ordered=$(printf "%s\n%s\n" "$current" "$contexts" | awk '!seen[$0]++')

  local target
  target=$(echo "$ordered" | fzf \
    --reverse \
    --header "Select Cluster Context (current: $current)" \
    --height 80% \
    --preview "kubectl --kubeconfig $tmp config view --minify --context {}" \
    --preview-window right:50%:wrap)

  if [[ -n "$target" ]]; then
    kubectl --kubeconfig "$tmp" config use-context "$target" >/dev/null 2>&1
    KUBE_DATA_CACHE=$(kubectl --kubeconfig "$tmp" config view --raw)
    export KUBE_DATA_CACHE
    export K8S_CONTEXT_DISPLAY="$target"
    printf "Switched to context: %s\n" "$target"
  fi

  rm -f "$tmp"
}

ssh-select() {
  unsetopt nomatch
  set -o noglob

  local raw_list
  raw_list=$'ID\tTITLE\tVAULT\n'

  raw_list+=$(
    op item list --tags ssh-key --format json |
    jq -r '.[] | "\(.id)\t\(.title)\t\(.vault.name)"' |
    sort -k2 -t$'\t'
  )

  local selection
  selection=$(printf "%s\n" "$raw_list" | \
    fzf --reverse --inline-info --tabstop=30 --header-lines=1)

  [[ -z "$selection" ]] && {
    set +o noglob
    setopt nomatch
    return 1
  }

  local item_id
  item_id=$(printf "%s\n" "$selection" | cut -f1)

  local item_title
  item_title=$(printf "%s\n" "$selection" | cut -f2)

  echo "Adding key: $item_title"

  op item get "$item_id" --reveal --format json |
    jq -r '
      .. | objects
      | select(
          (.id? == "private_key") or
          (.label? == "private key") or
          (.label? == "Private key")
        )
      | .value
    ' |
    tr -d '\r' |
    ssh-add -t 1h -

  set +o noglob
  setopt nomatch
}
